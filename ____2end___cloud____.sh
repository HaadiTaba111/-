#!/bin/bash
# ============================================
# 🚀 COMPLETE CRYPTO FUTURES SIGNAL SYSTEM V3.0
# با ذخیره کامل در دیتابیس برای تحلیل آینده
# ============================================

cat << 'BANNER'
╔════════════════════════════════════════════════════════════════════╗
║  🚀 CRYPTO FUTURES SIGNAL SYSTEM - V3.0 COMPLETE                   ║
║  ═══════════════════════════════════════════════════════════════   ║
║  📊 250 Futures Pairs | Real Data | Full Database Storage          ║
║  🐋 Whale Detection | Smart Money | Liquidity Hunt                 ║
║  📈 All Indicators | UT Bot | Signal Validation                    ║
║  💾 Complete History for Future Analysis                           ║
╚════════════════════════════════════════════════════════════════════╝
BANNER

PROJECT_DIR="crypto_signal_complete"
mkdir -p $PROJECT_DIR/{templates,static/{css,js}}
cd $PROJECT_DIR

echo "📦 Creating requirements.txt..."
cat > requirements.txt << 'EOF'
flask==2.3.3
flask-socketio==5.3.6
ccxt==4.1.22
pandas==2.0.3
numpy==1.24.3
ta==0.10.2
python-socketio==5.9.0
eventlet==0.33.3
requests==2.31.0
apscheduler==3.10.4
EOF

# ═══════════════════════════════════════════════════════════════
# 💾 DATABASE - ذخیره کامل همه اطلاعات برای تحلیل آینده
# ═══════════════════════════════════════════════════════════════
echo "💾 Creating database.py - Complete Storage System..."
cat > database.py << 'EOF'
"""
💾 سیستم کامل ذخیره‌سازی برای تحلیل آینده
همه اطلاعات مفید ذخیره می‌شود!
"""
import sqlite3
from datetime import datetime, timedelta
import json
import threading
import pandas as pd

class CompleteDatabase:
    """دیتابیس کامل برای ذخیره همه اطلاعات"""
    
    def __init__(self, db_path='crypto_signals.db'):
        self.db_path = db_path
        self.lock = threading.Lock()
        self.init_db()
    
    def get_conn(self):
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn
    
    def init_db(self):
        """ایجاد همه جداول مورد نیاز"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            # ═══════════════════════════════════════════════════
            # جدول 1: سیگنال‌های اصلی
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS signals (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    exchange TEXT DEFAULT 'kucoin',
                    signal_type TEXT NOT NULL,
                    direction TEXT NOT NULL,
                    entry_price REAL NOT NULL,
                    current_price REAL,
                    target_price REAL,
                    stop_loss REAL,
                    strength INTEGER DEFAULT 50,
                    confidence REAL,
                    reason TEXT,
                    category TEXT,
                    timeframe TEXT DEFAULT '15m',
                    
                    -- اندیکاتورها در لحظه سیگنال
                    rsi REAL,
                    macd REAL,
                    macd_signal REAL,
                    ema_9 REAL,
                    ema_21 REAL,
                    ma_20 REAL,
                    ma_50 REAL,
                    bb_upper REAL,
                    bb_lower REAL,
                    atr REAL,
                    volume REAL,
                    volume_avg REAL,
                    volume_ratio REAL,
                    
                    -- وضعیت و نتیجه
                    status TEXT DEFAULT 'ACTIVE',
                    validation_count INTEGER DEFAULT 0,
                    last_validation TIMESTAMP,
                    final_result TEXT,
                    profit_loss_pct REAL,
                    max_profit REAL,
                    max_loss REAL,
                    
                    -- زمان‌ها
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    closed_at TIMESTAMP,
                    duration_minutes INTEGER
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 2: تشخیص نهنگ‌ها
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS whale_activities (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    activity_type TEXT NOT NULL,
                    direction TEXT,
                    price REAL,
                    volume REAL,
                    volume_usd REAL,
                    volume_zscore REAL,
                    volume_ratio REAL,
                    price_impact REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- نتیجه پیگیری
                    price_after_1h REAL,
                    price_after_4h REAL,
                    price_after_24h REAL,
                    was_profitable INTEGER,
                    follow_up_done INTEGER DEFAULT 0
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 3: Smart Money (پول هوشمند)
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS smart_money (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    activity_type TEXT NOT NULL,
                    price REAL,
                    volume REAL,
                    volume_ratio REAL,
                    price_change_pct REAL,
                    accumulation_score REAL,
                    distribution_score REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- تحلیل بعدی
                    price_after_1h REAL,
                    price_after_24h REAL,
                    result TEXT
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 4: Order Blocks
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS order_blocks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    block_type TEXT NOT NULL,
                    top_price REAL,
                    bottom_price REAL,
                    mid_price REAL,
                    move_strength REAL,
                    volume_at_block REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- آیا قیمت برگشت؟
                    tested INTEGER DEFAULT 0,
                    test_count INTEGER DEFAULT 0,
                    held INTEGER,
                    broken_at TIMESTAMP
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 5: Liquidity Hunt (شکار نقدینگی)
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS liquidity_hunts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    hunt_type TEXT NOT NULL,
                    direction TEXT,
                    hunt_level REAL,
                    hunt_depth_pct REAL,
                    recovery_price REAL,
                    volume_spike REAL,
                    strength INTEGER,
                    suggested_entry REAL,
                    suggested_stop REAL,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- نتیجه
                    was_successful INTEGER,
                    profit_if_traded REAL
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 6: Divergence (واگرایی)
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS divergences (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    divergence_type TEXT NOT NULL,
                    indicator TEXT DEFAULT 'RSI',
                    price_direction TEXT,
                    indicator_direction TEXT,
                    price_at_signal REAL,
                    indicator_value REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- نتیجه
                    reversal_happened INTEGER,
                    reversal_size_pct REAL
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 7: Pump & Dump
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS pump_dump (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    alert_type TEXT NOT NULL,
                    start_price REAL,
                    peak_price REAL,
                    current_price REAL,
                    price_change_pct REAL,
                    volume_change_pct REAL,
                    momentum_score INTEGER,
                    duration_candles INTEGER,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- تحلیل بعدی
                    final_price REAL,
                    total_move_pct REAL,
                    reversal_happened INTEGER,
                    analysis_notes TEXT
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 8: MA/EMA Crosses
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS ma_crosses (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    cross_type TEXT NOT NULL,
                    fast_ma TEXT,
                    slow_ma TEXT,
                    fast_value REAL,
                    slow_value REAL,
                    price_at_cross REAL,
                    volume_at_cross REAL,
                    rsi_at_cross REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- نتیجه
                    price_after_24h REAL,
                    was_profitable INTEGER,
                    profit_pct REAL
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 9: UT Bot Alerts
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS ut_bot_alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    alert_type TEXT NOT NULL,
                    price REAL,
                    trailing_stop REAL,
                    atr_value REAL,
                    sensitivity REAL,
                    strength INTEGER,
                    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    
                    -- نتیجه
                    exit_price REAL,
                    profit_pct REAL,
                    was_profitable INTEGER
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 10: اعتبارسنجی سیگنال‌ها
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS signal_validations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    signal_id INTEGER,
                    signal_type TEXT,
                    check_number INTEGER,
                    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    entry_price REAL,
                    current_price REAL,
                    change_pct REAL,
                    current_rsi REAL,
                    current_trend TEXT,
                    status TEXT,
                    notes TEXT,
                    FOREIGN KEY (signal_id) REFERENCES signals(id)
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 11: تاریخچه قیمت (برای تحلیل آینده)
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS price_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    timeframe TEXT DEFAULT '15m',
                    timestamp TIMESTAMP,
                    open REAL,
                    high REAL,
                    low REAL,
                    close REAL,
                    volume REAL,
                    
                    -- اندیکاتورهای محاسبه شده
                    rsi REAL,
                    macd REAL,
                    ema_9 REAL,
                    ema_21 REAL,
                    bb_upper REAL,
                    bb_lower REAL,
                    atr REAL,
                    
                    UNIQUE(symbol, timeframe, timestamp)
                )
            ''')
            
            # ═══════════════════════════════════════════════════
            # جدول 12: آمار روزانه
            # ═══════════════════════════════════════════════════
            c.execute('''
                CREATE TABLE IF NOT EXISTS daily_stats (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    date DATE UNIQUE,
                    total_signals INTEGER DEFAULT 0,
                    buy_signals INTEGER DEFAULT 0,
                    sell_signals INTEGER DEFAULT 0,
                    successful INTEGER DEFAULT 0,
                    failed INTEGER DEFAULT 0,
                    total_profit_pct REAL DEFAULT 0,
                    best_signal_profit REAL,
                    worst_signal_loss REAL,
                    whale_detections INTEGER DEFAULT 0,
                    pump_detections INTEGER DEFAULT 0,
                    dump_detections INTEGER DEFAULT 0,
                    avg_strength REAL
                )
            ''')
            
            # ایندکس‌ها برای سرعت بیشتر
            c.execute('CREATE INDEX IF NOT EXISTS idx_signals_symbol ON signals(symbol)')
            c.execute('CREATE INDEX IF NOT EXISTS idx_signals_created ON signals(created_at)')
            c.execute('CREATE INDEX IF NOT EXISTS idx_signals_status ON signals(status)')
            c.execute('CREATE INDEX IF NOT EXISTS idx_whale_symbol ON whale_activities(symbol)')
            c.execute('CREATE INDEX IF NOT EXISTS idx_pump_dump_symbol ON pump_dump(symbol)')
            
            conn.commit()
            conn.close()
            print("✅ Database initialized with 12 tables for complete analysis!")
    
    # ═══════════════════════════════════════════════════════════════
    # توابع ذخیره‌سازی
    # ═══════════════════════════════════════════════════════════════
    
    def save_signal(self, data, indicators=None):
        """ذخیره سیگنال با تمام اندیکاتورها"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            ind = indicators or {}
            
            c.execute('''
                INSERT INTO signals 
                (symbol, exchange, signal_type, direction, entry_price, 
                 target_price, stop_loss, strength, confidence, reason, category,
                 rsi, macd, macd_signal, ema_9, ema_21, ma_20, ma_50,
                 bb_upper, bb_lower, atr, volume, volume_avg, volume_ratio)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('exchange', 'kucoin'),
                data.get('type', 'UNKNOWN'),
                data.get('signal', 'NEUTRAL'),
                data.get('price', 0),
                data.get('target'),
                data.get('stop_loss'),
                data.get('strength', 50),
                data.get('confidence'),
                data.get('reason', ''),
                data.get('category', ''),
                ind.get('rsi'),
                ind.get('macd'),
                ind.get('macd_signal'),
                ind.get('ema_9'),
                ind.get('ema_21'),
                ind.get('ma_20'),
                ind.get('ma_50'),
                ind.get('bb_upper'),
                ind.get('bb_lower'),
                ind.get('atr'),
                ind.get('volume'),
                ind.get('volume_avg'),
                ind.get('volume_ratio')
            ))
            
            signal_id = c.lastrowid
            conn.commit()
            conn.close()
            return signal_id
    
    def save_whale_activity(self, data):
        """ذخیره فعالیت نهنگ"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO whale_activities 
                (symbol, activity_type, direction, price, volume, volume_usd,
                 volume_zscore, volume_ratio, price_impact, strength)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type', 'WHALE_ACTIVITY'),
                data.get('signal'),
                data.get('price'),
                data.get('volume'),
                data.get('volume_usd'),
                data.get('volume_zscore'),
                data.get('volume_ratio'),
                data.get('price_impact'),
                data.get('strength', 50)
            ))
            
            whale_id = c.lastrowid
            conn.commit()
            conn.close()
            return whale_id
    
    def save_smart_money(self, data):
        """ذخیره فعالیت پول هوشمند"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO smart_money 
                (symbol, activity_type, price, volume, volume_ratio,
                 price_change_pct, accumulation_score, distribution_score, strength)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('price'),
                data.get('volume'),
                data.get('volume_ratio'),
                data.get('price_change'),
                data.get('accumulation_score'),
                data.get('distribution_score'),
                data.get('strength', 50)
            ))
            
            conn.commit()
            conn.close()
    
    def save_order_block(self, data):
        """ذخیره Order Block"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO order_blocks 
                (symbol, block_type, top_price, bottom_price, mid_price,
                 move_strength, volume_at_block, strength)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('top'),
                data.get('bottom'),
                (data.get('top', 0) + data.get('bottom', 0)) / 2,
                data.get('move_strength'),
                data.get('volume'),
                data.get('strength', 50)
            ))
            
            conn.commit()
            conn.close()
    
    def save_liquidity_hunt(self, data):
        """ذخیره شکار نقدینگی"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO liquidity_hunts 
                (symbol, hunt_type, direction, hunt_level, hunt_depth_pct,
                 recovery_price, volume_spike, strength, suggested_entry, suggested_stop)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('signal'),
                data.get('hunt_level'),
                data.get('hunt_depth'),
                data.get('price'),
                data.get('volume_spike'),
                data.get('strength', 50),
                data.get('price'),
                data.get('stop_loss')
            ))
            
            conn.commit()
            conn.close()
    
    def save_divergence(self, data):
        """ذخیره واگرایی"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO divergences 
                (symbol, divergence_type, indicator, price_at_signal,
                 indicator_value, strength)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('indicator', 'RSI'),
                data.get('price'),
                data.get('rsi') or data.get('indicator_value'),
                data.get('strength', 50)
            ))
            
            conn.commit()
            conn.close()
    
    def save_pump_dump(self, data):
        """ذخیره پامپ/دامپ"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO pump_dump 
                (symbol, alert_type, start_price, current_price, price_change_pct,
                 volume_change_pct, momentum_score, strength)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('alert_type') or data.get('type'),
                data.get('start_price'),
                data.get('price'),
                data.get('price_change'),
                data.get('volume_change'),
                data.get('momentum'),
                data.get('strength', 50)
            ))
            
            alert_id = c.lastrowid
            conn.commit()
            conn.close()
            return alert_id
    
    def save_ma_cross(self, data):
        """ذخیره تقاطع MA/EMA"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO ma_crosses 
                (symbol, cross_type, fast_ma, slow_ma, price_at_cross,
                 volume_at_cross, rsi_at_cross, strength)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('fast_ma', 'EMA9'),
                data.get('slow_ma', 'EMA21'),
                data.get('price'),
                data.get('volume'),
                data.get('rsi'),
                data.get('strength', 50)
            ))
            
            conn.commit()
            conn.close()
    
    def save_ut_bot_alert(self, data):
        """ذخیره سیگنال UT Bot"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('''
                INSERT INTO ut_bot_alerts 
                (symbol, alert_type, price, trailing_stop, atr_value, strength)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                data.get('symbol'),
                data.get('type'),
                data.get('price'),
                data.get('stop'),
                data.get('atr'),
                data.get('strength', 50)
            ))
            
            conn.commit()
            conn.close()
    
    def save_price_history(self, symbol, df):
        """ذخیره تاریخچه قیمت با اندیکاتورها"""
        if df.empty:
            return
        
        with self.lock:
            conn = self.get_conn()
            
            for _, row in df.tail(50).iterrows():  # آخرین 50 کندل
                try:
                    conn.execute('''
                        INSERT OR REPLACE INTO price_history 
                        (symbol, timestamp, open, high, low, close, volume,
                         rsi, macd, ema_9, ema_21, bb_upper, bb_lower, atr)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        symbol,
                        row.get('timestamp'),
                        row.get('open'),
                        row.get('high'),
                        row.get('low'),
                        row.get('close'),
                        row.get('volume'),
                        row.get('rsi'),
                        row.get('macd'),
                        row.get('ema_9'),
                        row.get('ema_21'),
                        row.get('bb_upper'),
                        row.get('bb_lower'),
                        row.get('atr')
                    ))
                except:
                    pass
            
            conn.commit()
            conn.close()
    
    def update_signal_validation(self, signal_id, current_price, status, notes='', indicators=None):
        """بروزرسانی اعتبارسنجی سیگنال"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            # دریافت اطلاعات سیگنال
            c.execute('SELECT * FROM signals WHERE id = ?', (signal_id,))
            row = c.fetchone()
            
            if row:
                entry_price = row['entry_price']
                direction = row['direction']
                
                # محاسبه تغییر
                if direction == 'BUY':
                    change = ((current_price - entry_price) / entry_price) * 100
                else:
                    change = ((entry_price - current_price) / entry_price) * 100
                
                # دریافت شماره چک
                c.execute('SELECT COUNT(*) FROM signal_validations WHERE signal_id = ?', (signal_id,))
                check_num = c.fetchone()[0] + 1
                
                # ذخیره اعتبارسنجی
                ind = indicators or {}
                c.execute('''
                    INSERT INTO signal_validations 
                    (signal_id, signal_type, check_number, entry_price, current_price,
                     change_pct, current_rsi, status, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    signal_id,
                    row['signal_type'],
                    check_num,
                    entry_price,
                    current_price,
                    change,
                    ind.get('rsi'),
                    status,
                    notes
                ))
                
                # بروزرسانی سیگنال اصلی
                c.execute('''
                    UPDATE signals SET 
                        current_price = ?,
                        validation_count = validation_count + 1,
                        last_validation = CURRENT_TIMESTAMP,
                        max_profit = MAX(COALESCE(max_profit, 0), ?),
                        max_loss = MIN(COALESCE(max_loss, 0), ?)
                    WHERE id = ?
                ''', (current_price, max(0, change), min(0, change), signal_id))
                
                # اگر بسته شد
                if status in ['SUCCESS', 'FAILED', 'STOPPED']:
                    c.execute('''
                        UPDATE signals SET 
                            status = 'CLOSED',
                            final_result = ?,
                            profit_loss_pct = ?,
                            closed_at = CURRENT_TIMESTAMP
                        WHERE id = ?
                    ''', (status, change, signal_id))
            
            conn.commit()
            conn.close()
    
    def update_whale_followup(self, whale_id, price_1h, price_4h=None, price_24h=None):
        """پیگیری فعالیت نهنگ"""
        with self.lock:
            conn = self.get_conn()
            c = conn.cursor()
            
            c.execute('SELECT price, direction FROM whale_activities WHERE id = ?', (whale_id,))
            row = c.fetchone()
            
            if row:
                entry = row['price']
                direction = row['direction']
                
                profitable = 0
                if direction == 'BUY' and price_1h and price_1h > entry:
                    profitable = 1
                elif direction == 'SELL' and price_1h and price_1h < entry:
                    profitable = 1
                
                c.execute('''
                    UPDATE whale_activities SET 
                        price_after_1h = ?,
                        price_after_4h = ?,
                        price_after_24h = ?,
                        was_profitable = ?,
                        follow_up_done = 1
                    WHERE id = ?
                ''', (price_1h, price_4h, price_24h, profitable, whale_id))
            
            conn.commit()
            conn.close()
    
    # ═══════════════════════════════════════════════════════════════
    # توابع خواندن و گزارش
    # ═══════════════════════════════════════════════════════════════
    
    def get_active_signals(self, limit=100):
        """سیگنال‌های فعال"""
        conn = self.get_conn()
        c = conn.cursor()
        c.execute('''
            SELECT * FROM signals 
            WHERE status = 'ACTIVE'
            ORDER BY created_at DESC
            LIMIT ?
        ''', (limit,))
        rows = c.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    
    def get_signal_history(self, days=7, limit=500):
        """تاریخچه سیگنال‌ها"""
        conn = self.get_conn()
        c = conn.cursor()
        since = datetime.now() - timedelta(days=days)
        c.execute('''
            SELECT * FROM signals 
            WHERE created_at >= ?
            ORDER BY created_at DESC
            LIMIT ?
        ''', (since, limit))
        rows = c.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    
    def get_whale_history(self, hours=48):
        """تاریخچه فعالیت نهنگ‌ها"""
        conn = self.get_conn()
        c = conn.cursor()
        since = datetime.now() - timedelta(hours=hours)
        c.execute('''
            SELECT * FROM whale_activities 
            WHERE detected_at >= ?
            ORDER BY detected_at DESC
        ''', (since,))
        rows = c.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    
    def get_pump_dump_history(self, hours=24):
        """تاریخچه پامپ و دامپ"""
        conn = self.get_conn()
        c = conn.cursor()
        since = datetime.now() - timedelta(hours=hours)
        c.execute('''
            SELECT * FROM pump_dump 
            WHERE detected_at >= ?
            ORDER BY detected_at DESC
        ''', (since,))
        rows = c.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    
    def get_statistics(self):
        """آمار کلی"""
        conn = self.get_conn()
        c = conn.cursor()
        
        stats = {}
        
        # سیگنال‌ها
        c.execute('''
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN final_result = 'SUCCESS' THEN 1 ELSE 0 END) as wins,
                SUM(CASE WHEN final_result = 'FAILED' THEN 1 ELSE 0 END) as losses,
                AVG(CASE WHEN profit_loss_pct IS NOT NULL THEN profit_loss_pct END) as avg_profit,
                MAX(profit_loss_pct) as best_profit,
                MIN(profit_loss_pct) as worst_loss
            FROM signals WHERE status = 'CLOSED'
        ''')
        row = c.fetchone()
        stats['signals'] = dict(row) if row else {}
        
        # نهنگ‌ها
        c.execute('''
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN was_profitable = 1 THEN 1 ELSE 0 END) as profitable
            FROM whale_activities WHERE follow_up_done = 1
        ''')
        row = c.fetchone()
        stats['whales'] = dict(row) if row else {}
        
        # پامپ و دامپ
        c.execute('SELECT COUNT(*) as total FROM pump_dump')
        row = c.fetchone()
        stats['pump_dump'] = {'total': row['total']} if row else {}
        
        # امروز
        today = datetime.now().date()
        c.execute('''
            SELECT COUNT(*) as count FROM signals WHERE DATE(created_at) = ?
        ''', (today,))
        row = c.fetchone()
        stats['today_signals'] = row['count'] if row else 0
        
        conn.close()
        return stats
    
    def get_analysis_report(self, symbol=None, days=30):
        """گزارش تحلیلی برای یادگیری"""
        conn = self.get_conn()
        c = conn.cursor()
        
        since = datetime.now() - timedelta(days=days)
        
        report = {
            'period': f'{days} days',
            'generated_at': datetime.now().isoformat()
        }
        
        # بهترین نوع سیگنال
        c.execute('''
            SELECT signal_type, 
                   COUNT(*) as count,
                   AVG(CASE WHEN final_result='SUCCESS' THEN 1.0 ELSE 0.0 END) as win_rate,
                   AVG(profit_loss_pct) as avg_profit
            FROM signals 
            WHERE created_at >= ? AND status = 'CLOSED'
            GROUP BY signal_type
            ORDER BY win_rate DESC
        ''', (since,))
        report['signal_type_performance'] = [dict(r) for r in c.fetchall()]
        
        # بهترین ارزها
        if not symbol:
            c.execute('''
                SELECT symbol,
                       COUNT(*) as signals,
                       AVG(CASE WHEN final_result='SUCCESS' THEN 1.0 ELSE 0.0 END) as win_rate
                FROM signals 
                WHERE created_at >= ? AND status = 'CLOSED'
                GROUP BY symbol
                HAVING COUNT(*) >= 3
                ORDER BY win_rate DESC
                LIMIT 20
            ''', (since,))
            report['best_symbols'] = [dict(r) for r in c.fetchall()]
        
        # دقت نهنگ‌ها
        c.execute('''
            SELECT activity_type,
                   COUNT(*) as count,
                   AVG(CASE WHEN was_profitable=1 THEN 1.0 ELSE 0.0 END) as accuracy
            FROM whale_activities 
            WHERE detected_at >= ? AND follow_up_done = 1
            GROUP BY activity_type
        ''', (since,))
        report['whale_accuracy'] = [dict(r) for r in c.fetchall()]
        
        conn.close()
        return report

# نمونه گلوبال
db = CompleteDatabase()
EOF

# ═══════════════════════════════════════════════════════════════
# 📈 INDICATORS - همه اندیکاتورها
# ═══════════════════════════════════════════════════════════════
echo "📈 Creating indicators.py..."
cat > indicators.py << 'EOF'
"""
📈 محاسبه تمام اندیکاتورهای تکنیکال
MA, EMA, RSI, MACD, Bollinger Bands, ATR, Stochastic, UT Bot Alert
"""
import pandas as pd
import numpy as np
from ta.trend import EMAIndicator, SMAIndicator, MACD
from ta.momentum import RSIIndicator, StochasticOscillator
from ta.volatility import BollingerBands, AverageTrueRange

class Indicators:
    """محاسبه همه اندیکاتورها"""
    
    @staticmethod
    def calculate_all(df):
        """محاسبه تمام اندیکاتورها روی دیتافریم"""
        if len(df) < 50:
            return df
        
        df = df.copy()
        
        try:
            # Moving Averages
            df['ma_7'] = SMAIndicator(df['close'], window=7).sma_indicator()
            df['ma_20'] = SMAIndicator(df['close'], window=20).sma_indicator()
            df['ma_50'] = SMAIndicator(df['close'], window=50).sma_indicator()
            df['ma_100'] = SMAIndicator(df['close'], window=100).sma_indicator()
            df['ma_200'] = SMAIndicator(df['close'], window=200).sma_indicator()
            
            # EMA
            df['ema_9'] = EMAIndicator(df['close'], window=9).ema_indicator()
            df['ema_12'] = EMAIndicator(df['close'], window=12).ema_indicator()
            df['ema_21'] = EMAIndicator(df['close'], window=21).ema_indicator()
            df['ema_26'] = EMAIndicator(df['close'], window=26).ema_indicator()
            df['ema_50'] = EMAIndicator(df['close'], window=50).ema_indicator()
            
            # RSI
            df['rsi'] = RSIIndicator(df['close'], window=14).rsi()
            df['rsi_7'] = RSIIndicator(df['close'], window=7).rsi()
            
            # MACD
            macd = MACD(df['close'])
            df['macd'] = macd.macd()
            df['macd_signal'] = macd.macd_signal()
            df['macd_histogram'] = macd.macd_diff()
            
            # Bollinger Bands
            bb = BollingerBands(df['close'], window=20, window_dev=2)
            df['bb_upper'] = bb.bollinger_hband()
            df['bb_middle'] = bb.bollinger_mavg()
            df['bb_lower'] = bb.bollinger_lband()
            df['bb_width'] = (df['bb_upper'] - df['bb_lower']) / df['bb_middle']
            
            # ATR
            atr = AverageTrueRange(df['high'], df['low'], df['close'], window=14)
            df['atr'] = atr.average_true_range()
            df['atr_pct'] = (df['atr'] / df['close']) * 100
            
            # Stochastic
            stoch = StochasticOscillator(df['high'], df['low'], df['close'])
            df['stoch_k'] = stoch.stoch()
            df['stoch_d'] = stoch.stoch_signal()
            
            # Volume
            df['volume_sma'] = df['volume'].rolling(20).mean()
            df['volume_ratio'] = df['volume'] / df['volume_sma']
            
        except Exception as e:
            print(f"Indicator error: {e}")
        
        return df
    
    @staticmethod
    def ut_bot_alert(df, sensitivity=1.0, atr_period=10):
        """
        UT Bot Alert - مشابه تریدینگ ویو
        بهترین سیستم Trailing Stop
        """
        if len(df) < atr_period + 10:
            return df, []
        
        df = df.copy()
        
        # محاسبه ATR
        atr = AverageTrueRange(df['high'], df['low'], df['close'], window=atr_period)
        df['ut_atr'] = atr.average_true_range()
        df['ut_nLoss'] = sensitivity * df['ut_atr']
        
        # Trailing Stop
        df['ut_trailing'] = 0.0
        
        for i in range(1, len(df)):
            nLoss = df['ut_nLoss'].iloc[i]
            prev = df['ut_trailing'].iloc[i-1]
            close = df['close'].iloc[i]
            prev_close = df['close'].iloc[i-1]
            
            if close > prev and prev_close > prev:
                df.loc[df.index[i], 'ut_trailing'] = max(prev, close - nLoss)
            elif close < prev and prev_close < prev:
                df.loc[df.index[i], 'ut_trailing'] = min(prev, close + nLoss)
            elif close > prev:
                df.loc[df.index[i], 'ut_trailing'] = close - nLoss
            else:
                df.loc[df.index[i], 'ut_trailing'] = close + nLoss
        
        # Position
        df['ut_pos'] = 0
        df.loc[df['close'] > df['ut_trailing'], 'ut_pos'] = 1
        df.loc[df['close'] < df['ut_trailing'], 'ut_pos'] = -1
        
        # Signals
        df['ut_signal'] = df['ut_pos'].diff()
        
        alerts = []
        for i in range(1, len(df)):
            if df['ut_signal'].iloc[i] == 2:
                alerts.append({
                    'index': i,
                    'type': 'UT_BOT_BUY',
                    'signal': 'BUY',
                    'price': df['close'].iloc[i],
                    'stop': df['ut_trailing'].iloc[i],
                    'atr': df['ut_atr'].iloc[i],
                    'strength': 80,
                    'reason': f"📈 UT Bot BUY | Stop: {df['ut_trailing'].iloc[i]:.6f}"
                })
            elif df['ut_signal'].iloc[i] == -2:
                alerts.append({
                    'index': i,
                    'type': 'UT_BOT_SELL',
                    'signal': 'SELL',
                    'price': df['close'].iloc[i],
                    'stop': df['ut_trailing'].iloc[i],
                    'atr': df['ut_atr'].iloc[i],
                    'strength': 80,
                    'reason': f"📉 UT Bot SELL | Stop: {df['ut_trailing'].iloc[i]:.6f}"
                })
        
        return df, alerts[-5:]
    
    @staticmethod
    def detect_ma_cross(df):
        """تشخیص تقاطع MA و EMA"""
        if len(df) < 55:
            return []
        
        df = Indicators.calculate_all(df)
        crosses = []
        
        for i in range(1, len(df)):
            try:
                # EMA 9/21 Golden Cross
                if (df['ema_9'].iloc[i] > df['ema_21'].iloc[i] and 
                    df['ema_9'].iloc[i-1] <= df['ema_21'].iloc[i-1]):
                    crosses.append({
                        'index': i,
                        'type': 'EMA_GOLDEN_CROSS_9_21',
                        'signal': 'BUY',
                        'price': df['close'].iloc[i],
                        'fast_ma': 'EMA9',
                        'slow_ma': 'EMA21',
                        'rsi': df['rsi'].iloc[i] if pd.notna(df['rsi'].iloc[i]) else None,
                        'volume': df['volume'].iloc[i],
                        'strength': 75,
                        'reason': '🔀 EMA 9/21 Golden Cross (BUY)'
                    })
                
                # EMA 9/21 Death Cross
                if (df['ema_9'].iloc[i] < df['ema_21'].iloc[i] and 
                    df['ema_9'].iloc[i-1] >= df['ema_21'].iloc[i-1]):
                    crosses.append({
                        'index': i,
                        'type': 'EMA_DEATH_CROSS_9_21',
                        'signal': 'SELL',
                        'price': df['close'].iloc[i],
                        'fast_ma': 'EMA9',
                        'slow_ma': 'EMA21',
                        'rsi': df['rsi'].iloc[i] if pd.notna(df['rsi'].iloc[i]) else None,
                        'volume': df['volume'].iloc[i],
                        'strength': 75,
                        'reason': '🔀 EMA 9/21 Death Cross (SELL)'
                    })
                
                # MA 20/50 Golden Cross (قوی‌تر)
                if pd.notna(df['ma_50'].iloc[i]) and pd.notna(df['ma_50'].iloc[i-1]):
                    if (df['ma_20'].iloc[i] > df['ma_50'].iloc[i] and 
                        df['ma_20'].iloc[i-1] <= df['ma_50'].iloc[i-1]):
                        crosses.append({
                            'index': i,
                            'type': 'MA_GOLDEN_CROSS_20_50',
                            'signal': 'BUY',
                            'price': df['close'].iloc[i],
                            'fast_ma': 'MA20',
                            'slow_ma': 'MA50',
                            'rsi': df['rsi'].iloc[i] if pd.notna(df['rsi'].iloc[i]) else None,
                            'strength': 85,
                            'reason': '🌟 MA 20/50 Golden Cross (STRONG BUY)'
                        })
                    
                    if (df['ma_20'].iloc[i] < df['ma_50'].iloc[i] and 
                        df['ma_20'].iloc[i-1] >= df['ma_50'].iloc[i-1]):
                        crosses.append({
                            'index': i,
                            'type': 'MA_DEATH_CROSS_20_50',
                            'signal': 'SELL',
                            'price': df['close'].iloc[i],
                            'fast_ma': 'MA20',
                            'slow_ma': 'MA50',
                            'rsi': df['rsi'].iloc[i] if pd.notna(df['rsi'].iloc[i]) else None,
                            'strength': 85,
                            'reason': '💀 MA 20/50 Death Cross (STRONG SELL)'
                        })
            except:
                continue
        
        return crosses[-10:]
    
    @staticmethod
    def get_summary(df):
        """خلاصه وضعیت اندیکاتورها"""
        if len(df) < 50:
            return {}
        
        df = Indicators.calculate_all(df)
        latest = df.iloc[-1]
        
        return {
            'price': latest['close'],
            'rsi': round(latest['rsi'], 2) if pd.notna(latest['rsi']) else None,
            'rsi_signal': 'OVERBOUGHT' if latest['rsi'] > 70 else 'OVERSOLD' if latest['rsi'] < 30 else 'NEUTRAL',
            'macd': round(latest['macd'], 8) if pd.notna(latest['macd']) else None,
            'macd_signal': round(latest['macd_signal'], 8) if pd.notna(latest['macd_signal']) else None,
            'macd_trend': 'BULLISH' if latest['macd'] > latest['macd_signal'] else 'BEARISH',
            'bb_position': round(((latest['close'] - latest['bb_lower']) / 
                                 (latest['bb_upper'] - latest['bb_lower'])) * 100, 1) 
                          if pd.notna(latest['bb_upper']) else None,
            'atr': round(latest['atr'], 8) if pd.notna(latest['atr']) else None,
            'atr_pct': round(latest['atr_pct'], 2) if pd.notna(latest['atr_pct']) else None,
            'ema_9': latest['ema_9'],
            'ema_21': latest['ema_21'],
            'ma_20': latest['ma_20'],
            'ma_50': latest['ma_50'],
            'volume_ratio': round(latest['volume_ratio'], 2) if pd.notna(latest['volume_ratio']) else None,
            'trend': 'BULLISH' if latest['close'] > latest['ma_20'] > latest['ma_50'] else 
                     'BEARISH' if latest['close'] < latest['ma_20'] < latest['ma_50'] else 'NEUTRAL'
        }

indicators = Indicators()
EOF

# ═══════════════════════════════════════════════════════════════
# 🔥 SIGNALS - سیستم کامل سیگنال با نهنگ و Smart Money
# ═══════════════════════════════════════════════════════════════
echo "🔥 Creating signals.py - Complete Signal Engine..."
cat > signals.py << 'EOF'
"""
🔥 سیستم کامل سیگنالدهی
شامل: Whale Detection, Smart Money, Order Blocks, Liquidity Hunt, Divergence
همه سیگنال‌ها در دیتابیس ذخیره می‌شوند!
"""
import pandas as pd
import numpy as np
from datetime import datetime
from ta.momentum import RSIIndicator
from ta.volatility import AverageTrueRange
from indicators import Indicators
from database import db

class WhaleDetector:
    """
    🐋 تشخیص فعالیت نهنگ‌ها
    بر اساس حجم غیرعادی و تاثیر قیمت
    """
    
    @staticmethod
    def detect(df, symbol, std_multiplier=2.5):
        """تشخیص خرید/فروش نهنگ"""
        if len(df) < 60:
            return []
        
        df = df.copy()
        df['vol_mean'] = df['volume'].rolling(50).mean()
        df['vol_std'] = df['volume'].rolling(50).std()
        
        signals = []
        
        for i in range(50, len(df)):
            try:
                vol_std = df['vol_std'].iloc[i]
                if vol_std == 0 or pd.isna(vol_std):
                    continue
                
                # Z-Score حجم
                zscore = (df['volume'].iloc[i] - df['vol_mean'].iloc[i]) / vol_std
                
                if zscore > std_multiplier:
                    price_change = ((df['close'].iloc[i] - df['open'].iloc[i]) / 
                                   df['open'].iloc[i]) * 100
                    
                    volume_usd = df['volume'].iloc[i] * df['close'].iloc[i]
                    vol_ratio = df['volume'].iloc[i] / df['vol_mean'].iloc[i]
                    
                    signal_data = {
                        'symbol': symbol,
                        'price': df['close'].iloc[i],
                        'volume': df['volume'].iloc[i],
                        'volume_usd': volume_usd,
                        'volume_zscore': round(zscore, 2),
                        'volume_ratio': round(vol_ratio, 2),
                        'price_impact': round(price_change, 2),
                        'strength': min(65 + int(zscore * 10), 95),
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                    }
                    
                    if price_change > 0.5:
                        signal_data['type'] = 'WHALE_BUYING'
                        signal_data['signal'] = 'BUY'
                        signal_data['reason'] = f"🐋 نهنگ در حال خرید! Vol: {vol_ratio:.1f}x | Z: {zscore:.1f}"
                        signals.append(signal_data)
                        
                        # ذخیره در دیتابیس
                        db.save_whale_activity(signal_data)
                        
                    elif price_change < -0.5:
                        signal_data['type'] = 'WHALE_SELLING'
                        signal_data['signal'] = 'SELL'
                        signal_data['reason'] = f"🐋 نهنگ در حال فروش! Vol: {vol_ratio:.1f}x | Z: {zscore:.1f}"
                        signals.append(signal_data)
                        
                        db.save_whale_activity(signal_data)
                    
                    elif zscore > 3:  # حجم خیلی بالا بدون حرکت قیمت = جمع‌آوری
                        signal_data['type'] = 'WHALE_ACCUMULATION'
                        signal_data['signal'] = 'BUY'
                        signal_data['reason'] = f"🐋 جمع‌آوری نهنگ (حجم بالا، قیمت ثابت) Z: {zscore:.1f}"
                        signals.append(signal_data)
                        
                        db.save_whale_activity(signal_data)
                        
            except Exception as e:
                continue
        
        return signals[-5:]


class SmartMoneyDetector:
    """
    💰 تشخیص پول هوشمند
    Accumulation و Distribution
    """
    
    @staticmethod
    def detect(df, symbol, volume_threshold=2.0):
        """تشخیص ورود و خروج پول هوشمند"""
        if len(df) < 30:
            return []
        
        df = df.copy()
        df['vol_sma'] = df['volume'].rolling(20).mean()
        df['vol_ratio'] = df['volume'] / df['vol_sma']
        df['price_change'] = df['close'].pct_change() * 100
        
        signals = []
        
        for i in range(20, len(df)):
            vol_ratio = df['vol_ratio'].iloc[i]
            price_change = abs(df['price_change'].iloc[i])
            
            if pd.isna(vol_ratio):
                continue
            
            signal_data = {
                'symbol': symbol,
                'price': df['close'].iloc[i],
                'volume': df['volume'].iloc[i],
                'volume_ratio': round(vol_ratio, 2),
                'price_change': round(price_change, 2),
                'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
            }
            
            # جمع‌آوری: حجم بالا + تغییر قیمت کم
            if vol_ratio > volume_threshold and price_change < 0.5:
                signal_data['type'] = 'SMART_MONEY_ACCUMULATION'
                signal_data['signal'] = 'BUY'
                signal_data['strength'] = min(int(vol_ratio * 30), 95)
                signal_data['accumulation_score'] = vol_ratio * (1 - price_change/5)
                signal_data['reason'] = f"💰 جمع‌آوری پول هوشمند | Vol: {vol_ratio:.1f}x | تغییر: {price_change:.2f}%"
                signals.append(signal_data)
                
                db.save_smart_money(signal_data)
            
            # توزیع: حجم بالا + قیمت بالا رفته
            elif vol_ratio > volume_threshold and price_change > 2:
                if df['close'].iloc[i] > df['close'].iloc[i-1]:
                    signal_data['type'] = 'SMART_MONEY_DISTRIBUTION'
                    signal_data['signal'] = 'SELL'
                    signal_data['strength'] = min(int(vol_ratio * 25), 90)
                    signal_data['distribution_score'] = vol_ratio * price_change / 5
                    signal_data['reason'] = f"💰 توزیع پول هوشمند | Vol: {vol_ratio:.1f}x | تغییر: +{price_change:.2f}%"
                    signals.append(signal_data)
                    
                    db.save_smart_money(signal_data)
        
        return signals[-5:]


class OrderBlockDetector:
    """
    📦 تشخیص Order Blocks
    نواحی که سفارشات بزرگ قرار داده شده
    """
    
    @staticmethod
    def detect(df, symbol):
        """یافتن Order Blocks"""
        if len(df) < 10:
            return []
        
        df = df.copy()
        blocks = []
        
        for i in range(3, len(df) - 1):
            try:
                # Bullish Order Block
                if (df['close'].iloc[i-1] < df['open'].iloc[i-1] and  # کندل قبلی نزولی
                    df['close'].iloc[i] > df['open'].iloc[i] and       # کندل فعلی صعودی
                    df['close'].iloc[i] > df['high'].iloc[i-1]):       # بالاتر از high قبلی
                    
                    move = ((df['close'].iloc[i] - df['low'].iloc[i-1]) / df['low'].iloc[i-1]) * 100
                    
                    if move > 0.5:
                        signal_data = {
                            'symbol': symbol,
                            'type': 'BULLISH_ORDER_BLOCK',
                            'signal': 'BUY',
                            'top': df['high'].iloc[i-1],
                            'bottom': df['low'].iloc[i-1],
                            'price': df['close'].iloc[i],
                            'move_strength': round(move, 2),
                            'volume': df['volume'].iloc[i],
                            'strength': min(int(move * 20), 90),
                            'reason': f"📦 Bullish Order Block | حرکت: {move:.1f}%",
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                        }
                        blocks.append(signal_data)
                        db.save_order_block(signal_data)
                
                # Bearish Order Block
                if (df['close'].iloc[i-1] > df['open'].iloc[i-1] and  # کندل قبلی صعودی
                    df['close'].iloc[i] < df['open'].iloc[i] and       # کندل فعلی نزولی
                    df['close'].iloc[i] < df['low'].iloc[i-1]):        # پایین‌تر از low قبلی
                    
                    move = ((df['high'].iloc[i-1] - df['close'].iloc[i]) / df['high'].iloc[i-1]) * 100
                    
                    if move > 0.5:
                        signal_data = {
                            'symbol': symbol,
                            'type': 'BEARISH_ORDER_BLOCK',
                            'signal': 'SELL',
                            'top': df['high'].iloc[i-1],
                            'bottom': df['low'].iloc[i-1],
                            'price': df['close'].iloc[i],
                            'move_strength': round(move, 2),
                            'volume': df['volume'].iloc[i],
                            'strength': min(int(move * 20), 90),
                            'reason': f"📦 Bearish Order Block | حرکت: {move:.1f}%",
                            'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                        }
                        blocks.append(signal_data)
                        db.save_order_block(signal_data)
                        
            except:
                continue
        
        return blocks[-5:]


class LiquidityHuntDetector:
    """
    🎯 تشخیص شکار نقدینگی
    وقتی قیمت از سطح مهم رد می‌شود و برمی‌گردد
    """
    
    @staticmethod
    def detect(df, symbol, lookback=20):
        """تشخیص Liquidity Hunt"""
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
                if (current['low'] < prev_low and          # رفته زیر کف
                    current['close'] > prev_low and        # بسته شده بالای کف
                    current['close'] > current['open']):   # کندل صعودی
                    
                    hunt_depth = ((prev_low - current['low']) / prev_low) * 100
                    
                    signal_data = {
                        'symbol': symbol,
                        'type': 'LIQUIDITY_GRAB_LOW',
                        'signal': 'BUY',
                        'price': current['close'],
                        'hunt_level': prev_low,
                        'hunt_depth': round(hunt_depth, 3),
                        'stop_loss': current['low'] * 0.995,
                        'volume_spike': df['volume'].iloc[i] / df['volume'].iloc[i-1] if df['volume'].iloc[i-1] > 0 else 1,
                        'strength': min(75 + int(hunt_depth * 15), 95),
                        'reason': f"🎯 شکار نقدینگی زیر حمایت | عمق: {hunt_depth:.2f}%",
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                    }
                    signals.append(signal_data)
                    db.save_liquidity_hunt(signal_data)
                
                # شکار نقدینگی بالا (Short Signal)
                if (current['high'] > prev_high and        # رفته بالای سقف
                    current['close'] < prev_high and       # بسته شده زیر سقف
                    current['close'] < current['open']):   # کندل نزولی
                    
                    hunt_depth = ((current['high'] - prev_high) / prev_high) * 100
                    
                    signal_data = {
                        'symbol': symbol,
                        'type': 'LIQUIDITY_GRAB_HIGH',
                        'signal': 'SELL',
                        'price': current['close'],
                        'hunt_level': prev_high,
                        'hunt_depth': round(hunt_depth, 3),
                        'stop_loss': current['high'] * 1.005,
                        'volume_spike': df['volume'].iloc[i] / df['volume'].iloc[i-1] if df['volume'].iloc[i-1] > 0 else 1,
                        'strength': min(75 + int(hunt_depth * 15), 95),
                        'reason': f"🎯 شکار نقدینگی بالای مقاومت | عمق: {hunt_depth:.2f}%",
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                    }
                    signals.append(signal_data)
                    db.save_liquidity_hunt(signal_data)
                    
            except:
                continue
        
        return signals[-5:]


class DivergenceDetector:
    """
    📊 تشخیص واگرایی
    RSI Divergence
    """
    
    @staticmethod
    def detect(df, symbol):
        """یافتن واگرایی‌ها"""
        if len(df) < 30:
            return []
        
        df = df.copy()
        df['rsi'] = RSIIndicator(df['close'], window=14).rsi()
        
        signals = []
        lookback = 5
        
        for i in range(lookback * 2, len(df)):
            try:
                # واگرایی صعودی (Bullish Divergence)
                if (df['close'].iloc[i] < df['close'].iloc[i-lookback] and    # قیمت کف جدید
                    df['rsi'].iloc[i] > df['rsi'].iloc[i-lookback] and         # RSI کف جدید نداده
                    df['rsi'].iloc[i] < 40):                                    # RSI در منطقه oversold
                    
                    signal_data = {
                        'symbol': symbol,
                        'type': 'BULLISH_DIVERGENCE',
                        'signal': 'BUY',
                        'price': df['close'].iloc[i],
                        'rsi': round(df['rsi'].iloc[i], 1),
                        'indicator': 'RSI',
                        'strength': 85,
                        'reason': f"📈 واگرایی صعودی RSI | RSI: {df['rsi'].iloc[i]:.1f}",
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                    }
                    signals.append(signal_data)
                    db.save_divergence(signal_data)
                
                # واگرایی نزولی (Bearish Divergence)
                if (df['close'].iloc[i] > df['close'].iloc[i-lookback] and    # قیمت سقف جدید
                    df['rsi'].iloc[i] < df['rsi'].iloc[i-lookback] and         # RSI سقف جدید نداده
                    df['rsi'].iloc[i] > 60):                                    # RSI در منطقه overbought
                    
                    signal_data = {
                        'symbol': symbol,
                        'type': 'BEARISH_DIVERGENCE',
                        'signal': 'SELL',
                        'price': df['close'].iloc[i],
                        'rsi': round(df['rsi'].iloc[i], 1),
                        'indicator': 'RSI',
                        'strength': 85,
                        'reason': f"📉 واگرایی نزولی RSI | RSI: {df['rsi'].iloc[i]:.1f}",
                        'timestamp': df['timestamp'].iloc[i] if 'timestamp' in df.columns else datetime.utcnow()
                    }
                    signals.append(signal_data)
                    db.save_divergence(signal_data)
                    
            except:
                continue
        
        return signals[-5:]


class PumpDumpDetector:
    """
    🚀📉 تشخیص پامپ و دامپ
    """
    
    @staticmethod
    def detect_pump(df, symbol, threshold=5, window=15):
        """تشخیص پامپ"""
        if len(df) < window + 50:
            return []
        
        alerts = []
        
        try:
            recent = df.tail(window)
            start_price = recent['close'].iloc[0]
            end_price = recent['close'].iloc[-1]
            price_change = ((end_price - start_price) / start_price) * 100
            
            avg_vol = df['volume'].tail(100).mean()
            recent_vol = recent['volume'].mean()
            vol_change = ((recent_vol - avg_vol) / avg_vol) * 100 if avg_vol > 0 else 0
            
            # محاسبه momentum
            momentum = sum(1 if recent['close'].iloc[i] > recent['close'].iloc[i-1] else -1 
                          for i in range(1, len(recent)))
            
            if price_change >= threshold and vol_change > 30:
                alert = {
                    'symbol': symbol,
                    'alert_type': 'PUMP',
                    'type': 'STRONG_PUMP',
                    'signal': 'BUY',
                    'price': end_price,
                    'start_price': start_price,
                    'price_change': round(price_change, 2),
                    'volume_change': round(vol_change, 2),
                    'momentum': momentum,
                    'strength': min(70 + int(price_change * 2), 95),
                    'reason': f"🚀 PUMP! +{price_change:.1f}% | Vol +{vol_change:.0f}%",
                    'timestamp': datetime.utcnow()
                }
                alerts.append(alert)
                db.save_pump_dump(alert)
                
        except Exception as e:
            pass
        
        return alerts
    
    @staticmethod
    def detect_dump(df, symbol, threshold=5, window=15):
        """تشخیص دامپ"""
        if len(df) < window + 50:
            return []
        
        alerts = []
        
        try:
            recent = df.tail(window)
            start_price = recent['close'].iloc[0]
            end_price = recent['close'].iloc[-1]
            price_change = ((end_price - start_price) / start_price) * 100
            
            avg_vol = df['volume'].tail(100).mean()
            recent_vol = recent['volume'].mean()
            vol_change = ((recent_vol - avg_vol) / avg_vol) * 100 if avg_vol > 0 else 0
            
            momentum = sum(1 if recent['close'].iloc[i] > recent['close'].iloc[i-1] else -1 
                          for i in range(1, len(recent)))
            
            if price_change <= -threshold and vol_change > 30:
                alert = {
                    'symbol': symbol,
                    'alert_type': 'DUMP',
                    'type': 'STRONG_DUMP',
                    'signal': 'SELL',
                    'price': end_price,
                    'start_price': start_price,
                    'price_change': round(price_change, 2),
                    'volume_change': round(vol_change, 2),
                    'momentum': momentum,
                    'strength': min(70 + int(abs(price_change) * 2), 95),
                    'reason': f"📉 DUMP! {price_change:.1f}% | Vol +{vol_change:.0f}%",
                    'timestamp': datetime.utcnow()
                }
                alerts.append(alert)
                db.save_pump_dump(alert)
                
        except:
            pass
        
        return alerts


class SignalGenerator:
    """
    🎯 تولیدکننده سیگنال نهایی
    ترکیب همه روش‌ها
    """
    
    def __init__(self):
        self.whale = WhaleDetector()
        self.smart_money = SmartMoneyDetector()
        self.order_block = OrderBlockDetector()
        self.liquidity = LiquidityHuntDetector()
        self.divergence = DivergenceDetector()
        self.pump_dump = PumpDumpDetector()
    
    def analyze(self, df, symbol):
        """تحلیل کامل و تولید همه سیگنال‌ها"""
        all_signals = []
        
        try:
            # محاسبه اندیکاتورها
            df = Indicators.calculate_all(df)
            
            # جمع‌آوری سیگنال‌ها از همه منابع
            whale_signals = self.whale.detect(df, symbol)
            smart_signals = self.smart_money.detect(df, symbol)
            ob_signals = self.order_block.detect(df, symbol)
            liq_signals = self.liquidity.detect(df, symbol)
            div_signals = self.divergence.detect(df, symbol)
            
            # UT Bot
            _, ut_signals = Indicators.ut_bot_alert(df)
            for s in ut_signals:
                s['symbol'] = symbol
                db.save_ut_bot_alert(s)
            
            # MA Cross
            ma_signals = Indicators.detect_ma_cross(df)
            for s in ma_signals:
                s['symbol'] = symbol
                db.save_ma_cross(s)
            
            # پامپ و دامپ
            pump = self.pump_dump.detect_pump(df, symbol)
            dump = self.pump_dump.detect_dump(df, symbol)
            
            # ترکیب همه
            all_signals.extend(whale_signals)
            all_signals.extend(smart_signals)
            all_signals.extend(ob_signals)
            all_signals.extend(liq_signals)
            all_signals.extend(div_signals)
            all_signals.extend(ut_signals)
            all_signals.extend(ma_signals)
            all_signals.extend(pump)
            all_signals.extend(dump)
            
            # ذخیره اندیکاتورها در سیگنال‌ها
            ind_summary = Indicators.get_summary(df)
            for sig in all_signals:
                sig['indicators'] = ind_summary
            
            # ذخیره تاریخچه قیمت
            db.save_price_history(symbol, df)
            
        except Exception as e:
            print(f"Error analyzing {symbol}: {e}")
        
        return all_signals
    
    def get_best_signals(self, df, symbol, top_n=5):
        """بهترین سیگنال‌ها"""
        signals = self.analyze(df, symbol)
        signals.sort(key=lambda x: x.get('strength', 0), reverse=True)
        
        # ذخیره بهترین سیگنال‌ها
        ind_summary = Indicators.get_summary(df) if len(df) > 50 else {}
        for sig in signals[:top_n]:
            db.save_signal(sig, ind_summary)
        
        return signals[:top_n]

signal_generator = SignalGenerator()
EOF

# ═══════════════════════════════════════════════════════════════
# 📡 DATA FETCHER - دریافت داده واقعی
# ═══════════════════════════════════════════════════════════════
echo "📡 Creating data_fetcher.py - Real Data from Exchanges..."
cat > data_fetcher.py << 'EOF'
"""
📡 دریافت داده‌های واقعی از صرافی‌ها
بدون تحریم: KuCoin, Bybit, OKX, Gate.io, MEXC, Bitget
"""
import ccxt
import pandas as pd
from datetime import datetime
import time

class ExchangeManager:
    """مدیریت صرافی‌ها - داده واقعی فیوچرز"""
    
    # صرافی‌های بدون تحریم ایران
    EXCHANGES = {
        'kucoin': {
            'name': 'KuCoin Futures',
            'class': ccxt.kucoinfutures,
            'has_futures': True
        },
        'bybit': {
            'name': 'Bybit',
            'class': ccxt.bybit,
            'has_futures': True
        },
        'okx': {
            'name': 'OKX',
            'class': ccxt.okx,
            'has_futures': True
        },
        'gate': {
            'name': 'Gate.io',
            'class': ccxt.gateio,
            'has_futures': True
        },
        'mexc': {
            'name': 'MEXC',
            'class': ccxt.mexc,
            'has_futures': True
        },
        'bitget': {
            'name': 'Bitget',
            'class': ccxt.bitget,
            'has_futures': True
        }
    }
    
    def __init__(self, exchange_id='kucoin'):
        self.exchange_id = exchange_id
        self.exchange = None
        self.symbols = []
        self.init_exchange()
    
    def init_exchange(self):
        """اتصال به صرافی"""
        if self.exchange_id not in self.EXCHANGES:
            self.exchange_id = 'kucoin'
        
        try:
            info = self.EXCHANGES[self.exchange_id]
            self.exchange = info['class']({
                'enableRateLimit': True,
                'options': {'defaultType': 'swap'}  # فیوچرز
            })
            print(f"✅ Connected to {info['name']} (Real Futures Data)")
        except Exception as e:
            print(f"❌ Error: {e}, fallback to KuCoin")
            self.exchange = ccxt.kucoinfutures({'enableRateLimit': True})
    
    def change_exchange(self, new_id):
        """تغییر صرافی"""
        if new_id in self.EXCHANGES:
            self.exchange_id = new_id
            self.init_exchange()
            self.load_symbols()
            return True
        return False
    
    def load_symbols(self, limit=250):
        """بارگذاری لیست ارزهای فیوچرز"""
        try:
            self.exchange.load_markets()
            
            futures = []
            for symbol, market in self.exchange.markets.items():
                if market.get('swap') or market.get('future') or market.get('linear'):
                    if market.get('active', True):
                        if 'USDT' in symbol:  # فقط جفت‌های USDT
                            futures.append(symbol)
            
            self.symbols = sorted(futures)[:limit]
            print(f"📊 Loaded {len(self.symbols)} REAL futures pairs from {self.exchange_id}")
            return self.symbols
            
        except Exception as e:
            print(f"❌ Error loading symbols: {e}")
            self.symbols = ['BTC/USDT:USDT', 'ETH/USDT:USDT']
            return self.symbols
    
    def fetch_ohlcv(self, symbol, timeframe='15m', limit=200):
        """دریافت کندل‌های واقعی"""
        try:
            ohlcv = self.exchange.fetch_ohlcv(symbol, timeframe, limit=limit)
            
            df = pd.DataFrame(ohlcv, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume'])
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
            df['symbol'] = symbol
            
            return df
            
        except Exception as e:
            print(f"❌ Error fetching {symbol}: {e}")
            return pd.DataFrame()
    
    def get_ticker(self, symbol):
        """قیمت لحظه‌ای"""
        try:
            ticker = self.exchange.fetch_ticker(symbol)
            return {
                'symbol': symbol,
                'price': ticker.get('last', 0),
                'change_24h': ticker.get('percentage', 0),
                'volume_24h': ticker.get('quoteVolume', 0),
                'high_24h': ticker.get('high', 0),
                'low_24h': ticker.get('low', 0)
            }
        except:
            return None
    
    def get_all_tickers(self):
        """همه قیمت‌ها"""
        try:
            return self.exchange.fetch_tickers()
        except:
            return {}
    
    def get_top_movers(self, limit=20):
        """برترین تغییرات"""
        try:
            tickers = self.get_all_tickers()
            
            movers = []
            for symbol, data in tickers.items():
                if data.get('percentage') is not None:
                    movers.append({
                        'symbol': symbol,
                        'price': data.get('last', 0),
                        'change': data.get('percentage', 0),
                        'volume': data.get('quoteVolume', 0)
                    })
            
            gainers = sorted(movers, key=lambda x: x['change'], reverse=True)[:limit]
            losers = sorted(movers, key=lambda x: x['change'])[:limit]
            
            return {'gainers': gainers, 'losers': losers}
        except:
            return {'gainers': [], 'losers': []}

exchange = ExchangeManager('kucoin')
EOF

# ═══════════════════════════════════════════════════════════════
# ✅ VALIDATOR - اعتبارسنجی هر 3 دقیقه
# ═══════════════════════════════════════════════════════════════
echo "✅ Creating validator.py..."
cat > validator.py << 'EOF'
"""
✅ اعتبارسنجی سیگنال‌ها هر 3 دقیقه
بررسی صحت و ذخیره نتایج
"""
from datetime import datetime, timedelta
from database import db
from data_fetcher import exchange
from indicators import Indicators
import threading
import time

class SignalValidator:
    """اعتبارسنجی خودکار سیگنال‌ها"""
    
    def __init__(self, interval=180):  # 3 دقیقه
        self.interval = interval
        self.running = False
        self.thread = None
    
    def validate_signal(self, signal):
        """اعتبارسنجی یک سیگنال"""
        try:
            symbol = signal['symbol']
            entry = signal['entry_price']
            direction = signal['direction']
            target = signal.get('target_price')
            stop = signal.get('stop_loss')
            
            # قیمت فعلی
            ticker = exchange.get_ticker(symbol)
            if not ticker:
                return None
            
            current = ticker['price']
            
            # محاسبه سود/زیان
            if direction == 'BUY':
                change = ((current - entry) / entry) * 100
            else:
                change = ((entry - current) / entry) * 100
            
            # دریافت اندیکاتورها
            df = exchange.fetch_ohlcv(symbol, '15m', 50)
            ind = Indicators.get_summary(df) if not df.empty else {}
            
            # تعیین وضعیت
            status = 'ACTIVE'
            notes = f"قیمت: {current:.6f} | تغییر: {change:+.2f}%"
            
            if target and direction == 'BUY' and current >= target:
                status = 'SUCCESS'
                notes = f"🎯 هدف رسید! +{change:.2f}%"
            elif target and direction == 'SELL' and current <= target:
                status = 'SUCCESS'
                notes = f"🎯 هدف رسید! +{change:.2f}%"
            elif stop and direction == 'BUY' and current <= stop:
                status = 'STOPPED'
                notes = f"🛑 استاپ خورد! {change:.2f}%"
            elif stop and direction == 'SELL' and current >= stop:
                status = 'STOPPED'
                notes = f"🛑 استاپ خورد! {change:.2f}%"
            elif change >= 5:
                status = 'SUCCESS'
                notes = f"✅ سود +5%! {change:.2f}%"
            elif change <= -5:
                status = 'FAILED'
                notes = f"❌ زیان -5%! {change:.2f}%"
            
            # ذخیره در دیتابیس
            db.update_signal_validation(
                signal['id'],
                current,
                status,
                notes,
                ind
            )
            
            return {
                'signal_id': signal['id'],
                'symbol': symbol,
                'entry': entry,
                'current': current,
                'change': change,
                'status': status,
                'notes': notes
            }
            
        except Exception as e:
            print(f"Validation error: {e}")
            return None
    
    def validate_all(self):
        """اعتبارسنجی همه سیگنال‌های فعال"""
        signals = db.get_active_signals()
        results = []
        
        for sig in signals:
            result = self.validate_signal(sig)
            if result:
                results.append(result)
            time.sleep(0.3)
        
        return results
    
    def run_loop(self):
        """حلقه اعتبارسنجی"""
        while self.running:
            try:
                print(f"\n🔍 Validating signals... {datetime.now()}")
                results = self.validate_all()
                
                success = len([r for r in results if r['status'] == 'SUCCESS'])
                failed = len([r for r in results if r['status'] in ['FAILED', 'STOPPED']])
                active = len([r for r in results if r['status'] == 'ACTIVE'])
                
                print(f"✅ Done: {len(results)} signals | ✓{success} | ✗{failed} | ⏳{active}")
                
            except Exception as e:
                print(f"Validation loop error: {e}")
            
            time.sleep(self.interval)
    
    def start(self):
        """شروع"""
        if not self.running:
            self.running = True
            self.thread = threading.Thread(target=self.run_loop, daemon=True)
            self.thread.start()
            print("🔄 Validator started (every 3 minutes)")
    
    def stop(self):
        self.running = False

validator = SignalValidator()
EOF

# ═══════════════════════════════════════════════════════════════
# 🌐 APP - سرور اصلی
# ═══════════════════════════════════════════════════════════════
echo "🌐 Creating app.py..."
cat > app.py << 'EOF'
"""
🚀 سرور اصلی - Crypto Futures Signal System V3.0
"""
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
from datetime import datetime
import threading
import time

from database import db
from data_fetcher import exchange
from signals import signal_generator
from indicators import Indicators
from validator import validator

app = Flask(__name__)
app.config['SECRET_KEY'] = 'crypto_v3_2024'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

# کش داده‌ها
cache = {
    'signals': [],
    'whale_activities': [],
    'pump_dump': [],
    'movers': {'gainers': [], 'losers': []},
    'last_update': None
}

def scan_markets():
    """اسکن بازار و تولید سیگنال"""
    global cache
    
    while True:
        try:
            all_signals = []
            whale_list = []
            pump_dump_list = []
            
            symbols = exchange.symbols[:100]
            
            for symbol in symbols:
                try:
                    df = exchange.fetch_ohlcv(symbol, '15m', 200)
                    if df.empty:
                        continue
                    
                    # تولید سیگنال
                    signals = signal_generator.get_best_signals(df, symbol, 3)
                    
                    for sig in signals:
                        sig['detected_at'] = datetime.utcnow().isoformat()
                        all_signals.append(sig)
                        
                        # دسته‌بندی
                        if 'WHALE' in sig.get('type', ''):
                            whale_list.append(sig)
                        if 'PUMP' in sig.get('type', '') or 'DUMP' in sig.get('type', ''):
                            pump_dump_list.append(sig)
                    
                    if signals:
                        socketio.emit('new_signals', signals)
                    
                    time.sleep(0.5)
                    
                except Exception as e:
                    continue
            
            # بروزرسانی کش
            cache['signals'] = all_signals[-100:]
            cache['whale_activities'] = whale_list[-50:]
            cache['pump_dump'] = pump_dump_list[-50:]
            cache['movers'] = exchange.get_top_movers(20)
            cache['last_update'] = datetime.utcnow().isoformat()
            
            socketio.emit('cache_update', cache)
            
            print(f"✅ Scan: {len(all_signals)} signals | 🐋{len(whale_list)} whales | 🚀{len(pump_dump_list)} pump/dump")
            
            time.sleep(60)
            
        except Exception as e:
            print(f"Scan error: {e}")
            time.sleep(30)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/analytics')
def analytics():
    return render_template('analytics.html')

@app.route('/api/signals')
def get_signals():
    return jsonify(cache['signals'][-50:])

@app.route('/api/signals/history')
def signal_history():
    days = request.args.get('days', 7, type=int)
    return jsonify(db.get_signal_history(days))

@app.route('/api/whales')
def get_whales():
    return jsonify(cache['whale_activities'])

@app.route('/api/whales/history')
def whale_history():
    hours = request.args.get('hours', 48, type=int)
    return jsonify(db.get_whale_history(hours))

@app.route('/api/pump-dump')
def get_pump_dump():
    return jsonify(cache['pump_dump'])

@app.route('/api/pump-dump/history')
def pump_dump_history():
    hours = request.args.get('hours', 24, type=int)
    return jsonify(db.get_pump_dump_history(hours))

@app.route('/api/movers')
def get_movers():
    return jsonify(cache['movers'])

@app.route('/api/stats')
def get_stats():
    return jsonify(db.get_statistics())

@app.route('/api/report')
def get_report():
    days = request.args.get('days', 30, type=int)
    return jsonify(db.get_analysis_report(days=days))

@app.route('/api/exchange/change', methods=['POST'])
def change_exchange():
    data = request.json
    new_ex = data.get('exchange', 'kucoin')
    if exchange.change_exchange(new_ex):
        exchange.load_symbols()
        return jsonify({'success': True, 'exchange': new_ex})
    return jsonify({'success': False})

@app.route('/api/exchanges')
def get_exchanges():
    return jsonify({
        'current': exchange.exchange_id,
        'available': list(exchange.EXCHANGES.keys())
    })

@app.route('/api/symbols')
def get_symbols():
    return jsonify({
        'count': len(exchange.symbols),
        'symbols': exchange.symbols[:50]
    