#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  🚀 سیستم معاملات فیوچرز - نسخه پیشرفته                  ║"
echo "║     شامل: Smart Money, Order Blocks, Liquidity Hunt      ║"
echo "║     ساخته شده با ❤️ برای برادران ایرانی                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}[1/6] ایجاد پوشه پروژه...${NC}"
mkdir -p crypto_futures
cd crypto_futures

echo -e "${BLUE}[2/6] ایجاد محیط مجازی...${NC}"
python3 -m venv venv
source venv/bin/activate

echo -e "${BLUE}[3/6] نصب پکیجها...${NC}"
pip install --upgrade pip

cat > requirements.txt << 'EOF'
flask==3.0.0
flask-socketio==5.3.6
flask-cors==4.0.0
sqlalchemy==2.0.23
pandas==2.1.3
numpy==1.26.2
ta==0.11.0
ccxt==4.1.89
apscheduler==3.10.4
eventlet==0.34.2
python-dotenv==1.0.0
EOF

pip install -r requirements.txt

echo -e "${BLUE}[4/6] ایجاد ساختار پوشهها...${NC}"
mkdir -p templates static/css static/js data

echo -e "${BLUE}[5/6] ایجاد فایلهای پروژه...${NC}"

# ═══════════════════════════════════════════════════════════════════════
# advanced_signals.py
# ═══════════════════════════════════════════════════════════════════════
cat > advanced_signals.py << 'ADVEOF'
"""
🔥 سیستم سیگنالدهی پیشرفته
شامل: Smart Money, Order Blocks, Liquidity Hunt, Divergence, Whale Detection
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from ta.trend import EMAIndicator, SMAIndicator
from ta.momentum import RSIIndicator
from ta.volatility import AverageTrueRange

class AdvancedSignalEngine:
    """موتور سیگنالدهی پیشرفته"""
    
    @staticmethod
    def detect_smart_money(df, volume_threshold=2.0):
        """تشخیص ورود و خروج پول هوشمند"""
        if len(df) < 30:
            return []
        
        df = df.copy()
        df['volume_sma'] = df['volume'].rolling(20).mean()
        df['volume_ratio'] = df['volume'] / df['volume_sma']
        df['price_change'] = df['close'].pct_change() * 100
        
        signals = []
        
        for i in range(20, len(df)):
            vol_ratio = df['volume_ratio'].iloc[i]
            price_change = abs(df['price_change'].iloc[i])
            
            if pd.isna(vol_ratio):
                continue
            
            # جمعآوری: حجم بالا، تغییر قیمت کم
            if vol_ratio > volume_threshold and price_change < 0.5:
                signals.append({
                    'index': i,
                    'type': 'SMART_MONEY_ACCUMULATION',
                    'signal': 'BUY',
                    'strength': min(vol_ratio * 30, 95),
                    'reason': f'💰 Smart Money Accumulation (Vol: {vol_ratio:.1f}x)',
                    'price': df['close'].iloc[i],
                    'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                })
            
            # توزیع: حجم بالا، قیمت بالا رفته
            elif vol_ratio > volume_threshold and price_change > 2:
                if df['close'].iloc[i] > df['close'].iloc[i-1]:
                    signals.append({
                        'index': i,
                        'type': 'SMART_MONEY_DISTRIBUTION',
                        'signal': 'SELL',
                        'strength': min(vol_ratio * 25, 90),
                        'reason': f'💰 Smart Money Distribution (Vol: {vol_ratio:.1f}x)',
                        'price': df['close'].iloc[i],
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                    })
        
        return signals[-5:] if signals else []
    
    @staticmethod
    def find_order_blocks(df, lookback=50):
        """یافتن Order Blocks"""
        if len(df) < 10:
            return []
        
        df = df.copy()
        order_blocks = []
        
        for i in range(3, len(df) - 1):
            try:
                # Bullish Order Block
                if (df['close'].iloc[i-1] < df['open'].iloc[i-1] and
                    df['close'].iloc[i] > df['open'].iloc[i] and
                    df['close'].iloc[i] > df['high'].iloc[i-1]):
                    
                    move_strength = ((df['close'].iloc[i] - df['low'].iloc[i-1]) / 
                                    df['low'].iloc[i-1]) * 100
                    
                    if move_strength > 0.5:
                        order_blocks.append({
                            'index': i,
                            'type': 'BULLISH_ORDER_BLOCK',
                            'signal': 'BUY',
                            'top': df['high'].iloc[i-1],
                            'bottom': df['low'].iloc[i-1],
                            'strength': min(move_strength * 20, 90),
                            'reason': f'📦 Bullish Order Block ({move_strength:.1f}% move)',
                            'price': df['close'].iloc[i],
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                        })
                
                # Bearish Order Block
                if (df['close'].iloc[i-1] > df['open'].iloc[i-1] and
                    df['close'].iloc[i] < df['open'].iloc[i] and
                    df['close'].iloc[i] < df['low'].iloc[i-1]):
                    
                    move_strength = ((df['high'].iloc[i-1] - df['close'].iloc[i]) / 
                                    df['high'].iloc[i-1]) * 100
                    
                    if move_strength > 0.5:
                        order_blocks.append({
                            'index': i,
                            'type': 'BEARISH_ORDER_BLOCK',
                            'signal': 'SELL',
                            'top': df['high'].iloc[i-1],
                            'bottom': df['low'].iloc[i-1],
                            'strength': min(move_strength * 20, 90),
                            'reason': f'📦 Bearish Order Block ({move_strength:.1f}% move)',
                            'price': df['close'].iloc[i],
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                        })
            except:
                continue
        
        return order_blocks[-5:] if order_blocks else []
    
    @staticmethod
    def detect_liquidity_hunt(df, lookback=20):
        """تشخیص شکار نقدینگی - بهترین نقطه ورود!"""
        if len(df) < lookback + 5:
            return []
        
        df = df.copy()
        signals = []
        
        for i in range(lookback, len(df)):
            try:
                window = df.iloc[i-lookback:i]
                current = df.iloc[i]
                
                prev_high = window['high'].max()
                prev_low = window['low'].min()
                
                # شکار نقدینگی پایین (Long Signal)
                if (current['low'] < prev_low and 
                    current['close'] > prev_low and
                    current['close'] > current['open']):
                    
                    hunt_depth = ((prev_low - current['low']) / prev_low) * 100
                    
                    signals.append({
                        'index': i,
                        'type': 'LIQUIDITY_GRAB_LOW',
                        'signal': 'BUY',
                        'strength': min(75 + hunt_depth * 10, 95),
                        'reason': f'🎯 Liquidity Hunt Below Support ({hunt_depth:.2f}%)',
                        'price': current['close'],
                        'stop_loss': current['low'] * 0.995,
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                    })
                
                # شکار نقدینگی بالا (Short Signal)
                if (current['high'] > prev_high and 
                    current['close'] < prev_high and
                    current['close'] < current['open']):
                    
                    hunt_depth = ((current['high'] - prev_high) / prev_high) * 100
                    
                    signals.append({
                        'index': i,
                        'type': 'LIQUIDITY_GRAB_HIGH',
                        'signal': 'SELL',
                        'strength': min(75 + hunt_depth * 10, 95),
                        'reason': f'🎯 Liquidity Hunt Above Resistance ({hunt_depth:.2f}%)',
                        'price': current['close'],
                        'stop_loss': current['high'] * 1.005,
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                    })
            except:
                continue
        
        return signals[-5:] if signals else []
    
    @staticmethod
    def find_divergences(df):
        """یافتن واگراییها"""
        if len(df) < 30:
            return []
        
        df = df.copy()
        df['rsi'] = RSIIndicator(df['close'], window=14).rsi()
        
        divergences = []
        lookback = 5
        
        for i in range(lookback * 2, len(df)):
            try:
                # واگرایی صعودی
                if (df['close'].iloc[i] < df['close'].iloc[i-lookback] and
                    df['rsi'].iloc[i] > df['rsi'].iloc[i-lookback] and
                    df['rsi'].iloc[i] < 40):
                    
                    divergences.append({
                        'index': i,
                        'type': 'BULLISH_DIVERGENCE',
                        'signal': 'BUY',
                        'strength': 85,
                        'reason': f'📈 RSI Bullish Divergence (RSI: {df["rsi"].iloc[i]:.1f})',
                        'price': df['close'].iloc[i],
                        'rsi': df['rsi'].iloc[i],
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                    })
                
                # واگرایی نزولی
                if (df['close'].iloc[i] > df['close'].iloc[i-lookback] and
                    df['rsi'].iloc[i] < df['rsi'].iloc[i-lookback] and
                    df['rsi'].iloc[i] > 60):
                    
                    divergences.append({
                        'index': i,
                        'type': 'BEARISH_DIVERGENCE',
                        'signal': 'SELL',
                        'strength': 85,
                        'reason': f'📉 RSI Bearish Divergence (RSI: {df["rsi"].iloc[i]:.1f})',
                        'price': df['close'].iloc[i],
                        'rsi': df['rsi'].iloc[i],
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                    })
            except:
                continue
        
        return divergences[-5:] if divergences else []
    
    @staticmethod
    def detect_whale_activity(df, std_multiplier=2.5):
        """تشخیص فعالیت نهنگها"""
        if len(df) < 60:
            return []
        
        df = df.copy()
        df['volume_mean'] = df['volume'].rolling(50).mean()
        df['volume_std'] = df['volume'].rolling(50).std()
        
        whale_signals = []
        
        for i in range(50, len(df)):
            try:
                if df['volume_std'].iloc[i] == 0 or pd.isna(df['volume_std'].iloc[i]):
                    continue
                
                zscore = (df['volume'].iloc[i] - df['volume_mean'].iloc[i]) / df['volume_std'].iloc[i]
                
                if zscore > std_multiplier:
                    price_change = ((df['close'].iloc[i] - df['open'].iloc[i]) / 
                                   df['open'].iloc[i]) * 100
                    
                    if price_change > 0.3:
                        whale_signals.append({
                            'index': i,
                            'type': 'WHALE_BUYING',
                            'signal': 'BUY',
                            'strength': min(65 + zscore * 8, 95),
                            'reason': f'🐋 Whale Buying Detected (Vol Z: {zscore:.1f})',
                            'price': df['close'].iloc[i],
                            'volume_zscore': round(zscore, 2),
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                        })
                    elif price_change < -0.3:
                        whale_signals.append({
                            'index': i,
                            'type': 'WHALE_SELLING',
                            'signal': 'SELL',
                            'strength': min(65 + zscore * 8, 95),
                            'reason': f'🐋 Whale Selling Detected (Vol Z: {zscore:.1f})',
                            'price': df['close'].iloc[i],
                            'volume_zscore': round(zscore, 2),
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else None
                        })
            except:
                continue
        
        return whale_signals[-5:] if whale_signals else []


class AdvancedPumpDumpDetector:
    """تشخیص پیشرفته پامپ و دامپ"""
    
    @staticmethod
    def detect_pump_starting(df, symbol):
        """تشخیص شروع پامپ"""
        if len(df) < 100:
            return []
        
        alerts = []
        
        try:
            recent_30 = df.tail(30)
            older_30 = df.tail(60).head(30)
            
            recent_volatility = recent_30['close'].std() / recent_30['close'].mean()
            older_volatility = older_30['close'].std() / older_30['close'].mean()
            
            recent_volume = recent_30['volume'].mean()
            older_volume = older_30['volume'].mean()
            
            # جمعآوری = نوسان کم + حجم کمی بیشتر
            if older_volatility > 0 and recent_volatility < older_volatility * 0.7:
                if older_volume > 0 and recent_volume > older_volume * 1.2:
                    
                    last_5 = df.tail(5)
                    resistance = df.tail(50)['high'].quantile(0.9)
                    
                    if last_5['close'].iloc[-1] > resistance:
                        avg_vol = df['volume'].tail(20).mean()
                        if avg_vol > 0:
                            volume_spike = last_5['volume'].iloc[-1] / avg_vol
                            
                            if volume_spike > 1.5:
                                alerts.append({
                                    'symbol': symbol,
                                    'alert_type': 'PUMP_STARTING',
                                    'signal': 'BUY',
                                    'confidence': min(70 + volume_spike * 5, 95),
                                    'strength': min(70 + volume_spike * 5, 95),
                                    'price': df['close'].iloc[-1],
                                    'resistance_broken': resistance,
                                    'volume_spike': round(volume_spike, 2),
                                    'reason': f'🚀 Pump Starting! Vol Spike: {volume_spike:.1f}x',
                                    'timestamp': datetime.utcnow()
                                })
        except:
            pass
        
        return alerts
    
    @staticmethod
    def detect_dump_warning(df, symbol):
        """هشدار دامپ"""
        if len(df) < 50:
            return []
        
        alerts = []
        
        try:
            df = df.copy()
            df['rsi'] = RSIIndicator(df['close'], window=14).rsi()
            
            latest = df.iloc[-1]
            conditions_met = 0
            reasons = []
            
            # RSI بالا
            if latest['rsi'] > 75:
                conditions_met += 1
                reasons.append(f"RSI: {latest['rsi']:.1f}")
            
            # سایه بالای بلند
            upper_wick = latest['high'] - max(latest['open'], latest['close'])
            body = abs(latest['close'] - latest['open'])
            
            if body > 0 and upper_wick > body * 2:
                conditions_met += 1
                reasons.append("Long Upper Wick")
            
            # حجم بالا با کندل نزولی
            volume_avg = df['volume'].tail(20).mean()
            if volume_avg > 0 and latest['volume'] > volume_avg * 1.5:
                if latest['close'] < latest['open']:
                    conditions_met += 1
                    reasons.append("High Vol Selling")
            
            if conditions_met >= 2:
                alerts.append({
                    'symbol': symbol,
                    'alert_type': 'DUMP_WARNING',
                    'signal': 'SELL',
                    'confidence': min(40 + conditions_met * 20, 90),
                    'strength': min(40 + conditions_met * 20, 90),
                    'price': latest['close'],
                    'rsi': latest['rsi'],
                    'reason': f'⚠️ Dump Warning! {" | ".join(reasons)}',
                    'timestamp': datetime.utcnow()
                })
        except:
            pass
        
        return alerts
    
    @staticmethod
    def detect_advanced_pump_dump(df, symbol, threshold=5, window=15):
        """تشخیص پامپ و دامپ پیشرفته"""
        if len(df) < window + 10:
            return []
        
        alerts = []
        
        try:
            recent = df.tail(window)
            
            start_price = recent['close'].iloc[0]
            end_price = recent['close'].iloc[-1]
            price_change = ((end_price - start_price) / start_price) * 100
            
            avg_volume = df['volume'].tail(100).mean()
            recent_volume = recent['volume'].mean()
            volume_change = ((recent_volume - avg_volume) / avg_volume) * 100 if avg_volume > 0 else 0
            
            # بررسی مومنتوم
            momentum = 0
            for i in range(1, len(recent)):
                if recent['close'].iloc[i] > recent['close'].iloc[i-1]:
                    momentum += 1
                else:
                    momentum -= 1
            
            # پامپ قوی
            if price_change >= threshold and volume_change > 50 and momentum > window * 0.5:
                alerts.append({
                    'symbol': symbol,
                    'alert_type': 'STRONG_PUMP',
                    'signal': 'BUY',
                    'price_change': round(price_change, 2),
                    'volume_change': round(volume_change, 2),
                    'momentum': momentum,
                    'strength': min(70 + price_change * 3, 95),
                    'price': end_price,
                    'reason': f'🚀 STRONG PUMP! +{price_change:.1f}% | Vol +{volume_change:.0f}%',
                    'timestamp': datetime.utcnow()
                })
            
            # دامپ قوی
            elif price_change <= -threshold and volume_change > 50 and momentum < -window * 0.5:
                alerts.append({
                    'symbol': symbol,
                    'alert_type': 'STRONG_DUMP',
                    'signal': 'SELL',
                    'price_change': round(price_change, 2),
                    'volume_change': round(volume_change, 2),
                    'momentum': momentum,
                    'strength': min(70 + abs(price_change) * 3, 95),
                    'price': end_price,
                    'reason': f'📉 STRONG DUMP! {price_change:.1f}% | Vol +{volume_change:.0f}%',
                    'timestamp': datetime.utcnow()
                })
        except:
            pass
        
        return alerts


class UltimateSignalGenerator:
    """ترکیب همه روشها برای بهترین سیگنال"""
    
    def __init__(self):
        self.engine = AdvancedSignalEngine()
        self.pump_dump = AdvancedPumpDumpDetector()
    
    def analyze(self, df, symbol):
        """تحلیل کامل و تولید سیگنال نهایی"""
        all_signals = []
        
        try:
            # جمعآوری همه سیگنالها
            smart_money = self.engine.detect_smart_money(df)
            order_blocks = self.engine.find_order_blocks(df)
            liquidity = self.engine.detect_liquidity_hunt(df)
            divergence = self.engine.find_divergences(df)
            whale = self.engine.detect_whale_activity(df)
            pump = self.pump_dump.detect_pump_starting(df, symbol)
            dump = self.pump_dump.detect_dump_warning(df, symbol)
            pump_dump = self.pump_dump.detect_advanced_pump_dump(df, symbol)
            
            # اضافه کردن symbol به همه
            for sig_list in [smart_money, order_blocks, liquidity, divergence, whale]:
                for sig in sig_list:
                    sig['symbol'] = symbol
                    all_signals.append(sig)
            
            all_signals.extend(pump)
            all_signals.extend(dump)
            all_signals.extend(pump_dump)
            
        except Exception as e:
            print(f"خطا در تحلیل {symbol}: {e}")
        
        return all_signals
    
    def get_best_signals(self, df, symbol, top_n=3):
        """بهترین سیگنالها"""
        all_signals = self.analyze(df, symbol)
        
        # مرتبسازی بر اساس قدرت
        all_signals.sort(key=lambda x: x.get('strength', 0), reverse=True)
        
        return all_signals[:top_n]
    
    def get_combined_score(self, df, symbol):
        """امتیاز ترکیبی"""
        signals = self.analyze(df, symbol)
        
        buy_score = 0
        sell_score = 0
        buy_reasons = []
        sell_reasons = []
        
        weights = {
            'LIQUIDITY_GRAB': 1.5,
            'SMART_MONEY': 1.4,
            'DIVERGENCE': 1.3,
            'WHALE': 1.2,
            'ORDER_BLOCK': 1.1,
            'PUMP': 1.0,
            'DUMP': 1.0
        }
        
        for sig in signals:
            sig_type = sig.get('type', '')
            strength = sig.get('strength', 50)
            
            weight = 1.0
            for key, w in weights.items():
                if key in sig_type:
                    weight = w
                    break
            
            if sig.get('signal') == 'BUY':
                buy_score += strength * weight
                buy_reasons.append(sig.get('reason', sig_type))
            elif sig.get('signal') == 'SELL':
                sell_score += strength * weight
                sell_reasons.append(sig.get('reason', sig_type))
        
        if buy_score > sell_score and buy_score > 80:
            return {
                'symbol': symbol,
                'recommendation': 'STRONG_BUY',
                'score': round(buy_score, 1),
                'confidence': min(buy_score / 3, 95),
                'reasons': buy_reasons[:5],
                'price': df['close'].iloc[-1] if len(df) > 0 else 0
            }
        elif sell_score > buy_score and sell_score > 80:
            return {
                'symbol': symbol,
                'recommendation': 'STRONG_SELL',
                'score': round(sell_score, 1),
                'confidence': min(sell_score / 3, 95),
                'reasons': sell_reasons[:5],
                'price': df['close'].iloc[-1] if len(df) > 0 else 0
            }
        else:
            return {
                'symbol': symbol,
                'recommendation': 'NEUTRAL',
                'buy_score': round(buy_score, 1),
                'sell_score': round(sell_score, 1)
            }

# نمونه گلوبال
ultimate_generator = UltimateSignalGenerator()
ADVEOF

# ═══════════════════════════════════════════════════════════════════════
# database_extended.py (آپدیت شده)
# ═══════════════════════════════════════════════════════════════════════
cat > database_extended.py << 'DBEOF'
"""دیتابیس پیشرفته با پشتیبانی از سیگنالهای جدید"""

from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Boolean, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime, timedelta

Base = declarative_base()

class CryptoPrice(Base):
    __tablename__ = 'crypto_prices'
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), index=True)
    price = Column(Float)
    open_price = Column(Float)
    high_price = Column(Float)
    low_price = Column(Float)
    close_price = Column(Float)
    volume = Column(Float)
    quote_volume = Column(Float)
    price_change = Column(Float)
    price_change_percent = Column(Float)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)
    timeframe = Column(String(10), default='1m')

class SignalRecord(Base):
    __tablename__ = 'signal_records'
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), index=True)
    signal_type = Column(String(10))
    signal_source = Column(String(50))
    signal_category = Column(String(30))  # BASIC, ADVANCED, PUMP_DUMP
    strength = Column(Float)
    reason = Column(Text)
    entry_price = Column(Float)
    target_percent = Column(Float, default=2.0)
    stop_percent = Column(Float, default=1.0)
    target_price = Column(Float)
    stop_price = Column(Float)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    validated_at = Column(DateTime, nullable=True)
    expires_at = Column(DateTime)
    status = Column(String(20), default='pending')
    result = Column(String(20), default='unknown')
    exit_price = Column(Float, nullable=True)
    profit_percent = Column(Float, nullable=True)
    max_profit_percent = Column(Float, nullable=True)
    max_loss_percent = Column(Float, nullable=True)
    validation_note = Column(Text, nullable=True)
    timeframe = Column(String(10), default='1m')
    # فیلدهای جدید برای سیگنالهای پیشرفته
    is_smart_money = Column(Boolean, default=False)
    is_order_block = Column(Boolean, default=False)
    is_liquidity_hunt = Column(Boolean, default=False)
    is_divergence = Column(Boolean, default=False)
    is_whale = Column(Boolean, default=False)
    is_pump_dump = Column(Boolean, default=False)
    rsi_value = Column(Float, nullable=True)
    volume_zscore = Column(Float, nullable=True)

class PumpDumpRecord(Base):
    __tablename__ = 'pump_dump_records'
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), index=True)
    alert_type = Column(String(20))
    price_at_alert = Column(Float)
    price_change_percent = Column(Float)
    volume_change_percent = Column(Float)
    momentum = Column(Integer, nullable=True)
    time_period = Column(String(20))
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    validated_at = Column(DateTime, nullable=True)
    price_after_5min = Column(Float, nullable=True)
    price_after_15min = Column(Float, nullable=True)
    price_after_30min = Column(Float, nullable=True)
    continued = Column(Boolean, nullable=True)
    reversal_percent = Column(Float, nullable=True)
    max_continuation = Column(Float, nullable=True)
    status = Column(String(20), default='pending')
    result = Column(String(20), default='unknown')

class AdvancedSignalRecord(Base):
    """جدول مخصوص سیگنالهای پیشرفته"""
    __tablename__ = 'advanced_signals'
    id = Column(Integer, primary_key=True)
    symbol = Column(String(20), index=True)
    signal_type = Column(String(50))  # SMART_MONEY, ORDER_BLOCK, etc.
    direction = Column(String(10))  # BUY, SELL
    strength = Column(Float)
    reason = Column(Text)
    price = Column(Float)
    stop_loss = Column(Float, nullable=True)
    take_profit = Column(Float, nullable=True)
    volume_zscore = Column(Float, nullable=True)
    rsi = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    status = Column(String(20), default='pending')
    result = Column(String(20), default='unknown')
    profit_percent = Column(Float, nullable=True)
    validated_at = Column(DateTime, nullable=True)

class SignalAccuracy(Base):
    __tablename__ = 'signal_accuracy'
    id = Column(Integer, primary_key=True)
    period = Column(String(20))
    period_start = Column(DateTime, index=True)
    period_end = Column(DateTime)
    total_signals = Column(Integer, default=0)
    successful_signals = Column(Integer, default=0)
    failed_signals = Column(Integer, default=0)
    pending_signals = Column(Integer, default=0)
    success_rate = Column(Float, default=0.0)
    # آمار پیشرفته
    smart_money_total = Column(Integer, default=0)
    smart_money_success = Column(Integer, default=0)
    order_block_total = Column(Integer, default=0)
    order_block_success = Column(Integer, default=0)
    liquidity_total = Column(Integer, default=0)
    liquidity_success = Column(Integer, default=0)
    divergence_total = Column(Integer, default=0)
    divergence_success = Column(Integer, default=0)
    whale_total = Column(Integer, default=0)
    whale_success = Column(Integer, default=0)
    avg_profit_percent = Column(Float, default=0.0)
    calculated_at = Column(DateTime, default=datetime.utcnow)

class Database:
    def __init__(self, db_url='sqlite:///crypto_futures.db'):
        self.engine = create_engine(db_url, echo=False)
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine)
    
    def get_session(self):
        return self.Session()
    
    def save_price(self, data):
        session = self.Session()
        try:
            price = CryptoPrice(**data)
            session.add(price)
            session.commit()
            return price.id
        except Exception as e:
            session.rollback()
        finally:
            session.close()
    
    def save_signal(self, signal_data):
        session = self.Session()
        try:
            entry_price = signal_data.get('price', 0)
            target_pct = signal_data.get('target_percent', 2.0)
            stop_pct = signal_data.get('stop_percent', 1.0)
            
            if signal_data.get('signal_type') == 'BUY' or signal_data.get('signal') == 'BUY':
                target_price = entry_price * (1 + target_pct / 100)
                stop_price = entry_price * (1 - stop_pct / 100)
                sig_type = 'BUY'
            else:
                target_price = entry_price * (1 - target_pct / 100)
                stop_price = entry_price * (1 + stop_pct / 100)
                sig_type = 'SELL'
            
            sig_source = signal_data.get('signal_source', signal_data.get('type', 'MIXED'))
            
            record = SignalRecord(
                symbol=signal_data.get('symbol'),
                signal_type=sig_type,
                signal_source=sig_source,
                signal_category=self._get_category(sig_source),
                strength=signal_data.get('strength', 50),
                reason=signal_data.get('reason', ''),
                entry_price=entry_price,
                target_percent=target_pct,
                stop_percent=stop_pct,
                target_price=target_price,
                stop_price=stop_price,
                expires_at=datetime.utcnow() + timedelta(hours=1),
                is_smart_money='SMART_MONEY' in sig_source,
                is_order_block='ORDER_BLOCK' in sig_source,
                is_liquidity_hunt='LIQUIDITY' in sig_source,
                is_divergence='DIVERGENCE' in sig_source,
                is_whale='WHALE' in sig_source,
                is_pump_dump='PUMP' in sig_source or 'DUMP' in sig_source,
                rsi_value=signal_data.get('rsi'),
                volume_zscore=signal_data.get('volume_zscore')
            )
            
            session.add(record)
            session.commit()
            return record.id
        except Exception as e:
            session.rollback()
            print(f"خطا در ذخیره سیگنال: {e}")
        finally:
            session.close()
    
    def save_advanced_signal(self, signal_data):
        session = self.Session()
        try:
            record = AdvancedSignalRecord(
                symbol=signal_data.get('symbol'),
                signal_type=signal_data.get('type', ''),
                direction=signal_data.get('signal', ''),
                strength=signal_data.get('strength', 50),
                reason=signal_data.get('reason', ''),
                price=signal_data.get('price', 0),
                stop_loss=signal_data.get('stop_loss'),
                take_profit=signal_data.get('take_profit'),
                volume_zscore=signal_data.get('volume_zscore'),
                rsi=signal_data.get('rsi')
            )
            session.add(record)
            session.commit()
            return record.id
        except Exception as e:
            session.rollback()
        finally:
            session.close()
    
    def save_pump_dump(self, alert_data):
        session = self.Session()
        try:
            record = PumpDumpRecord(
                symbol=alert_data.get('symbol'),
                alert_type=alert_data.get('alert_type'),
                price_at_alert=alert_data.get('price'),
                price_change_percent=alert_data.get('price_change'),
                volume_change_percent=alert_data.get('volume_change'),
                momentum=alert_data.get('momentum'),
                time_period=alert_data.get('time_period', '15m')
            )
            session.add(record)
            session.commit()
            return record.id
        except Exception as e:
            session.rollback()
        finally:
            session.close()
    
    def _get_category(self, source):
        if any(x in source for x in ['SMART_MONEY', 'ORDER_BLOCK', 'LIQUIDITY', 'DIVERGENCE', 'WHALE']):
            return 'ADVANCED'
        elif any(x in source for x in ['PUMP', 'DUMP']):
            return 'PUMP_DUMP'
        return 'BASIC'
    
    def get_pending_signals(self, min_age_minutes=3):
        session = self.Session()
        try:
            cutoff = datetime.utcnow() - timedelta(minutes=min_age_minutes)
            signals = session.query(SignalRecord).filter(
                SignalRecord.status == 'pending',
                SignalRecord.created_at <= cutoff,
                SignalRecord.expires_at > datetime.utcnow()
            ).all()
            return signals
        finally:
            session.close()
    
    def get_pending_pump_dumps(self, min_age_minutes=5):
        session = self.Session()
        try:
            cutoff = datetime.utcnow() - timedelta(minutes=min_age_minutes)
            alerts = session.query(PumpDumpRecord).filter(
                PumpDumpRecord.status == 'pending',
                PumpDumpRecord.created_at <= cutoff
            ).all()
            return alerts
        finally:
            session.close()
    
    def update_signal_result(self, signal_id, result_data):
        session = self.Session()
        try:
            signal = session.query(SignalRecord).filter(SignalRecord.id == signal_id).first()
            if signal:
                signal.status = result_data.get('status', 'validated')
                signal.result = result_data.get('result', 'unknown')
                signal.exit_price = result_data.get('exit_price')
                signal.profit_percent = result_data.get('profit_percent')
                signal.max_profit_percent = result_data.get('max_profit')
                signal.max_loss_percent = result_data.get('max_loss')
                signal.validated_at = datetime.utcnow()
                signal.validation_note = result_data.get('note', '')
                session.commit()
        finally:
            session.close()
    
    def update_pump_dump_result(self, alert_id, result_data):
        session = self.Session()
        try:
            alert = session.query(PumpDumpRecord).filter(PumpDumpRecord.id == alert_id).first()
            if alert:
                for key, value in result_data.items():
                    if hasattr(alert, key):
                        setattr(alert, key, value)
                alert.validated_at = datetime.utcnow()
                session.commit()
        finally:
            session.close()
    
    def get_accuracy_stats(self, hours=24):
        session = self.Session()
        try:
            from sqlalchemy import func
            cutoff = datetime.utcnow() - timedelta(hours=hours)
            
            total = session.query(SignalRecord).filter(SignalRecord.created_at >= cutoff).count()
            successful = session.query(SignalRecord).filter(
                SignalRecord.created_at >= cutoff,
                SignalRecord.result == 'success'
            ).count()
            failed = session.query(SignalRecord).filter(
                SignalRecord.created_at >= cutoff,
                SignalRecord.result == 'failure'
            ).count()
            pending = session.query(SignalRecord).filter(
                SignalRecord.created_at >= cutoff,
                SignalRecord.status == 'pending'
            ).count()
            
            # آمار پیشرفته
            advanced_stats = {}
            for field, name in [
                ('is_smart_money', 'smart_money'),
                ('is_order_block', 'order_block'),
                ('is_liquidity_hunt', 'liquidity'),
                ('is_divergence', 'divergence'),
                ('is_whale', 'whale')
            ]:
                field_total = session.query(SignalRecord).filter(
                    SignalRecord.created_at >= cutoff,
                    getattr(SignalRecord, field) == True
                ).count()
                field_success = session.query(SignalRecord).filter(
                    SignalRecord.created_at >= cutoff,
                    getattr(SignalRecord, field) == True,
                    SignalRecord.result == 'success'
                ).count()
                advanced_stats[name] = {
                    'total': field_total,
                    'success': field_success,
                    'rate': round((field_success / field_total * 100) if field_total > 0 else 0, 2)
                }
            
            avg_profit = session.query(func.avg(SignalRecord.profit_percent)).filter(
                SignalRecord.created_at >= cutoff,
                SignalRecord.result == 'success'
            ).scalar() or 0
            
            return {
                'period_hours': hours,
                'total_signals': total,
                'successful': successful,
                'failed': failed,
                'pending': pending,
                'success_rate': round((successful / total * 100) if total > 0 else 0, 2),
                'failure_rate': round((failed / total * 100) if total > 0 else 0, 2),
                'advanced': advanced_stats,
                'avg_profit': round(avg_profit, 2),
                'calculated_at': datetime.utcnow().isoformat()
            }
        finally:
            session.close()
    
    def get_signal_history(self, limit=100, symbol=None, category=None):
        session = self.Session()
        try:
            query = session.query(SignalRecord)
            if symbol:
                query = query.filter(SignalRecord.symbol == symbol)
            if category:
                query = query.filter(SignalRecord.signal_category == category)
            
            signals = query.order_by(SignalRecord.created_at.desc()).limit(limit).all()
            
            return [{
                'id': s.id,
                'symbol': s.symbol,
                'signal_type': s.signal_type,
                'signal_source': s.signal_source,
                'category': s.signal_category,
                'strength': s.strength,
                'reason': s.reason,
                'entry_price': s.entry_price,
                'exit_price': s.exit_price,
                'profit_percent': s.profit_percent,
                'status': s.status,
                'result': s.result,
                'created_at': s.created_at.isoformat() if s.created_at else None,
                'is_advanced': s.signal_category == 'ADVANCED'
            } for s in signals]
        finally:
            session.close()
    
    def get_pump_dump_history(self, limit=50):
        session = self.Session()
        try:
            alerts = session.query(PumpDumpRecord).order_by(
                PumpDumpRecord.created_at.desc()
            ).limit(limit).all()
            
            return [{
                'id': a.id,
                'symbol': a.symbol,
                'alert_type': a.alert_type,
                'price_at_alert': a.price_at_alert,
                'price_change': a.price_change_percent,
                'volume_change': a.volume_change_percent,
                'momentum': a.momentum,
                'continued': a.continued,
                'status': a.status,
                'result': a.result,
                'created_at': a.created_at.isoformat() if a.created_at else None
            } for a in alerts]
        finally:
            session.close()
    
    def get_latest_prices(self, limit=250):
        session = self.Session()
        try:
            from sqlalchemy import func
            subquery = session.query(
                CryptoPrice.symbol,
                func.max(CryptoPrice.id).label('max_id')
            ).group_by(CryptoPrice.symbol).subquery()
            
            prices = session.query(CryptoPrice).join(
                subquery,
                (CryptoPrice.symbol == subquery.c.symbol) & 
                (CryptoPrice.id == subquery.c.max_id)
            ).limit(limit).all()
            
            return [{
                'symbol': p.symbol,
                'price': p.price,
                'price_change_percent': p.price_change_percent,
                'volume': p.volume,
                'quote_volume': p.quote_volume
            } for p in prices]
        finally:
            session.close()

db = Database()
DBEOF

# ═══════════════════════════════════════════════════════════════════════
# data_fetcher.py
# ═══════════════════════════════════════════════════════════════════════
cat > data_fetcher.py << 'FETCHEOF'
import ccxt
import pandas as pd
from datetime import datetime

class DataFetcher:
    SOURCES = {
        'kucoin': 'کوکوین ⭐',
        'bybit': 'بایبیت',
        'okx': 'OKX',
        'mexc': 'MEXC',
        'gateio': 'Gate.io'
    }
    
    def __init__(self, source='kucoin'):
        self.source = source
        self.exchange = None
        self._init_exchange()
    
    def _init_exchange(self):
        try:
            exchanges = {
                'kucoin': lambda: ccxt.kucoinfutures({'enableRateLimit': True, 'options': {'defaultType': 'swap'}}),
                'bybit': lambda: ccxt.bybit({'enableRateLimit': True, 'options': {'defaultType': 'linear'}}),
                'okx': lambda: ccxt.okx({'enableRateLimit': True, 'options': {'defaultType': 'swap'}}),
                'mexc': lambda: ccxt.mexc({'enableRateLimit': True, 'options': {'defaultType': 'swap'}}),
                'gateio': lambda: ccxt.gateio({'enableRateLimit': True, 'options': {'defaultType': 'swap'}})
            }
            self.exchange = exchanges.get(self.source, exchanges['kucoin'])()
        except Exception as e:
            print(f"خطا: {e}")
    
    def get_futures_symbols(self, limit=250):
        try:
            self.exchange.load_markets()
            symbols = [s for s, m in self.exchange.markets.items() 
                      if (m.get('swap') or m.get('future') or m.get('linear')) 
                      and 'USDT' in s and m.get('active', True)]
            return symbols[:limit]
        except:
            return []
    
    def get_ticker(self, symbol):
        try:
            ticker = self.exchange.fetch_ticker(symbol)
            return {
                'symbol': symbol.replace('/', '').replace(':USDT', '').replace('-', ''),
                'price': ticker.get('last', 0),
                'open_price': ticker.get('open', ticker.get('last', 0)),
                'high_price': ticker.get('high', ticker.get('last', 0)),
                'low_price': ticker.get('low', ticker.get('last', 0)),
                'close_price': ticker.get('last', 0),
                'volume': ticker.get('baseVolume', 0) or 0,
                'quote_volume': ticker.get('quoteVolume', 0) or 0,
                'price_change': ticker.get('change', 0) or 0,
                'price_change_percent': ticker.get('percentage', 0) or 0,
                'timestamp': datetime.utcnow()
            }
        except:
            return None
    
    def get_all_tickers(self):
        try:
            tickers = self.exchange.fetch_tickers()
            results = []
            for symbol, ticker in tickers.items():
                if 'USDT' in symbol and (ticker.get('last') or 0) > 0:
                    results.append({
                        'symbol': symbol.replace('/', '').replace(':USDT', '').replace('-', ''),
                        'price': ticker['last'],
                        'open_price': ticker.get('open', ticker['last']) or ticker['last'],
                        'high_price': ticker.get('high', ticker['last']) or ticker['last'],
                        'low_price': ticker.get('low', ticker['last']) or ticker['last'],
                        'close_price': ticker['last'],
                        'volume': ticker.get('baseVolume', 0) or 0,
                        'quote_volume': ticker.get('quoteVolume', 0) or 0,
                        'price_change': ticker.get('change', 0) or 0,
                        'price_change_percent': ticker.get('percentage', 0) or 0,
                        'timestamp': datetime.utcnow()
                    })
            results.sort(key=lambda x: x.get('quote_volume', 0) or 0, reverse=True)
            return results[:250]
        except:
            return []
    
    def get_ohlcv(self, symbol, timeframe='1m', limit=500):
        try:
            ohlcv = self.exchange.fetch_ohlcv(symbol, timeframe, limit=limit)
            if not ohlcv:
                return pd.DataFrame()
            df = pd.DataFrame(ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
            df['symbol'] = symbol.replace('/', '').replace(':USDT', '').replace('-', '')
            return df
        except:
            return pd.DataFrame()
    
    def switch_source(self, new_source):
        if new_source in self.SOURCES:
            self.source = new_source
            self._init_exchange()
            return True
        return False
    
    def test_connection(self):
        try:
            self.exchange.load_markets()
            return True
        except:
            return False
FETCHEOF

# ═══════════════════════════════════════════════════════════════════════
# indicators.py
# ═══════════════════════════════════════════════════════════════════════
cat > indicators.py << 'INDEOF'
import pandas as pd
import numpy as np
from ta.trend import MACD, EMAIndicator, SMAIndicator
from ta.momentum import RSIIndicator, StochasticOscillator
from ta.volatility import BollingerBands, AverageTrueRange

class TechnicalIndicators:
    @staticmethod
    def calculate_all(df):
        if len(df) < 100:
            return df
        df = df.copy()
        df['ma_7'] = SMAIndicator(df['close'], window=7).sma_indicator()
        df['ma_25'] = SMAIndicator(df['close'], window=25).sma_indicator()
        df['ma_99'] = SMAIndicator(df['close'], window=99).sma_indicator()
        df['ema_7'] = EMAIndicator(df['close'], window=7).ema_indicator()
        df['ema_25'] = EMAIndicator(df['close'], window=25).ema_indicator()
        df['ema_99'] = EMAIndicator(df['close'], window=99).ema_indicator()
        df['rsi'] = RSIIndicator(df['close'], window=14).rsi()
        macd = MACD(df['close'])
        df['macd'] = macd.macd()
        df['macd_signal'] = macd.macd_signal()
        df['macd_histogram'] = macd.macd_diff()
        bb = BollingerBands(df['close'], window=20)
        df['bb_upper'] = bb.bollinger_hband()
        df['bb_middle'] = bb.bollinger_mavg()
        df['bb_lower'] = bb.bollinger_lband()
        df['atr'] = AverageTrueRange(df['high'], df['low'], df['close'], window=14).average_true_range()
        df['volume_sma'] = SMAIndicator(df['volume'], window=20).sma_indicator()
        stoch = StochasticOscillator(df['high'], df['low'], df['close'])
        df['stoch_k'] = stoch.stoch()
        df['stoch_d'] = stoch.stoch_signal()
        return df
    
    @staticmethod
    def calculate_ut_bot(df, key_value=1, atr_period=10):
        if len(df) < atr_period + 5:
            return df
        df = df.copy()
        df['xATR'] = AverageTrueRange(df['high'], df['low'], df['close'], window=atr_period).average_true_range()
        df['nLoss'] = key_value * df['xATR']
        df['xATRTrailingStop'] = 0.0
        for i in range(1, len(df)):
            close_now = df['close'].iloc[i]
            close_prev = df['close'].iloc[i-1]
            atr_stop_prev = df['xATRTrailingStop'].iloc[i-1]
            n_loss = df['nLoss'].iloc[i]
            if close_now > atr_stop_prev and close_prev > atr_stop_prev:
                df.iloc[i, df.columns.get_loc('xATRTrailingStop')] = max(atr_stop_prev, close_now - n_loss)
            elif close_now < atr_stop_prev and close_prev < atr_stop_prev:
                df.iloc[i, df.columns.get_loc('xATRTrailingStop')] = min(atr_stop_prev, close_now + n_loss)
            elif close_now > atr_stop_prev:
                df.iloc[i, df.columns.get_loc('xATRTrailingStop')] = close_now - n_loss
            else:
                df.iloc[i, df.columns.get_loc('xATRTrailingStop')] = close_now + n_loss
        df['pos'] = 0
        for i in range(1, len(df)):
            close_now = df['close'].iloc[i]
            close_prev = df['close'].iloc[i-1]
            atr_stop_prev = df['xATRTrailingStop'].iloc[i-1]
            if close_prev < atr_stop_prev and close_now > atr_stop_prev:
                df.iloc[i, df.columns.get_loc('pos')] = 1
            elif close_prev > atr_stop_prev and close_now < atr_stop_prev:
                df.iloc[i, df.columns.get_loc('pos')] = -1
            else:
                df.iloc[i, df.columns.get_loc('pos')] = df['pos'].iloc[i-1]
        df['ut_buy'] = (df['pos'] == 1) & (df['pos'].shift(1) != 1)
        df['ut_sell'] = (df['pos'] == -1) & (df['pos'].shift(1) != -1)
        return df
    
    @staticmethod
    def find_ma_crossovers(df):
        crossovers = []
        if 'ma_7' not in df.columns or 'ma_25' not in df.columns:
            return crossovers
        for i in range(1, len(df)):
            if df['ma_7'].iloc[i-1] < df['ma_25'].iloc[i-1] and df['ma_7'].iloc[i] > df['ma_25'].iloc[i]:
                crossovers.append({'index': i, 'type': 'MA_GOLDEN', 'signal': 'BUY', 'price': df['close'].iloc[i]})
            if df['ma_7'].iloc[i-1] > df['ma_25'].iloc[i-1] and df['ma_7'].iloc[i] < df['ma_25'].iloc[i]:
                crossovers.append({'index': i, 'type': 'MA_DEATH', 'signal': 'SELL', 'price': df['close'].iloc[i]})
        return crossovers
    
    @staticmethod
    def find_ema_crossovers(df):
        crossovers = []
        if 'ema_7' not in df.columns or 'ema_25' not in df.columns:
            return crossovers
        for i in range(1, len(df)):
            if df['ema_7'].iloc[i-1] < df['ema_25'].iloc[i-1] and df['ema_7'].iloc[i] > df['ema_25'].iloc[i]:
                crossovers.append({'index': i, 'type': 'EMA_GOLDEN', 'signal': 'BUY', 'price': df['close'].iloc[i]})
            if df['ema_7'].iloc[i-1] > df['ema_25'].iloc[i-1] and df['ema_7'].iloc[i] < df['ema_25'].iloc[i]:
                crossovers.append({'index': i, 'type': 'EMA_DEATH', 'signal': 'SELL', 'price': df['close'].iloc[i]})
        return crossovers
INDEOF

# ═══════════════════════════════════════════════════════════════════════
# signals.py
# ═══════════════════════════════════════════════════════════════════════
cat > signals.py << 'SIGEOF'
import pandas as pd
from datetime import datetime

class SignalGenerator:
    @staticmethod
    def analyze_for_signals(df, symbol):
        signals = []
        if len(df) < 100:
            return signals
        latest = df.iloc[-1]
        prev = df.iloc[-2]
        strength = 0
        reasons = []
        signal_type = None
        
        rsi = latest.get('rsi', 50)
        if rsi < 30:
            strength += 25
            reasons.append(f'RSI Oversold ({rsi:.1f})')
            signal_type = 'BUY'
        elif rsi > 70:
            strength += 25
            reasons.append(f'RSI Overbought ({rsi:.1f})')
            signal_type = 'SELL'
        
        macd = latest.get('macd', 0)
        macd_signal = latest.get('macd_signal', 0)
        prev_macd = prev.get('macd', 0)
        prev_macd_signal = prev.get('macd_signal', 0)
        if prev_macd < prev_macd_signal and macd > macd_signal:
            strength += 30
            reasons.append('MACD Bullish Cross')
            if signal_type != 'SELL':
                signal_type = 'BUY'
        elif prev_macd > prev_macd_signal and macd < macd_signal:
            strength += 30
            reasons.append('MACD Bearish Cross')
            if signal_type != 'BUY':
                signal_type = 'SELL'
        
        ma_7 = latest.get('ma_7', 0)
        ma_25 = latest.get('ma_25', 0)
        prev_ma_7 = prev.get('ma_7', 0)
        prev_ma_25 = prev.get('ma_25', 0)
        if prev_ma_7 < prev_ma_25 and ma_7 > ma_25:
            strength += 25
            reasons.append('MA Golden Cross')
            if signal_type != 'SELL':
                signal_type = 'BUY'
        elif prev_ma_7 > prev_ma_25 and ma_7 < ma_25:
            strength += 25
            reasons.append('MA Death Cross')
            if signal_type != 'BUY':
                signal_type = 'SELL'
        
        ema_7 = latest.get('ema_7', 0)
        ema_25 = latest.get('ema_25', 0)
        prev_ema_7 = prev.get('ema_7', 0)
        prev_ema_25 = prev.get('ema_25', 0)
        if prev_ema_7 < prev_ema_25 and ema_7 > ema_25:
            strength += 25
            reasons.append('EMA Golden Cross')
            if signal_type != 'SELL':
                signal_type = 'BUY'
        elif prev_ema_7 > prev_ema_25 and ema_7 < ema_25:
            strength += 25
            reasons.append('EMA Death Cross')
            if signal_type != 'BUY':
                signal_type = 'SELL'
        
        close = latest.get('close', 0)
        bb_lower = latest.get('bb_lower', 0)
        bb_upper = latest.get('bb_upper', 0)
        if bb_lower > 0 and close < bb_lower:
            strength += 15
            reasons.append('Below Bollinger Lower')
            if signal_type != 'SELL':
                signal_type = 'BUY'
        elif bb_upper > 0 and close > bb_upper:
            strength += 15
            reasons.append('Above Bollinger Upper')
            if signal_type != 'BUY':
                signal_type = 'SELL'
        
        volume = latest.get('volume', 0)
        volume_sma = latest.get('volume_sma', 0)
        if volume_sma > 0 and volume > volume_sma * 2:
            strength += 10
            reasons.append('High Volume')
        
        if strength >= 35 and signal_type:
            signals.append({
                'symbol': symbol,
                'signal_type': signal_type,
                'signal_source': 'BASIC_ANALYSIS',
                'strength': min(strength, 100),
                'price': close,
                'reason': ' | '.join(reasons),
                'rsi_value': rsi,
                'timestamp': datetime.utcnow()
            })
        return signals
    
    @staticmethod
    def generate_ut_bot_signals(df, symbol):
        signals = []
        if len(df) < 10:
            return signals
        latest = df.iloc[-1]
        if latest.get('ut_buy', False):
            signals.append({
                'symbol': symbol,
                'signal_type': 'BUY',
                'signal_source': 'UT_BOT',
                'strength': 85,
                'price': latest['close'],
                'reason': '🤖 UT Bot Alert - BUY Signal',
                'timestamp': datetime.utcnow()
            })
        if latest.get('ut_sell', False):
            signals.append({
                'symbol': symbol,
                'signal_type': 'SELL',
                'signal_source': 'UT_BOT',
                'strength': 85,
                'price': latest['close'],
                'reason': '🤖 UT Bot Alert - SELL Signal',
                'timestamp': datetime.utcnow()
            })
        return signals
    
    @staticmethod
    def detect_pump_dump(df, symbol, threshold_percent=5, time_window=15):
        alerts = []
        if len(df) < time_window:
            return alerts
        recent = df.tail(time_window)
        start_price = recent['close'].iloc[0]
        end_price = recent['close'].iloc[-1]
        price_change = ((end_price - start_price) / start_price) * 100
        avg_volume = df['volume'].tail(100).mean()
        recent_volume = recent['volume'].mean()
        volume_change = ((recent_volume - avg_volume) / avg_volume) * 100 if avg_volume > 0 else 0
        if price_change >= threshold_percent and volume_change > 50:
            alerts.append({
                'symbol': symbol,
                'alert_type': 'PUMP',
                'price_change': round(price_change, 2),
                'volume_change': round(volume_change, 2),
                'time_period': f'{time_window}m',
                'price': end_price,
                'timestamp': datetime.utcnow()
            })
        elif price_change <= -threshold_percent and volume_change > 50:
            alerts.append({
                'symbol': symbol,
                'alert_type': 'DUMP',
                'price_change': round(price_change, 2),
                'volume_change': round(volume_change, 2),
                'time_period': f'{time_window}m',
                'price': end_price,
                'timestamp': datetime.utcnow()
            })
        return alerts
SIGEOF

# ═══════════════════════════════════════════════════════════════════════
# signal_validator.py
# ═══════════════════════════════════════════════════════════════════════
cat > signal_validator.py << 'VALEOF'
from datetime import datetime, timedelta
from database_extended import db, SignalRecord, PumpDumpRecord

class SignalValidator:
    def __init__(self, fetcher):
        self.fetcher = fetcher
    
    def validate_pending_signals(self):
        print(f"[{datetime.now()}] 🔍 اعتبارسنجی سیگنالها...")
        pending_signals = db.get_pending_signals(min_age_minutes=3)
        results = {'validated': 0, 'success': 0, 'failure': 0, 'details': []}
        for signal in pending_signals:
            try:
                result = self._validate_single_signal(signal)
                if result.get('status') != 'pending':
                    results['validated'] += 1
                    if result.get('result') == 'success':
                        results['success'] += 1
                    elif result.get('result') == 'failure':
                        results['failure'] += 1
                    results['details'].append(result)
            except Exception as e:
                print(f"  خطا در بررسی {signal.symbol}: {e}")
        print(f"  ✅ بررسی: {results['validated']} | موفق: {results['success']} | ناموفق: {results['failure']}")
        return results
    
    def _validate_single_signal(self, signal):
        current_price = self._get_current_price(signal.symbol)
        if not current_price:
            return {'status': 'pending', 'message': 'قیمت دریافت نشد'}
        entry_price = signal.entry_price
        if signal.signal_type == 'BUY':
            profit_percent = ((current_price - entry_price) / entry_price) * 100
        else:
            profit_percent = ((entry_price - current_price) / entry_price) * 100
        result = 'unknown'
        status = 'validated'
        note = ''
        if profit_percent >= signal.target_percent:
            result = 'success'
            note = f'🎯 تارگت! سود: {profit_percent:.2f}%'
        elif profit_percent <= -signal.stop_percent:
            result = 'failure'
            note = f'❌ استاپ! ضرر: {profit_percent:.2f}%'
        elif datetime.utcnow() > signal.expires_at:
            status = 'expired'
            if profit_percent > 0:
                result = 'success'
                note = f'⏰ منقضی با سود {profit_percent:.2f}%'
            elif profit_percent < -0.5:
                result = 'failure'
                note = f'⏰ منقضی با ضرر {profit_percent:.2f}%'
            else:
                result = 'breakeven'
                note = '⏰ منقضی - سربهسر'
        else:
            return {'status': 'pending', 'profit_percent': profit_percent}
        db.update_signal_result(signal.id, {
            'status': status, 'result': result, 'exit_price': current_price,
            'profit_percent': round(profit_percent, 2), 'note': note
        })
        return {
            'signal_id': signal.id, 'symbol': signal.symbol, 'signal_type': signal.signal_type,
            'profit_percent': round(profit_percent, 2), 'status': status, 'result': result, 'note': note
        }
    
    def validate_pump_dumps(self):
        pending = db.get_pending_pump_dumps(min_age_minutes=5)
        results = {'validated': 0, 'continued': 0, 'reversed': 0}
        for alert in pending:
            try:
                result = self._validate_pump_dump(alert)
                results['validated'] += 1
                if result.get('continued'):
                    results['continued'] += 1
                else:
                    results['reversed'] += 1
            except:
                pass
        return results
    
    def _validate_pump_dump(self, alert):
        current_price = self._get_current_price(alert.symbol)
        if not current_price:
            return {'status': 'error'}
        initial_price = alert.price_at_alert
        price_change = ((current_price - initial_price) / initial_price) * 100
        continued = (alert.alert_type == 'PUMP' and price_change > 0) or \
                   (alert.alert_type == 'DUMP' and price_change < 0)
        result = 'success' if continued else 'failure'
        db.update_pump_dump_result(alert.id, {
            'status': 'validated', 'result': result, 'continued': continued,
            'reversal_percent': round(price_change, 2) if not continued else None,
            'max_continuation': round(price_change, 2) if continued else None
        })
        return {'alert_id': alert.id, 'continued': continued, 'result': result}
    
    def _get_current_price(self, symbol):
        try:
            symbols = self.fetcher.get_futures_symbols(300)
            full_symbol = None
            for s in symbols:
                if symbol.upper() in s.upper().replace('/', '').replace(':USDT', '').replace('-', ''):
                    full_symbol = s
                    break
            if not full_symbol:
                return None
            ticker = self.fetcher.get_ticker(full_symbol)
            return ticker.get('price') if ticker else None
        except:
            return None
    
    def get_realtime_stats(self):
        return {
            'last_hour': db.get_accuracy_stats(hours=1),
            'last_24h': db.get_accuracy_stats(hours=24),
            'last_7d': db.get_accuracy_stats(hours=168)
        }

validator = None

def init_validator(fetcher):
    global validator
    validator = SignalValidator(fetcher)

def run_validation():
    if validator:
        try:
            signal_results = validator.validate_pending_signals()
            pump_results = validator.validate_pump_dumps()
            return {'signals': signal_results, 'pump_dumps': pump_results, 'timestamp': datetime.utcnow().isoformat()}
        except Exception as e:
            print(f"خطا: {e}")
    return None
VALEOF

echo -e "${BLUE}[6/6] ایجاد فایل اصلی و قالبها...${NC}"

# ادامه در پیام بعدی به دلیل محدودیت طول...

echo ""
echo -e "${GREEN}✅ فایلهای اصلی ایجاد شد!${NC}"
echo ""
echo -e "${YELLOW}⚠️ حالا فایلهای زیر را جداگانه ایجاد کنید:${NC}"
echo "   - app.py"
echo "   - templates/index.html"
echo "   - templates/advanced.html"
echo "   - templates/analytics.html"