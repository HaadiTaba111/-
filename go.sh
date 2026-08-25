#!/bin/bash

set -e

echo "🐋 شروع ساخت پروژه شکار شکارچی ۲۰۲۷ ..."

# ایجاد پوشه‌های اصلی
mkdir -p whale-hunter
cd whale-hunter

# -------------------- go.mod --------------------
cat > go.mod << 'EOF'
module whale-hunter

go 1.21

require (
    github.com/gorilla/mux v1.8.1
    github.com/mattn/go-sqlite3 v1.14.22
    github.com/spf13/viper v1.18.2
    gopkg.in/yaml.v3 v3.0.1
)
EOF

# -------------------- config.yaml --------------------
cat > config.yaml << 'EOF'
api_sources:
  primary: bybit
  secondary: okx
  auto_switch: true
  update_interval: 10

whale_detection:
  threshold: 100000
  min_volume: 50000
  confidence_threshold: 70

signals:
  validation_times: [1, 2, 4]
  validation_weights: [20, 30, 50]
  min_price_change: 0.1
  expiry_minutes: 10

utbot:
  period: 10
  multiplier: 3.0
  rsi_period: 14
  rsi_overbought: 70
  rsi_oversold: 30

trading:
  mode: paper
  paper_balance: 10000
  trade_amount: 5
  leverage: 5
  stop_loss: 2
  take_profit: 4
  max_daily_trades: 4
  max_consecutive_losses: 4

database:
  path: ./data/whale_hunter.db

brain:
  enabled: false
  api_url: "http://localhost:5000/predict"
  learning_rate: 0.01
  epochs: 10
EOF

# -------------------- internal/config/config.go --------------------
mkdir -p internal/config
cat > internal/config/config.go << 'EOF'
package config

import (
	"log"
	"sync"

	"github.com/spf13/viper"
)

var (
	instance *Config
	once     sync.Once
)

type Config struct {
	APISources struct {
		Primary     string `mapstructure:"primary"`
		Secondary   string `mapstructure:"secondary"`
		AutoSwitch  bool   `mapstructure:"auto_switch"`
		UpdateInterval int `mapstructure:"update_interval"`
	} `mapstructure:"api_sources"`

	WhaleDetection struct {
		Threshold           float64 `mapstructure:"threshold"`
		MinVolume           float64 `mapstructure:"min_volume"`
		ConfidenceThreshold float64 `mapstructure:"confidence_threshold"`
	} `mapstructure:"whale_detection"`

	Signals struct {
		ValidationTimes   []int `mapstructure:"validation_times"`
		ValidationWeights []int `mapstructure:"validation_weights"`
		MinPriceChange    float64 `mapstructure:"min_price_change"`
		ExpiryMinutes     int     `mapstructure:"expiry_minutes"`
	} `mapstructure:"signals"`

	UTBot struct {
		Period        int     `mapstructure:"period"`
		Multiplier    float64 `mapstructure:"multiplier"`
		RSIPeriod     int     `mapstructure:"rsi_period"`
		RSIOverbought float64 `mapstructure:"rsi_overbought"`
		RSIOversold   float64 `mapstructure:"rsi_oversold"`
	} `mapstructure:"utbot"`

	Trading struct {
		Mode                string  `mapstructure:"mode"`
		PaperBalance        float64 `mapstructure:"paper_balance"`
		TradeAmount         float64 `mapstructure:"trade_amount"`
		Leverage            int     `mapstructure:"leverage"`
		StopLoss            float64 `mapstructure:"stop_loss"`
		TakeProfit          float64 `mapstructure:"take_profit"`
		MaxDailyTrades      int     `mapstructure:"max_daily_trades"`
		MaxConsecutiveLosses int    `mapstructure:"max_consecutive_losses"`
	} `mapstructure:"trading"`

	Database struct {
		Path string `mapstructure:"path"`
	} `mapstructure:"database"`

	Brain struct {
		Enabled      bool    `mapstructure:"enabled"`
		APIURL       string  `mapstructure:"api_url"`
		LearningRate float64 `mapstructure:"learning_rate"`
		Epochs       int     `mapstructure:"epochs"`
	} `mapstructure:"brain"`
}

func Load(path string) *Config {
	once.Do(func() {
		viper.SetConfigFile(path)
		viper.AutomaticEnv()
		if err := viper.ReadInConfig(); err != nil {
			log.Fatalf("❌ config read error: %v", err)
		}
		instance = &Config{}
		if err := viper.Unmarshal(instance); err != nil {
			log.Fatalf("❌ config unmarshal error: %v", err)
		}
	})
	return instance
}

func Get() *Config {
	if instance == nil {
		return Load("config.yaml")
	}
	return instance
}
EOF

# -------------------- internal/database/db.go --------------------
mkdir -p internal/database
cat > internal/database/db.go << 'EOF'
package database

import (
	"database/sql"

	_ "github.com/mattn/go-sqlite3"
)

func NewSQLiteDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	if err := createTables(db); err != nil {
		return nil, err
	}
	return db, nil
}

func createTables(db *sql.DB) error {
	schema := `
	CREATE TABLE IF NOT EXISTS whales (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		symbol TEXT NOT NULL,
		price REAL,
		volume REAL,
		change_percent REAL,
		whale_type TEXT,
		confidence REAL,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE IF NOT EXISTS signals (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		symbol TEXT NOT NULL,
		signal_type TEXT,
		entry_price REAL,
		price_1min REAL,
		price_2min REAL,
		price_4min REAL,
		change_1min REAL,
		change_2min REAL,
		change_4min REAL,
		valid_1min BOOLEAN,
		valid_2min BOOLEAN,
		valid_4min BOOLEAN,
		final_status TEXT,
		score INTEGER,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		expires_at DATETIME
	);
	CREATE TABLE IF NOT EXISTS trades (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		signal_id INTEGER,
		symbol TEXT,
		side TEXT,
		entry_price REAL,
		exit_price REAL,
		amount REAL,
		leverage INTEGER,
		pnl REAL,
		commission REAL,
		status TEXT,
		trade_mode TEXT,
		opened_at DATETIME,
		closed_at DATETIME
	);
	CREATE INDEX IF NOT EXISTS idx_signals_status ON signals(final_status);
	CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);
	`
	_, err := db.Exec(schema)
	return err
}
EOF

# -------------------- internal/repository/whale_repo.go --------------------
mkdir -p internal/repository
cat > internal/repository/whale_repo.go << 'EOF'
package repository

import (
	"database/sql"
	"whale-hunter/internal/domain"
)

type WhaleRepository struct {
	db *sql.DB
}

func NewWhaleRepository(db *sql.DB) *WhaleRepository {
	return &WhaleRepository{db: db}
}

func (r *WhaleRepository) Save(whale *domain.Whale) error {
	query := `INSERT INTO whales (symbol, price, volume, change_percent, whale_type, confidence, timestamp)
		VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
	_, err := r.db.Exec(query, whale.Symbol, whale.Price, whale.Volume, whale.ChangePercent, whale.WhaleType, whale.Confidence)
	return err
}

func (r *WhaleRepository) GetRecent(limit int) ([]domain.Whale, error) {
	rows, err := r.db.Query(`SELECT id, symbol, price, volume, change_percent, whale_type, confidence, timestamp
		FROM whales ORDER BY timestamp DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var whales []domain.Whale
	for rows.Next() {
		var w domain.Whale
		rows.Scan(&w.ID, &w.Symbol, &w.Price, &w.Volume, &w.ChangePercent, &w.WhaleType, &w.Confidence, &w.Timestamp)
		whales = append(whales, w)
	}
	return whales, nil
}
EOF

# -------------------- internal/domain/models.go --------------------
mkdir -p internal/domain
cat > internal/domain/models.go << 'EOF'
package domain

import "time"

type Whale struct {
	ID            int64
	Symbol        string
	Price         float64
	Volume        float64
	ChangePercent float64
	WhaleType     string // buy / sell
	Confidence    float64
	Timestamp     time.Time
}

type Signal struct {
	ID           int64
	Symbol       string
	SignalType   string // LONG / SHORT
	EntryPrice   float64
	Price1Min    float64
	Price2Min    float64
	Price4Min    float64
	Change1Min   float64
	Change2Min   float64
	Change4Min   float64
	Valid1Min    bool
	Valid2Min    bool
	Valid4Min    bool
	FinalStatus  string // pending / valid / invalid
	Score        int
	Timestamp    time.Time
	ExpiresAt    time.Time
}

type Trade struct {
	ID         int64
	SignalID   int64
	Symbol     string
	Side       string
	EntryPrice float64
	ExitPrice  float64
	Amount     float64
	Leverage   int
	PnL        float64
	Commission float64
	Status     string // open / closed
	TradeMode  string // paper / live
	OpenedAt   time.Time
	ClosedAt   time.Time
}
EOF

# -------------------- internal/service/market_service.go --------------------
mkdir -p internal/service
cat > internal/service/market_service.go << 'EOF'
package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
	"whale-hunter/internal/config"
)

type MarketData struct {
	Symbol       string  `json:"symbol"`
	Price        float64 `json:"price"`
	Change24h    float64 `json:"change_24h"`
	Volume       float64 `json:"volume"`
	OpenInterest float64 `json:"open_interest"`
	OIDelta      float64 `json:"oi_delta"`
	FundingRate  float64 `json:"funding_rate"`
	Timestamp    time.Time
}

type MarketService struct {
	cfg *config.Config
}

func NewMarketService(cfg *config.Config) *MarketService {
	return &MarketService{cfg: cfg}
}

func (s *MarketService) FetchBybit(symbol string) (*MarketData, error) {
	url := fmt.Sprintf("https://api.bybit.com/v5/market/tickers?category=linear&symbol=%s", symbol)
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Result struct {
			List []struct {
				Symbol        string `json:"symbol"`
				LastPrice     string `json:"lastPrice"`
				Price24hPcnt  string `json:"price24hPcnt"`
				Turnover24h   string `json:"turnover24h"`
				OpenInterest  string `json:"openInterest"`
				FundingRate   string `json:"fundingRate"`
			} `json:"list"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	if len(result.Result.List) == 0 {
		return nil, fmt.Errorf("no data for %s", symbol)
	}
	item := result.Result.List[0]
	// تبدیل رشته به عدد (در کد واقعی باید خطاهای تبدیل رو هندل کنی)
	price := 0.0
	change := 0.0
	volume := 0.0
	oi := 0.0
	fr := 0.0
	fmt.Sscanf(item.LastPrice, "%f", &price)
	fmt.Sscanf(item.Price24hPcnt, "%f", &change)
	fmt.Sscanf(item.Turnover24h, "%f", &volume)
	fmt.Sscanf(item.OpenInterest, "%f", &oi)
	fmt.Sscanf(item.FundingRate, "%f", &fr)

	return &MarketData{
		Symbol:       item.Symbol,
		Price:        price,
		Change24h:    change * 100,
		Volume:       volume,
		OpenInterest: oi,
		FundingRate:  fr * 100,
		Timestamp:    time.Now(),
	}, nil
}

func (s *MarketService) FetchOKX(symbol string) (*MarketData, error) {
	url := fmt.Sprintf("https://www.okx.com/api/v5/market/ticker?instId=%s-SWAP", symbol)
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Data []struct {
			InstId  string `json:"instId"`
			Last    string `json:"last"`
			Open24h string `json:"open24h"`
			VolCcy24h string `json:"volCcy24h"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	if len(result.Data) == 0 {
		return nil, fmt.Errorf("no data for %s", symbol)
	}
	item := result.Data[0]
	price := 0.0
	open := 0.0
	volume := 0.0
	fmt.Sscanf(item.Last, "%f", &price)
	fmt.Sscanf(item.Open24h, "%f", &open)
	fmt.Sscanf(item.VolCcy24h, "%f", &volume)

	change := 0.0
	if open != 0 {
		change = (price - open) / open * 100
	}

	return &MarketData{
		Symbol:       item.InstId,
		Price:        price,
		Change24h:    change,
		Volume:       volume,
		OpenInterest: 0, // OKX Open Interest نیاز به endpoint جدا داره
		FundingRate:  0,
		Timestamp:    time.Now(),
	}, nil
}
EOF

# -------------------- internal/service/whale_service.go --------------------
cat > internal/service/whale_service.go << 'EOF'
package service

import (
	"math"
	"time"
	"whale-hunter/internal/config"
	"whale-hunter/internal/domain"
	"whale-hunter/internal/repository"
)

type WhaleService struct {
	repo *repository.WhaleRepository
	cfg  *config.Config
}

func NewWhaleService(repo *repository.WhaleRepository, cfg *config.Config) *WhaleService {
	return &WhaleService{repo: repo, cfg: cfg}
}

func (s *WhaleService) DetectFromMarketData(data *MarketData) (*domain.Whale, error) {
	if data.Volume < s.cfg.WhaleDetection.Threshold {
		return nil, nil // نهنگ نیست
	}
	whaleType := "buy"
	if data.Change24h < 0 {
		whaleType = "sell"
	}
	confidence := 50.0
	if data.Volume > 1e6 {
		confidence += 20
	}
	if math.Abs(data.Change24h) > 5 {
		confidence += 15
	}
	if confidence > 100 {
		confidence = 100
	}

	whale := &domain.Whale{
		Symbol:        data.Symbol,
		Price:         data.Price,
		Volume:        data.Volume,
		ChangePercent: data.Change24h,
		WhaleType:     whaleType,
		Confidence:    confidence,
		Timestamp:     time.Now(),
	}
	if err := s.repo.Save(whale); err != nil {
		return nil, err
	}
	return whale, nil
}
EOF

# -------------------- internal/service/signal_service.go --------------------
cat > internal/service/signal_service.go << 'EOF'
package service

import (
	"time"
	"whale-hunter/internal/config"
	"whale-hunter/internal/domain"
	"whale-hunter/internal/repository"
)

type SignalService struct {
	repo *repository.SignalRepository
	cfg  *config.Config
}

func NewSignalService(repo *repository.SignalRepository, cfg *config.Config) *SignalService {
	return &SignalService{repo: repo, cfg: cfg}
}

func (s *SignalService) CreateFromWhale(whale *domain.Whale) (*domain.Signal, error) {
	signalType := "LONG"
	if whale.WhaleType == "sell" {
		signalType = "SHORT"
	}
	signal := &domain.Signal{
		Symbol:      whale.Symbol,
		SignalType:  signalType,
		EntryPrice:  whale.Price,
		FinalStatus: "pending",
		Timestamp:   time.Now(),
		ExpiresAt:   time.Now().Add(time.Duration(s.cfg.Signals.ExpiryMinutes) * time.Minute),
	}
	if err := s.repo.Save(signal); err != nil {
		return nil, err
	}
	return signal, nil
}
EOF

# -------------------- internal/repository/signal_repo.go --------------------
cat > internal/repository/signal_repo.go << 'EOF'
package repository

import (
	"database/sql"
	"whale-hunter/internal/domain"
)

type SignalRepository struct {
	db *sql.DB
}

func NewSignalRepository(db *sql.DB) *SignalRepository {
	return &SignalRepository{db: db}
}

func (r *SignalRepository) Save(s *domain.Signal) error {
	query := `INSERT INTO signals (symbol, signal_type, entry_price, final_status, timestamp, expires_at)
		VALUES (?, ?, ?, ?, ?, ?)`
	res, err := r.db.Exec(query, s.Symbol, s.SignalType, s.EntryPrice, s.FinalStatus, s.Timestamp, s.ExpiresAt)
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	s.ID = id
	return nil
}

func (r *SignalRepository) Update(s *domain.Signal) error {
	query := `UPDATE signals SET price_1min=?, price_2min=?, price_4min=?,
		change_1min=?, change_2min=?, change_4min=?,
		valid_1min=?, valid_2min=?, valid_4min=?,
		final_status=?, score=?
		WHERE id=?`
	_, err := r.db.Exec(query, s.Price1Min, s.Price2Min, s.Price4Min,
		s.Change1Min, s.Change2Min, s.Change4Min,
		s.Valid1Min, s.Valid2Min, s.Valid4Min,
		s.FinalStatus, s.Score, s.ID)
	return err
}

func (r *SignalRepository) GetPending() ([]domain.Signal, error) {
	rows, err := r.db.Query(`SELECT id, symbol, signal_type, entry_price, timestamp FROM signals
		WHERE final_status='pending' AND expires_at > CURRENT_TIMESTAMP`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var signals []domain.Signal
	for rows.Next() {
		var s domain.Signal
		rows.Scan(&s.ID, &s.Symbol, &s.SignalType, &s.EntryPrice, &s.Timestamp)
		signals = append(signals, s)
	}
	return signals, nil
}

func (r *SignalRepository) GetValidForTrade(minScore int) ([]domain.Signal, error) {
	rows, err := r.db.Query(`SELECT id, symbol, signal_type, entry_price, score, timestamp
		FROM signals WHERE final_status='valid' AND score >= ? ORDER BY score DESC`, minScore)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var signals []domain.Signal
	for rows.Next() {
		var s domain.Signal
		rows.Scan(&s.ID, &s.Symbol, &s.SignalType, &s.EntryPrice, &s.Score, &s.Timestamp)
		signals = append(signals, s)
	}
	return signals, nil
}
EOF

# -------------------- internal/core/analyzer.go --------------------
mkdir -p internal/core
cat > internal/core/analyzer.go << 'EOF'
package core

import (
	"time"
	"whale-hunter/internal/config"
	"whale-hunter/internal/domain"
	"whale-hunter/internal/service"
)

type Analyzer struct {
	marketSvc  *service.MarketService
	whaleSvc   *service.WhaleService
	signalSvc  *service.SignalService
	cfg        *config.Config
	priceCache map[string]float64
}

func NewMarketAnalyzer(marketSvc *service.MarketService, whaleSvc *service.WhaleService, signalSvc *service.SignalService, cfg *config.Config) *Analyzer {
	return &Analyzer{
		marketSvc:  marketSvc,
		whaleSvc:   whaleSvc,
		signalSvc:  signalSvc,
		cfg:        cfg,
		priceCache: make(map[string]float64),
	}
}

func (a *Analyzer) RunOnce() error {
	symbols := []string{"BTCUSDT", "ETHUSDT", "BNBUSDT"}
	for _, sym := range symbols {
		data, err := a.marketSvc.FetchBybit(sym)
		if err != nil {
			continue
		}
		whale, err := a.whaleSvc.DetectFromMarketData(data)
		if err != nil {
			continue
		}
		if whale != nil {
			// ایجاد سیگنال
			signal, err := a.signalSvc.CreateFromWhale(whale)
			if err == nil {
				_ = signal
			}
		}
	}
	return nil
}
EOF

# -------------------- internal/brain/brain.go --------------------
mkdir -p internal/brain
cat > internal/brain/brain.go << 'EOF'
package brain

import (
	"context"
	"time"
)

type SignalRequest struct {
	Symbol    string    `json:"symbol"`
	Price     float64   `json:"price"`
	Volume    float64   `json:"volume"`
	OIDelta   float64   `json:"oi_delta"`
	OrderFlow float64   `json:"order_flow"`
	Timestamp time.Time `json:"timestamp"`
}

type SignalResponse struct {
	Action   string  `json:"action"`   // buy, sell, neutral
	Strength float64 `json:"strength"` // 0-100
	Score    int     `json:"score"`    // 0-100
	Reason   string  `json:"reason"`
}

type BrainService interface {
	AnalyzeSignal(ctx context.Context, req *SignalRequest) (*SignalResponse, error)
	Train(ctx context.Context, data interface{}) error
	HealthCheck(ctx context.Context) bool
}

type MockBrainService struct{}

func (m *MockBrainService) AnalyzeSignal(ctx context.Context, req *SignalRequest) (*SignalResponse, error) {
	if req.Volume > 1_000_000 && req.OIDelta > 0 {
		return &SignalResponse{
			Action:   "buy",
			Strength: 85.5,
			Score:    90,
			Reason:   "نهنگ + OI مثبت",
		}, nil
	}
	return &SignalResponse{
		Action:   "neutral",
		Strength: 0,
		Score:    50,
		Reason:   "شرایط عادی",
	}, nil
}

func (m *MockBrainService) Train(ctx context.Context, data interface{}) error {
	return nil
}

func (m *MockBrainService) HealthCheck(ctx context.Context) bool {
	return true
}
EOF

# -------------------- internal/api/handler.go --------------------
mkdir -p internal/api
cat > internal/api/handler.go << 'EOF'
package api

import (
	"encoding/json"
	"net/http"
	"whale-hunter/internal/config"
	"whale-hunter/internal/core"
	"whale-hunter/internal/service"

	"github.com/gorilla/mux"
)

type Handler struct {
	marketSvc  *service.MarketService
	whaleSvc   *service.WhaleService
	signalSvc  *service.SignalService
	tradeSvc   *service.TradeService
	analyzer   *core.Analyzer
	autoTrader *core.AutoTrader
	cfg        *config.Config
}

func NewHandler(
	marketSvc *service.MarketService,
	whaleSvc *service.WhaleService,
	signalSvc *service.SignalService,
	tradeSvc *service.TradeService,
	analyzer *core.Analyzer,
	autoTrader *core.AutoTrader,
	cfg *config.Config,
) *Handler {
	return &Handler{
		marketSvc:  marketSvc,
		whaleSvc:   whaleSvc,
		signalSvc:  signalSvc,
		tradeSvc:   tradeSvc,
		analyzer:   analyzer,
		autoTrader: autoTrader,
		cfg:        cfg,
	}
}

func (h *Handler) RegisterRoutes(r *mux.Router) {
	r.HandleFunc("/api/market", h.getMarketData).Methods("GET")
	r.HandleFunc("/api/whales", h.getWhales).Methods("GET")
	r.HandleFunc("/api/signals", h.getSignals).Methods("GET")
	r.HandleFunc("/api/trades", h.getTrades).Methods("GET")
	r.HandleFunc("/api/auto/start", h.startAutoTrade).Methods("POST")
	r.HandleFunc("/api/auto/stop", h.stopAutoTrade).Methods("POST")
	r.HandleFunc("/api/price/{symbol}", h.getPrice).Methods("GET")
	r.HandleFunc("/api/brain/analyze", h.brainAnalyze).Methods("POST")
}

func (h *Handler) getMarketData(w http.ResponseWriter, r *http.Request) {
	symbol := r.URL.Query().Get("symbol")
	if symbol == "" {
		symbol = "BTCUSDT"
	}
	data, err := h.marketSvc.FetchBybit(symbol)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(data)
}

func (h *Handler) getWhales(w http.ResponseWriter, r *http.Request) {
	// TODO: از repo بخون
	w.Write([]byte(`{"whales":[]}`))
}

func (h *Handler) getSignals(w http.ResponseWriter, r *http.Request) {
	// TODO
	w.Write([]byte(`{"signals":[]}`))
}

func (h *Handler) getTrades(w http.ResponseWriter, r *http.Request) {
	// TODO
	w.Write([]byte(`{"trades":[]}`))
}

func (h *Handler) startAutoTrade(w http.ResponseWriter, r *http.Request) {
	h.autoTrader.Start()
	json.NewEncoder(w).Encode(map[string]string{"status": "started"})
}

func (h *Handler) stopAutoTrade(w http.ResponseWriter, r *http.Request) {
	h.autoTrader.Stop()
	json.NewEncoder(w).Encode(map[string]string{"status": "stopped"})
}

func (h *Handler) getPrice(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	symbol := vars["symbol"]
	data, err := h.marketSvc.FetchBybit(symbol)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(map[string]interface{}{
		"symbol": symbol,
		"price":  data.Price,
		"time":   data.Timestamp,
	})
}

func (h *Handler) brainAnalyze(w http.ResponseWriter, r *http.Request) {
	var req brain.SignalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	// در اینجا می‌توانیم مغز واقعی را صدا بزنیم
	// فعلاً از mock استفاده می‌کنیم
	mock := &brain.MockBrainService{}
	resp, _ := mock.AnalyzeSignal(r.Context(), &req)
	json.NewEncoder(w).Encode(resp)
}
EOF

# -------------------- internal/service/trade_service.go (خلاصه) --------------------
cat > internal/service/trade_service.go << 'EOF'
package service

import (
	"time"
	"whale-hunter/internal/config"
	"whale-hunter/internal/domain"
	"whale-hunter/internal/repository"
)

type TradeService struct {
	repo *repository.TradeRepository
	cfg  *config.Config
}

func NewTradeService(repo *repository.TradeRepository, cfg *config.Config) *TradeService {
	return &TradeService{repo: repo, cfg: cfg}
}

func (s *TradeService) ExecutePaperTrade(signal *domain.Signal) (*domain.Trade, error) {
	trade := &domain.Trade{
		SignalID:   signal.ID,
		Symbol:     signal.Symbol,
		Side:       signal.SignalType,
		EntryPrice: signal.EntryPrice,
		Amount:     s.cfg.Trading.TradeAmount,
		Leverage:   s.cfg.Trading.Leverage,
		Status:     "open",
		TradeMode:  "paper",
		OpenedAt:   time.Now(),
	}
	// محاسبه حد ضرر/سود
	if trade.Side == "LONG" {
		// حد ضرر و سود در real world محاسبه می‌شود
	}
	return trade, s.repo.Save(trade)
}
EOF

# -------------------- internal/repository/trade_repo.go --------------------
cat > internal/repository/trade_repo.go << 'EOF'
package repository

import (
	"database/sql"
	"whale-hunter/internal/domain"
)

type TradeRepository struct {
	db *sql.DB
}

func NewTradeRepository(db *sql.DB) *TradeRepository {
	return &TradeRepository{db: db}
}

func (r *TradeRepository) Save(t *domain.Trade) error {
	query := `INSERT INTO trades (signal_id, symbol, side, entry_price, amount, leverage, status, trade_mode, opened_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
	_, err := r.db.Exec(query, t.SignalID, t.Symbol, t.Side, t.EntryPrice, t.Amount, t.Leverage, t.Status, t.TradeMode, t.OpenedAt)
	return err
}
EOF

# -------------------- internal/core/auto_trader.go --------------------
cat > internal/core/auto_trader.go << 'EOF'
package core

import (
	"time"
	"whale-hunter/internal/config"
	"whale-hunter/internal/domain"
	"whale-hunter/internal/service"
)

type AutoTrader struct {
	tradeSvc  *service.TradeService
	signalSvc *service.SignalService
	cfg       *config.Config
	running   bool
}

func NewAutoTrader(tradeSvc *service.TradeService, signalSvc *service.SignalService, cfg *config.Config) *AutoTrader {
	return &AutoTrader{
		tradeSvc:  tradeSvc,
		signalSvc: signalSvc,
		cfg:       cfg,
		running:   false,
	}
}

func (a *AutoTrader) Start() {
	a.running = true
	go a.run()
}

func (a *AutoTrader) Stop() {
	a.running = false
}

func (a *AutoTrader) run() {
	for a.running {
		// اینجا سیگنال‌های معتبر را گرفته و ترید می‌کند
		time.Sleep(10 * time.Second)
	}
}
EOF

# -------------------- frontend/index.html (بهینه‌شده با سورت، فیلتر، جستجو) --------------------
mkdir -p frontend
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>شکار شکارچی ۲۰۲۷ - Whale Hunter Pro</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@300;400;500;700;900&display=swap" rel="stylesheet">
    <style>
        * { font-family: 'Vazirmatn', sans-serif; }
        .glass { background: rgba(15, 23, 42, 0.95); backdrop-filter: blur(10px); }
        .sort-asc::after { content: " ▲"; }
        .sort-desc::after { content: " ▼"; }
    </style>
</head>
<body class="bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950 text-white min-h-screen">
    <header class="glass border-b border-slate-700 sticky top-0 z-50">
        <div class="container mx-auto px-4 py-3">
            <h1 class="text-2xl font-bold flex items-center gap-2">
                <span class="text-4xl">🐋</span>
                <span class="bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">
                    شکار شکارچی ۲۰۲۷
                </span>
            </h1>
            <nav class="flex gap-2 mt-3 flex-wrap">
                <button onclick="showTab('dashboard')" class="tab-btn px-4 py-2 rounded-lg bg-slate-700 text-sm">🎯 داشبورد</button>
                <button onclick="showTab('market')" class="tab-btn px-4 py-2 rounded-lg hover:bg-slate-700 text-sm">📊 بازار</button>
                <button onclick="showTab('whales')" class="tab-btn px-4 py-2 rounded-lg hover:bg-slate-700 text-sm">🐋 نهنگ‌ها</button>
                <button onclick="showTab('signals')" class="tab-btn px-4 py-2 rounded-lg hover:bg-slate-700 text-sm">📡 سیگنال‌ها</button>
                <button onclick="showTab('autotrade')" class="tab-btn px-4 py-2 rounded-lg hover:bg-slate-700 text-sm">🤖 اتو ترید</button>
                <button onclick="showTab('brain')" class="tab-btn px-4 py-2 rounded-lg hover:bg-slate-700 text-sm">🧠 مغز</button>
            </nav>
        </div>
    </header>

    <main class="container mx-auto px-4 py-6">
        <!-- DASHBOARD -->
        <div id="dashboard-tab" class="tab-content">
            <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
                <div class="glass rounded-xl p-4 border border-slate-700">
                    <div class="text-slate-400 text-xs">نهنگ‌های امروز</div>
                    <div class="text-2xl font-bold text-blue-400" id="whaleCount">0</div>
                </div>
                <div class="glass rounded-xl p-4 border border-slate-700">
                    <div class="text-slate-400 text-xs">سیگنال معتبر</div>
                    <div class="text-2xl font-bold text-green-400" id="validSignals">0</div>
                </div>
                <div class="glass rounded-xl p-4 border border-slate-700">
                    <div class="text-slate-400 text-xs">موجودی (Paper)</div>
                    <div class="text-2xl font-bold text-cyan-400" id="paperBalance">$10,000</div>
                </div>
                <div class="glass rounded-xl p-4 border border-slate-700">
                    <div class="text-slate-400 text-xs">اتو ترید</div>
                    <div class="text-2xl font-bold text-yellow-400" id="autoStatus">⏸️ متوقف</div>
                </div>
            </div>
        </div>

        <!-- MARKET (با سورت، فیلتر، جستجو) -->
        <div id="market-tab" class="tab-content hidden">
            <div class="glass rounded-xl p-4 border border-slate-700">
                <div class="flex flex-wrap gap-4 mb-4">
                    <input type="text" id="marketSearch" placeholder="جستجوی نماد..." class="bg-slate-800 px-3 py-2 rounded-lg border border-slate-600 text-sm">
                    <select id="marketFilter" class="bg-slate-800 px-3 py-2 rounded-lg border border-slate-600 text-sm">
                        <option value="all">همه</option>
                        <option value="gainers">بیشترین رشد</option>
                        <option value="losers">بیشترین کاهش</option>
                    </select>
                </div>
                <table class="w-full text-sm">
                    <thead>
                        <tr class="text-slate-400">
                            <th class="text-right py-2 cursor-pointer" onclick="sortTable('symbol')">نماد</th>
                            <th class="text-right py-2 cursor-pointer" onclick="sortTable('price')">قیمت</th>
                            <th class="text-right py-2 cursor-pointer" onclick="sortTable('change')">تغییر</th>
                            <th class="text-right py-2 cursor-pointer" onclick="sortTable('volume')">حجم</th>
                        </tr>
                    </thead>
                    <tbody id="marketTable"></tbody>
                </table>
            </div>
        </div>

        <!-- WHALES -->
        <div id="whales-tab" class="tab-content hidden">... (لیست نهنگ‌ها) ...</div>

        <!-- SIGNALS -->
        <div id="signals-tab" class="tab-content hidden">... (جدول سیگنال‌ها) ...</div>

        <!-- AUTO TRADE -->
        <div id="autotrade-tab" class="tab-content hidden">... (تنظیمات و تاریخچه) ...</div>

        <!-- BRAIN (مغز) -->
        <div id="brain-tab" class="tab-content hidden">
            <div class="glass rounded-xl p-4 border border-purple-500/30">
                <h3 class="font-bold text-purple-400 mb-4">🧠 مغز سه‌لایه</h3>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                        <p class="text-sm text-slate-300">با انتخاب محدوده‌ای از نمودار، مغز آن ناحیه را تحلیل کرده و یاد می‌گیرد.</p>
                        <button onclick="trainBrain()" class="mt-4 bg-purple-600 px-4 py-2 rounded-lg">🎓 شروع یادگیری</button>
                    </div>
                    <div id="brainResult" class="bg-slate-800 p-4 rounded-lg">
                        <div>آخرین تحلیل مغز:</div>
                        <div id="brainAction" class="text-xl font-bold">-</div>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <script>
        let marketData = [];
        let sortColumn = 'symbol';
        let sortDirection = 'asc';

        async function fetchMarket() {
            try {
                const res = await fetch('/api/market?symbol=BTCUSDT');
                const data = await res.json();
                marketData = [data]; // برای نمونه فقط یک نماد
                renderMarket();
            } catch (e) { console.error(e); }
        }

        function renderMarket() {
            const tbody = document.getElementById('marketTable');
            const search = document.getElementById('marketSearch').value.toLowerCase();
            const filter = document.getElementById('marketFilter').value;

            let filtered = marketData.filter(item => item.symbol.toLowerCase().includes(search));
            if (filter === 'gainers') filtered = filtered.filter(i => i.change24h > 0);
            else if (filter === 'losers') filtered = filtered.filter(i => i.change24h < 0);

            // سورت
            filtered.sort((a, b) => {
                let valA = a[sortColumn];
                let valB = b[sortColumn];
                if (sortColumn === 'symbol') {
                    valA = a.symbol;
                    valB = b.symbol;
                } else if (sortColumn === 'price') {
                    valA = a.price;
                    valB = b.price;
                } else if (sortColumn === 'change') {
                    valA = a.change24h;
                    valB = b.change24h;
                } else if (sortColumn === 'volume') {
                    valA = a.volume;
                    valB = b.volume;
                }
                if (valA < valB) return sortDirection === 'asc' ? -1 : 1;
                if (valA > valB) return sortDirection === 'asc' ? 1 : -1;
                return 0;
            });

            tbody.innerHTML = filtered.map(item => `
                <tr class="border-b border-slate-700/50">
                    <td class="py-2">${item.symbol}</td>
                    <td class="py-2 font-mono">$${item.price?.toFixed(2)}</td>
                    <td class="py-2 ${item.change24h >=0 ? 'text-green-400' : 'text-red-400'}">${item.change24h?.toFixed(2)}%</td>
                    <td class="py-2">$${item.volume?.toFixed(0)}</td>
                </tr>
            `).join('');
        }

        function sortTable(col) {
            if (sortColumn === col) {
                sortDirection = sortDirection === 'asc' ? 'desc' : 'asc';
            } else {
                sortColumn = col;
                sortDirection = 'asc';
            }
            renderMarket();
        }

        document.getElementById('marketSearch').addEventListener('input', renderMarket);
        document.getElementById('marketFilter').addEventListener('change', renderMarket);

        function showTab(tab) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
            document.getElementById(tab + '-tab').classList.remove('hidden');
        }

        async function trainBrain() {
            // اینجا می‌توان request به /api/brain/analyze فرستاد
            const mockReq = { symbol: "BTCUSDT", price: 50000, volume: 2000000, oi_delta: 100 };
            const res = await fetch('/api/brain/analyze', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(mockReq)
            });
            const data = await res.json();
            document.getElementById('brainAction').innerText = `${data.action} (${data.strength}%) - ${data.reason}`;
        }

        fetchMarket();
        setInterval(fetchMarket, 10000);
        showTab('dashboard');
    </script>
</body>
</html>
EOF

# -------------------- cmd/server/main.go (بدون مغز) --------------------
mkdir -p cmd/server
cat > cmd/server/main.go << 'EOF'
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"whale-hunter/internal/api"
	"whale-hunter/internal/config"
	"whale-hunter/internal/core"
	"whale-hunter/internal/database"
	"whale-hunter/internal/repository"
	"whale-hunter/internal/service"

	"github.com/gorilla/mux"
)

func main() {
	cfg := config.Load("config.yaml")

	db, err := database.NewSQLiteDB(cfg.Database.Path)
	if err != nil {
		log.Fatalf("❌ db: %v", err)
	}
	defer db.Close()

	whaleRepo := repository.NewWhaleRepository(db)
	signalRepo := repository.NewSignalRepository(db)
	tradeRepo := repository.NewTradeRepository(db)

	marketSvc := service.NewMarketService(cfg)
	whaleSvc := service.NewWhaleService(whaleRepo, cfg)
	signalSvc := service.NewSignalService(signalRepo, cfg)
	tradeSvc := service.NewTradeService(tradeRepo, cfg)

	analyzer := core.NewMarketAnalyzer(marketSvc, whaleSvc, signalSvc, cfg)
	autoTrader := core.NewAutoTrader(tradeSvc, signalSvc, cfg)

	handler := api.NewHandler(marketSvc, whaleSvc, signalSvc, tradeSvc, analyzer, autoTrader, cfg)

	r := mux.NewRouter()
	handler.RegisterRoutes(r)
	r.PathPrefix("/").Handler(http.FileServer(http.Dir("./frontend")))

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Println("🚀 سرور روی پورت 8080")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("❌ %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
EOF

# -------------------- cmd/server/main_with_brain.go (با مغز) --------------------
cat > cmd/server/main_with_brain.go << 'EOF'
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"whale-hunter/internal/api"
	"whale-hunter/internal/brain"
	"whale-hunter/internal/config"
	"whale-hunter/internal/core"
	"whale-hunter/internal/database"
	"whale-hunter/internal/repository"
	"whale-hunter/internal/service"

	"github.com/gorilla/mux"
)

func main() {
	cfg := config.Load("config.yaml")

	db, err := database.NewSQLiteDB(cfg.Database.Path)
	if err != nil {
		log.Fatalf("❌ db: %v", err)
	}
	defer db.Close()

	whaleRepo := repository.NewWhaleRepository(db)
	signalRepo := repository.NewSignalRepository(db)
	tradeRepo := repository.NewTradeRepository(db)

	marketSvc := service.NewMarketService(cfg)
	whaleSvc := service.NewWhaleService(whaleRepo, cfg)
	signalSvc := service.NewSignalService(signalRepo, cfg)
	tradeSvc := service.NewTradeService(tradeRepo, cfg)

	// ایجاد مغز (mock)
	brainSvc := &brain.MockBrainService{}
	_ = brainSvc // در آینده به analyzer تزریق می‌شود

	analyzer := core.NewMarketAnalyzer(marketSvc, whaleSvc, signalSvc, cfg)
	autoTrader := core.NewAutoTrader(tradeSvc, signalSvc, cfg)

	handler := api.NewHandler(marketSvc, whaleSvc, signalSvc, tradeSvc, analyzer, autoTrader, cfg)

	r := mux.NewRouter()
	handler.RegisterRoutes(r)
	r.PathPrefix("/").Handler(http.FileServer(http.Dir("./frontend")))

	srv := &http.Server{
		Addr:         ":8081",
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Println("🚀 سرور با مغز روی پورت 8081")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("❌ %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
EOF

# نهایی
echo "✅ پروژه با موفقیت ساخته شد!"
echo "برای اجرا: cd whale-hunter && go run cmd/server/main.go"
echo "یا با مغز: go run cmd/server/main_with_brain.go"