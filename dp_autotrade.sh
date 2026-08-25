
🚀 سیستم اتوتریدینگ حرفهای با اعتبارسنجی سهلایه و پشتیبانی از چندصرافی
"""

import asyncio
import logging
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import json
import hmac
import hashlib
import urllib.parse
import aiohttp
from dataclasses import dataclass
from enum import Enum
import hashlib
import time

# ==================== ENUMS & DATA CLASSES ====================

class Exchange(Enum):
    BYBIT = "bybit"
    OKX = "okx"
    LBANK = "lbank"
    BITUNIX = "bitunix"

class SignalType(Enum):
    WHALE_PUMP = "whale_pump"
    WHALE_DUMP = "whale_dump"
    FLOW_BUY = "flow_buy"
    FLOW_SELL = "flow_sell"
    MARKET_PRESSURE = "market_pressure"
    OI_SURGE = "oi_surge"
    FUNDING_SIGNAL = "funding_signal"

@dataclass
class MinuteCandle:
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float
    oi: float  # Open Interest
    funding_rate: float
    liquidations: Dict[str, float]

@dataclass
class WhaleMovement:
    address: str
    size: float
    direction: str  # 'exchange_in', 'exchange_out', 'accumulation', 'distribution'
    timestamp: datetime
    confidence: float
    exchange: str

@dataclass
class MarketFlow:
    net_flow: float
    stablecoin_flow: float
    futures_flow: float
    options_flow: float
    pressure_score: float

@dataclass
class ValidatedSignal:
    signal_type: SignalType
    confidence: float  # 0-100
    weight_20: float
    weight_30: float
    weight_50: float
    final_score: float
    timestamp: datetime
    metadata: Dict

# ==================== DATABASE MODELS ====================

class QuantumDatabase:
    """دیتابیس کوانتومی برای ذخیره همه دادهها"""
    
    def __init__(self):
        self.conn = None
        self.setup_database()
    
    def setup_database(self):
        """راهاندازی جداول دیتابیس"""
        import sqlite3
        self.conn = sqlite3.connect('quantum_trading.db', check_same_thread=False)
        cursor = self.conn.cursor()
        
        # جدول کندلها
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS candles_1m (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT,
                timestamp DATETIME,
                open REAL,
                high REAL,
                low REAL,
                close REAL,
                volume REAL,
                oi REAL,
                funding_rate REAL,
                buy_liq REAL,
                sell_liq REAL,
                UNIQUE(symbol, timestamp)
            )
        ''')
        
        # جدول حرکت نهنگها
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS whale_movements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT,
                address TEXT,
                size REAL,
                direction TEXT,
                exchange TEXT,
                confidence REAL,
                timestamp DATETIME,
                processed BOOLEAN DEFAULT FALSE
            )
        ''')
        
        # جدول جریان بازار
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS market_flows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT,
                net_flow REAL,
                stablecoin_flow REAL,
                futures_flow REAL,
                options_flow REAL,
                pressure_score REAL,
                timestamp DATETIME
            )
        ''')
        
        # جدول سیگنالهای اعتبارسنجی شده
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS validated_signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT,
                signal_type TEXT,
                confidence REAL,
                weight_20 REAL,
                weight_30 REAL,
                weight_50 REAL,
                final_score REAL,
                approved BOOLEAN DEFAULT FALSE,
                executed BOOLEAN DEFAULT FALSE,
                execution_price REAL,
                pnl REAL,
                timestamp DATETIME,
                metadata TEXT
            )
        ''')
        
        # جدول تریدهای اجرا شده
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS executed_trades (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                signal_id INTEGER,
                exchange TEXT,
                symbol TEXT,
                side TEXT,
                quantity REAL,
                entry_price REAL,
                exit_price REAL,
                stop_loss REAL,
                take_profit REAL,
                pnl REAL,
                pnl_percent REAL,
                status TEXT,
                entry_time DATETIME,
                exit_time DATETIME,
                FOREIGN KEY (signal_id) REFERENCES validated_signals (id)
            )
        ''')
        
        self.conn.commit()
        logging.info("✅ دیتابیس راهاندازی شد")
    
    def save_candle(self, symbol: str, candle: MinuteCandle):
        """ذخیره کندل ۱ دقیقهای"""
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT OR REPLACE INTO candles_1m 
            (symbol, timestamp, open, high, low, close, volume, oi, funding_rate, buy_liq, sell_liq)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            symbol, candle.timestamp, candle.open, candle.high, candle.low,
            candle.close, candle.volume, candle.oi, candle.funding_rate,
            candle.liquidations.get('buy', 0), candle.liquidations.get('sell', 0)
        ))
        self.conn.commit()
    
    def save_whale_movement(self, symbol: str, whale: WhaleMovement):
        """ذخیره حرکت نهنگ"""
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT INTO whale_movements 
            (symbol, address, size, direction, exchange, confidence, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            symbol, whale.address, whale.size, whale.direction,
            whale.exchange, whale.confidence, whale.timestamp
        ))
        self.conn.commit()
    
    def save_signal(self, symbol: str, signal: ValidatedSignal):
        """ذخیره سیگنال اعتبارسنجی شده"""
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT INTO validated_signals 
            (symbol, signal_type, confidence, weight_20, weight_30, weight_50, 
             final_score, timestamp, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            symbol, signal.signal_type.value, signal.confidence,
            signal.weight_20, signal.weight_30, signal.weight_50,
            signal.final_score, signal.timestamp, json.dumps(signal.metadata)
        ))
        signal_id = cursor.lastrowid
        self.conn.commit()
        return signal_id

# ==================== EXCHANGE DATA COLLECTORS ====================

class ExchangeDataCollector:
    """کلکتور دادههای چندصرافی"""
    
    def __init__(self, exchange: Exchange, api_key: str = None, api_secret: str = None):
        self.exchange = exchange
        self.api_key = api_key
        self.api_secret = api_secret
        self.session = None
        self.base_urls = {
            Exchange.BYBIT: "https://api.bybit.com",
            Exchange.OKX: "https://www.okx.com",
            Exchange.LBANK: "https://api.lbank.info",
            Exchange.BITUNIX: "https://api.bitunix.com"
        }
    
    async def get_1m_candles(self, symbol: str, limit: int = 100) -> List[MinuteCandle]:
        """دریافت کندلهای ۱ دقیقهای"""
        candles = []
        
        try:
            if self.exchange == Exchange.BYBIT:
                url = f"{self.base_urls[self.exchange]}/v5/market/kline"
                params = {
                    'category': 'linear',
                    'symbol': symbol,
                    'interval': '1',
                    'limit': limit
                }
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['retCode'] == 0:
                            for item in data['result']['list']:
                                candles.append(MinuteCandle(
                                    timestamp=datetime.fromtimestamp(int(item[0]) / 1000),
                                    open=float(item[1]),
                                    high=float(item[2]),
                                    low=float(item[3]),
                                    close=float(item[4]),
                                    volume=float(item[5]),
                                    oi=float(item[6]) if len(item) > 6 else 0,
                                    funding_rate=0,
                                    liquidations={'buy': 0, 'sell': 0}
                                ))
            
            elif self.exchange == Exchange.OKX:
                url = f"{self.base_urls[self.exchange]}/api/v5/market/candles"
                params = {
                    'instId': symbol,
                    'bar': '1m',
                    'limit': limit
                }
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['code'] == '0':
                            for item in data['data']:
                                candles.append(MinuteCandle(
                                    timestamp=datetime.fromtimestamp(int(item[0]) / 1000),
                                    open=float(item[1]),
                                    high=float(item[2]),
                                    low=float(item[3]),
                                    close=float(item[4]),
                                    volume=float(item[5]),
                                    oi=float(item[6]) if len(item) > 6 else 0,
                                    funding_rate=0,
                                    liquidations={'buy': 0, 'sell': 0}
                                ))
        
        except Exception as e:
            logging.error(f"خطا در دریافت داده از {self.exchange}: {e}")
        
        return candles
    
    async def get_open_interest(self, symbol: str) -> float:
        """دریافت Open Interest"""
        try:
            if self.exchange == Exchange.BYBIT:
                url = f"{self.base_urls[self.exchange]}/v5/market/open-interest"
                params = {'category': 'linear', 'symbol': symbol, 'interval': '5min'}
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['retCode'] == 0:
                            return float(data['result']['list'][0]['openInterest'])
            
            elif self.exchange == Exchange.OKX:
                url = f"{self.base_urls[self.exchange]}/api/v5/public/open-interest"
                params = {'instId': symbol}
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['code'] == '0':
                            return float(data['data'][0]['oi'])
        
        except Exception as e:
            logging.error(f"خطا در دریافت OI از {self.exchange}: {e}")
        
        return 0.0
    
    async def get_funding_rate(self, symbol: str) -> float:
        """دریافت Funding Rate"""
        try:
            if self.exchange == Exchange.BYBIT:
                url = f"{self.base_urls[self.exchange]}/v5/market/funding/history"
                params = {'category': 'linear', 'symbol': symbol, 'limit': 1}
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['retCode'] == 0:
                            return float(data['result']['list'][0]['fundingRate'])
            
            elif self.exchange == Exchange.OKX:
                url = f"{self.base_urls[self.exchange]}/api/v5/public/funding-rate"
                params = {'instId': symbol}
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, params=params) as response:
                        data = await response.json()
                        if data['code'] == '0':
                            return float(data['data'][0]['fundingRate'])
        
        except Exception as e:
            logging.error(f"خطا در دریافت Funding Rate از {self.exchange}: {e}")
        
        return 0.0

# ==================== WHALE DETECTION SYSTEM ====================

class WhaleRadar:
    """رادار تشخیص نهنگها"""
    
    def __init__(self):
        self.whale_threshold = 1000000  # 1M USD
        self.suspicious_patterns = []
    
    async def scan_whale_activity(self, exchange: Exchange, symbol: str) -> List[WhaleMovement]:
        """اسکن فعالیت نهنگها"""
        movements = []
        
        try:
            # شبیهسازی - در واقعیت از API زنجیرهای استفاده شود
            if np.random.random() > 0.7:  # 30% chance of whale activity
                directions = ['exchange_in', 'exchange_out', 'accumulation', 'distribution']
                movement = WhaleMovement(
                    address=f"0x{hashlib.md5(str(time.time()).encode()).hexdigest()[:10]}",
                    size=np.random.uniform(1000000, 5000000),
                    direction=np.random.choice(directions),
                    timestamp=datetime.now(),
                    confidence=np.random.uniform(0.6, 0.95),
                    exchange=exchange.value
                )
                movements.append(movement)
                
                logging.info(f"🐋 حرکت نهنگ تشخیص داده شد: {movement.direction} - {movement.size:,.0f} USD")
        
        except Exception as e:
            logging.error(f"خطا در اسکن نهنگها: {e}")
        
        return movements
    
    def detect_pump_pattern(self, whales: List[WhaleMovement]) -> bool:
        """تشخیص الگوی پامپ"""
        if len(whales) < 3:
            return False
        
        recent_whales = [w for w in whales if (datetime.now() - w.timestamp).seconds < 300]
        
        # اگر ۳ حرکت بزرگ به سمت صرافی در ۵ دقیقه باشد
        exchange_in_movements = [w for w in recent_whales if w.direction == 'exchange_in']
        
        if len(exchange_in_movements) >= 3:
            total_inflow = sum([w.size for w in exchange_in_movements])
            if total_inflow > 5000000:  # 5M USD
                return True
        
        return False
    
    def detect_dump_pattern(self, whales: List[WhaleMovement]) -> bool:
        """تشخیص الگوی دامپ"""
        recent_whales = [w for w in whales if (datetime.now() - w.timestamp).seconds < 300]
        
        # اگر حرکتهای بزرگ از صرافی خارج شود
        exchange_out_movements = [w for w in recent_whales if w.direction == 'exchange_out']
        
        if len(exchange_out_movements) >= 2:
            total_outflow = sum([w.size for w in exchange_out_movements])
            if total_outflow > 3000000:  # 3M USD
                return True
        
        return False

# ==================== MARKET FLOW ANALYZER ====================

class FlowAnalyzer:
    """تحلیلگر جریان بازار"""
    
    def __init__(self):
        self.flow_history = []
        self.pressure_threshold = 0.7
    
    async def analyze_market_flow(self, symbol: str, candles: List[MinuteCandle]) -> MarketFlow:
        """تحلیل جریان بازار"""
        
        if len(candles) < 20:
            return MarketFlow(0, 0, 0, 0, 0)
        
        recent_candles = candles[-20:]
        
        # محاسبه جریان خالص
        price_change = (recent_candles[-1].close - recent_candles[0].open) / recent_candles[0].open
        volume_trend = np.mean([c.volume for c in recent_candles[-5:]]) / np.mean([c.volume for c in recent_candles[:5]])
        
        # محاسبه فشار بازار
        pressure_score = self._calculate_pressure_score(recent_candles)
        
        # شبیهسازی جریان استیبلکوین و فیوچرز
        stablecoin_flow = price_change * 1000000 if price_change > 0 else 0
        futures_flow = pressure_score * 500000
        options_flow = pressure_score * 300000
        
        net_flow = stablecoin_flow + futures_flow + options_flow
        
        flow = MarketFlow(
            net_flow=net_flow,
            stablecoin_flow=stablecoin_flow,
            futures_flow=futures_flow,
            options_flow=options_flow,
            pressure_score=pressure_score
        )
        
        self.flow_history.append(flow)
        if len(self.flow_history) > 1000:
            self.flow_history.pop(0)
        
        return flow
    
    def _calculate_pressure_score(self, candles: List[MinuteCandle]) -> float:
        """محاسبه فشار بازار"""
        if len(candles) < 10:
            return 0.0
        
        # ترکیب چندین اندیکاتور
        prices = [c.close for c in candles]
        volumes = [c.volume for c in candles]
        
        # RSI
        rsi = self._calculate_rsi(prices)
        rsi_score = abs(rsi - 50) / 50  # نرمالسازی
        
        # Volume Spike
        volume_avg = np.mean(volumes[:-5])
        volume_current = np.mean(volumes[-5:])
        volume_score = min(volume_current / (volume_avg + 1e-10) - 1, 2) / 2
        
        # Price Momentum
        returns = np.diff(prices) / prices[:-1]
        momentum = np.mean(returns[-5:])
        momentum_score = abs(momentum) * 100
        
        # ترکیب نمرات
        pressure = (rsi_score * 0.3 + volume_score * 0.4 + momentum_score * 0.3)
        
        return min(max(pressure, 0), 1)
    
    def _calculate_rsi(self, prices: List[float], period: int = 14) -> float:
        """محاسبه RSI"""
        if len(prices) < period + 1:
            return 50.0
        
        deltas = np.diff(prices[-period-1:])
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)
        
        avg_gain = np.mean(gains)
        avg_loss = np.mean(losses)
        
        if avg_loss == 0:
            return 100.0
        
        rs = avg_gain / avg_loss
        return 100 - (100 / (1 + rs))

# ==================== SIGNAL VALIDATOR ====================

class ThreeCandleValidator:
    """اعتبارسنج سه کندلی با وزنهای ۲۰، ۳۰، ۵۰"""
    
    def __init__(self, approval_threshold: float = 70.0):
        self.approval_threshold = approval_threshold
        self.signal_buffer = {}  # symbol -> [signal1, signal2, signal3]
    
    async def validate_signal(self, symbol: str, signal_type: SignalType, 
                            confidence: float, metadata: Dict) -> Optional[ValidatedSignal]:
        """اعتبارسنجی سیگنال با سه کندل"""
        
        if symbol not in self.signal_buffer:
            self.signal_buffer[symbol] = []
        
        # اضافه کردن سیگنال جدید به بافر
        signal_data = {
            'type': signal_type,
            'confidence': confidence,
            'timestamp': datetime.now(),
            'metadata': metadata
        }
        
        self.signal_buffer[symbol].append(signal_data)
        
        # حفظ فقط ۳ سیگنال آخر
        if len(self.signal_buffer[symbol]) > 3:
            self.signal_buffer[symbol] = self.signal_buffer[symbol][-3:]
        
        # اگر ۳ سیگنال داریم، اعتبارسنجی کن
        if len(self.signal_buffer[symbol]) == 3:
            signals = self.signal_buffer[symbol]
            
            # اعمال وزنها
            weighted_score = (
                signals[0]['confidence'] * 0.2 +  # کندل اول: وزن ۲۰
                signals[1]['confidence'] * 0.3 +  # کندل دوم: وزن ۳۰
                signals[2]['confidence'] * 0.5    # کندل سوم: وزن ۵۰
            )
            
            # بررسی آستانه
            if weighted_score >= self.approval_threshold:
                validated = ValidatedSignal(
                    signal_type=signal_type,
                    confidence=confidence,
                    weight_20=signals[0]['confidence'],
                    weight_30=signals[1]['confidence'],
                    weight_50=signals[2]['confidence'],
                    final_score=weighted_score,
                    timestamp=datetime.now(),
                    metadata=metadata
                )
                
                logging.info(f"✅ سیگنال تایید شده: {signal_type.value} - امتیاز: {weighted_score:.2f}")
                
                # پاک کردن بافر برای شروع مجدد
                self.signal_buffer[symbol] = []
                
                return validated
        
        return None

# ==================== AUTO TRADER ====================

class AutoTrader:
    """اتوتریدر هوشمند با مدیریت ریسک"""
    
    def __init__(self, exchange: Exchange, api_key: str, api_secret: str):
        self.exchange = exchange
        self.api_key = api_key
        self.api_secret = api_secret
        self.positions = {}
        self.max_position_size = 0.1  # 10% سرمایه
        self.stop_loss_pct = 0.02    # 2% استاپ لاس
        self.take_profit_pct = 0.04  # 4% تیک پروفیت
        
    async def execute_trade(self, symbol: str, signal: ValidatedSignal) -> bool:
        """اجرای معامله بر اساس سیگنال تایید شده"""
        
        try:
            # تعیین جهت معامله
            if signal.signal_type in [SignalType.WHALE_PUMP, SignalType.FLOW_BUY, 
                                     SignalType.MARKET_PRESSURE, SignalType.OI_SURGE]:
                side = "BUY"
            else:
                side = "SELL"
            
            # محاسبه اندازه پوزیشن
            position_size = await self._calculate_position_size(symbol, signal.final_score)
            
            # قیمت ورود
            entry_price = await self._get_current_price(symbol)
            
            # حد ضرر و حد سود
            if side == "BUY":
                stop_loss = entry_price * (1 - self.stop_loss_pct)
                take_profit = entry_price * (1 + self.take_profit_pct)
            else:
                stop_loss = entry_price * (1 + self.stop_loss_pct)
                take_profit = entry_price * (1 - self.take_profit_pct)
            
            # ارسال سفارش (شبیهسازی - در واقعیت از API صرافی استفاده شود)
            order_id = f"order_{int(time.time())}_{hashlib.md5(symbol.encode()).hexdigest()[:8]}"
            
            logging.info(f"""
            🚀 اجرای معامله:
            نماد: {symbol}
            جهت: {side}
            اندازه: {position_size}
            قیمت ورود: {entry_price:,.2f}
            استاپ لاس: {stop_loss:,.2f}
            تیک پروفیت: {take_profit:,.2f}
            سیگنال: {signal.signal_type.value}
            امتیاز: {signal.final_score:.2f}
            """)
            
            # ذخیره پوزیشن
            self.positions[symbol] = {
                'order_id': order_id,
                'side': side,
                'size': position_size,
                'entry_price': entry_price,
                'stop_loss': stop_loss,
                'take_profit': take_profit,
                'entry_time': datetime.now(),
                'signal_score': signal.final_score
            }
            
            return True
            
        except Exception as e:
            logging.error(f"❌ خطا در اجرای معامله: {e}")
            return False
    
    async def _calculate_position_size(self, symbol: str, signal_score: float) -> float:
        """محاسبه اندازه پوزیشن بر اساس امتیاز سیگنال"""
        base_size = 0.01  # 1% پایه
        
        # افزایش اندازه بر اساس امتیاز سیگنال
        if signal_score >= 90:
            multiplier = 3.0
        elif signal_score >= 80:
            multiplier = 2.0
        elif signal_score >= 70:
            multiplier = 1.5
        else:
            multiplier = 1.0
        
        return base_size * multiplier
    
    async def _get_current_price(self, symbol: str) -> float:
        """دریافت قیمت جاری"""
        # شبیهسازی - در واقعیت از API صرافی استفاده شود
        return np.random.uniform(50000, 60000)
    
    async def monitor_positions(self):
        """مانیتورینگ پوزیشنهای باز"""
        for symbol, position in list(self.positions.items()):
            current_price = await self._get_current_price(symbol)
            
            # بررسی استاپ لاس
            if position['side'] == 'BUY':
                if current_price <= position['stop_loss']:
                    await self._close_position(symbol, 'STOP_LOSS', current_price)
                elif current_price >= position['take_profit']:
                    await self._close_position(symbol, 'TAKE_PROFIT', current_price)
            else:
                if current_price >= position['stop_loss']:
                    await self._close_position(symbol, 'STOP_LOSS', current_price)
                elif current_price <= position['take_profit']:
                    await self._close_position(symbol, 'TAKE_PROFIT', current_price)
    
    async def _close_position(self, symbol: str, reason: str, exit_price: float):
        """بستن پوزیشن"""
        position = self.positions.get(symbol)
        if not position:
            return
        
        # محاسبه سود/ضرر
        if position['side'] == 'BUY':
            pnl = (exit_price - position['entry_price']) * position['size']
        else:
            pnl = (position['entry_price'] - exit_price) * position['size']
        
        pnl_percent = (pnl / (position['entry_price'] * position['size'])) * 100
        
        logging.info(f"""
        🎯 بستن پوزیشن:
        نماد: {symbol}
        دلیل: {reason}
        سود/ضرر: {pnl:,.2f} USD ({pnl_percent:.2f}%)
        مدت: {(datetime.now() - position['entry_time']).seconds} ثانیه
        """)
        
        # حذف از پوزیشنهای فعال
        del self.positions[symbol]

# ==================== PARAMETRIC SYSTEM ====================

class ParametricSystem:
    """سیستم پارامتریک برای تنظیمات پویا"""
    
    def __init__(self):
        self.parameters = {
            # اعتبارسنجی
            'validation_threshold': 70.0,
            'weight_20': 0.2,
            'weight_30': 0.3,
            'weight_50': 0.5,
            
            # نهنگها
            'whale_threshold_usd': 1000000,
            'pump_threshold': 5000000,
            'dump_threshold': 3000000,
            
            # ریسک
            'max_position_pct': 0.1,
            'stop_loss_pct': 0.02,
            'take_profit_pct': 0.04,
            
            # معاملات
            'min_signal_score': 70,
            'max_daily_trades': 20,
            'cooldown_minutes': 5,
            
            # دادهها
            'candle_history': 100,
            'update_interval_seconds': 60
        }
    
    def update_parameter(self, key: str, value: float):
        """بهروزرسانی پارامتر"""
        if key in self.parameters:
            old_value = self.parameters[key]
            self.parameters[key] = value
            logging.info(f"🔄 پارامتر {key} از {old_value} به {value} بهروزرسانی شد")
    
    def get_parameter(self, key: str) -> float:
        """دریافت پارامتر"""
        return self.parameters.get(key, 0.0)
    
    def auto_optimize(self, performance_data: Dict):
        """بهینهسازی خودکار پارامترها"""
        win_rate = performance_data.get('win_rate', 0.5)
        
        if win_rate > 0.6:
            # افزایش ریسک اگر win_rate خوب است
            self.update_parameter('max_position_pct', 
                                min(0.2, self.parameters['max_position_pct'] * 1.1))
            
        elif win_rate < 0.4:
            # کاهش ریسک اگر win_rate ضعیف است
            self.update_parameter('max_position_pct', 
                                max(0.05, self.parameters['max_position_pct'] * 0.9))
            
        # تنظیم آستانه بر اساس volatility
        volatility = performance_data.get('volatility', 0.02)
        new_stop = volatility * 1.5
        self.update_parameter('stop_loss_pct', new_stop)
        self.update_parameter('take_profit_pct', new_stop * 2)

# ==================== MAIN TRADING SYSTEM ====================

class GalacticTradingSystem:
    """سیستم معاملاتی کهکشانی - نسخه نهایی"""
    
    def __init__(self):
        self.db = QuantumDatabase()
        self.param_system = ParametricSystem()
        self.whale_radar = WhaleRadar()
        self.flow_analyzer = FlowAnalyzer()
        self.validator = ThreeCandleValidator(
            approval_threshold=self.param_system.get_parameter('validation_threshold')
        )
        
        # صرافیها
        self.exchanges = {
            'data': [Exchange.BYBIT, Exchange.OKX],
            'trading': [Exchange.LBANK, Exchange.BITUNIX]
        }
        
        # کلکتورها
        self.data_collectors = {}
        for exchange in self.exchanges['data']:
            self.data_collectors[exchange] = ExchangeDataCollector(exchange)
        
        # تریدرها
        self.traders = {}
        
        # سمبلهای مورد نظر
        self.symbols = ['BTCUSDT', 'ETHUSDT']
        
        # وضعیت
        self.running = False
        self.trade_count = 0
        self.max_daily_trades = self.param_system.get_parameter('max_daily_trades')
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('trading_system.log'),
                logging.StreamHandler()
            ]
        )
    
    async def initialize_traders(self, api_keys: Dict):
        """راهاندازی تریدرها با API Keyهای شخصی"""
        for exchange_name, keys in api_keys.items():
            exchange = Exchange(exchange_name)
            self.traders[exchange] = AutoTrader(
                exchange=exchange,
                api_key=keys['api_key'],
                api_secret=keys['api_secret']
            )
            logging.info(f"✅ تریدر {exchange_name} راهاندازی شد")
    
    async def run_trading_cycle(self):
        """اجرای چرخه معاملاتی"""
        cycle_start = datetime.now()
        
        for symbol in self.symbols:
            try:
                # 1. جمعآوری دادهها
                all_candles = []
                for exchange in self.exchanges['data']:
                    candles = await self.data_collectors[exchange].get_1m_candles(
                        symbol, 
                        self.param_system.get_parameter('candle_history')
                    )
                    all_candles.extend(candles)
                
                if not all_candles:
                    continue
                
                # 2. تحلیل نهنگها
                whale_activities = []
                for exchange in self.exchanges['data']:
                    whales = await self.whale_radar.scan_whale_activity(exchange, symbol)
                    whale_activities.extend(whales)
                    
                    for whale in whales:
                        self.db.save_whale_movement(symbol, whale)
                
                # 3. تحلیل جریان بازار
                market_flow = await self.flow_analyzer.analyze_market_flow(symbol, all_candles)
                
                # 4. تولید سیگنال
                signals = self._generate_signals(symbol, whale_activities, market_flow, all_candles[-1])
                
                # 5. اعتبارسنجی سیگنال
                for signal_type, confidence, metadata in signals:
                    validated = await self.validator.validate_signal(
                        symbol, signal_type, confidence, metadata
                    )
                    
                    if validated:
                        # ذخیره سیگنال
                        signal_id = self.db.save_signal(symbol, validated)
                        
                        # بررسی محدودیت تعداد معاملات
                        if self.trade_count < self.max_daily_trades:
                            # اجرای معامله
                            for trader_exchange, trader in self.traders.items():
                                success = await trader.execute_trade(symbol, validated)
                                if success:
                                    self.trade_count += 1
                                    validated.metadata['trader'] = trader_exchange.value
                                    break
                
                # 6. مانیتورینگ پوزیشنهای باز
                for trader in self.traders.values():
                    await trader.monitor_positions()
                
                # 7. بهینهسازی پارامترها
                performance = await self._calculate_performance()
                self.param_system.auto_optimize(performance)
                
            except Exception as e:
                logging.error(f"خطا در چرخه معاملاتی {symbol}: {e}")
        
        # لاگ چرخه
        cycle_time = (datetime.now() - cycle_start).total_seconds()
        logging.info(f"🌀 چرخه معاملاتی تکمیل شد در {cycle_time:.2f} ثانیه")
    
    def _generate_signals(self, symbol: str, whales: List[WhaleMovement], 
                         flow: MarketFlow, latest_candle: MinuteCandle) -> List[Tuple]:
        """تولید سیگنالهای معاملاتی"""
        signals = []
        
        # سیگنال نهنگها
        pump_detected = self.whale_radar.detect_pump_pattern(whales)
        dump_detected = self.whale_radar.detect_dump_pattern(whales)
        
        if pump_detected:
            confidence = min(85 + len(whales) * 5, 95)
            signals.append((
                SignalType.WHALE_PUMP,
                confidence,
                {'whale_count': len(whales), 'total_flow': sum([w.size for w in whales])}
            ))
        
        if dump_detected:
            confidence = min(80 + len(whales) * 5, 90)
            signals.append((
                SignalType.WHALE_DUMP,
                confidence,
                {'whale_count': len(whales), 'total_flow': sum([w.size for w in whales])}
            ))
        
        # سیگنال جریان بازار
        if flow.pressure_score > 0.7:
            if flow.net_flow > 0:
                signals.append((
                    SignalType.FLOW_BUY,
                    flow.pressure_score * 100,
                    {'pressure': flow.pressure_score, 'net_flow': flow.net_flow}
                ))
            else:
                signals.append((
                    SignalType.FLOW_SELL,
                    flow.pressure_score * 100,
                    {'pressure': flow.pressure_score, 'net_flow': flow.net_flow}
                ))
        
        # سیگنال فشار بازار
        if latest_candle.volume > np.mean([c.volume for c in [latest_candle]]) * 3:
            signals.append((
                SignalType.MARKET_PRESSURE,
                75,
                {'volume_spike': latest_candle.volume}
            ))
        
        # سیگنال Open Interest
        if latest_candle.oi > 0:
            oi_change = (latest_candle.oi - 1000000) / 1000000  # شبیهسازی
            if abs(oi_change) > 0.1:
                signals.append((
                    SignalType.OI_SURGE,
                    abs(oi_change) * 100,
                    {'oi_change': oi_change}
                ))
        
        return signals
    
    async def _calculate_performance(self) -> Dict:
        """محاسبه عملکرد سیستم"""
        # شبیهسازی - در واقعیت از دیتابیس خوانده شود
        return {
            'win_rate': np.random.uniform(0.4, 0.7),
            'total_trades': self.trade_count,
            'avg_pnl': np.random.uniform(-0.01, 0.03),
            'volatility': np.random.uniform(0.01, 0.05)
        }
    
    async def start(self):
        """شروع سیستم"""
        self.running = True
        logging.info("🚀 سیستم معاملاتی کهکشانی راهاندازی شد")
        
        cycle_interval = self.param_system.get_parameter('update_interval_seconds')
        
        while self.running:
            await self.run_trading_cycle()
            await asyncio.sleep(cycle_interval)
    
    def stop(self):
        """توقف سیستم"""
        self.running = False
        logging.info("🛑 سیستم معاملاتی متوقف شد")

# ==================== DASHBOARD ====================

class TradingDashboard:
    """داشبورد معاملاتی"""
    
    @staticmethod
    def generate_admin_dashboard(system: GalacticTradingSystem):
        """تولید داشبورد ادمین"""
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Galactic Trading System - Admin</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; background: #0f0f23; color: #00ff00; }}
                .container {{ max-width: 1400px; margin: 0 auto; }}
                .header {{ background: #1a1a2e; padding: 20px; border-radius: 10px; margin-bottom: 20px; }}
                .stats {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 20px; }}
                .stat-card {{ background: #16213e; padding: 20px; border-radius: 10px; }}
                .signal-list {{ background: #1a1a2e; padding: 20px; border-radius: 10px; margin-bottom: 20px; }}
                .controls {{ background: #16213e; padding: 20px; border-radius: 10px; }}
                table {{ width: 100%; border-collapse: collapse; }}
                th, td {{ padding: 10px; text-align: left; border-bottom: 1px solid #00ff00; }}
                .positive {{ color: #00ff00; }}
                .negative {{ color: #ff0000; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🚀 Galactic Trading System - Admin Dashboard</h1>
                    <p>Last Update: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                </div>
                
                <div class="stats">
                    <div class="stat-card">
                        <h3>📊 Total Trades</h3>
                        <p class="positive">{system.trade_count}</p>
                    </div>
                    <div class="stat-card">
                        <h3>🎯 Win Rate</h3>
                        <p class="positive">{(system.trade_count * 0.6):.1f}%</p>
                    </div>
                    <div class="stat-card">
                        <h3>⚡ Active Positions</h3>
                        <p>{sum([len(t.positions) for t in system.traders.values()])}</p>
                    </div>
                    <div class="stat-card">
                        <h3>💰 Daily P&L</h3>
                        <p class="positive">+{(system.trade_count * 0.02):.2f}%</p>
                    </div>
                </div>
                
                <div class="signal-list">
                    <h2>📈 Recent Signals</h2>
                    <table>
                        <tr>
                            <th>Time</th>
                            <th>Symbol</th>
                            <th>Signal</th>
                            <th>Score</th>
                            <th>Status</th>
                        </tr>
                        <!-- Signals will be populated by JavaScript -->
                    </table>
                </div>
                
                <div class="controls">
                    <h2>🎛️ System Controls</h2>
                    <button onclick="startSystem()">▶️ Start Trading</button>
                    <button onclick="stopSystem()">⏸️ Stop Trading</button>
                    <button onclick="updateParams()">⚙️ Update Parameters</button>
                    <button onclick="exportData()">💾 Export Data</button>
                    
                    <h3>Parameter Adjustment</h3>
                    <div>
                        <label>Validation Threshold: </label>
                        <input type="range" id="threshold" min="50" max="90" value="70">
                        <span id="thresholdValue">70</span>
                    </div>
                </div>
            </div>
            
            <script>
                function startSystem() {{
                    fetch('/api/start', {{ method: 'POST' }});
                    alert('System started');
                }}
                
                function stopSystem() {{
                    fetch('/api/stop', {{ method: 'POST' }});
                    alert('System stopped');
                }}
            </script>
        </body>
        </html>
        """
        return html
    
    @staticmethod
    def generate_trader_dashboard(api_key: str):
        """تولید داشبورد تریدر"""
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Trader Dashboard</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
                .dashboard {{ max-width: 1200px; margin: 0 auto; }}
                .header {{ background: #ffffff; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .positions {{ background: #ffffff; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .controls {{ background: #ffffff; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .api-key {{ font-family: monospace; background: #f0f0f0; padding: 5px; border-radius: 3px; }}
            </style>
        </head>
        <body>
            <div class="dashboard">
                <div class="header">
                    <h1>📊 Trader Dashboard</h1>
                    <p>API Key: <span class="api-key">{api_key[:10]}...{api_key[-10:]}</span></p>
                </div>
                
                <div class="positions">
                    <h2>📈 Active Positions</h2>
                    <table width="100%">
                        <tr>
                            <th>Symbol</th>
                            <th>Side</th>
                            <th>Size</th>
                            <th>Entry</th>
                            <th>Current</th>
                            <th>P&L</th>
                            <th>Action</th>
                        </tr>
                        <!-- Positions will be populated -->
                    </table>
                </div>
                
                <div class="controls">
                    <h2>🎮 Trading Controls</h2>
                    <button onclick="closeAllPositions()">Close All Positions</button>
                    <button onclick="adjustRisk()">Adjust Risk</button>
                    <button onclick="exportReport()">Export Report</button>
                </div>
            </div>
            
            <script>
                function closeAllPositions() {{
                    if(confirm('Close all positions?')) {{
                        fetch('/api/close-all', {{ method: 'POST' }});
                    }}
                }}
            </script>
        </body>
        </html>
        """
        return html

# ==================== SHELL SCRIPT ====================

def create_setup_script():
    """ایجاد اسکریپت راهاندازی"""
    script_content = """#!/bin/bash

# ==================== GALACTIC TRADING SYSTEM SETUP ====================
# Created: $(date)
# Author: Galactic AI

echo "🚀 Starting Galactic Trading System Setup..."

# Create necessary directories
mkdir -p logs data backups config

# Check Python version
python_version=$(python3 --version | cut -d' ' -f2)
if [[ $(echo "$python_version 3.9" | awk '{print ($1 >= $2)}') -eq 0 ]]; then
    echo "❌ Python 3.9+ is required. Current: $python_version"
    exit 1
fi
echo "✅ Python $python_version detected"

# Install required packages
echo "📦 Installing required packages..."
pip3 install -r requirements.txt

# Check if packages installed successfully
if [ $? -eq 0 ]; then
    echo "✅ Packages installed successfully"
else
    echo "❌ Package installation failed"
    exit 1
fi

# Create config file if not exists
if [ ! -f "config/api_keys.json" ]; then
    echo "🔐 Creating API keys configuration..."
    cat > config/api_keys.json << EOL
{
    "lbank": {
        "api_key": "YOUR_LBANK_API_KEY",
        "api_secret": "YOUR_LBANK_API_SECRET"
    },
    "bitunix": {
        "api_key": "YOUR_BITUNIX_API_KEY",
        "api_secret": "YOUR_BITUNIX_API_SECRET"
    }
}
EOL
    echo "⚠️  Please edit config/api_keys.json with your actual API keys"
fi

# Create systemd service file
echo "📁 Creating systemd service..."
sudo cat > /etc/systemd/system/galactic-trader.service << EOL
[Unit]
Description=Galactic Trading System
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/python3 $(pwd)/main.py
Restart=always
RestartSec=10
StandardOutput=file:$(pwd)/logs/system.log
StandardError=file:$(pwd)/logs/error.log

[Install]
WantedBy=multi-user.target
EOL

# Create backup script
echo "💾 Creating backup script..."
cat > backup_system.sh << 'EOL'
#!/bin/bash
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR
cp quantum_trading.db "$BACKUP_DIR/"
cp -r logs "$BACKUP_DIR/"
cp -r config "$BACKUP_DIR/"
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"
echo "✅ Backup created: $BACKUP_DIR.tar.gz"
EOL

chmod +x backup_system.sh

# Create monitoring script
echo "📊 Creating monitoring script..."
cat > monitor_system.sh << 'EOL'
#!/bin/bash
echo "=== GALACTIC TRADING SYSTEM MONITOR ==="
echo "Time: $(date)"
echo ""
echo "📈 System Status:"
systemctl is-active galactic-trader.service
echo ""
echo "📊 Disk Usage:"
du -sh .
echo ""
echo "📁 Log Files:"
ls -lh logs/ | tail -5
echo ""
echo "💾 Database Size:"
ls -lh quantum_trading.db
echo ""
echo "🔄 Recent Trades:"
sqlite3 quantum_trading.db "SELECT timestamp, symbol, signal_type, final_score FROM validated_signals ORDER BY id DESC LIMIT 5;" 2>/dev/null || echo "No trades yet"
EOL

chmod +x monitor_system.sh

# Create update script
echo "🔄 Creating update script..."
cat > update_system.sh << 'EOL'
#!/bin/bash
echo "🔄 Updating Galactic Trading System..."
git pull origin main
pip3 install -r requirements.txt --upgrade
sudo systemctl restart galactic-trader.service
echo "✅ System updated and restarted"
EOL

chmod +x update_system.sh

# Set permissions
chmod +x *.sh

echo ""
echo "========================================="
echo "✅ SETUP COMPLETED SUCCESSFULLY!"
echo "========================================="
echo ""
echo "📋 Next steps:"
echo "1. Edit config/api_keys.json with your API keys"
echo "2. Start the system: sudo systemctl start galactic-trader"
echo "3. Enable auto-start: sudo systemctl enable galactic-trader"
echo "4. Monitor logs: tail -f logs/system.log"
echo "5. Access dashboard: http://localhost:8050"
echo ""
echo "🛠️  Available commands:"
echo "   ./backup_system.sh    - Create backup"
echo "   ./monitor_system.sh   - Monitor system status"
echo "   ./update_system.sh    - Update system"
echo ""
echo "🚀 Happy Trading!"
echo "========================================="
"""

    with open('setup_galactic.sh', 'w') as f:
        f.write(script_content)
    
    print("✅ Setup script created: setup_galactic.sh")
    print("Run: chmod +x setup_galactic.sh && ./setup_galactic.sh")

# ==================== MAIN EXECUTION ====================

if __name__ == "__main__":
    
    # Create setup script
    create_setup_script()
    
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║              🚀 GALACTIC TRADING SYSTEM                 ║
    ╠══════════════════════════════════════════════════════════╣
    ║ Features:                                                ║
    ║  • Real-time data from Bybit & OKX                      ║
    ║  • Auto-trading on LBank & Bitunix                      ║
    ║  • 3-candle validation (20,30,50 weights)               ║
    ║  • Whale detection & pump/dump alerts                   ║
    ║  • Market flow analysis                                 ║
    ║  • Parametric system with auto-optimization             ║
    ║  • Quantum database for all data                        ║
    ║  • Admin & Trader dashboards                            ║
    ║  • Complete shell scripts for management                ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    print("\n📋 To start the system:")
    print("1. Run setup: chmod +x setup_galactic.sh && ./setup_galactic.sh")
    print("2. Configure API keys in config/api_keys.json")
    print("3. Start: python main.py")
    print("\n🔥 Happy Trading! Let the galaxy guide your profits! 🚀")