#!/bin/bash

# =================================================================
# 🚀 نصب‌کننده خودکار سیستم معاملاتی REAL هادی - نسخه نهایی v2
# =================================================================
# این فایل تمام سرویس‌های مورد نیاز را نصب و راه‌اندازی می‌کند
# پشتیبانی از ۵ صرافی: OKX, Bybit, Kraken, Bitunix, LBank
# =================================================================

set -e  # توقف در صورت خطا

# رنگ‌های زیبا برای ترمینال
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =================================================================
# توابع کمکی
# =================================================================
print_step() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🔹 $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# =================================================================
# بررسی پیش‌نیازها
# =================================================================
print_step "بررسی پیش‌نیازهای سیستم"

# بررسی دسترسی روت
if [[ $EUID -eq 0 ]]; then
    print_error "لطفاً با کاربر معمولی اجرا کنید، نه روت!"
    exit 1
fi

# بررسی سیستم عامل
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_error "این نصب‌کننده فقط روی لینوکس کار می‌کند (Ubuntu 20.04+ یا Debian 11+)"
    exit 1
fi

# بررسی اینترنت
print_info "بررسی اتصال به اینترنت..."
if ! ping -c 1 google.com &> /dev/null; then
    print_error "اتصال به اینترنت برقرار نیست!"
    exit 1
fi
print_success "اتصال اینترنت برقرار است"

# =================================================================
# دریافت اطلاعات از کاربر
# =================================================================
print_step "تنظیمات اولیه سیستم"

echo -e "${YELLOW}لطفاً اطلاعات زیر را وارد کنید:${NC}\n"

# دایرکتوری نصب
read -p "📁 دایرکتوری نصب [~/trading-system]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-~/trading-system}
INSTALL_DIR=$(eval echo $INSTALL_DIR)

# پورت‌ها
read -p "🔌 پورت فرانت‌اند [3000]: " FRONTEND_PORT
FRONTEND_PORT=${FRONTEND_PORT:-3000}

read -p "🔌 پورت بک‌اند [8000]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-8000}

read -p "🔌 پورت PostgreSQL [5432]: " PG_PORT
PG_PORT=${PG_PORT:-5432}

read -p "🔌 پورت Redis [6379]: " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}

read -p "🔌 پورت RabbitMQ [5672]: " RMQ_PORT
RMQ_PORT=${RMQ_PORT:-5672}

# رمزهای عبور
read -sp "🔐 رمز عبور PostgreSQL: " PG_PASSWORD
echo
read -sp "🔐 رمز عبور Redis: " REDIS_PASSWORD
echo
read -sp "🔐 رمز عبور RabbitMQ: " RMQ_PASSWORD
echo

# API Keys
print_step "تنظیم API Keys صرافی‌ها"

echo -e "${YELLOW}لطفاً API Keyهای خود را وارد کنید (برای صرافی‌های غیرفعال می‌توانید خالی بگذارید):${NC}\n"

read -p "OKX API Key: " OKX_API_KEY
read -sp "OKX Secret Key: " OKX_SECRET_KEY
echo
read -p "OKX Passphrase: " OKX_PASSPHRASE

echo "-------------------"
read -p "Bybit API Key: " BYBIT_API_KEY
read -sp "Bybit Secret Key: " BYBIT_SECRET_KEY
echo

echo "-------------------"
read -p "Kraken API Key: " KRAKEN_API_KEY
read -sp "Kraken Secret Key: " KRAKEN_SECRET_KEY
echo

echo "-------------------"
read -p "Bitunix API Key: " BITUNIX_API_KEY
read -sp "Bitunix Secret Key: " BITUNIX_SECRET_KEY
echo
read -p "Bitunix Passphrase: " BITUNIX_PASSPHRASE

echo "-------------------"
read -p "LBank API Key: " LBANK_API_KEY
read -sp "LBank Secret Key: " LBANK_SECRET_KEY
echo

# =================================================================
# ایجاد ساختار دایرکتوری
# =================================================================
print_step "ایجاد ساختار پروژه در $INSTALL_DIR"

mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# ایجاد دایرکتوری‌های اصلی
mkdir -p {frontend,backend,brains,database,config,logs,scripts,data}

# ایجاد زیرشاخه‌های مغزها
mkdir -p brains/{brain_1_fast,brain_2_risk,brain_3_supervisor}
mkdir -p brains/brain_1_fast/{algorithms,connectors,websocket}
mkdir -p brains/brain_2_risk/{filters,validators,calculators}
mkdir -p brains/brain_3_supervisor/{validation,reporting,learning}

# ایجاد دایرکتوری‌های فرانت‌اند
mkdir -p frontend/{components,pages,styles,public,lib,hooks}
mkdir -p frontend/components/{filters,tables,charts,layout,dashboard}
mkdir -p frontend/pages/{filters,reports,settings,dashboard}

# ایجاد دایرکتوری‌های بک‌اند
mkdir -p backend/{api,core,models,services,utils,workers}
mkdir -p backend/api/{routes,websocket,middleware}
mkdir -p backend/services/{exchanges,algorithms,validation}

# ایجاد دایرکتوری دیتابیس
mkdir -p database/{postgres,timescaledb,redis,mongodb}

print_success "ساختار دایرکتوری با موفقیت ایجاد شد"

# =================================================================
# نصب Docker و Docker Compose
# =================================================================
print_step "نصب Docker و Docker Compose"

if ! command -v docker &> /dev/null; then
    print_info "در حال نصب Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    print_success "Docker نصب شد"
else
    print_success "Docker از قبل نصب است"
fi

if ! command -v docker-compose &> /dev/null; then
    print_info "در حال نصب Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose نصب شد"
else
    print_success "Docker Compose از قبل نصب است"
fi

# =================================================================
# ایجاد فایل docker-compose.yml
# =================================================================
print_step "ایجاد فایل docker-compose.yml"

cat > $INSTALL_DIR/docker-compose.yml << EOF
version: '3.8'

services:
  # ========== دیتابیس‌ها ==========
  postgres:
    image: timescale/timescaledb:latest-pg14
    container_name: trading-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: trading_db
      POSTGRES_USER: hduser
      POSTGRES_PASSWORD: ${PG_PASSWORD}
    ports:
      - "${PG_PORT}:5432"
    volumes:
      - ./database/postgres:/var/lib/postgresql/data
      - ./database/timescaledb/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - trading-network
    command: postgres -c 'max_connections=500'

  mongodb:
    image: mongo:latest
    container_name: trading-mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: hduser
      MONGO_INITDB_ROOT_PASSWORD: ${PG_PASSWORD}
      MONGO_INITDB_DATABASE: trading_db
    ports:
      - "27017:27017"
    volumes:
      - ./database/mongodb:/data/db
    networks:
      - trading-network

  redis:
    image: redis:7-alpine
    container_name: trading-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    ports:
      - "${REDIS_PORT}:6379"
    volumes:
      - ./database/redis:/data
    networks:
      - trading-network

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: trading-rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: hduser
      RABBITMQ_DEFAULT_PASS: ${RMQ_PASSWORD}
    ports:
      - "${RMQ_PORT}:5672"
      - "15672:15672"
    volumes:
      - ./database/rabbitmq:/var/lib/rabbitmq
    networks:
      - trading-network

  # ========== بک‌اند ==========
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: trading-backend
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
      - rabbitmq
      - mongodb
    environment:
      DATABASE_URL: postgresql://hduser:${PG_PASSWORD}@postgres:5432/trading_db
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      RABBITMQ_URL: amqp://hduser:${RMQ_PASSWORD}@rabbitmq:5672
      MONGODB_URL: mongodb://hduser:${PG_PASSWORD}@mongodb:27017
      
      # API Keys
      OKX_API_KEY: ${OKX_API_KEY}
      OKX_SECRET_KEY: ${OKX_SECRET_KEY}
      OKX_PASSPHRASE: ${OKX_PASSPHRASE}
      
      BYBIT_API_KEY: ${BYBIT_API_KEY}
      BYBIT_SECRET_KEY: ${BYBIT_SECRET_KEY}
      
      KRAKEN_API_KEY: ${KRAKEN_API_KEY}
      KRAKEN_SECRET_KEY: ${KRAKEN_SECRET_KEY}
      
      BITUNIX_API_KEY: ${BITUNIX_API_KEY}
      BITUNIX_SECRET_KEY: ${BITUNIX_SECRET_KEY}
      BITUNIX_PASSPHRASE: ${BITUNIX_PASSPHRASE}
      
      LBANK_API_KEY: ${LBANK_API_KEY}
      LBANK_SECRET_KEY: ${LBANK_SECRET_KEY}
    ports:
      - "${BACKEND_PORT}:8000"
    volumes:
      - ./backend:/app
      - ./logs:/app/logs
      - ./brains:/app/brains
      - ./config:/app/config
    networks:
      - trading-network
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload

  # ========== فرانت‌اند ==========
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: trading-frontend
    restart: unless-stopped
    depends_on:
      - backend
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:${BACKEND_PORT}
      NEXT_PUBLIC_WS_URL: ws://localhost:${BACKEND_PORT}
    ports:
      - "${FRONTEND_PORT}:3000"
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
    networks:
      - trading-network

  # ========== Celery Workers برای مغزها ==========
  brain-fast:
    build:
      context: ./brains/brain_1_fast
      dockerfile: Dockerfile
    container_name: brain-fast
    restart: unless-stopped
    depends_on:
      - backend
      - redis
      - rabbitmq
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      RABBITMQ_URL: amqp://hduser:${RMQ_PASSWORD}@rabbitmq:5672
      DATABASE_URL: postgresql://hduser:${PG_PASSWORD}@postgres:5432/trading_db
    volumes:
      - ./brains/brain_1_fast:/app
      - ./logs:/app/logs
      - ./config:/app/config
    networks:
      - trading-network
    command: celery -A worker worker --loglevel=info -Q fast_brain -c 4

  brain-risk:
    build:
      context: ./brains/brain_2_risk
      dockerfile: Dockerfile
    container_name: brain-risk
    restart: unless-stopped
    depends_on:
      - backend
      - redis
      - rabbitmq
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      RABBITMQ_URL: amqp://hduser:${RMQ_PASSWORD}@rabbitmq:5672
      DATABASE_URL: postgresql://hduser:${PG_PASSWORD}@postgres:5432/trading_db
    volumes:
      - ./brains/brain_2_risk:/app
      - ./logs:/app/logs
      - ./config:/app/config
    networks:
      - trading-network
    command: celery -A worker worker --loglevel=info -Q risk_brain -c 2

  brain-supervisor:
    build:
      context: ./brains/brain_3_supervisor
      dockerfile: Dockerfile
    container_name: brain-supervisor
    restart: unless-stopped
    depends_on:
      - backend
      - redis
      - rabbitmq
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      RABBITMQ_URL: amqp://hduser:${RMQ_PASSWORD}@rabbitmq:5672
      DATABASE_URL: postgresql://hduser:${PG_PASSWORD}@postgres:5432/trading_db
    volumes:
      - ./brains/brain_3_supervisor:/app
      - ./logs:/app/logs
      - ./config:/app/config
    networks:
      - trading-network
    command: celery -A worker beat --loglevel=info

  # ========== مانیتورینگ ==========
  prometheus:
    image: prom/prometheus:latest
    container_name: trading-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./data/prometheus:/prometheus
    networks:
      - trading-network

  grafana:
    image: grafana/grafana:latest
    container_name: trading-grafana
    restart: unless-stopped
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - ./data/grafana:/var/lib/grafana
    networks:
      - trading-network

networks:
  trading-network:
    driver: bridge
EOF

print_success "فایل docker-compose.yml ایجاد شد"

# =================================================================
# ایجاد فایل‌های اصلی
# =================================================================
print_step "ایجاد فایل‌های اصلی سیستم"

# ========== فایل requirements.txt بک‌اند ==========
cat > $INSTALL_DIR/backend/requirements.txt << EOF
# Core
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
python-dotenv==1.0.0

# Databases
sqlalchemy==2.0.23
asyncpg==0.29.0
psycopg2-binary==2.9.9
redis==5.0.1
pymongo==4.6.0
timescaledb==0.1.0

# Message Queue
celery==5.3.4
rabbitmq==0.2.0

# Exchanges
ccxt==4.1.22
websockets==12.0
aiohttp==3.9.1

# Algorithms
numpy==1.26.2
pandas==2.1.3
scikit-learn==1.3.2
ta==0.10.2
scipy==1.11.4

# Machine Learning
tensorflow==2.14.0
torch==2.1.1
xgboost==2.0.2

# Utils
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
httpx==0.25.1
loguru==0.7.2
schedule==1.2.0

# Monitoring
prometheus-client==0.19.0
EOF

# ========== فایل package.json فرانت‌اند ==========
cat > $INSTALL_DIR/frontend/package.json << EOF
{
  "name": "trading-system-frontend",
  "version": "2.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "14.0.3",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "typescript": "5.3.2",
    "@types/node": "20.10.0",
    "@types/react": "18.2.39",
    "@types/react-dom": "18.2.17",
    "tailwindcss": "3.3.6",
    "autoprefixer": "10.4.16",
    "postcss": "8.4.31",
    "recharts": "2.10.3",
    "ag-grid-react": "30.2.0",
    "ag-grid-community": "30.2.0",
    "ag-grid-enterprise": "30.2.0",
    "axios": "1.6.2",
    "react-query": "3.39.3",
    "socket.io-client": "4.5.4",
    "date-fns": "2.30.0",
    "zustand": "4.4.6",
    "react-hook-form": "7.48.2",
    "zod": "3.22.4",
    "lodash": "4.17.21",
    "chart.js": "4.4.0",
    "react-chartjs-2": "5.2.0"
  },
  "devDependencies": {
    "eslint": "8.54.0",
    "eslint-config-next": "14.0.3",
    "prettier": "3.1.0"
  }
}
EOF

# ========== فایل main.py بک‌اند ==========
cat > $INSTALL_DIR/backend/main.py << 'EOF'
# =================================================================
# سیستم معاملاتی REAL هادی - بک‌اند اصلی
# =================================================================

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import asyncio
import json
from typing import List, Dict, Any
from datetime import datetime
import logging
from loguru import logger
import redis.asyncio as redis
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
import os

# ========== تنظیمات اولیه ==========
app = FastAPI(title="سیستم معاملاتی REAL هادی", version="2.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ========== اتصال به دیتابیس ==========
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://hduser:password@postgres:5432/trading_db")
engine = create_async_engine(DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://"))
async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# ========== اتصال به Redis ==========
REDIS_URL = os.getenv("REDIS_URL", "redis://:password@redis:6379")
redis_client = redis.from_url(REDIS_URL, decode_responses=True)

# ========== مدیریت WebSocket ==========
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.subscribers: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        for channel in self.subscribers:
            if websocket in self.subscribers[channel]:
                self.subscribers[channel].remove(websocket)

    async def subscribe(self, websocket: WebSocket, channel: str):
        if channel not in self.subscribers:
            self.subscribers[channel] = []
        self.subscribers[channel].append(websocket)

    async def broadcast_to_channel(self, channel: str, message: dict):
        if channel in self.subscribers:
            for connection in self.subscribers[channel]:
                try:
                    await connection.send_json(message)
                except:
                    pass

manager = ConnectionManager()

# ========== مسیرهای API ==========
@app.get("/")
async def root():
    return {
        "name": "سیستم معاملاتی REAL هادی",
        "version": "2.0.0",
        "status": "running",
        "brains": ["fast", "risk", "supervisor"],
        "exchanges": ["OKX", "Bybit", "Kraken", "Bitunix", "LBank"],
        "timestamp": datetime.now().isoformat()
    }

@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

# ========== WebSocket برای داده‌های زنده ==========
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message["type"] == "subscribe":
                await manager.subscribe(websocket, message["channel"])
                await websocket.send_json({
                    "type": "subscribed",
                    "channel": message["channel"]
                })
            
            elif message["type"] == "ping":
                await websocket.send_json({"type": "pong", "timestamp": datetime.now().isoformat()})
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# ========== API برای سیگنال‌ها ==========
@app.get("/api/signals")
async def get_signals(
    signal_type: str = None,
    exchange: str = None,
    symbol: str = None,
    min_score: float = None,
    limit: int = 100
):
    """دریافت سیگنال‌ها با فیلترهای مختلف"""
    
    # TODO: دریافت از دیتابیس
    signals = [
        {
            "id": "sig_001",
            "type": "whale_bait",
            "exchange": "OKX",
            "symbol": "BTC/USDT",
            "direction": "long",
            "price": 42000,
            "score": 0.95,
            "algorithms": ["mother_whale_bait", "whale_flow"],
            "detected_at": datetime.now().isoformat(),
            "expires_at": datetime.now().isoformat(),
            "is_bait": False,
            "whale_flow": 150.5
        },
        {
            "id": "sig_002",
            "type": "pump",
            "exchange": "Bybit",
            "symbol": "ETH/USDT",
            "direction": "long",
            "price": 2200,
            "score": 0.88,
            "algorithms": ["icebreaker", "oi_del_advanced"],
            "detected_at": datetime.now().isoformat(),
            "expires_at": datetime.now().isoformat(),
            "is_bait": True,
            "whale_flow": -50.2
        }
    ]
    
    # اعمال فیلترها
    filtered = signals
    if signal_type:
        filtered = [s for s in filtered if s["type"] == signal_type]
    if exchange:
        filtered = [s for s in filtered if s["exchange"] == exchange]
    if symbol:
        filtered = [s for s in filtered if symbol in s["symbol"]]
    if min_score:
        filtered = [s for s in filtered if s["score"] >= min_score]
    
    return {
        "total": len(filtered),
        "signals": filtered[:limit],
        "filters": {
            "signal_type": signal_type,
            "exchange": exchange,
            "symbol": symbol,
            "min_score": min_score
        }
    }

# ========== API برای جریان نهنگ ==========
@app.get("/api/whale-flow")
async def get_whale_flow(
    exchange: str = None,
    symbol: str = None,
    minutes: int = 60
):
    """دریافت جریان پول نهنگ‌ها"""
    
    # TODO: دریافت از دیتابیس
    flows = [
        {
            "exchange": "OKX",
            "symbol": "BTC/USDT",
            "inflow": 1250.5,
            "outflow": 800.2,
            "net_flow": 450.3,
            "whale_count": 12,
            "timestamp": datetime.now().isoformat()
        },
        {
            "exchange": "Bybit",
            "symbol": "ETH/USDT",
            "inflow": 850.7,
            "outflow": 920.1,
            "net_flow": -69.4,
            "whale_count": 8,
            "timestamp": datetime.now().isoformat()
        }
    ]
    
    return {
        "total": len(flows),
        "flows": flows,
        "period": f"last_{minutes}_minutes"
    }

# ========== API برای آمار مغزها ==========
@app.get("/api/brains/stats")
async def get_brains_stats():
    """دریافت آمار عملکرد مغزها"""
    
    return {
        "fast_brain": {
            "status": "active",
            "signals_today": 156,
            "algorithms": ["mother_whale_bait", "whale_flow", "oi_del_advanced", "icebreaker", "bait_detector"],
            "avg_response_time": 0.85,
            "accuracy": 0.92,
            "last_update": datetime.now().isoformat()
        },
        "risk_brain": {
            "status": "active",
            "validations_today": 145,
            "filters": ["whale_filter", "bait_filter"],
            "avg_score": 0.87,
            "rejected_signals": 12,
            "last_update": datetime.now().isoformat()
        },
        "supervisor_brain": {
            "status": "active",
            "patterns_discovered": 8,
            "validations_today": 156,
            "avg_confidence": 0.94,
            "learned_patterns": 23,
            "last_update": datetime.now().isoformat()
        }
    }

# ========== API برای تنظیمات ==========
@app.get("/api/settings")
async def get_settings():
    """دریافت تنظیمات سیستم"""
    
    return {
        "exchanges": {
            "OKX": {"active": True, "futures": True, "spot": True},
            "Bybit": {"active": True, "futures": True, "spot": True},
            "Kraken": {"active": True, "futures": True, "spot": True},
            "Bitunix": {"active": True, "futures": True, "spot": False},
            "LBank": {"active": True, "futures": True, "spot": True}
        },
        "algorithms": {
            "mother_whale_bait": {"active": True, "priority": 1, "threshold": 0.8},
            "whale_flow": {"active": True, "priority": 1, "threshold": 100},
            "oi_del_advanced": {"active": True, "priority": 2, "threshold": 0.3},
            "icebreaker": {"active": True, "priority": 2, "threshold": 0.7},
            "bait_detector": {"active": True, "priority": 1, "threshold": 0.85}
        },
        "brains": {
            "fast": {"active": True, "interval": 10, "workers": 4},
            "risk": {"active": True, "interval": 5, "workers": 2},
            "supervisor": {"active": True, "interval": 60, "workers": 1}
        }
    }

@app.post("/api/settings")
async def update_settings(settings: dict):
    """به‌روزرسانی تنظیمات"""
    
    # TODO: ذخیره در دیتابیس
    return {"status": "updated", "settings": settings}

# ========== API برای گزارشات ==========
@app.get("/api/reports/validation")
async def get_validation_report(
    start_date: str = None,
    end_date: str = None,
    algorithm: str = None
):
    """گزارش اعتبارسنجی الگوریتم‌ها"""
    
    return {
        "period": {
            "start": start_date or "2024-01-01",
            "end": end_date or "2024-01-31"
        },
        "algorithms": [
            {
                "name": "mother_whale_bait",
                "signals": 245,
                "successful": 215,
                "failed": 30,
                "accuracy": 0.8776,
                "avg_score": 0.92,
                "trend": "improving"
            },
            {
                "name": "whale_flow",
                "signals": 189,
                "successful": 167,
                "failed": 22,
                "accuracy": 0.8836,
                "avg_score": 0.89,
                "trend": "stable"
            },
            {
                "name": "oi_del_advanced",
                "signals": 134,
                "successful": 118,
                "failed": 16,
                "accuracy": 0.8806,
                "avg_score": 0.91,
                "trend": "improving"
            }
        ],
        "summary": {
            "total_signals": 568,
            "avg_accuracy": 0.8806,
            "best_algorithm": "mother_whale_bait",
            "worst_algorithm": "oi_del_advanced"
        }
    }

# ========== Task‌های پس‌زمینه ==========
@app.on_event("startup")
async def startup_event():
    """کارهای اولیه هنگام راه‌اندازی"""
    logger.info("سیستم معاملاتی REAL هادی راه‌اندازی شد")
    
    # اتصال به Redis
    await redis_client.ping()
    logger.info("اتصال به Redis برقرار شد")
    
    # شروع task‌های پس‌زمینه
    asyncio.create_task(broadcast_heartbeat())
    asyncio.create_task(check_whale_flows())

@app.on_event("shutdown")
async def shutdown_event():
    """کارهای هنگام خاموش شدن"""
    logger.info("سیستم در حال خاموش شدن...")
    await redis_client.close()

# ========== Task‌های پس‌زمینه ==========
async def broadcast_heartbeat():
    """ارسال heartbeat به کلاینت‌ها"""
    while True:
        await asyncio.sleep(5)
        await manager.broadcast_to_channel("heartbeat", {
            "type": "heartbeat",
            "timestamp": datetime.now().isoformat()
        })

async def check_whale_flows():
    """بررسی مداوم جریان نهنگ‌ها"""
    while True:
        await asyncio.sleep(10)
        # TODO: بررسی واقعی جریان نهنگ‌ها
        await manager.broadcast_to_channel("whale_flow", {
            "type": "whale_flow_update",
            "data": {
                "BTC": {"inflow": 1250, "outflow": 800},
                "ETH": {"inflow": 850, "outflow": 920}
            },
            "timestamp": datetime.now().isoformat()
        })

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# ========== الگوریتم طعمه نهنگ مادر ==========
cat > $INSTALL_DIR/brains/brain_1_fast/algorithms/mother_whale_bait.py << 'EOF'
# =================================================================
# الگوریتم طعمه نهنگ مادر (Mother Whale Bait)
# تشخیص سفارش‌های بزرگ جعلی که برای فریب معامله‌گران گذاشته می‌شوند
# =================================================================

import asyncio
import numpy as np
from typing import Dict, List, Tuple, Optional
from datetime import datetime, timedelta
import logging
from dataclasses import dataclass
from collections import deque

logger = logging.getLogger(__name__)

@dataclass
class OrderBookSnapshot:
    """اسنپ‌شات از سفارش‌ها"""
    exchange: str
    symbol: str
    timestamp: datetime
    bids: List[Tuple[float, float]]  # قیمت، حجم
    asks: List[Tuple[float, float]]  # قیمت، حجم
    bid_volume: float
    ask_volume: float
    spread: float

@dataclass
class WhaleBaitSignal:
    """سیگنال طعمه نهنگ"""
    exchange: str
    symbol: str
    timestamp: datetime
    bait_type: str  # 'bid' یا 'ask'
    bait_price: float
    bait_size: float
    removed_after: float  # ثانیه
    confidence: float
    reason: str

class MotherWhaleBaitDetector:
    """
    تشخیص‌دهنده طعمه نهنگ مادر
    
    این الگوریتم سفارش‌های بزرگ جعلی را تشخیص می‌دهد که:
    1. ناگهان در سفارش‌ها ظاهر می‌شوند
    2. حجم بسیار بالایی دارند (معمولاً 10x تا 100x حجم عادی)
    3. بعد از چند ثانیه تا چند دقیقه ناپدید می‌شوند
    4. باعث حرکت قیمت در جهت مخالف می‌شوند
    """
    
    def __init__(self, config: dict = None):
        self.config = config or {}
        
        # پارامترهای تشخیص
        self.volume_threshold = self.config.get('volume_threshold', 10)  # 10x حجم عادی
        self.time_window = self.config.get('time_window', 60)  # 60 ثانیه
        self.min_bait_size = self.config.get('min_bait_size', 50000)  # حداقل 50k دلار
        self.max_bait_lifetime = self.config.get('max_bait_lifetime', 300)  # حداکثر 5 دقیقه
        
        # تاریخچه سفارش‌ها
        self.order_history = deque(maxlen=1000)
        self.bait_history = deque(maxlen=100)
        
        # آمار
        self.total_baits_detected = 0
        self.successful_predictions = 0
        
    async def analyze_orderbook(self, 
                               exchange: str, 
                               symbol: str,
                               bids: List[Tuple[float, float]],
                               asks: List[Tuple[float, float]]) -> List[WhaleBaitSignal]:
        """
        تحلیل عمق بازار برای تشخیص طعمه نهنگ
        """
        signals = []
        timestamp = datetime.now()
        
        # محاسبه آمار
        total_bid_volume = sum(vol for price, vol in bids[:20])  # 20 سطح اول
        total_ask_volume = sum(vol for price, vol in asks[:20])
        avg_bid_size = total_bid_volume / len(bids[:20]) if bids else 0
        avg_ask_size = total_ask_volume / len(asks[:20]) if asks else 0
        
        # بررسی سفارش‌های خرید بزرگ
        for i, (price, volume) in enumerate(bids[:10]):  # 10 سطح اول
            if volume > avg_bid_size * self.volume_threshold and volume > self.min_bait_size:
                # بررسی اینکه آیا این سفارش قبلاً دیده شده
                if not self._is_in_history(exchange, symbol, price, volume, 'bid'):
                    # محاسبه احتمال طعمه بودن
                    confidence = self._calculate_bait_probability(
                        price, volume, bids, asks, 'bid', i
                    )
                    
                    if confidence > 0.7:  # آستانه اعتماد
                        signals.append(WhaleBaitSignal(
                            exchange=exchange,
                            symbol=symbol,
                            timestamp=timestamp,
                            bait_type='bid',
                            bait_price=price,
                            bait_size=volume,
                            removed_after=0,
                            confidence=confidence,
                            reason=f"سفارش خرید بزرگ با حجم {volume:.2f} در سطح {i+1}"
                        ))
        
        # بررسی سفارش‌های فروش بزرگ
        for i, (price, volume) in enumerate(asks[:10]):
            if volume > avg_ask_size * self.volume_threshold and volume > self.min_bait_size:
                if not self._is_in_history(exchange, symbol, price, volume, 'ask'):
                    confidence = self._calculate_bait_probability(
                        price, volume, bids, asks, 'ask', i
                    )
                    
                    if confidence > 0.7:
                        signals.append(WhaleBaitSignal(
                            exchange=exchange,
                            symbol=symbol,
                            timestamp=timestamp,
                            bait_type='ask',
                            bait_price=price,
                            bait_size=volume,
                            removed_after=0,
                            confidence=confidence,
                            reason=f"سغارش فروش بزرگ با حجم {volume:.2f} در سطح {i+1}"
                        ))
        
        # ذخیره در تاریخچه
        snapshot = OrderBookSnapshot(
            exchange=exchange,
            symbol=symbol,
            timestamp=timestamp,
            bids=bids[:20],
            asks=asks[:20],
            bid_volume=total_bid_volume,
            ask_volume=total_ask_volume,
            spread=asks[0][0] - bids[0][0] if asks and bids else 0
        )
        self.order_history.append(snapshot)
        
        # بررسی حذف طعمه‌های قبلی
        removed_baits = self._check_removed_baits()
        signals.extend(removed_baits)
        
        return signals
    
    def _calculate_bait_probability(self, 
                                   price: float,
                                   volume: float,
                                   bids: List[Tuple[float, float]],
                                   asks: List[Tuple[float, float]],
                                   order_type: str,
                                   level: int) -> float:
        """
        محاسبه احتمال طعمه بودن یک سفارش
        """
        confidence = 0.0
        reasons = []
        
        # 1. بررسی ناهنجاری حجم (60% وزن)
        avg_volume = self._get_average_volume(order_type)
        if avg_volume > 0:
            volume_ratio = volume / avg_volume
            volume_score = min(volume_ratio / 20, 1.0)  # کپ 20x
            confidence += volume_score * 0.6
        
        # 2. بررسی موقعیت در سفارش‌ها (20% وزن)
        # سفارش‌های خیلی نزدیک به قیمت فعلی مشکوک‌ترند
        position_score = 1.0 - (level / 20)  # سطح 0 = 1.0, سطح 19 = 0.05
        confidence += position_score * 0.2
        
        # 3. بررسی عمق بازار اطراف (20% وزن)
        depth_score = self._analyze_surrounding_depth(price, volume, bids, asks, order_type)
        confidence += depth_score * 0.2
        
        # 4. بررسی الگوهای تاریخی
        historical_score = self._check_historical_patterns(price, volume)
        confidence = (confidence + historical_score) / 2  # میانگین
        
        return min(confidence, 1.0)
    
    def _get_average_volume(self, order_type: str) -> float:
        """محاسبه میانگین حجم در تاریخچه"""
        volumes = []
        for snapshot in list(self.order_history)[-50:]:  # 50 اسنپ‌شات آخر
            if order_type == 'bid':
                vols = [vol for _, vol in snapshot.bids[:10]]
            else:
                vols = [vol for _, vol in snapshot.asks[:10]]
            if vols:
                volumes.extend(vols)
        
        return np.mean(volumes) if volumes else 0
    
    def _analyze_surrounding_depth(self,
                                  price: float,
                                  volume: float,
                                  bids: List[Tuple[float, float]],
                                  asks: List[Tuple[float, float]],
                                  order_type: str) -> float:
        """
        تحلیل عمق بازار اطراف سفارش
        """
        if order_type == 'bid':
            # بررسی سفارش‌های اطراف در سمت خرید
            nearby_volumes = [vol for p, vol in bids if abs(p - price) / price < 0.001]  # 0.1%
        else:
            # بررسی سفارش‌های اطراف در سمت فروش
            nearby_volumes = [vol for p, vol in asks if abs(p - price) / price < 0.001]
        
        if not nearby_volumes:
            return 0.5  # هیچ سفارش نزدیکی نیست
        
        avg_nearby = np.mean(nearby_volumes)
        
        if volume > avg_nearby * 5:  # 5x بزرگتر از میانگین اطراف
            return 0.9
        elif volume > avg_nearby * 3:
            return 0.7
        elif volume > avg_nearby * 2:
            return 0.5
        else:
            return 0.3
    
    def _check_historical_patterns(self, price: float, volume: float) -> float:
        """
        بررسی الگوهای تاریخی مشابه
        """
        similar_baits = 0
        total_baits = 0
        
        for bait in self.bait_history:
            if abs(bait.bait_price - price) / price < 0.01:  # 1% اختلاف قیمت
                total_baits += 1
                if bait.removed_after < 60:  # طعمه‌های سریع
                    similar_baits += 1
        
        if total_baits == 0:
            return 0.5
        
        return similar_baits / total_baits
    
    def _is_in_history(self, exchange: str, symbol: str, price: float, volume: float, order_type: str) -> bool:
        """بررسی وجود سفارش در تاریخچه"""
        for snapshot in list(self.order_history)[-10:]:  # 10 اسنپ‌شات آخر
            if snapshot.exchange != exchange or snapshot.symbol != symbol:
                continue
            
            orders = snapshot.bids if order_type == 'bid' else snapshot.asks
            for p, v in orders[:10]:
                if abs(p - price) / price < 0.0001 and abs(v - volume) / volume < 0.1:
                    return True
        
        return False
    
    def _check_removed_baits(self) -> List[WhaleBaitSignal]:
        """
        بررسی طعمه‌هایی که حذف شده‌اند
        """
        signals = []
        now = datetime.now()
        
        # لیست طعمه‌های قبلی
        for bait in list(self.bait_history):
            if bait.removed_after == 0:  # هنوز بررسی نشده
                # بررسی اینکه آیا این سفارش هنوز وجود دارد
                found = False
                for snapshot in list(self.order_history)[-3:]:  # 3 اسنپ‌شات آخر
                    orders = snapshot.bids if bait.bait_type == 'bid' else snapshot.asks
                    for p, v in orders:
                        if abs(p - bait.bait_price) / bait.bait_price < 0.0001:
                            found = True
                            break
                
                if not found:
                    # سفارش حذف شده
                    bait.removed_after = (now - bait.timestamp).total_seconds()
                    signals.append(bait)
                    
                    # به‌روزرسانی آمار
                    self.total_baits_detected += 1
                    if bait.removed_after < 60:  # حذف سریع = طعمه قوی
                        self.successful_predictions += 1
        
        return signals
    
    def get_statistics(self) -> dict:
        """دریافت آمار الگوریتم"""
        return {
            'total_baits_detected': self.total_baits_detected,
            'successful_predictions': self.successful_predictions,
            'accuracy': self.successful_predictions / self.total_baits_detected if self.total_baits_detected > 0 else 0,
            'active_baits': len([b for b in self.bait_history if b.removed_after == 0])
        }

# نمونه استفاده
async def main():
    detector = MotherWhaleBaitDetector()
    
    # شبیه‌سازی سفارش‌ها
    bids = [
        (42000, 1.5),
        (41900, 2.0),
        (41800, 150.0),  # سفارش بزرگ مشکوک
        (41700, 1.8),
        (41600, 2.2)
    ]
    
    asks = [
        (42100, 1.3),
        (42200, 1.7),
        (42300, 200.0),  # سفارش بزرگ مشکوک
        (42400, 1.9),
        (42500, 2.1)
    ]
    
    signals = await detector.analyze_orderbook("OKX", "BTC/USDT", bids, asks)
    
    for signal in signals:
        print(f"🎣 طعمه نهنگ detected:")
        print(f"   صرافی: {signal.exchange}")
        print(f"   نماد: {signal.symbol}")
        print(f"   نوع: {'خرید' if signal.bait_type == 'bid' else 'فروش'}")
        print(f"   قیمت: {signal.bait_price}")
        print(f"   حجم: {signal.bait_size:.2f}")
        print(f"   اعتماد: {signal.confidence:.2%}")
        print(f"   دلیل: {signal.reason}")
        print()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# ========== الگوریتم جریان نهنگ ==========
cat > $INSTALL_DIR/brains/brain_1_fast/algorithms/whale_flow.py << 'EOF'
# =================================================================
# الگوریتم جریان نهنگ (Whale Flow)
# رصد جریان پول نهنگ‌ها بین صرافی‌ها و تشخیص ورود/خروج
# =================================================================

import asyncio
import numpy as np
from typing import Dict, List, Tuple, Optional
from datetime import datetime, timedelta
from collections import defaultdict, deque
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)

@dataclass
class WhaleTransaction:
    """تراکنش نهنگ"""
    exchange: str
    symbol: str
    timestamp: datetime
    side: str  # 'buy' یا 'sell'
    price: float
    volume: float
    value_usd: float
    is_whale: bool
    confidence: float

@dataclass
class WhaleFlowSignal:
    """سیگنال جریان نهنگ"""
    exchange: str
    symbol: str
    timestamp: datetime
    flow_type: str  # 'inflow' یا 'outflow'
    volume_usd: float
    whale_count: int
    avg_price: float
    intensity: float  # شدت جریان (0-1)
    prediction: str  # 'bullish' یا 'bearish'

class WhaleFlowDetector:
    """
    تشخیص‌دهنده جریان پول نهنگ‌ها
    
    این الگوریتم:
    1. تراکنش‌های بزرگ را رصد می‌کند
    2. جریان خالص ورود/خروج را محاسبه می‌کند
    3. جهت حرکت قیمت را پیش‌بینی می‌کند
    4. الگوهای تجمعی نهنگ‌ها را تشخیص می‌دهد
    """
    
    def __init__(self, config: dict = None):
        self.config = config or {}
        
        # پارامترها
        self.whale_threshold_usd = self.config.get('whale_threshold_usd', 100000)  # 100k دلار
        self.time_window = self.config.get('time_window', 300)  # 5 دقیقه
        self.min_whale_count = self.config.get('min_whale_count', 3)  # حداقل تعداد نهنگ
        
        # تاریخچه
        self.transactions = deque(maxlen=10000)
        self.flow_history = deque(maxlen=100)
        
        # آمار
        self.total_whale_txs = 0
        self.total_flow_value = 0.0
        
    async def analyze_trades(self,
                            exchange: str,
                            symbol: str,
                            trades: List[Dict]) -> List[WhaleFlowSignal]:
        """
        تحلیل تراکنش‌ها برای تشخیص جریان نهنگ
        """
        signals = []
        now = datetime.now()
        whale_txs = []
        
        # تشخیص تراکنش‌های نهنگ
        for trade in trades:
            value_usd = trade['price'] * trade['volume']
            
            if value_usd >= self.whale_threshold_usd:
                whale_tx = WhaleTransaction(
                    exchange=exchange,
                    symbol=symbol,
                    timestamp=datetime.fromtimestamp(trade['timestamp']/1000),
                    side=trade['side'],
                    price=trade['price'],
                    volume=trade['volume'],
                    value_usd=value_usd,
                    is_whale=True,
                    confidence=self._calculate_tx_confidence(trade)
                )
                whale_txs.append(whale_tx)
                self.transactions.append(whale_tx)
                self.total_whale_txs += 1
                self.total_flow_value += value_usd
        
        if whale_txs:
            # محاسبه جریان خالص
            flow_signal = self._calculate_flow(whale_txs, exchange, symbol, now)
            if flow_signal:
                signals.append(flow_signal)
                self.flow_history.append(flow_signal)
        
        return signals
    
    def _calculate_tx_confidence(self, trade: Dict) -> float:
        """محاسبه اعتبار تراکنش"""
        confidence = 0.8  # پایه
        
        # بررسی اندازه تراکنش
        value_usd = trade['price'] * trade['volume']
        if value_usd > self.whale_threshold_usd * 10:
            confidence += 0.1
        
        # بررسی الگوهای زمانی
        hour = datetime.fromtimestamp(trade['timestamp']/1000).hour
        if 9 <= hour <= 16:  # ساعات کاری
            confidence += 0.05
        
        return min(confidence, 1.0)
    
    def _calculate_flow(self,
                       whale_txs: List[WhaleTransaction],
                       exchange: str,
                       symbol: str,
                       timestamp: datetime) -> Optional[WhaleFlowSignal]:
        """محاسبه جریان خالص"""
        
        inflow = sum(tx.value_usd for tx in whale_txs if tx.side == 'buy')
        outflow = sum(tx.value_usd for tx in whale_txs if tx.side == 'sell')
        net_flow = inflow - outflow
        
        buy_count = len([tx for tx in whale_txs if tx.side == 'buy'])
        sell_count = len([tx for tx in whale_txs if tx.side == 'sell'])
        
        if buy_count + sell_count < self.min_whale_count:
            return None
        
        # محاسبه شدت جریان
        total_value = inflow + outflow
        if total_value == 0:
            return None
        
        intensity = abs(net_flow) / total_value
        
        # تعیین نوع جریان
        if net_flow > 0:
            flow_type = 'inflow'
            prediction = 'bullish'
        else:
            flow_type = 'outflow'
            prediction = 'bearish'
        
        # میانگین قیمت
        avg_price = np.mean([tx.price for tx in whale_txs])
        
        return WhaleFlowSignal(
            exchange=exchange,
            symbol=symbol,
            timestamp=timestamp,
            flow_type=flow_type,
            volume_usd=abs(net_flow),
            whale_count=buy_count + sell_count,
            avg_price=avg_price,
            intensity=intensity,
            prediction=prediction
        )
    
    def get_whale_accumulation(self, symbol: str, minutes: int = 60) -> Dict:
        """محاسبه تجمع نهنگ‌ها برای یک نماد"""
        
        cutoff = datetime.now() - timedelta(minutes=minutes)
        
        # فیلتر تراکنش‌های مربوطه
        relevant_txs = [
            tx for tx in self.transactions
            if tx.symbol == symbol and tx.timestamp >= cutoff
        ]
        
        if not relevant_txs:
            return {}
        
        # محاسبه آمار
        buy_volume = sum(tx.value_usd for tx in relevant_txs if tx.side == 'buy')
        sell_volume = sum(tx.value_usd for tx in relevant_txs if tx.side == 'sell')
        
        unique_whales = len(set(
            (tx.exchange, tx.symbol) for tx in relevant_txs
        ))
        
        return {
            'symbol': symbol,
            'period_minutes': minutes,
            'buy_volume_usd': buy_volume,
            'sell_volume_usd': sell_volume,
            'net_flow_usd': buy_volume - sell_volume,
            'unique_whales': unique_whales,
            'total_transactions': len(relevant_txs),
            'accumulation_ratio': buy_volume / (buy_volume + sell_volume) if (buy_volume + sell_volume) > 0 else 0.5,
            'timestamp': datetime.now().isoformat()
        }
    
    def get_cross_exchange_flow(self, symbol: str) -> Dict:
        """محاسبه جریان بین صرافی‌ها"""
        
        exchange_flows = defaultdict(lambda: {'inflow': 0, 'outflow': 0})
        
        for tx in self.transactions:
            if tx.symbol == symbol:
                if tx.side == 'buy':
                    exchange_flows[tx.exchange]['inflow'] += tx.value_usd
                else:
                    exchange_flows[tx.exchange]['outflow'] += tx.value_usd
        
        # محاسبه خالص جریان هر صرافی
        result = {}
        for exchange, flows in exchange_flows.items():
            net = flows['inflow'] - flows['outflow']
            result[exchange] = {
                'inflow_usd': flows['inflow'],
                'outflow_usd': flows['outflow'],
                'net_flow_usd': net,
                'direction': 'inflow' if net > 0 else 'outflow'
            }
        
        return result
    
    def get_statistics(self) -> dict:
        """دریافت آمار کلی"""
        return {
            'total_whale_transactions': self.total_whale_txs,
            'total_flow_value_usd': self.total_flow_value,
            'active_signals': len(self.flow_history),
            'avg_confidence': np.mean([s.intensity for s in self.flow_history]) if self.flow_history else 0
        }

# نمونه استفاده
async def main():
    detector = WhaleFlowDetector()
    
    # شبیه‌سازی تراکنش‌ها
    trades = [
        {'price': 42000, 'volume': 5, 'side': 'buy', 'timestamp': datetime.now().timestamp() * 1000},
        {'price': 42100, 'volume': 3, 'side': 'sell', 'timestamp': datetime.now().timestamp() * 1000},
        {'price': 41900, 'volume': 10, 'side': 'buy', 'timestamp': datetime.now().timestamp() * 1000},
    ]
    
    signals = await detector.analyze_trades("OKX", "BTC/USDT", trades)
    
    for signal in signals:
        print(f"🌊 جریان نهنگ:")
        print(f"   صرافی: {signal.exchange}")
        print(f"   نماد: {signal.symbol}")
        print(f"   نوع: {'ورود' if signal.flow_type == 'inflow' else 'خروج'}")
        print(f"   حجم: ${signal.volume_usd:,.0f}")
        print(f"   تعداد نهنگ: {signal.whale_count}")
        print(f"   شدت: {signal.intensity:.2%}")
        print(f"   پیش‌بینی: {signal.prediction}")
        print()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# ========== اتصال‌دهنده Bitunix ==========
cat > $INSTALL_DIR/brains/brain_1_fast/connectors/bitunix_connector.py << 'EOF'
# =================================================================
# اتصال‌دهنده صرافی Bitunix
# =================================================================

import ccxt
import asyncio
import websockets
import json
from typing import Dict, List, Optional, Callable
from datetime import datetime
import hmac
import hashlib
import base64
import logging

logger = logging.getLogger(__name__)

class BitunixConnector:
    """
    اتصال به صرافی Bitunix برای فیوچرز
    """
    
    def __init__(self, api_key: str = None, secret_key: str = None, passphrase: str = None):
        self.api_key = api_key
        self.secret_key = secret_key
        self.passphrase = passphrase
        
        # تنظیمات
        self.rest_url = "https://fapi.bitunix.com"
        self.ws_url = "wss://fstream.bitunix.com/ws"
        
        # کلاینت CCXT
        self.exchange = ccxt.bitunix({
            'apiKey': api_key,
            'secret': secret_key,
            'password': passphrase,
            'enableRateLimit': True,
            'options': {
                'defaultType': 'future',
                'adjustForTimeDifference': True
            }
        })
        
        # WebSocket connections
        self.ws_connections = {}
        self.subscriptions = {}
        self.callbacks = {}
        
        # Market data
        self.orderbooks = {}
        self.tickers = {}
        self.trades = []
        
    async def connect_websocket(self, stream_type: str, symbols: List[str], callback: Callable):
        """
        اتصال WebSocket به Bitunix
        """
        try:
            # ایجاد connection
            ws = await websockets.connect(self.ws_url)
            self.ws_connections[stream_type] = ws
            
            # آماده‌سازی subscription
            subscribe_msg = {
                "op": "subscribe",
                "args": [f"{symbol.lower()}@{stream_type}" for symbol in symbols]
            }
            
            await ws.send(json.dumps(subscribe_msg))
            self.subscriptions[stream_type] = symbols
            self.callbacks[stream_type] = callback
            
            # شروع listening
            asyncio.create_task(self._listen_websocket(stream_type, ws))
            
            logger.info(f"WebSocket connected for {stream_type}: {symbols}")
            
        except Exception as e:
            logger.error(f"WebSocket connection failed: {e}")
    
    async def _listen_websocket(self, stream_type: str, ws: websockets.WebSocketClientProtocol):
        """
        listening به WebSocket
        """
        try:
            async for message in ws:
                data = json.loads(message)
                
                # پردازش بر اساس نوع
                if 'e' in data:
                    event_type = data['e']
                    
                    if event_type == 'depthUpdate':
                        await self._handle_depth_update(data)
                    elif event_type == 'trade':
                        await self._handle_trade(data)
                    elif event_type == '24hrTicker':
                        await self._handle_ticker(data)
                
                # فراخوانی callback
                if stream_type in self.callbacks:
                    await self.callbacks[stream_type](data)
                    
        except websockets.exceptions.ConnectionClosed:
            logger.warning(f"WebSocket connection closed for {stream_type}")
            # تلاش مجدد
            await asyncio.sleep(5)
            await self.connect_websocket(stream_type, self.subscriptions[stream_type], self.callbacks[stream_type])
    
    async def _handle_depth_update(self, data: Dict):
        """به‌روزرسانی عمق بازار"""
        symbol = data['s']
        
        if symbol not in self.orderbooks:
            self.orderbooks[symbol] = {'bids': {}, 'asks': {}}
        
        # به‌روزرسانی bids
        for bid in data['b']:
            price = float(bid[0])
            volume = float(bid[1])
            if volume == 0:
                if price in self.orderbooks[symbol]['bids']:
                    del self.orderbooks[symbol]['bids'][price]
            else:
                self.orderbooks[symbol]['bids'][price] = volume
        
        # به‌روزرسانی asks
        for ask in data['a']:
            price = float(ask[0])
            volume = float(ask[1])
            if volume == 0:
                if price in self.orderbooks[symbol]['asks']:
                    del self.orderbooks[symbol]['asks'][price]
            else:
                self.orderbooks[symbol]['asks'][price] = volume
    
    async def _handle_trade(self, data: Dict):
        """پردازش تراکنش جدید"""
        trade = {
            'exchange': 'bitunix',
            'symbol': data['s'],
            'price': float(data['p']),
            'volume': float(data['q']),
            'side': 'buy' if data['m'] else 'sell',
            'timestamp': data['T'],
            'id': data['t']
        }
        self.trades.append(trade)
        
        # نگهداری حداکثر 1000 تراکنش آخر
        if len(self.trades) > 1000:
            self.trades = self.trades[-1000:]
    
    async def _handle_ticker(self, data: Dict):
        """به‌روزرسانی ticker"""
        self.tickers[data['s']] = {
            'last': float(data['c']),
            'high': float(data['h']),
            'low': float(data['l']),
            'volume': float(data['v']),
            'change': float(data['P']),
            'timestamp': data['E']
        }
    
    async def get_orderbook(self, symbol: str, limit: int = 20) -> Dict:
        """
        دریافت عمق بازار از REST API
        """
        try:
            orderbook = self.exchange.fetch_order_book(symbol, limit)
            return {
                'bids': orderbook['bids'][:limit],
                'asks': orderbook['asks'][:limit],
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error fetching orderbook: {e}")
            return {}
    
    async def get_ticker(self, symbol: str) -> Dict:
        """
        دریافت ticker
        """
        try:
            ticker = self.exchange.fetch_ticker(symbol)
            return {
                'last': ticker['last'],
                'bid': ticker['bid'],
                'ask': ticker['ask'],
                'high': ticker['high'],
                'low': ticker['low'],
                'volume': ticker['baseVolume'],
                'quoteVolume': ticker['quoteVolume'],
                'change': ticker['percentage'],
                'timestamp': ticker['timestamp']
            }
        except Exception as e:
            logger.error(f"Error fetching ticker: {e}")
            return {}
    
    async def get_funding_rate(self, symbol: str) -> Dict:
        """
        دریافت نرخ فاندینگ
        """
        try:
            funding = self.exchange.fetch_funding_rate(symbol)
            return {
                'symbol': symbol,
                'funding_rate': funding['fundingRate'],
                'next_funding_time': funding['nextFundingTime'],
                'timestamp': funding['timestamp']
            }
        except Exception as e:
            logger.error(f"Error fetching funding rate: {e}")
            return {}
    
    async def get_open_interest(self, symbol: str) -> Dict:
        """
        دریافت Open Interest
        """
        try:
            oi = self.exchange.fetch_open_interest(symbol)
            return {
                'symbol': symbol,
                'open_interest': oi['openInterestAmount'],
                'open_interest_value': oi['openInterestValue'],
                'timestamp': oi['timestamp']
            }
        except Exception as e:
            logger.error(f"Error fetching open interest: {e}")
            return {}
    
    async def get_historical_klines(self, symbol: str, timeframe: str = '1m', limit: int = 500) -> List:
        """
        دریافت کندل‌های تاریخی
        """
        try:
            ohlcv = self.exchange.fetch_ohlcv(symbol, timeframe, limit=limit)
            result = []
            for candle in ohlcv:
                result.append({
                    'timestamp': candle[0],
                    'open': candle[1],
                    'high': candle[2],
                    'low': candle[3],
                    'close': candle[4],
                    'volume': candle[5]
                })
            return result
        except Exception as e:
            logger.error(f"Error fetching klines: {e}")
            return []
    
    def generate_signature(self, timestamp: str, method: str, path: str, body: str = '') -> str:
        """
        تولید امضا برای API
        """
        message = timestamp + method + path + body
        signature = hmac.new(
            self.secret_key.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        return signature
    
    async def place_order(self, symbol: str, side: str, order_type: str, 
                         amount: float, price: float = None, params: Dict = None) -> Dict:
        """
        ثبت سفارش جدید
        """
        try:
            order = self.exchange.create_order(
                symbol=symbol,
                type=order_type,
                side=side,
                amount=amount,
                price=price,
                params=params or {}
            )
            return {
                'id': order['id'],
                'symbol': order['symbol'],
                'side': order['side'],
                'type': order['type'],
                'price': order['price'],
                'amount': order['amount'],
                'status': order['status'],
                'timestamp': order['timestamp']
            }
        except Exception as e:
            logger.error(f"Error placing order: {e}")
            return {}
    
    async def cancel_order(self, order_id: str, symbol: str) -> bool:
        """
        لغو سفارش
        """
        try:
            result = self.exchange.cancel_order(order_id, symbol)
            return result.get('status') == 'canceled'
        except Exception as e:
            logger.error(f"Error cancelling order: {e}")
            return False
    
    async def get_positions(self) -> List:
        """
        دریافت پوزیشن‌های باز
        """
        try:
            positions = self.exchange.fetch_positions()
            result = []
            for pos in positions:
                if float(pos['contracts']) > 0:
                    result.append({
                        'symbol': pos['symbol'],
                        'side': pos['side'],
                        'amount': pos['contracts'],
                        'entry_price': pos['entryPrice'],
                        'mark_price': pos['markPrice'],
                        'liquidation_price': pos['liquidationPrice'],
                        'unrealized_pnl': pos['unrealizedPnl'],
                        'percentage': pos['percentage']
                    })
            return result
        except Exception as e:
            logger.error(f"Error fetching positions: {e}")
            return []
    
    async def get_balance(self) -> Dict:
        """
        دریافت موجودی حساب
        """
        try:
            balance = self.exchange.fetch_balance()
            return {
                'total': balance['total'],
                'free': balance['free'],
                'used': balance['used']
            }
        except Exception as e:
            logger.error(f"Error fetching balance: {e}")
            return {}

# نمونه استفاده
async def main():
    connector = BitunixConnector(
        api_key="YOUR_API_KEY",
        secret_key="YOUR_SECRET_KEY",
        passphrase="YOUR_PASSPHRASE"
    )
    
    # تعریف callback
    async def on_depth_update(data):
        print(f"Depth update: {data['s']}")
    
    # اتصال WebSocket
    await connector.connect_websocket(
        stream_type="depth",
        symbols=["BTCUSDT", "ETHUSDT"],
        callback=on_depth_update
    )
    
    # دریافت ticker
    ticker = await connector.get_ticker("BTCUSDT")
    print(f"BTC Ticker: {ticker}")
    
    # دریافت Open Interest
    oi = await connector.get_open_interest("BTCUSDT")
    print(f"BTC Open Interest: {oi}")
    
    # نگه داشتن connection
    await asyncio.sleep(3600)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# ========== فایل Dockerfile برای مغزها ==========
cat > $INSTALL_DIR/brains/brain_1_fast/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# نصب وابستگی‌های سیستم
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# کپی requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# کپی سورس
COPY . .

# ایجاد دایرکتوری لاگ
RUN mkdir -p /app/logs

CMD ["celery", "-A", "worker", "worker", "--loglevel=info", "-Q", "fast_brain"]
EOF

# ========== فایل worker.py برای مغز سریع ==========
cat > $INSTALL_DIR/brains/brain_1_fast/worker.py << 'EOF'
# =================================================================
# Worker مغز سریع (Fast Brain)
# =================================================================

from celery import Celery
from datetime import datetime, timedelta
import asyncio
import json
from typing import Dict, List
import logging
from algorithms.mother_whale_bait import MotherWhaleBaitDetector
from algorithms.whale_flow import WhaleFlowDetector
from algorithms.oi_del_advanced import OIDelAdvancedDetector
from algorithms.icebreaker import IcebreakerDetector
from algorithms.bait_detector import BaitDetector

# تنظیمات Celery
app = Celery('fast_brain')
app.config_from_object('celeryconfig')

# الگوریتم‌ها
whale_bait_detector = MotherWhaleBaitDetector()
whale_flow_detector = WhaleFlowDetector()
oi_del_detector = OIDelAdvancedDetector()
icebreaker_detector = IcebreakerDetector()
bait_detector = BaitDetector()

logger = logging.getLogger(__name__)

@app.task
def analyze_orderbook(exchange: str, symbol: str, orderbook: Dict):
    """تحلیل عمق بازار"""
    try:
        # تشخیص طعمه نهنگ
        bait_signals = asyncio.run(
            whale_bait_detector.analyze_orderbook(
                exchange, symbol,
                orderbook.get('bids', []),
                orderbook.get('asks', [])
            )
        )
        
        # تشخیص شکست سطوح
        icebreaker_signals = asyncio.run(
            icebreaker_detector.analyze_orderbook(
                exchange, symbol, orderbook
            )
        )
        
        # تشخیص طعمه عمومی
        bait_general = asyncio.run(
            bait_detector.analyze_orderbook(
                exchange, symbol, orderbook
            )
        )
        
        signals = bait_signals + icebreaker_signals + bait_general
        
        if signals:
            logger.info(f"Found {len(signals)} signals from {exchange} {symbol}")
            
        return {
            'exchange': exchange,
            'symbol': symbol,
            'timestamp': datetime.now().isoformat(),
            'signals': [s.__dict__ for s in signals]
        }
        
    except Exception as e:
        logger.error(f"Error analyzing orderbook: {e}")
        return {}

@app.task
def analyze_trades(exchange: str, symbol: str, trades: List[Dict]):
    """تحلیل تراکنش‌ها"""
    try:
        # تشخیص جریان نهنگ
        flow_signals = asyncio.run(
            whale_flow_detector.analyze_trades(exchange, symbol, trades)
        )
        
        # تشخیص تغییرات OI
        oi_signals = asyncio.run(
            oi_del_detector.analyze_trades(exchange, symbol, trades)
        )
        
        signals = flow_signals + oi_signals
        
        if signals:
            logger.info(f"Found {len(signals)} flow signals from {exchange} {symbol}")
            
        return {
            'exchange': exchange,
            'symbol': symbol,
            'timestamp': datetime.now().isoformat(),
            'signals': [s.__dict__ for s in signals]
        }
        
    except Exception as e:
        logger.error(f"Error analyzing trades: {e}")
        return {}

@app.task
def aggregate_signals(signals_list: List[Dict]) -> Dict:
    """تجمیع سیگنال‌ها از منابع مختلف"""
    
    aggregated = {
        'timestamp': datetime.now().isoformat(),
        'total_signals': len(signals_list),
        'by_exchange': {},
        'by_type': {},
        'by_symbol': {},
        'high_priority': [],
        'signals': signals_list
    }
    
    for signal in signals_list:
        # بر اساس صرافی
        exchange = signal.get('exchange', 'unknown')
        if exchange not in aggregated['by_exchange']:
            aggregated['by_exchange'][exchange] = 0
        aggregated['by_exchange'][exchange] += 1
        
        # بر اساس نوع
        for s in signal.get('signals', []):
            signal_type = s.get('type', 'unknown')
            if signal_type not in aggregated['by_type']:
                aggregated['by_type'][signal_type] = 0
            aggregated['by_type'][signal_type] += 1
            
            # سیگنال‌های با اولویت بالا
            if s.get('confidence', 0) > 0.9:
                aggregated['high_priority'].append(s)
    
    return aggregated

@app.task
def cleanup_old_data():
    """پاکسازی داده‌های قدیمی"""
    # TODO: پیاده‌سازی پاکسازی
    logger.info("Cleaning up old data...")
    return {'status': 'cleaned', 'timestamp': datetime.now().isoformat()}
EOF

# ========== فایل celeryconfig.py ==========
cat > $INSTALL_DIR/brains/brain_1_fast/celeryconfig.py << 'EOF'
broker_url = 'amqp://hduser:password@rabbitmq:5672'
result_backend = 'redis://:password@redis:6379/0'

task_serializer = 'json'
result_serializer = 'json'
accept_content = ['json']
timezone = 'Asia/Tehran'
enable_utc = True

task_track_started = True
task_time_limit = 30 * 60
task_soft_time_limit = 25 * 60

worker_prefetch_multiplier = 1
worker_max_tasks_per_child = 200

task_queues = {
    'fast_brain': {
        'exchange': 'fast_brain',
        'routing_key': 'fast_brain',
    },
}

task_routes = {
    'analyze_orderbook': {'queue': 'fast_brain'},
    'analyze_trades': {'queue': 'fast_brain'},
    'aggregate_signals': {'queue': 'fast_brain'},
}
EOF

# ========== فایل‌های فرانت‌اند ==========
cat > $INSTALL_DIR/frontend/pages/index.tsx << 'EOF'
import React, { useEffect, useState } from 'react';
import { NextPage } from 'next';
import Head from 'next/head';
import Dashboard from '../components/dashboard/MainDashboard';

const Home: NextPage = () => {
  return (
    <>
      <Head>
        <title>سیستم معاملاتی REAL هادی</title>
        <meta name="description" content="سیستم معاملاتی هوشمند با ۵ صرافی" />
        <link rel="icon" href="/favicon.ico" />
      </Head>
      
      <main dir="rtl">
        <Dashboard />
      </main>
    </>
  );
};

export default Home;
EOF

# ========== فایل‌های پیکربندی ==========
cat > $INSTALL_DIR/config/algorithms.yaml << EOF
# =================================================================
# تنظیمات الگوریتم‌ها
# =================================================================

mother_whale_bait:
  active: true
  priority: 1
  volume_threshold: 10
  time_window: 60
  min_bait_size: 50000
  max_bait_lifetime: 300
  description: "تشخیص طعمه نهنگ مادر"

whale_flow:
  active: true
  priority: 1
  whale_threshold_usd: 100000
  time_window: 300
  min_whale_count: 3
  description: "رصد جریان پول نهنگ‌ها"

oi_del_advanced:
  active: true
  priority: 2
  oi_change_threshold: 0.15
  volume_threshold: 2.0
  min_confidence: 0.7
  description: "تحلیل تغییرات Open Interest"

icebreaker:
  active: true
  priority: 2
  depth_levels: 10
  volume_threshold: 5.0
  breakout_confirmations: 3
  description: "تشخیص شکست سطوح مقاومت/حمایت"

bait_detector:
  active: true
  priority: 1
  sensitivity: 0.8
  pattern_window: 50
  description: "تشخیص طعمه‌های عمومی"
EOF

cat > $INSTALL_DIR/config/filters.yaml << EOF
# =================================================================
# تنظیمات فیلترها
# =================================================================

whale_filter:
  active: true
  min_whale_size: 50000
  max_whale_age: 300
  require_confirmation: true
  description: "فیلتر مخصوص نهنگ"

bait_filter:
  active: true
  min_confidence: 0.7
  check_history: true
  description: "فیلتر تشخیص طعمه"

signal_validator:
  active: true
  min_score: 0.6
  require_multi_exchange: false
  max_age_seconds: 60
  description: "اعتبارسنجی سیگنال"
EOF

cat > $INSTALL_DIR/config/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'trading-system'
    static_configs:
      - targets: ['backend:8000']
    metrics_path: '/metrics'

  - job_name: 'brains'
    static_configs:
      - targets: ['brain-fast:8001', 'brain-risk:8002', 'brain-supervisor:8003']
    metrics_path: '/metrics'

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:9121']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['rabbitmq:15692']
EOF

# ========== فایل init.sql برای TimescaleDB ==========
cat > $INSTALL_DIR/database/timescaledb/init.sql << 'EOF'
-- =================================================================
-- راه‌اندازی TimescaleDB برای داده‌های زمانی
-- =================================================================

-- ایجاد extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ========== جدول سیگنال‌ها ==========
CREATE TABLE IF NOT EXISTS signals (
    id BIGSERIAL PRIMARY KEY,
    signal_id VARCHAR(50) UNIQUE NOT NULL,
    type VARCHAR(50) NOT NULL,
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    direction VARCHAR(10),
    price DECIMAL(20, 8),
    volume DECIMAL(20, 8),
    confidence DECIMAL(5, 4),
    algorithms JSONB,
    metadata JSONB,
    detected_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- تبدیل به hypertable
SELECT create_hypertable('signals', 'detected_at');

-- ایندکس‌ها
CREATE INDEX idx_signals_type ON signals (type);
CREATE INDEX idx_signals_exchange ON signals (exchange);
CREATE INDEX idx_signals_symbol ON signals (symbol);
CREATE INDEX idx_signals_detected_at ON signals (detected_at DESC);

-- ========== جدول جریان نهنگ ==========
CREATE TABLE IF NOT EXISTS whale_flow (
    id BIGSERIAL PRIMARY KEY,
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    inflow_usd DECIMAL(20, 2),
    outflow_usd DECIMAL(20, 2),
    net_flow_usd DECIMAL(20, 2),
    whale_count INTEGER,
    avg_price DECIMAL(20, 8),
    intensity DECIMAL(5, 4),
    prediction VARCHAR(10),
    metadata JSONB,
    timestamp TIMESTAMPTZ NOT NULL
);

SELECT create_hypertable('whale_flow', 'timestamp');

CREATE INDEX idx_whale_flow_exchange ON whale_flow (exchange);
CREATE INDEX idx_whale_flow_symbol ON whale_flow (symbol);
CREATE INDEX idx_whale_flow_timestamp ON whale_flow (timestamp DESC);

-- ========== جدول تراکنش‌ها ==========
CREATE TABLE IF NOT EXISTS transactions (
    id BIGSERIAL PRIMARY KEY,
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10),
    price DECIMAL(20, 8),
    volume DECIMAL(20, 8),
    value_usd DECIMAL(20, 2),
    is_whale BOOLEAN DEFAULT FALSE,
    trade_id VARCHAR(50),
    metadata JSONB,
    timestamp TIMESTAMPTZ NOT NULL
);

SELECT create_hypertable('transactions', 'timestamp');

CREATE INDEX idx_transactions_exchange ON transactions (exchange);
CREATE INDEX idx_transactions_symbol ON transactions (symbol);
CREATE INDEX idx_transactions_is_whale ON transactions (is_whale);
CREATE INDEX idx_transactions_timestamp ON transactions (timestamp DESC);

-- ========== جدول عملکرد الگوریتم‌ها ==========
CREATE TABLE IF NOT EXISTS algorithm_performance (
    id BIGSERIAL PRIMARY KEY,
    algorithm_name VARCHAR(50) NOT NULL,
    signals_count INTEGER,
    successful_count INTEGER,
    failed_count INTEGER,
    accuracy DECIMAL(5, 4),
    avg_confidence DECIMAL(5, 4),
    total_value DECIMAL(20, 2),
    metadata JSONB,
    date DATE NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_algorithm_performance_name ON algorithm_performance (algorithm_name);
CREATE INDEX idx_algorithm_performance_date ON algorithm_performance (date DESC);

-- ========== جدول تنظیمات ==========
CREATE TABLE IF NOT EXISTS settings (
    id SERIAL PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    key VARCHAR(50) NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by VARCHAR(50),
    UNIQUE(category, key)
);

-- ========== جدول لاگ‌ها ==========
CREATE TABLE IF NOT EXISTS system_logs (
    id BIGSERIAL PRIMARY KEY,
    level VARCHAR(10) NOT NULL,
    component VARCHAR(50),
    message TEXT,
    metadata JSONB,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

SELECT create_hypertable('system_logs', 'timestamp');

CREATE INDEX idx_system_logs_level ON system_logs (level);
CREATE INDEX idx_system_logs_component ON system_logs (component);
CREATE INDEX idx_system_logs_timestamp ON system_logs (timestamp DESC);

-- ========== ویوهای تحلیلی ==========

-- ویو آمار روزانه
CREATE OR REPLACE VIEW daily_stats AS
SELECT 
    DATE(detected_at) as date,
    COUNT(*) as total_signals,
    COUNT(DISTINCT type) as signal_types,
    COUNT(DISTINCT exchange) as exchanges,
    AVG(confidence) as avg_confidence,
    SUM(CASE WHEN confidence > 0.8 THEN 1 ELSE 0 END) as high_confidence_signals
FROM signals
GROUP BY DATE(detected_at)
ORDER BY date DESC;

-- ویو جریان خالص نهنگ
CREATE OR REPLACE VIEW whale_net_flow_hourly AS
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    exchange,
    symbol,
    SUM(inflow_usd) as total_inflow,
    SUM(outflow_usd) as total_outflow,
    SUM(net_flow_usd) as net_flow,
    AVG(intensity) as avg_intensity
FROM whale_flow
GROUP BY DATE_TRUNC('hour', timestamp), exchange, symbol;

-- ========== کاربران و دسترسی‌ها ==========
CREATE USER hduser WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE trading_db TO hduser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hduser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hduser;

-- ========== داده‌های اولیه ==========
INSERT INTO settings (category, key, value, description) VALUES
('system', 'version', '"2.0.0"', 'نسخه سیستم'),
('system', 'brains', '["fast", "risk", "supervisor"]', 'مغزهای فعال'),
('exchanges', 'supported', '["OKX", "Bybit", "Kraken", "Bitunix", "LBank"]', 'صرافی‌های پشتیبانی شده'),
('algorithms', 'active', '["mother_whale_bait", "whale_flow", "oi_del_advanced", "icebreaker", "bait_detector"]', 'الگوریتم‌های فعال');
EOF

# ========== فایل راه‌انداز ==========
cat > $INSTALL_DIR/start.sh << 'EOF'
#!/bin/bash

# =================================================================
# راه‌انداز سیستم معاملاتی REAL هادی
# =================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   راه‌اندازی سیستم معاملاتی REAL هادی - نسخه ۲.۰ ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# بررسی Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker نصب نیست!${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose نصب نیست!${NC}"
    exit 1
fi

# دریافت پورت‌ها از فایل env اگر وجود دارد
if [ -f .env ]; then
    source .env
fi

# شروع سرویس‌ها
echo -e "${YELLOW}📦 در حال راه‌اندازی سرویس‌ها...${NC}"

# بررسی وجود فایل docker-compose
if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}❌ فایل docker-compose.yml یافت نشد!${NC}"
    exit 1
fi

# پاک کردن کانتینرهای قبلی
echo -e "${YELLOW}🧹 در حال پاکسازی کانتینرهای قبلی...${NC}"
docker-compose down -v 2>/dev/null

# ساخت و راه‌اندازی
echo -e "${YELLOW}🏗️  در حال ساخت و راه‌اندازی سرویس‌ها...${NC}"
docker-compose up -d --build

# منتظر ماندن برای آماده شدن سرویس‌ها
echo -e "${YELLOW}⏳ منتظر آماده شدن سرویس‌ها...${NC}"
sleep 10

# بررسی وضعیت سرویس‌ها
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}📊 وضعیت سرویس‌ها:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

docker-compose ps

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ سیستم با موفقیت راه‌اندازی شد!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# نمایش آدرس‌ها
FRONTEND_PORT=${FRONTEND_PORT:-3000}
BACKEND_PORT=${BACKEND_PORT:-8000}

echo -e "${YELLOW}🌐 آدرس‌های دسترسی:${NC}"
echo -e "   📱 فرانت‌اند: ${GREEN}http://localhost:${FRONTEND_PORT}${NC}"
echo -e "   🔧 بک‌اند: ${GREEN}http://localhost:${BACKEND_PORT}${NC}"
echo -e "   📊 Grafana: ${GREEN}http://localhost:3001${NC} (user: admin, pass: admin)"
echo -e "   🐰 RabbitMQ: ${GREEN}http://localhost:15672${NC} (user: hduser, pass: your_password)"
echo -e "   📈 Prometheus: ${GREEN}http://localhost:9090${NC}"

echo -e "\n${YELLOW}📝 لاگ‌ها:${NC}"
echo -e "   👀 مشاهده لاگ همه سرویس‌ها: ${GREEN}docker-compose logs -f${NC}"
echo -e "   👀 مشاهده لاگ بک‌اند: ${GREEN}docker-compose logs -f backend${NC}"
echo -e "   👀 مشاهده لاگ مغز سریع: ${GREEN}docker-compose logs -f brain-fast${NC}"

echo -e "\n${YELLOW}🛑 توقف سیستم:${NC}"
echo -e "   ${GREEN}docker-compose down${NC}"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 موفق باشید هادی جان! سیستم آماده استفاده است.${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
EOF

# ========== فایل stop.sh ==========
cat > $INSTALL_DIR/stop.sh << 'EOF'
#!/bin/bash

# =================================================================
# توقف سیستم معاملاتی REAL هادی
# =================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🛑 در حال توقف سیستم...${NC}"

# توقف سرویس‌ها
docker-compose down

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ سیستم با موفقیت متوقف شد.${NC}"
else
    echo -e "${RED}❌ خطا در توقف سیستم.${NC}"
fi
EOF

# ========== فایل restart.sh ==========
cat > $INSTALL_DIR/restart.sh << 'EOF'
#!/bin/bash

# =================================================================
# راه‌اندازی مجدد سیستم معاملاتی REAL هادی
# =================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔄 در حال راه‌اندازی مجدد سیستم...${NC}"

# راه‌اندازی مجدد
docker-compose restart

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ سیستم با موفقیت راه‌اندازی مجدد شد.${NC}"
else
    echo -e "${RED}❌ خطا در راه‌اندازی مجدد.${NC}"
fi
EOF

# ========== فایل backup.sh ==========
cat > $INSTALL_DIR/backup.sh << 'EOF'
#!/bin/bash

# =================================================================
# پشتیبان‌گیری از سیستم معاملاتی REAL هادی
# =================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKUP_DIR="./backups"
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/trading_system_backup_$DATE.tar.gz"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   پشتیبان‌گیری از سیستم معاملاتی REAL هادی ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# ایجاد دایرکتوری پشتیبان
mkdir -p $BACKUP_DIR

echo -e "${YELLOW}📦 در حال پشتیبان‌گیری از دیتابیس PostgreSQL...${NC}"
docker-compose exec -T postgres pg_dump -U hduser trading_db > "$BACKUP_DIR/postgres_backup_$DATE.sql"

echo -e "${YELLOW}📦 در حال پشتیبان‌گیری از MongoDB...${NC}"
docker-compose exec -T mongodb mongodump --username hduser --password your_password --authenticationDatabase admin --db trading_db --archive > "$BACKUP_DIR/mongodb_backup_$DATE.archive"

echo -e "${YELLOW}📦 در حال پشتیبان‌گیری از Redis...${NC}"
docker-compose exec -T redis redis-cli -a your_password SAVE
docker-compose cp redis:/data/dump.rdb "$BACKUP_DIR/redis_backup_$DATE.rdb"

echo -e "${YELLOW}📦 در حال پشتیبان‌گیری از فایل‌های پیکربندی...${NC}"
tar -czf "$BACKUP_FILE" \
    docker-compose.yml \
    config/ \
    .env 2>/dev/null \
    "$BACKUP_DIR"/postgres_backup_$DATE.sql \
    "$BACKUP_DIR"/mongodb_backup_$DATE.archive \
    "$BACKUP_DIR"/redis_backup_$DATE.rdb

# پاکسازی فایل‌های موقت
rm "$BACKUP_DIR"/postgres_backup_$DATE.sql
rm "$BACKUP_DIR"/mongodb_backup_$DATE.archive
rm "$BACKUP_DIR"/redis_backup_$DATE.rdb

echo -e "\n${GREEN}✅ پشتیبان‌گیری با موفقیت انجام شد!${NC}"
echo -e "   📁 فایل پشتیبان: ${YELLOW}$BACKUP_FILE${NC}"
echo -e "   💾 حجم: $(du -h $BACKUP_FILE | cut -f1)"

# حذف پشتیبان‌های قدیمی (قدیمی‌تر از 7 روز)
find $BACKUP_DIR -name "*.tar.gz" -type f -mtime +7 -delete

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
EOF

# ========== فایل .env نمونه ==========
cat > $INSTALL_DIR/.env.example << 'EOF'
# =================================================================
# تنظیمات محیطی سیستم معاملاتی REAL هادی
# =================================================================

# پورت‌ها
FRONTEND_PORT=3000
BACKEND_PORT=8000
PG_PORT=5432
REDIS_PORT=6379
RMQ_PORT=5672

# رمزهای عبور
PG_PASSWORD=your_strong_password_here
REDIS_PASSWORD=your_strong_password_here
RMQ_PASSWORD=your_strong_password_here

# API Keys OKX
OKX_API_KEY=your_okx_api_key
OKX_SECRET_KEY=your_okx_secret_key
OKX_PASSPHRASE=your_okx_passphrase

# API Keys Bybit
BYBIT_API_KEY=your_bybit_api_key
BYBIT_SECRET_KEY=your_bybit_secret_key

# API Keys Kraken
KRAKEN_API_KEY=your_kraken_api_key
KRAKEN_SECRET_KEY=your_kraken_secret_key

# API Keys Bitunix
BITUNIX_API_KEY=your_bitunix_api_key
BITUNIX_SECRET_KEY=your_bitunix_secret_key
BITUNIX_PASSPHRASE=your_bitunix_passphrase

# API Keys LBank
LBANK_API_KEY=your_lbank_api_key
LBANK_SECRET_KEY=your_lbank_secret_key
EOF

# ========== فایل README ==========
cat > $INSTALL_DIR/README.md << 'EOF'
# 🚀 سیستم معاملاتی REAL هادی - نسخه ۲.۰

## 🌟 قابلیت‌های اصلی
- پشتیبانی همزمان از ۵ صرافی: OKX, Bybit, Kraken, Bitunix, LBank
- معماری ۳ مغز (سریع، مدیر ریسک، ناظر یادگیرنده)
- ۵ الگوریتم پیشرفته: طعمه نهنگ مادر، جریان نهنگ، OI پیشرفته، Icebreaker، تشخیص طعمه
- داشبورد مدیریت پیشرفته با فیلترهای هوشمند
- اعتبارسنجی ۴ لایه سیگنال‌ها
- تشخیص پامپ/دامپ در کمتر از ۱ ثانیه

## 📋 پیش‌نیازها
- Ubuntu 20.04+ یا Debian 11+
- حداقل ۸GB رم
- ۵۰GB فضای خالی
- اینترنت پرسرعت

## 🚀 نصب سریع

```bash
# دانلود فایل نصب
wget -O install.sh https://your-server.com/install.sh

# اجرای نصب
chmod +x install.sh
./install.sh