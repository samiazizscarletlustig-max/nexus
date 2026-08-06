# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          NEXUS v11.0  ─  QUANTUM INSTITUTIONAL ENGINE  (engine.py)          ║
# ║          Math • News • Intelligence  |  Broker-Independent                   ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  PRICE FEEDS     ✅  yfinance + ccxt/Binance (OHLCV multi-timeframe)        ║
# ║  INDICATORS      ✅  RSI, MACD, Stoch, EMAs, BB, ADX, %R, CCI, OBV, Ich.  ║
# ║  NEW v11         ✅  Supertrend · VWAP+Bands · Pivot Points (Classic+Fib)  ║
# ║  NEW v11         ✅  Multi-Timeframe Confluence (5m·15m·1h·4h)             ║
# ║  NEW v11         ✅  Probability Score (weighted 7-factor model)            ║
# ║  NEW v11         ✅  Trade Plan Generator (Entry·SL·TP1·TP2·TP3·RR·Conf)  ║
# ║  NEW v11         ✅  Advanced Regime Detection (5 states)                  ║
# ║  NEW v11         ✅  Asset Correlation Matrix (30-day rolling)             ║
# ║  QUANTUM         ✅  Hurst · Entropy · KER · Fractal Dim · Z-Score        ║
# ║  SMART MONEY     ✅  Order Blocks · FVGs · Liquidity Sweeps (enhanced)    ║
# ║  TTM SQUEEZE     ✅  BB vs Keltner breakout detector                       ║
# ║  ELLIOTT WAVE    ✅  1-5 Impulse + ABC + Fibonacci Targets                 ║
# ║  SESSIONS        ✅  Asian/London/NY/Overlap + 24/7 Crypto Mapping         ║
# ║  NEWS ENGINE     ✅  Live headlines + VADER Sentiment + Macro Score        ║
# ║  LOT CALCULATOR  ✅  Capital × Risk% ÷ (SL_pips × pip_value)              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 — IMPORTS
# ══════════════════════════════════════════════════════════════════════════════

import math
import time
import json
import traceback
from dataclasses import dataclass, field
from typing      import Optional, Tuple, List, Dict, Any
from datetime    import datetime, timezone, timedelta

import numpy as np
from scipy.stats  import kurtosis as sp_kurtosis, skew as sp_skew
from scipy.signal import argrelextrema

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 — ASSET CONFIGURATIONS
# ══════════════════════════════════════════════════════════════════════════════

@dataclass
class AssetConfig:
    """Full specification for a tradable instrument."""
    name:              str
    symbol:            str
    yf_ticker:         str
    ccxt_symbol:       Optional[str]
    asset_type:        str            # commodity | crypto | index | forex
    pip_size:          float
    pip_value_per_lot: float
    contract_size:     float
    price_lo:          float
    price_hi:          float
    is_24_7:           bool
    color:             str
    emoji:             str

GOLD_CFG = AssetConfig(
    name="GOLD (XAU/USD)", symbol="XAUUSD", yf_ticker="GC=F",
    ccxt_symbol=None, asset_type="commodity",
    pip_size=0.01, pip_value_per_lot=10.0, contract_size=100,
    price_lo=1000.0, price_hi=9000.0, is_24_7=False,
    color="#D4AF37", emoji="⚡"
)
BTC_CFG = AssetConfig(
    name="BITCOIN (BTC/USD)", symbol="BTCUSD", yf_ticker="BTC-USD",
    ccxt_symbol="BTC/USDT", asset_type="crypto",
    pip_size=0.10, pip_value_per_lot=0.10, contract_size=1.0,
    price_lo=5000.0, price_hi=500000.0, is_24_7=True,
    color="#F7931A", emoji="₿"
)
ETH_CFG = AssetConfig(
    name="ETHEREUM (ETH/USD)", symbol="ETHUSD", yf_ticker="ETH-USD",
    ccxt_symbol="ETH/USDT", asset_type="crypto",
    pip_size=0.01, pip_value_per_lot=0.01, contract_size=1.0,
    price_lo=50.0, price_hi=50000.0, is_24_7=True,
    color="#627EEA", emoji="Ξ"
)
SPX_CFG = AssetConfig(
    name="S&P 500", symbol="SPX500", yf_ticker="^GSPC",
    ccxt_symbol=None, asset_type="index",
    pip_size=0.01, pip_value_per_lot=10.0, contract_size=50,
    price_lo=500.0, price_hi=15000.0, is_24_7=False,
    color="#00BCD4", emoji="📊"
)
EURUSD_CFG = AssetConfig(
    name="EUR/USD", symbol="EURUSD", yf_ticker="EURUSD=X",
    ccxt_symbol=None, asset_type="forex",
    pip_size=0.0001, pip_value_per_lot=10.0, contract_size=100000,
    price_lo=0.50, price_hi=2.50, is_24_7=False,
    color="#4CAF50", emoji="💱"
)

ALL_ASSETS: List[AssetConfig] = [GOLD_CFG, BTC_CFG, ETH_CFG, SPX_CFG, EURUSD_CFG]
ASSET_MAP:  Dict[str, AssetConfig] = {a.symbol: a for a in ALL_ASSETS}

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 3 — DATA MODELS
# ══════════════════════════════════════════════════════════════════════════════

@dataclass
class MarketIntelligence:
    """Complete market analysis snapshot — all indicators in one flat object."""
    # ── Identity ──────────────────────────────────────────────────────────────
    asset_name:          str   = ""
    asset_type:          str   = ""
    last_update:         str   = ""
    data_source:         str   = ""
    # ── Price ─────────────────────────────────────────────────────────────────
    current_price:       float = 0.0
    price_change:        float = 0.0
    price_change_pct:    float = 0.0
    prices:              List[float] = field(default_factory=list)
    # ── Master Signal ─────────────────────────────────────────────────────────
    safety_signal:       str   = "WAIT"
    signal_color:        str   = "#FFD600"
    signal_strength:     int   = 0
    direction:           str   = "NEUTRAL"
    bull_score:          int   = 0
    bear_score:          int   = 0
    entry_quality:       str   = "POOR"
    entry_explanation:   str   = ""
    # ── Probability Score (v11) ───────────────────────────────────────────────
    probability_bull:    float = 50.0
    probability_label:   str   = "NEUTRAL"
    # ── EMAs ──────────────────────────────────────────────────────────────────
    ema9:                float = 0.0
    ema21:               float = 0.0
    ema50:               float = 0.0
    ema200:              float = 0.0
    ema_alignment:       str   = "NEUTRAL"
    # ── RSI ───────────────────────────────────────────────────────────────────
    rsi:                 float = 50.0
    rsi_signal:          str   = "NEUTRAL"
    rsi_explanation:     str   = ""
    # ── MACD ──────────────────────────────────────────────────────────────────
    macd_line:           float = 0.0
    macd_signal:         float = 0.0
    macd_hist:           float = 0.0
    macd_cross:          str   = "NEUTRAL"
    # ── Stochastic ────────────────────────────────────────────────────────────
    stoch_k:             float = 50.0
    stoch_d:             float = 50.0
    stoch_signal:        str   = "NEUTRAL"
    # ── Bollinger Bands ───────────────────────────────────────────────────────
    bb_upper:            float = 0.0
    bb_mid:              float = 0.0
    bb_lower:            float = 0.0
    bb_width:            float = 0.0
    bb_position:         str   = "MIDDLE"
    bb_squeeze:          bool  = False
    # ── Keltner Channels ──────────────────────────────────────────────────────
    kc_upper:            float = 0.0
    kc_mid:              float = 0.0
    kc_lower:            float = 0.0
    # ── TTM Squeeze ───────────────────────────────────────────────────────────
    ttm_squeeze_active:  bool  = False
    ttm_squeeze_label:   str   = "SQUEEZE OFF"
    ttm_momentum:        float = 0.0
    # ── Supertrend (v11) ──────────────────────────────────────────────────────
    supertrend_value:    float = 0.0
    supertrend_signal:   str   = "NEUTRAL"
    supertrend_direction:str   = "NEUTRAL"
    # ── VWAP (v11) ────────────────────────────────────────────────────────────
    vwap:                float = 0.0
    vwap_upper:          float = 0.0
    vwap_lower:          float = 0.0
    vwap_signal:         str   = "NEUTRAL"
    # ── Pivot Points (v11) ────────────────────────────────────────────────────
    pivot_points:        Dict[str, float] = field(default_factory=dict)
    nearest_pivot_level: str   = ""
    nearest_pivot_dist:  float = 0.0
    # ── Z-Score ───────────────────────────────────────────────────────────────
    zscore:              float = 0.0
    zscore_signal:       str   = "NEUTRAL"
    # ── ADX ───────────────────────────────────────────────────────────────────
    adx_value:           float = 0.0
    adx_signal:          str   = "WEAK"
    adx_di_plus:         float = 0.0
    adx_di_minus:        float = 0.0
    # ── Williams %R ───────────────────────────────────────────────────────────
    williams_r:          float = -50.0
    williams_signal:     str   = "NEUTRAL"
    # ── CCI ───────────────────────────────────────────────────────────────────
    cci_value:           float = 0.0
    cci_signal:          str   = "NEUTRAL"
    # ── OBV ───────────────────────────────────────────────────────────────────
    obv_trend:           str   = "NEUTRAL"
    obv_value:           float = 0.0
    # ── Ichimoku ──────────────────────────────────────────────────────────────
    ichimoku_signal:     str   = "NEUTRAL"
    tenkan:              float = 0.0
    kijun:               float = 0.0
    # ── ATR & Stops ───────────────────────────────────────────────────────────
    atr_14:              float = 0.0
    sl_buy:              Optional[float] = None
    sl_sell:             Optional[float] = None
    tp_buy:              Optional[float] = None
    tp_sell:             Optional[float] = None
    sl_pips:             float = 0.0
    atr_explanation:     str   = ""
    atr_multiplier:      float = 1.5
    rr_ratio:            float = 2.5
    # ── Quantum Metrics ───────────────────────────────────────────────────────
    hurst:               float = 0.5
    regime:              str   = "RANDOM"
    regime_advanced:     str   = "CHOPPY"        # v11: 5-state regime
    shannon_entropy:     float = 0.0
    kaufman_er:          float = 0.0
    fractal_dim:         float = 1.5
    realized_vol:        float = 0.0
    vol_regime:          str   = "NORMAL"
    kurtosis:            float = 0.0
    skewness:            float = 0.0
    tail_risk:           str   = "NORMAL"
    autocorr_lag1:       float = 0.0
    stability_index:     int   = 50
    # ── Support / Resistance ──────────────────────────────────────────────────
    supports:            List[float] = field(default_factory=list)
    resistances:         List[float] = field(default_factory=list)
    nearest_support:     float = 0.0
    nearest_resist:      float = 0.0
    sr_zone:             str   = "MIDDLE"
    # ── Elliott Wave ──────────────────────────────────────────────────────────
    wave_position:       str   = "UNKNOWN"
    wave_confidence:     float = 0.0
    wave_target:         Optional[float] = None
    wave_trend:          str   = "NEUTRAL"
    # ── Fibonacci ─────────────────────────────────────────────────────────────
    fib_retracements:    Dict[str, float] = field(default_factory=dict)
    fib_extensions:      Dict[str, float] = field(default_factory=dict)
    fib_zone:            str   = "NEUTRAL"
    fib_strength:        float = 0.0
    fib_explanation:     str   = ""
    # ── Smart Money ───────────────────────────────────────────────────────────
    order_blocks:        List[Dict] = field(default_factory=list)
    fair_value_gaps:     List[Dict] = field(default_factory=list)
    liquidity_sweeps:    List[Dict] = field(default_factory=list)
    smc_bias:            str   = "NEUTRAL"
    smc_explanation:     str   = ""
    # ── Divergence Engine (from math_enginegd) ────────────────────────────────
    rsi_divergence:      str   = "NONE"
    macd_divergence:     str   = "NONE"
    obv_divergence:      str   = "NEUTRAL"
    divergence_signal:   str   = "NONE"
    divergence_strength: float = 0.0
    # ── Candlestick Pattern Detection ─────────────────────────────────────────
    candle_pattern:      str   = "NONE"
    candle_strength:     float = 0.0
    candle_direction:    str   = "NEUTRAL"
    candle_explanation:  str   = ""
    # ── Kelly Criterion ───────────────────────────────────────────────────────
    kelly_fraction:      float = 0.0
    kelly_recommendation:str   = ""
    # ── Session ───────────────────────────────────────────────────────────────
    trading_session:     str   = "OFF-HOURS"
    session_liquidity:   str   = "LOW"
    session_warning:     str   = ""
    session_explanation: str   = ""
    # ── News Lock ─────────────────────────────────────────────────────────────
    news_lock_active:    bool  = False
    news_lock_event:     str   = ""
    news_lock_reason:    str   = ""
    upcoming_news:       List[Dict] = field(default_factory=list)
    # ── Macro Sentiment ───────────────────────────────────────────────────────
    macro_sentiment_score: int  = 50
    macro_sentiment_label: str  = "NEUTRAL"
    macro_bull_hits:     int   = 0
    macro_bear_hits:     int   = 0
    # ── Multi-Timeframe Confluence (v11) ──────────────────────────────────────
    mtf_signals:         Dict[str, Dict] = field(default_factory=dict)
    mtf_confluence:      str   = "NEUTRAL"
    mtf_bull_count:      int   = 0
    mtf_bear_count:      int   = 0
    # ── Trade Plan (v11) ─────────────────────────────────────────────────────
    trade_plan:          Dict  = field(default_factory=dict)
    # ── Lot Calculator ────────────────────────────────────────────────────────
    risk_dollars:        float = 0.0
    recommended_lots:    float = 0.0
    lot_explanation:     str   = ""
    required_margin:     float = 0.0


@dataclass
class NewsItem:
    """Single financial news item with NEXUS Intelligence annotation."""
    title:           str
    source:          str
    published:       str
    url:             str
    category:        str
    nexus_comment:   str
    quant_action:    str
    sentiment_score: float = 0.0
    affected_assets: List[str] = field(default_factory=list)


@dataclass
class SignalRecord:
    """Historical signal record for Signal History tracker."""
    timestamp:   str
    asset:       str
    signal:      str
    price:       float
    strength:    int
    direction:   str
    quality:     str

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 4 — PRICE FEED  (yfinance + ccxt, OHLCV support)
# ══════════════════════════════════════════════════════════════════════════════

class PriceFeed:
    BARS = 300
    FAST_BARS = 240

    @staticmethod
    def _from_yfinance(ticker: str) -> Optional[List[float]]:
        try:
            import yfinance as yf
            import pandas as pd
            df = yf.download(ticker, period="5d", interval="5m",
                             progress=False, auto_adjust=True)
            if df is None or df.empty or len(df) < 40:
                df = yf.download(ticker, period="2d", interval="1m",
                                 progress=False, auto_adjust=True)
            if df is None or df.empty:
                return None
            col = df["Close"]
            if isinstance(col, pd.DataFrame):
                col = col.iloc[:, 0]
            closes = [float(c) for c in col.dropna().tail(PriceFeed.BARS) if c > 0]
            return closes if len(closes) >= 40 else None
        except Exception:
            return None

    @staticmethod
    def _from_yfinance_fast(ticker: str, bars: int = FAST_BARS) -> Optional[List[float]]:
        """
        Ultra-lightweight series fetch intended for high-frequency UI refresh.
        Uses short lookback and 1m candles when available.
        """
        try:
            import yfinance as yf
            import pandas as pd
            df = yf.download(ticker, period="1d", interval="1m",
                             progress=False, auto_adjust=True)
            if df is None or df.empty or len(df) < 10:
                df = yf.download(ticker, period="5d", interval="5m",
                                 progress=False, auto_adjust=True)
            if df is None or df.empty:
                return None
            col = df["Close"]
            if isinstance(col, pd.DataFrame):
                col = col.iloc[:, 0]
            closes = [float(c) for c in col.dropna().tail(int(bars)) if c > 0]
            return closes if len(closes) >= 10 else None
        except Exception:
            return None

    @staticmethod
    def _from_yfinance_ohlcv(ticker: str, period: str = "5d",
                              interval: str = "5m") -> Optional[Dict]:
        """Return OHLCV dict for richer indicator calculations."""
        try:
            import yfinance as yf
            import pandas as pd
            df = yf.download(ticker, period=period, interval=interval,
                             progress=False, auto_adjust=True)
            if df is None or df.empty or len(df) < 20:
                return None
            def _col(name: str) -> List[float]:
                c = df[name]
                if isinstance(c, pd.DataFrame): c = c.iloc[:, 0]
                return [float(v) for v in c.dropna().tail(PriceFeed.BARS) if v > 0]
            o = _col("Open"); h = _col("High"); l = _col("Low"); c = _col("Close")
            v_raw = df["Volume"]
            if isinstance(v_raw, pd.DataFrame): v_raw = v_raw.iloc[:, 0]
            v = [float(x) if x > 0 else 1.0 for x in v_raw.dropna().tail(PriceFeed.BARS)]
            n = min(len(o), len(h), len(l), len(c), len(v))
            if n < 40:
                return None
            return {"open": o[-n:], "high": h[-n:], "low": l[-n:],
                    "close": c[-n:], "volume": v[-n:]}
        except Exception:
            return None

    @staticmethod
    def _from_ccxt(symbol: str) -> Optional[List[float]]:
        try:
            import ccxt
            ex = ccxt.binance({"enableRateLimit": True,
                               "options": {"defaultType": "spot"}})
            ohlcv = ex.fetch_ohlcv(symbol, timeframe="5m", limit=PriceFeed.BARS)
            if ohlcv and len(ohlcv) >= 40:
                return [float(bar[4]) for bar in ohlcv]
            return None
        except Exception:
            return None

    @staticmethod
    def _from_ccxt_fast(symbol: str, bars: int = FAST_BARS) -> Optional[List[float]]:
        """1m close series for fast UI refresh (crypto only)."""
        try:
            import ccxt
            ex = ccxt.binance({"enableRateLimit": True,
                               "options": {"defaultType": "spot"}})
            ohlcv = ex.fetch_ohlcv(symbol, timeframe="1m", limit=int(bars))
            if ohlcv and len(ohlcv) >= 10:
                return [float(bar[4]) for bar in ohlcv if float(bar[4]) > 0]
            return None
        except Exception:
            return None

    @staticmethod
    def _simulate(cfg: AssetConfig) -> List[float]:
        np.random.seed(int(time.time()) % 10000)
        mid = (cfg.price_lo + cfg.price_hi) * 0.35
        vol = mid * 0.003
        trend = np.random.choice([-0.3, -0.1, 0.0, 0.1, 0.3])
        prices = mid + np.cumsum(np.random.normal(trend, vol, PriceFeed.BARS))
        return np.clip(prices, cfg.price_lo, cfg.price_hi).tolist()

    @staticmethod
    def get(cfg: AssetConfig) -> Tuple[List[float], str, Optional[Dict]]:
        """Returns (closes, source_label, ohlcv_dict_or_None)."""
        ohlcv = None
        # Crypto: try ccxt first
        if cfg.ccxt_symbol:
            data = PriceFeed._from_ccxt(cfg.ccxt_symbol)
            if data and cfg.price_lo < float(data[-1]) < cfg.price_hi:
                ohlcv = PriceFeed._from_yfinance_ohlcv(cfg.yf_ticker)
                return data, "Binance/ccxt", ohlcv
        # yfinance OHLCV first (richer data)
        raw = PriceFeed._from_yfinance_ohlcv(cfg.yf_ticker)
        if raw:
            ohlcv = raw
            return raw["close"], "Yahoo Finance", ohlcv
        # Fallback closes only
        data = PriceFeed._from_yfinance(cfg.yf_ticker)
        if data:
            return data, "Yahoo Finance", None
        # Simulator
        return PriceFeed._simulate(cfg), "Simulator (no live feed)", None

    @staticmethod
    def get_fast_series(cfg: AssetConfig, bars: int = FAST_BARS) -> Tuple[List[float], str]:
        """
        Returns (closes, source_label) optimized for frequent refresh.
        For crypto: ccxt 1m series; for others: yfinance 1m/5m.
        """
        if cfg.ccxt_symbol:
            data = PriceFeed._from_ccxt_fast(cfg.ccxt_symbol, bars=bars)
            if data and cfg.price_lo < float(data[-1]) < cfg.price_hi:
                return data, "Binance/ccxt (1m)"
        data = PriceFeed._from_yfinance_fast(cfg.yf_ticker, bars=bars)
        if data and cfg.price_lo < float(data[-1]) < cfg.price_hi:
            return data, "Yahoo Finance (1m/5m)"
        sim = PriceFeed._simulate(cfg)
        return sim[-int(bars):], "Simulator (no live feed)"

    @staticmethod
    def get_latest_price(cfg: AssetConfig) -> Tuple[float, str]:
        """
        Returns (latest_price, source_label).
        Designed to be paired with Streamlit caching at a 2s TTL.
        """
        try:
            if cfg.ccxt_symbol:
                import ccxt
                ex = ccxt.binance({"enableRateLimit": True,
                                   "options": {"defaultType": "spot"}})
                t = ex.fetch_ticker(cfg.ccxt_symbol)
                last = float(t.get("last") or t.get("close") or 0.0)
                if cfg.price_lo < last < cfg.price_hi:
                    return last, "Binance/ccxt ticker"
        except Exception:
            pass
        try:
            data = PriceFeed._from_yfinance_fast(cfg.yf_ticker, bars=20)
            if data:
                last = float(data[-1])
                if cfg.price_lo < last < cfg.price_hi:
                    return last, "Yahoo Finance (fast)"
        except Exception:
            pass
        sim = PriceFeed._simulate(cfg)
        return float(sim[-1]), "Simulator (no live feed)"

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 5 — NEWS ENGINE
# ══════════════════════════════════════════════════════════════════════════════

class NewsEngine:
    _KEYWORD_MAP: Dict[str, Dict] = {
        "CPI":            {"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"Consumer inflation data — direct USD mover. {asset_note}"},
        "inflation":      {"cat":"CRITICAL","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Inflation narrative active — safe-haven demand shifts. {asset_note}"},
        "FOMC":           {"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"Fed policy decision — maximum volatility. {asset_note}"},
        "Federal Reserve":{"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"Fed communication — rate path repricing. {asset_note}"},
        "interest rate":  {"cat":"CRITICAL","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Rate decision — risk/safe-haven rotation. {asset_note}"},
        "NFP":            {"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"Non-Farm Payrolls — largest monthly USD shock. {asset_note}"},
        "Non-Farm":       {"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"NFP — largest monthly USD shock. {asset_note}"},
        "employment":     {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Labor market data — Fed rate expectations. {asset_note}"},
        "jobless":        {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Jobless claims signal labor health. {asset_note}"},
        "GDP":            {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"GDP print — economic growth gauge. {asset_note}"},
        "PCE":            {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"PCE = Fed preferred inflation gauge. Binary reaction. {asset_note}"},
        "Powell":         {"cat":"CRITICAL","risk":"EXTREME","action":"TRADING SUSPENDED",
                           "comment_tmpl":"Fed Chair speaking — forward guidance triggers. {asset_note}"},
        "recession":      {"cat":"HIGH","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Recession fears → safe-haven rotation. {asset_note}"},
        "tariff":         {"cat":"HIGH","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Trade war/tariff rhetoric → macro uncertainty. {asset_note}"},
        "war":            {"cat":"CRITICAL","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Geopolitical escalation — safe-haven spike. {asset_note}"},
        "geopolit":       {"cat":"HIGH","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Geopolitical tension — safe-haven bid. {asset_note}"},
        "SEC":            {"cat":"HIGH","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Regulatory event — crypto sentiment impact. {asset_note}"},
        "ETF":            {"cat":"MEDIUM","risk":"MEDIUM","action":"MONITOR",
                           "comment_tmpl":"ETF flow data — institutional positioning. {asset_note}"},
        "halving":        {"cat":"HIGH","risk":"MEDIUM","action":"MONITOR",
                           "comment_tmpl":"Bitcoin supply shock — historically bullish medium-term. {asset_note}"},
        "sanctions":      {"cat":"HIGH","risk":"HIGH","action":"MONITOR",
                           "comment_tmpl":"Sanctions = USD alternatives demand. {asset_note}"},
        "Retail Sales":   {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Retail sales = consumer demand health. {asset_note}"},
        "ISM":            {"cat":"MEDIUM","risk":"MEDIUM","action":"MONITOR",
                           "comment_tmpl":"Manufacturing/services PMI — economic gauge. {asset_note}"},
        "PPI":            {"cat":"HIGH","risk":"HIGH","action":"AVOID ENTRY",
                           "comment_tmpl":"Producer prices — leading inflation indicator. {asset_note}"},
        "default":        {"cat":"LOW","risk":"LOW","action":"IGNORE",
                           "comment_tmpl":"Statistical noise — no macro significance for {asset_note}."},
    }

    _ASSET_NOTES: Dict[str, Dict[str, str]] = {
        "CPI": {
            "commodity": "High CPI → USD bullish → Gold may dip then rally as real yield falls.",
            "crypto":    "High CPI → rate hike fears → BTC risk-off selloff likely.",
            "index":     "Hot CPI → rate hike risk → equities sell off.",
            "forex":     "CPI miss/beat → immediate USD repricing. 20–60 pip move likely.",
            "default":   "monitor USD reaction for directional clue.",
        },
        "FOMC": {
            "commodity": "Rate hike → USD up, Gold under pressure. Rate cut → Gold rallies.",
            "crypto":    "Rate hike → BTC risk-off. Pause/cut → BTC relief rally.",
            "index":     "Hawkish = equities down. Dovish = equities rally.",
            "forex":     "Largest intraday USD mover — 50–150 pip potential.",
            "default":   "Maximum volatility event. Close all leveraged positions.",
        },
        "NFP": {
            "commodity": "Strong jobs → USD up → Gold pressured. Weak jobs → Gold bid.",
            "crypto":    "Strong NFP = risk-on rotation away from BTC.",
            "index":     "Strong jobs = Fed stays hawkish = equity headwinds.",
            "forex":     "NFP = King of forex events. Explosive initial move.",
            "default":   "Do not trade ±30 minutes around NFP.",
        },
    }

    # ── VADER Sentiment ──────────────────────────────────────────────────────
    _vader = None

    @classmethod
    def _get_vader(cls):
        if cls._vader is None:
            try:
                from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
                cls._vader = SentimentIntensityAnalyzer()
            except Exception:
                cls._vader = None
        return cls._vader

    @staticmethod
    def _vader_score(text: str) -> float:
        """Return compound VADER score [-1, +1]."""
        analyzer = NewsEngine._get_vader()
        if analyzer is None:
            return 0.0
        try:
            return float(analyzer.polarity_scores(text)["compound"])
        except Exception:
            return 0.0

    @staticmethod
    def _get_asset_note(keyword: str, asset_type: str) -> str:
        note_map = NewsEngine._ASSET_NOTES.get(keyword, {})
        return note_map.get(asset_type, note_map.get("default", f"relevant to {asset_type} pricing."))

    @staticmethod
    def _classify(title: str, asset_type: str) -> Tuple[str, str, str, List[str]]:
        title_lo = title.lower()
        for keyword, data in NewsEngine._KEYWORD_MAP.items():
            if keyword.lower() in title_lo:
                asset_note = NewsEngine._get_asset_note(keyword, asset_type)
                comment    = data["comment_tmpl"].format(asset_note=asset_note)
                affected   = []
                macro_kws  = {"CPI","FOMC","NFP","GDP","PCE","Powell","Federal Reserve",
                               "interest rate","recession","tariff","war","geopolit",
                               "PPI","Retail Sales","ISM","employment","jobless"}
                crypto_kws = {"SEC","ETF","halving"}
                if keyword in macro_kws:
                    affected = ["XAUUSD","BTCUSD","ETHUSD","SPX500","EURUSD"]
                elif keyword in crypto_kws:
                    affected = ["BTCUSD","ETHUSD"]
                else:
                    affected = ["ALL"]
                return data["cat"], comment, data["action"], affected
        return "LOW", f"Statistical noise — no macro significance for {asset_type}.", "IGNORE", []

    @staticmethod
    def _fetch_finnhub_calendar() -> List[Dict]:
        try:
            import urllib.request
            today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            url   = (f"https://finnhub.io/api/v1/calendar/economic"
                     f"?from={today}&to={today}&token=sandbox")
            req   = urllib.request.Request(url, headers={"User-Agent": "NEXUS/11.0"})
            with urllib.request.urlopen(req, timeout=6) as resp:
                data = json.loads(resp.read().decode())
            high_kw = ["CPI","NFP","Non-Farm","FOMC","Fed","GDP","PCE",
                       "Retail Sales","PPI","ISM","Jobless","Powell","Interest Rate"]
            events  = []
            for ev in data.get("economicCalendar", []):
                if ev.get("country","") != "US": continue
                name = ev.get("event","")
                if not any(kw.lower() in name.lower() for kw in high_kw): continue
                t = ev.get("time","00:00")[:5]
                events.append({
                    "title":    f"[CALENDAR] {name}  |  Forecast: {ev.get('estimate','?')}  Prev: {ev.get('prev','?')}",
                    "source":   "Finnhub Calendar",
                    "time_utc": t,
                    "impact":   "RED",
                })
            return events
        except Exception:
            return []

    @staticmethod
    def _fetch_yfinance_news(ticker: str) -> List[Dict]:
        try:
            import yfinance as yf
            t   = yf.Ticker(ticker)
            raw = t.news or []
            return [
                {"title":  n.get("title",""),
                 "source": n.get("publisher","Yahoo Finance"),
                 "url":    n.get("link",""),
                 "time":   datetime.fromtimestamp(
                               n.get("providerPublishTime", time.time()),
                               tz=timezone.utc
                           ).strftime("%H:%M UTC")}
                for n in raw[:12] if n.get("title")
            ]
        except Exception:
            return []

    @staticmethod
    def _fetch_rss(url: str, max_items: int = 8) -> List[Dict]:
        try:
            import urllib.request
            import xml.etree.ElementTree as ET
            req = urllib.request.Request(url, headers={"User-Agent": "NEXUS/11.0"})
            with urllib.request.urlopen(req, timeout=6) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
            root  = ET.fromstring(raw)
            items = []
            for item in root.iter("item"):
                te = item.find("title")
                le = item.find("link")
                pe = item.find("pubDate")
                if te is not None and te.text:
                    items.append({
                        "title":  te.text.strip(),
                        "source": "RSS",
                        "url":    le.text.strip() if le is not None else "",
                        "time":   pe.text.strip()[:16] if pe is not None else "",
                    })
                if len(items) >= max_items: break
            return items
        except Exception:
            return []

    @staticmethod
    def _check_news_lock(schedule: List[Dict],
                         window_mins: int = 30) -> Tuple[bool, str, str, List[Dict]]:
        now_utc  = datetime.now(timezone.utc)
        now_mins = now_utc.hour * 60 + now_utc.minute
        locked, event_name, reason = False, "", ""
        upcoming = []
        for ev in schedule:
            try:
                hh, mm  = map(int, ev.get("time_utc","00:00").split(":"))
                ev_mins = hh * 60 + mm
                diff    = now_mins - ev_mins
                if -window_mins <= diff <= window_mins and ev.get("impact","") == "RED":
                    locked     = True
                    event_name = ev.get("title", ev.get("event",""))
                    reason = (f"⚠ {event_name[:45]} in {abs(diff)} min — ENTRY BLOCKED"
                              if diff < 0 else
                              f"⚠ {event_name[:45]} fired {diff} min ago (clears in {window_mins-diff} min)")
                in_mins = ev_mins - now_mins
                if 0 < in_mins <= 240:
                    upcoming.append({"event":    ev.get("title","")[:50],
                                     "in_mins":  in_mins,
                                     "time_utc": ev.get("time_utc","")})
            except Exception:
                continue
        upcoming.sort(key=lambda x: x["in_mins"])
        return locked, event_name, reason, upcoming[:5]

    @staticmethod
    def calc_macro_sentiment(news_items: List["NewsItem"]) -> Tuple[int, str, int, int]:
        """
        Combined VADER + keyword scoring → 0-100 macro sentiment.
        Returns (score, label, bull_hits, bear_hits)
        """
        BULL_KW = ["rate cut","dovish","growth","rally","recovery","stimulus",
                   "record high","beat expectations","surge","upgrade","expansion",
                   "strong jobs","bullish","easing","soft landing","optimism",
                   "deal reached","ceasefire","gdp beat","earnings beat"]
        BEAR_KW = ["rate hike","hawkish","inflation","war","recession","crash",
                   "sell-off","collapse","downgrade","layoffs","tariff","ban",
                   "sanctions","stagflation","tightening","deficit","crisis",
                   "bank failure","contagion","selloff","default"]
        if not news_items:
            return 50, "NEUTRAL", 0, 0

        vader_scores, bull_hits, bear_hits = [], 0, 0
        for item in news_items:
            t = item.title.lower()
            for kw in BULL_KW:
                if kw in t: bull_hits += 1
            for kw in BEAR_KW:
                if kw in t: bear_hits += 1
            vs = NewsEngine._vader_score(item.title)
            vader_scores.append(vs)

        vader_avg = float(np.mean(vader_scores)) if vader_scores else 0.0
        kw_delta  = (bull_hits - bear_hits) / max(len(news_items), 1)
        combined  = 0.6 * vader_avg + 0.4 * kw_delta
        score     = int(min(100, max(0, 50 + combined * 35)))

        label = ("VERY BULLISH" if score >= 70 else
                 "BULLISH"      if score >= 58 else
                 "NEUTRAL"      if score >= 42 else
                 "BEARISH"      if score >= 30 else
                 "VERY BEARISH")
        return score, label, bull_hits, bear_hits

    @staticmethod
    def fetch(cfg: AssetConfig) -> Tuple[List["NewsItem"], List[Dict]]:
        """Fetch, deduplicate, classify headlines. Returns (news_items, calendar)."""
        raw: List[Dict] = []
        raw.extend(NewsEngine._fetch_yfinance_news(cfg.yf_ticker))
        if cfg.asset_type == "crypto":
            raw.extend(NewsEngine._fetch_yfinance_news("BTC-USD"))
        raw.extend(NewsEngine._fetch_rss(
            "https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines", 8))
        calendar = NewsEngine._fetch_finnhub_calendar()
        raw.extend(calendar)

        seen, unique = set(), []
        for item in raw:
            t = item.get("title","")[:60]
            if t and t not in seen:
                seen.add(t); unique.append(item)

        output: List[NewsItem] = []
        for item in unique[:22]:
            title = item.get("title","")
            if not title: continue
            cat, comment, action, affected = NewsEngine._classify(title, cfg.asset_type)
            vs = NewsEngine._vader_score(title)
            output.append(NewsItem(
                title=title, source=item.get("source","Unknown"),
                published=item.get("time", item.get("published","—")),
                url=item.get("url",""), category=cat, nexus_comment=comment,
                quant_action=action, sentiment_score=round(vs, 3), affected_assets=affected,
            ))
        _order = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3}
        output.sort(key=lambda x: _order.get(x.category, 4))
        return output, calendar

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 6 — MATH ENGINE
# ══════════════════════════════════════════════════════════════════════════════

class MathEngine:
    MIN_BARS = 60
    VERSION  = "11.0"

    # ── Utility ───────────────────────────────────────────────────────────────

    @staticmethod
    def _ema(arr: np.ndarray, period: int) -> np.ndarray:
        k   = 2.0 / (period + 1)
        out = np.full(len(arr), np.nan)
        if len(arr) < period: return out
        out[period-1] = np.mean(arr[:period])
        for i in range(period, len(arr)):
            out[i] = arr[i] * k + out[i-1] * (1 - k)
        return out

    @staticmethod
    def _wilder_smooth(arr: np.ndarray, period: int) -> np.ndarray:
        out = np.full(len(arr), np.nan)
        if len(arr) < period: return out
        out[period-1] = np.mean(arr[:period])
        for i in range(period, len(arr)):
            out[i] = (out[i-1] * (period - 1) + arr[i]) / period
        return out

    @staticmethod
    def _sma(arr: np.ndarray, period: int) -> np.ndarray:
        out = np.full(len(arr), np.nan)
        for i in range(period - 1, len(arr)):
            out[i] = float(np.mean(arr[i-period+1:i+1]))
        return out

    # ── ATR ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_atr(prices: np.ndarray, period: int = 14,
                  highs: Optional[np.ndarray] = None,
                  lows:  Optional[np.ndarray] = None) -> float:
        if len(prices) < period + 2: return 0.0
        if highs is not None and lows is not None and len(highs) == len(prices):
            h, l, c = highs, lows, prices
            tr = np.maximum(h[1:] - l[1:],
                 np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
        else:
            tr = np.abs(np.diff(prices)) * 1.5
        s = MathEngine._wilder_smooth(tr, period)
        val = s[-1] if not np.isnan(s[-1]) else float(np.mean(tr[-period:]))
        return float(val)

    @staticmethod
    def _build_stops(price: float, atr: float, atr_mult: float,
                     rr: float, cfg: AssetConfig) -> Tuple:
        if atr == 0:
            return None, None, None, None, 0.0, "ATR=0, cannot compute stops."
        sl_dist = atr * atr_mult
        tp_dist = sl_dist * rr
        sl_pips = round(sl_dist / cfg.pip_size, 1)
        expl    = (f"ATR(14)=${atr:.4f}  SL={atr_mult}×ATR=${sl_dist:.4f}"
                   f"  TP={rr}×SL=${tp_dist:.4f}  ({sl_pips:.0f} pips)")
        return (round(price - sl_dist, 4), round(price + sl_dist, 4),
                round(price + tp_dist, 4), round(price - tp_dist, 4),
                sl_pips, expl)

    # ── RSI ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_rsi(prices: np.ndarray, period: int = 14) -> float:
        if len(prices) < period + 2: return 50.0
        d   = np.diff(prices)
        ag  = MathEngine._wilder_smooth(np.where(d > 0, d,  0.0), period)
        al  = MathEngine._wilder_smooth(np.where(d < 0, -d, 0.0), period)
        av, lv = ag[-1], al[-1]
        if np.isnan(av) or np.isnan(lv) or lv == 0: return 50.0
        return round(100 - 100 / (1 + av / lv), 2)

    # ── MACD ──────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_macd(prices: np.ndarray) -> Tuple[float, float, float]:
        if len(prices) < 35: return 0.0, 0.0, 0.0
        e12  = MathEngine._ema(prices, 12)
        e26  = MathEngine._ema(prices, 26)
        diff = e12 - e26
        valid = diff[~np.isnan(diff)]
        if len(valid) < 9: return 0.0, 0.0, 0.0
        sig  = MathEngine._ema(valid, 9)
        line = float(valid[-1])
        sigv = float(sig[-1]) if not np.isnan(sig[-1]) else 0.0
        return round(line, 5), round(sigv, 5), round(line - sigv, 5)

    # ── Stochastic ────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_stoch(prices: np.ndarray, k: int = 14, d: int = 3) -> Tuple[float, float]:
        if len(prices) < k + d: return 50.0, 50.0
        raw_k = []
        for i in range(len(prices) - k + 1):
            w = prices[i:i+k]; lo, hi = np.min(w), np.max(w)
            raw_k.append(100.0 * (prices[i+k-1] - lo) / (hi - lo) if hi > lo else 50.0)
        raw_k = np.array(raw_k)
        kv = float(np.mean(raw_k[-d:])) if len(raw_k) >= d else float(raw_k[-1])
        dv = float(np.mean(raw_k[-d*2+1:])) if len(raw_k) >= d*2 else kv
        return round(kv, 2), round(dv, 2)

    # ── Bollinger Bands ───────────────────────────────────────────────────────

    @staticmethod
    def _calc_bb(prices: np.ndarray, period: int = 20, std: float = 2.0
                 ) -> Tuple[float, float, float, float]:
        if len(prices) < period:
            p = float(prices[-1]); return p, p, p, 0.0
        w   = prices[-period:]
        mid = float(np.mean(w)); s = float(np.std(w))
        u   = mid + std * s;   lo = mid - std * s
        return round(u,4), round(mid,4), round(lo,4), round((u-lo)/mid*100 if mid else 0.0,4)

    # ── Keltner Channels ──────────────────────────────────────────────────────

    @staticmethod
    def _calc_keltner(prices: np.ndarray, period: int = 20,
                      mult: float = 1.5) -> Tuple[float, float, float]:
        if len(prices) < period:
            p = float(prices[-1]); return p, p, p
        e   = MathEngine._ema(prices, period)
        mid = float(e[-1]) if not np.isnan(e[-1]) else float(np.mean(prices[-period:]))
        atr = MathEngine._calc_atr(prices, period)
        return round(mid + mult*atr,4), round(mid,4), round(mid - mult*atr,4)

    # ── TTM Squeeze ───────────────────────────────────────────────────────────

    @staticmethod
    def _calc_ttm_squeeze(prices: np.ndarray) -> Tuple[bool, str, float]:
        if len(prices) < 22: return False, "SQUEEZE OFF", 0.0
        bbu, _, bbl, _ = MathEngine._calc_bb(prices)
        kcu, _, kcl    = MathEngine._calc_keltner(prices)
        squeeze        = (bbu < kcu) and (bbl > kcl)
        # MACD-like momentum for direction
        sma20 = float(np.mean(prices[-20:]))
        delta = float(np.mean(prices[-5:])) - sma20
        label = ("🔴 SQUEEZE ON — BREAKOUT IMMINENT" if squeeze
                 else "🟢 SQUEEZE OFF — TREND IN MOTION")
        return squeeze, label, round(delta, 4)

    # ── Supertrend (v11) ──────────────────────────────────────────────────────

    @staticmethod
    def _calc_supertrend(prices: np.ndarray, highs: Optional[np.ndarray] = None,
                         lows: Optional[np.ndarray] = None,
                         period: int = 10, mult: float = 3.0) -> Tuple[float, str, str]:
        """ATR-based Supertrend — signals trend direction changes."""
        if len(prices) < period + 5:
            return float(prices[-1]), "NEUTRAL", "#888888"

        atr = MathEngine._calc_atr(prices, period, highs, lows)
        cur = float(prices[-1])

        if highs is not None and lows is not None:
            hl2 = (highs + lows) / 2
        else:
            hl2 = prices  # fallback: use closes as mid approximation

        basic_upper = float(hl2[-1]) + mult * atr
        basic_lower = float(hl2[-1]) - mult * atr

        # Compute rolling direction
        prev = float(prices[-2])
        direction = "BULLISH" if cur > basic_lower else "BEARISH" if cur < basic_upper else "NEUTRAL"

        # Supertrend line
        if direction == "BULLISH":
            st_line = basic_lower
            color   = "#00FF88"
        elif direction == "BEARISH":
            st_line = basic_upper
            color   = "#FF3131"
        else:
            st_line = float(np.mean([basic_upper, basic_lower]))
            color   = "#FFD600"

        return round(st_line, 4), direction, color

    # ── VWAP + Bands (v11) ────────────────────────────────────────────────────

    @staticmethod
    def _calc_vwap(prices: np.ndarray,
                   volumes: Optional[np.ndarray] = None) -> Tuple[float, float, float, str]:
        """VWAP with ±2σ bands. Uses price-change momentum as volume proxy if no volume."""
        if len(prices) < 20:
            p = float(prices[-1]); return p, p*1.002, p*0.998, "NEUTRAL"

        if volumes is not None and len(volumes) == len(prices) and np.sum(volumes) > 0:
            vol = np.array(volumes, dtype=float)
        else:
            # Momentum proxy: |Δprice| normalized
            chg = np.abs(np.diff(prices, prepend=prices[0]))
            vol = chg / (np.sum(chg) + 1e-10) * len(prices)

        tp   = prices.copy()  # typical price ≈ close (no H/L available)
        vwap = float(np.sum(tp * vol) / (np.sum(vol) + 1e-10))

        # Deviation bands
        dev  = float(np.sqrt(np.sum(vol * (tp - vwap) ** 2) / (np.sum(vol) + 1e-10)))
        up   = vwap + 2 * dev
        lo   = vwap - 2 * dev

        cur  = float(prices[-1])
        if cur > up:        signal = "FAR ABOVE VWAP — OVERBOUGHT"
        elif cur > vwap:    signal = "ABOVE VWAP — BULLISH"
        elif cur < lo:      signal = "FAR BELOW VWAP — OVERSOLD"
        else:               signal = "BELOW VWAP — BEARISH"

        return round(vwap,4), round(up,4), round(lo,4), signal

    # ── Pivot Points (v11) ────────────────────────────────────────────────────

    @staticmethod
    def _calc_pivot_points(prices: np.ndarray,
                           highs: Optional[np.ndarray] = None,
                           lows:  Optional[np.ndarray] = None) -> Dict[str, float]:
        """Classic and Fibonacci pivot points from prior session."""
        n  = min(len(prices), 20)
        seg = prices[-n:]
        H  = float(np.max(highs[-n:])) if highs is not None else float(np.max(seg))
        L  = float(np.min(lows[-n:]))  if lows  is not None else float(np.min(seg))
        C  = float(prices[-1])
        PP = round((H + L + C) / 3, 4)
        R  = H - L
        pivots = {
            "PP":  PP,
            "R1":  round(2*PP - L, 4),
            "R2":  round(PP + R, 4),
            "R3":  round(H + 2*(PP-L), 4),
            "S1":  round(2*PP - H, 4),
            "S2":  round(PP - R, 4),
            "S3":  round(L - 2*(H-PP), 4),
            # Fibonacci pivots
            "FR1": round(PP + 0.382*R, 4),
            "FR2": round(PP + 0.618*R, 4),
            "FR3": round(PP + 1.000*R, 4),
            "FS1": round(PP - 0.382*R, 4),
            "FS2": round(PP - 0.618*R, 4),
            "FS3": round(PP - 1.000*R, 4),
        }
        return pivots

    # ── Z-Score ───────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_zscore(prices: np.ndarray, period: int = 50) -> Tuple[float, str]:
        if len(prices) < period: return 0.0, "NEUTRAL"
        w   = prices[-period:]
        std = float(np.std(w))
        if std < 1e-10: return 0.0, "NEUTRAL"
        z   = (float(prices[-1]) - float(np.mean(w))) / std
        sig = ("EXTREME OVERBOUGHT" if z >  3 else "OVERBOUGHT"   if z >  2 else
               "EXTENDED HIGH"      if z >  1 else
               "EXTREME OVERSOLD"   if z < -3 else "OVERSOLD"     if z < -2 else
               "EXTENDED LOW"       if z < -1 else "NEUTRAL")
        return round(z, 3), sig

    # ── ADX ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_adx(prices: np.ndarray, period: int = 14) -> Tuple[float, float, float]:
        if len(prices) < period * 2 + 2: return 0.0, 0.0, 0.0
        highs = prices * 1.0005; lows = prices * 0.9995
        tr    = np.abs(np.diff(prices)) * 1.5
        dm_p  = np.where(np.diff(highs) > -np.diff(lows), np.maximum(np.diff(highs),0.0), 0.0)
        dm_m  = np.where(-np.diff(lows) > np.diff(highs), np.maximum(-np.diff(lows),0.0), 0.0)
        atr_s = MathEngine._wilder_smooth(tr, period)
        di_ps = MathEngine._wilder_smooth(dm_p, period)
        di_ms = MathEngine._wilder_smooth(dm_m, period)
        if np.isnan(atr_s[-1]) or atr_s[-1] == 0: return 0.0, 0.0, 0.0
        dip   = 100 * di_ps[-1] / atr_s[-1]
        dim   = 100 * di_ms[-1] / atr_s[-1]
        dx_d  = abs(dip + dim)
        dx    = 100 * abs(dip - dim) / dx_d if dx_d > 0 else 0.0
        adx_a = np.full(len(tr), np.nan)
        start = period * 2 - 2
        if start < len(tr):
            adx_a[start] = 25.0
            for i in range(start+1, len(tr)):
                if not np.isnan(adx_a[i-1]):
                    adx_a[i] = (adx_a[i-1] * (period-1) + dx) / period
        valid = adx_a[~np.isnan(adx_a)]
        adx   = float(valid[-1]) if len(valid) else 25.0
        return round(adx,2), round(dip,2), round(dim,2)

    # ── Williams %R ───────────────────────────────────────────────────────────

    @staticmethod
    def _calc_williams_r(prices: np.ndarray, period: int = 14) -> float:
        if len(prices) < period: return -50.0
        w = prices[-period:]; hi = np.max(w); lo = np.min(w)
        return round(-100*(hi - prices[-1])/(hi-lo), 2) if hi > lo else -50.0

    # ── CCI ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_cci(prices: np.ndarray, period: int = 14) -> float:
        if len(prices) < period: return 0.0
        tp  = prices[-period:]
        m   = np.mean(tp); md = np.mean(np.abs(tp - m))
        return round((prices[-1] - m) / (0.015 * md), 2) if md else 0.0

    # ── OBV ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_obv(prices: np.ndarray,
                  volumes: Optional[np.ndarray] = None) -> Tuple[float, str]:
        if len(prices) < 20: return 0.0, "NEUTRAL"
        obv = 0.0; recent = []
        for i in range(1, len(prices)):
            vol = float(volumes[i]) if volumes is not None else abs(prices[i]-prices[i-1])*1000
            obv += vol if prices[i] > prices[i-1] else (-vol if prices[i] < prices[i-1] else 0)
            recent.append(obv)
        half  = max(5, len(recent)//4)
        first = np.mean(recent[:half]); last = np.mean(recent[-half:])
        trend = "BULLISH" if last > first*1.01 else "BEARISH" if last < first*0.99 else "NEUTRAL"
        return round(obv, 0), trend

    # ── Ichimoku ──────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_ichimoku(prices: np.ndarray) -> Tuple[str, float, float]:
        if len(prices) < 52: return "NEUTRAL", 0.0, 0.0
        tenkan   = (np.max(prices[-9:])  + np.min(prices[-9:]))  / 2
        kijun    = (np.max(prices[-26:]) + np.min(prices[-26:])) / 2
        senkou_a = (tenkan + kijun) / 2
        senkou_b = (np.max(prices[-52:]) + np.min(prices[-52:])) / 2
        cur = prices[-1]
        above = cur > max(senkou_a, senkou_b)
        below = cur < min(senkou_a, senkou_b)
        tk_bull = tenkan > kijun
        if above and tk_bull:       sig = "STRONG BULLISH"
        elif above:                 sig = "BULLISH"
        elif below and not tk_bull: sig = "STRONG BEARISH"
        elif below:                 sig = "BEARISH"
        else:                       sig = "NEUTRAL (in cloud)"
        return sig, round(tenkan,4), round(kijun,4)

    # ── Hurst Exponent ────────────────────────────────────────────────────────

    @staticmethod
    def _calc_hurst(prices: np.ndarray) -> Tuple[float, str]:
        if len(prices) < 60: return 0.5, "RANDOM"
        try:
            lags = range(2, min(40, len(prices)//3))
            tau  = [np.std(np.subtract(prices[lag:], prices[:-lag])) for lag in lags]
            tau  = [t for t in tau if t > 0]
            if len(tau) < 4: return 0.5, "RANDOM"
            m = np.polyfit(np.log(list(lags[:len(tau)])), np.log(tau), 1)
            h = round(float(m[0]), 4)
            regime = ("TRENDING"       if h > 0.55 else
                      "MEAN-REVERTING" if h < 0.45 else "RANDOM")
            return max(0.0, min(1.0, h)), regime
        except Exception:
            return 0.5, "RANDOM"

    # ── Advanced Regime Detection (v11) ───────────────────────────────────────

    @staticmethod
    def _detect_regime_advanced(prices: np.ndarray, hurst: float,
                                 adx: float, vol_regime: str,
                                 bb_width: float) -> str:
        """
        5-state regime classifier:
        BULL TREND | BEAR TREND | MEAN-REVERTING | CHOPPY | CRISIS VOLATILITY
        """
        cur = float(prices[-1])
        if len(prices) < 30: return "CHOPPY"
        ema50_arr = MathEngine._ema(prices, min(50, len(prices)//2))
        ema50 = float(ema50_arr[-1]) if not np.isnan(ema50_arr[-1]) else cur
        returns = np.diff(prices[-20:]) / (prices[-20:-1] + 1e-10)
        rv = float(np.std(returns)) * math.sqrt(252 * 78)

        if vol_regime == "EXTREME" or rv > 60:
            return "CRISIS VOLATILITY"
        if hurst > 0.57 and adx > 25 and cur > ema50 and bb_width > 2.0:
            return "BULL TREND"
        if hurst > 0.57 and adx > 25 and cur < ema50 and bb_width > 2.0:
            return "BEAR TREND"
        if hurst < 0.45 and bb_width < 2.5:
            return "MEAN-REVERTING"
        if bb_width < 1.5 or adx < 15:
            return "CHOPPY"
        return "CHOPPY"

    # ── Shannon Entropy ───────────────────────────────────────────────────────

    @staticmethod
    def _calc_entropy(prices: np.ndarray) -> float:
        if len(prices) < 20: return 0.0
        try:
            returns = np.diff(prices) / (prices[:-1] + 1e-10)
            hist, _ = np.histogram(returns, bins=20, density=True)
            hist    = hist[hist > 0]
            return round(float(-np.sum(hist * np.log(hist + 1e-12))), 4)
        except Exception:
            return 0.0

    # ── KER ───────────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_ker(prices: np.ndarray, period: int = 20) -> float:
        if len(prices) < period + 1: return 0.0
        net   = abs(prices[-1] - prices[-period-1])
        noise = np.sum(np.abs(np.diff(prices[-period-1:])))
        return round(float(net / noise), 4) if noise > 0 else 0.0

    # ── Fractal Dimension ─────────────────────────────────────────────────────

    @staticmethod
    def _calc_fractal_dim(prices: np.ndarray) -> float:
        if len(prices) < 20: return 1.5
        n = min(len(prices), 60); p = prices[-n:]
        hi, lo = np.max(p), np.min(p); rng = hi - lo
        if rng == 0: return 1.5
        path = np.sum(np.abs(np.diff(p)))
        fd   = 1.0 + math.log(path/rng) / math.log(n)
        return round(max(1.0, min(2.0, fd)), 4)

    # ── Support & Resistance ──────────────────────────────────────────────────

    # ── Divergence Scanner (RSI + MACD) ───────────────────────────────────────

    @staticmethod
    def _detect_divergence(prices: np.ndarray) -> Tuple[str, str, str, float]:
        """
        Detects RSI and MACD divergences — one of the highest-probability
        reversal signals in technical analysis.
        Returns (rsi_div, macd_div, combined_signal, strength)
        """
        if len(prices) < 50:
            return "NONE", "NONE", "NONE", 0.0
        try:
            # RSI on last 50 bars
            p50 = prices[-50:]
            rsi_vals = []
            for i in range(14, len(p50)+1):
                rsi_vals.append(MathEngine._calc_rsi(p50[:i]))
            rsi_arr = np.array(rsi_vals)

            # Price swings vs RSI swings (last 10 vs prior 10)
            price_hi1, price_hi2 = float(np.max(prices[-20:-10])), float(np.max(prices[-10:]))
            price_lo1, price_lo2 = float(np.min(prices[-20:-10])), float(np.min(prices[-10:]))
            rsi_hi1,  rsi_hi2   = float(np.max(rsi_arr[-20:-10])) if len(rsi_arr)>=20 else 50.0, \
                                   float(np.max(rsi_arr[-10:]))    if len(rsi_arr)>=10 else 50.0
            rsi_lo1,  rsi_lo2   = float(np.min(rsi_arr[-20:-10])) if len(rsi_arr)>=20 else 50.0, \
                                   float(np.min(rsi_arr[-10:]))    if len(rsi_arr)>=10 else 50.0

            rsi_div = "NONE"
            # Bearish divergence: price makes higher high, RSI makes lower high
            if price_hi2 > price_hi1 * 1.001 and rsi_hi2 < rsi_hi1 - 2:
                rsi_div = "BEARISH"
            # Bullish divergence: price makes lower low, RSI makes higher low
            elif price_lo2 < price_lo1 * 0.999 and rsi_lo2 > rsi_lo1 + 2:
                rsi_div = "BULLISH"

            # MACD divergence
            macd_div = "NONE"
            if len(prices) >= 60:
                m1, _, h1 = MathEngine._calc_macd(prices[-60:-10])
                m2, _, h2 = MathEngine._calc_macd(prices[-40:])
                if price_hi2 > price_hi1 * 1.001 and h2 < h1 - 0.0001:
                    macd_div = "BEARISH"
                elif price_lo2 < price_lo1 * 0.999 and h2 > h1 + 0.0001:
                    macd_div = "BULLISH"

            # Combined signal
            if rsi_div == "BULLISH" and macd_div == "BULLISH":
                signal, strength = "STRONG BULLISH DIVERGENCE", 85.0
            elif rsi_div == "BEARISH" and macd_div == "BEARISH":
                signal, strength = "STRONG BEARISH DIVERGENCE", 85.0
            elif rsi_div == "BULLISH" or macd_div == "BULLISH":
                signal, strength = "BULLISH DIVERGENCE", 60.0
            elif rsi_div == "BEARISH" or macd_div == "BEARISH":
                signal, strength = "BEARISH DIVERGENCE", 60.0
            else:
                signal, strength = "NONE", 0.0

            return rsi_div, macd_div, signal, round(strength, 1)
        except Exception:
            return "NONE", "NONE", "NONE", 0.0

    # ── Candlestick Pattern Detector ──────────────────────────────────────────

    @staticmethod
    def _detect_candle_patterns(prices: np.ndarray) -> Tuple[str, float, str, str]:
        """
        Detects classic reversal/continuation candlestick patterns.
        Returns (pattern, strength, direction, explanation)
        """
        if len(prices) < 10:
            return "NONE", 0.0, "NEUTRAL", ""
        try:
            r = prices[-10:]
            avg_body = float(np.mean(np.abs(np.diff(r[-6:])))) + 1e-10

            # Bullish Engulfing
            b1 = abs(r[-2] - r[-3]); b2 = abs(r[-1] - r[-2])
            if b1 > 0 and b2 > b1 * 1.4 and r[-1] > r[-2] and r[-2] < r[-3]:
                return ("BULLISH ENGULFING", 78.0, "BULLISH",
                        "Last candle fully engulfs prior bearish candle — strong institutional buying.")
            # Bearish Engulfing
            if b1 > 0 and b2 > b1 * 1.4 and r[-1] < r[-2] and r[-2] > r[-3]:
                return ("BEARISH ENGULFING", 78.0, "BEARISH",
                        "Last candle fully engulfs prior bullish candle — strong institutional selling.")
            # Doji (indecision)
            last_body = abs(r[-1] - r[-2])
            if last_body < avg_body * 0.18:
                return ("DOJI", 52.0, "NEUTRAL",
                        "Near-equal open/close — market indecision. Wait for next candle confirmation.")
            # Hammer / Bullish Pin Bar
            body = r[-1] - r[-2]; prev_rng = abs(r[-2] - r[-3])
            if abs(body) < prev_rng * 0.32 and prev_rng > 0 and r[-3] < r[-4] and body > 0:
                return ("HAMMER", 68.0, "BULLISH",
                        "Small body after a decline with wick below — buyers absorbing selling pressure.")
            # Shooting Star / Bearish Pin Bar
            if abs(body) < prev_rng * 0.32 and prev_rng > 0 and r[-3] > r[-4] and body < 0:
                return ("SHOOTING STAR", 68.0, "BEARISH",
                        "Small body after a rally with wick above — sellers rejecting higher prices.")
            # Higher Highs + Higher Lows (uptrend structure)
            last5 = r[-5:]
            hh = all(last5[i] > last5[i-1] for i in range(1, len(last5)))
            ll = all(last5[i] < last5[i-1] for i in range(1, len(last5)))
            if hh:
                return ("UPTREND STRUCTURE (HH/HL)", 62.0, "BULLISH",
                        "5 consecutive higher closes — price action confirms bullish momentum.")
            if ll:
                return ("DOWNTREND STRUCTURE (LH/LL)", 62.0, "BEARISH",
                        "5 consecutive lower closes — price action confirms bearish momentum.")

            return "NONE", 0.0, "NEUTRAL", "No significant pattern on the last 10 bars."
        except Exception:
            return "NONE", 0.0, "NEUTRAL", ""

    # ── Kelly Criterion ───────────────────────────────────────────────────────

    @staticmethod
    def _calc_kelly(win_prob: float, rr_ratio: float) -> Tuple[float, str]:
        """
        Full Kelly Criterion: f* = W - (1-W)/R
        W = win probability (0–1), R = reward/risk ratio.
        Returns (kelly_fraction, recommendation).
        Capped at 25% (half-Kelly for risk management).
        """
        if win_prob <= 0 or rr_ratio <= 0:
            return 0.0, "Cannot compute — insufficient data."
        try:
            full_kelly = win_prob - (1.0 - win_prob) / rr_ratio
            # Half-Kelly is standard professional practice
            half_kelly = max(0.0, min(0.25, full_kelly * 0.5))
            if half_kelly <= 0:
                rec = "Negative Kelly — edge too small. DO NOT TRADE this setup."
            elif half_kelly < 0.02:
                rec = f"Very small edge ({half_kelly*100:.1f}%). Minimum size recommended."
            elif half_kelly < 0.08:
                rec = f"Moderate edge ({half_kelly*100:.1f}% of capital). Conservative sizing appropriate."
            elif half_kelly < 0.15:
                rec = f"Good edge ({half_kelly*100:.1f}% of capital). Standard position size."
            else:
                rec = f"Strong edge ({half_kelly*100:.1f}% of capital). Full allocation justified by math."
            return round(half_kelly, 4), rec
        except Exception:
            return 0.0, "Calculation error."

    @staticmethod
    def _calc_sr(prices: np.ndarray, cur: float) -> Tuple[List, List, float, float, str]:
        if len(prices) < 30:
            return [], [], cur, cur, "MIDDLE"
        order  = max(3, len(prices)//30)
        ri     = argrelextrema(prices, np.greater, order=order)[0]
        si     = argrelextrema(prices, np.less,    order=order)[0]
        rests  = sorted([round(float(prices[i]),4) for i in ri], reverse=True)[:6]
        supps  = sorted([round(float(prices[i]),4) for i in si])[:6]
        nr     = next((r for r in rests if r > cur), cur)
        ns     = next((s for s in reversed(supps) if s < cur), cur)
        rng    = nr - ns
        if rng < 1e-6: zone = "MIDDLE"
        else:
            pct  = (cur - ns) / rng
            zone = ("NEAR RESISTANCE" if pct > 0.75 else
                    "NEAR SUPPORT"    if pct < 0.25 else "MIDDLE")
        return supps, rests, round(ns,4), round(nr,4), zone

    # ── Order Blocks ──────────────────────────────────────────────────────────

    @staticmethod
    def _detect_obs(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 20: return []
        obs = []; r = prices[-min(100, len(prices)-1):]
        for i in range(2, len(r) - 3):
            move_after  = r[i+3] - r[i+1]
            candle_size = r[i] - r[i-1]
            if abs(candle_size) < 1e-10: continue
            strength = round(min(100, abs(move_after)/abs(candle_size)*20), 1)
            if candle_size < 0 and move_after > abs(candle_size) * 2:
                obs.append({"type":"BULLISH OB",
                             "high": round(max(r[i-1],r[i]),4),
                             "low":  round(min(r[i-1],r[i]),4),
                             "strength": strength,
                             "dist_pct": round(abs(cur-min(r[i-1],r[i]))/(cur+1e-10)*100,2),
                             "tip": "Price returning here = potential BUY zone"})
            elif candle_size > 0 and -move_after > candle_size * 2:
                obs.append({"type":"BEARISH OB",
                             "high": round(max(r[i-1],r[i]),4),
                             "low":  round(min(r[i-1],r[i]),4),
                             "strength": strength,
                             "dist_pct": round(abs(cur-max(r[i-1],r[i]))/(cur+1e-10)*100,2),
                             "tip": "Price returning here = potential SELL zone"})
        obs.sort(key=lambda x: x["dist_pct"])
        return obs[:5]

    # ── Fair Value Gaps ───────────────────────────────────────────────────────

    @staticmethod
    def _detect_fvgs(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 10: return []
        fvgs = []; r = prices[-min(80, len(prices)):]
        atr  = float(np.mean(np.abs(np.diff(r[-20:])))) if len(r) >= 20 else 1.0
        for i in range(len(r) - 2):
            gu = r[i+2] - r[i]; gd = r[i] - r[i+2]
            if gu > atr * 1.5:
                fh, fl = r[i+2], r[i]
                fvgs.append({"type":"BULLISH FVG", "high":round(fh,4), "low":round(fl,4),
                              "filled": any(fl <= r[j] <= fh for j in range(i+3, len(r))),
                              "dist_pct": round(abs(cur-fl)/(cur+1e-10)*100,2),
                              "tip": "BUY magnet — unfilled gap pulls price back"})
            elif gd > atr * 1.5:
                fh, fl = r[i], r[i+2]
                fvgs.append({"type":"BEARISH FVG", "high":round(fh,4), "low":round(fl,4),
                              "filled": any(fl <= r[j] <= fh for j in range(i+3, len(r))),
                              "dist_pct": round(abs(cur-fh)/(cur+1e-10)*100,2),
                              "tip": "SELL magnet — unfilled gap pulls price back"})
        fvgs = [f for f in fvgs if not f["filled"]]
        fvgs.sort(key=lambda x: x["dist_pct"])
        return fvgs[:4]

    # ── Liquidity Sweeps ──────────────────────────────────────────────────────

    @staticmethod
    def _detect_liquidity_sweeps(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 30: return []
        r = prices[-min(100, len(prices)):]; sweeps = []; lookback = 12
        for i in range(lookback, len(r) - 2):
            sh = float(np.max(r[i-lookback:i]))
            sl = float(np.min(r[i-lookback:i]))
            if r[i] > sh * 1.0002 and r[i+1] < sh:
                sweeps.append({"type":        "BEARISH SWEEP (Stop Hunt High)",
                                "swept_level": round(sh, 4),
                                "sweep_price": round(float(r[i]), 4),
                                "close_back":  round(float(r[i+1]), 4),
                                "dist_pct":    round(abs(cur-sh)/(cur+1e-10)*100,2),
                                "tip":         "Whales ran stops above high — look for SELL reversal",
                                "bias":        "SELL"})
            elif r[i] < sl * 0.9998 and r[i+1] > sl:
                sweeps.append({"type":        "BULLISH SWEEP (Stop Hunt Low)",
                                "swept_level": round(sl, 4),
                                "sweep_price": round(float(r[i]), 4),
                                "close_back":  round(float(r[i+1]), 4),
                                "dist_pct":    round(abs(cur-sl)/(cur+1e-10)*100,2),
                                "tip":         "Whales raided stops below low — look for BUY reversal",
                                "bias":        "BUY"})
        sweeps.sort(key=lambda x: x["dist_pct"])
        return sweeps[:5]

    # ── Elliott Wave ──────────────────────────────────────────────────────────

    @staticmethod
    def _detect_elliott(prices: np.ndarray) -> Dict:
        if len(prices) < 50:
            return {"detected":False,"position":"INSUFFICIENT DATA","confidence":0.0}
        try:
            order   = max(3, len(prices)//20)
            hi_ix   = argrelextrema(prices, np.greater, order=order)[0]
            lo_ix   = argrelextrema(prices, np.less,    order=order)[0]
            all_p   = sorted([(i, prices[i]) for i in hi_ix] +
                             [(i, prices[i]) for i in lo_ix], key=lambda x: x[0])
            if len(all_p) < 5:
                return {"detected":False,"position":"TOO FEW PIVOTS","confidence":0.0}
            wc      = len(all_p); recent = all_p[-8:]
            is_up   = prices[-1] > np.mean(prices[-20:])
            pos, conf, tgt = "EARLY WAVE", 35.0, None
            if wc >= 5:
                vals = [p[1] for p in recent[:6]]
                if wc == 5:
                    pos  = "WAVE 5 FORMING"; conf = 60.0
                    if len(vals) >= 5: tgt = vals[4] + abs(vals[0]-vals[1])
                elif wc == 6:
                    pos  = "WAVE 5 COMPLETE — REVERSAL EXPECTED"; conf = 70.0
                    if len(vals) >= 6: tgt = vals[5] - (vals[5]-vals[0]) * 0.382
                elif wc >= 7:
                    pos  = "ABC CORRECTION"; conf = 55.0
                    if len(vals) >= 7:
                        a_len = abs(vals[6]-vals[5]) if len(vals) >= 7 else 0
                        tgt   = (vals[6] - a_len) if is_up else (vals[6] + a_len)
            return {"detected":True,"position":pos,"confidence":round(conf,1),
                    "wave_count":wc,"trend":"BULLISH" if is_up else "BEARISH",
                    "target":round(tgt,4) if tgt else None}
        except Exception:
            return {"detected":False,"position":"COMPUTE ERROR","confidence":0.0}

    # ── Fibonacci ─────────────────────────────────────────────────────────────

    @staticmethod
    def _calc_fib(prices: np.ndarray, cur: float) -> Tuple[Dict,Dict,str,float,str]:
        if len(prices) < 30: return {},{}, "NEUTRAL", 0.0, ""
        r = prices[-min(100, len(prices)):]
        sh = float(np.max(r)); sl = float(np.min(r)); d = sh - sl
        if d < 0.01: return {},{}, "NEUTRAL", 0.0, "Flat range."
        is_up = cur > float(np.mean(r))
        def _r(pct): return round((sh-d*pct) if is_up else (sl+d*pct), 4)
        rets = {"0.0%":_r(0),"23.6%":_r(.236),"38.2%":_r(.382),
                "50.0%":_r(.5),"61.8%":_r(.618),"78.6%":_r(.786),"100.0%":_r(1)}
        exts = {"127.2%":round((sl+d*1.272) if is_up else (sh-d*1.272),4),
                "161.8%":round((sl+d*1.618) if is_up else (sh-d*1.618),4),
                "200.0%":round((sl+d*2.000) if is_up else (sh-d*2.000),4),
                "261.8%":round((sl+d*2.618) if is_up else (sh-d*2.618),4)}
        tol   = d * 0.015; zone, strength, expl = "NEUTRAL", 0.0, ""
        for name, price in rets.items():
            if abs(cur-price) < tol:
                if name in ("38.2%","50.0%","61.8%"):
                    zone, strength = ("STRONG_SUPPORT" if is_up else "STRONG_RESISTANCE"), 80.0
                    expl = f"AT {name} GOLDEN ZONE (${price:,.4f}) — high-probability reversal"
                elif name in ("23.6%","78.6%"):
                    zone, strength = "MINOR_LEVEL", 45.0
                    expl = f"Near {name} Fib (${price:,.4f}) — minor level, needs confluence"
                break
        if not expl:
            near = min(rets, key=lambda k: abs(rets[k]-cur))
            expl = f"Nearest Fib: {near} @ ${rets[near]:,.4f}  (${abs(cur-rets[near]):,.4f} away)"
        return rets, exts, zone, strength, expl

    # ── Session Awareness ─────────────────────────────────────────────────────

    @staticmethod
    def _get_session(cfg: AssetConfig) -> Tuple[str, str, str, str]:
        now = datetime.now(timezone.utc)
        nm  = now.hour * 60 + now.minute; warn = ""
        for label, open_m in [("LONDON OPEN", 7*60), ("NEW YORK OPEN", 12*60)]:
            diff = open_m - nm
            if 0 < diff <= 15:
                warn = f"⚡ {label} in {diff} min — volatility spike imminent!"
        if cfg.is_24_7:
            if 12*60 <= nm < 16*60:   sess,liq,expl = "NY TRADING HOURS","HIGH","Wall St open — highest BTC/ETH volume."
            elif 7*60 <= nm < 12*60:  sess,liq,expl = "LONDON HOURS","MEDIUM-HIGH","European session — moderate crypto."
            elif 0 <= nm < 7*60:      sess,liq,expl = "ASIAN HOURS","MEDIUM","Asian session — 24/7 crypto. Thinner books."
            else:                      sess,liq,expl = "LATE NY/OVERNIGHT","LOW","Thin liquidity — large moves on small orders."
        else:
            if 12*60 <= nm < 16*60:   sess,liq,expl = "OVERLAP (Ldn+NY)","EXTREME","Both sessions open — highest daily volume."
            elif 12*60 <= nm < 21*60: sess,liq,expl = "NEW YORK","HIGH","NY session — USD events drive price."
            elif 7*60 <= nm < 16*60:  sess,liq,expl = "LONDON","HIGH","London sets daily trend — best for trend entries."
            elif 0 <= nm < 9*60:      sess,liq,expl = "ASIAN","MEDIUM","Range-bound likely. Fakeouts near S/R common."
            else:                      sess,liq,expl = "OFF-HOURS","LOW","Minimal institutional participation. Avoid."
        return sess, liq, warn, expl

    # ── Probability Score (v11) ───────────────────────────────────────────────

    @staticmethod
    def _calc_probability(mi: "MarketIntelligence") -> Tuple[float, str]:
        """7-factor weighted probability model → bull% with label."""
        W = {"ema":0.20, "momentum":0.18, "volume":0.10,
             "quantum":0.15, "structure":0.18, "sentiment":0.09, "session":0.10}
        scores: Dict[str, float] = {}
        # EMA trend
        if   mi.ema_alignment == "BULLISH STACK":  scores["ema"] = 0.85
        elif mi.ema_alignment == "BEARISH STACK":  scores["ema"] = 0.15
        else:                                       scores["ema"] = 0.50
        # Momentum: RSI + MACD + Stoch + Supertrend
        m = 0.50
        m += 0.12 if mi.rsi < 30 else (-0.12 if mi.rsi > 70 else (0.04 if mi.rsi < 45 else -0.04))
        m += 0.10 if mi.macd_hist > 0 else -0.10
        m += 0.05 if mi.stoch_k < 20 else (-0.05 if mi.stoch_k > 80 else 0)
        m += 0.05 if mi.supertrend_signal == "BULLISH" else (-0.05 if mi.supertrend_signal == "BEARISH" else 0)
        scores["momentum"] = max(0.0, min(1.0, m))
        # Volume / OBV
        scores["volume"] = 0.70 if mi.obv_trend == "BULLISH" else (0.30 if mi.obv_trend == "BEARISH" else 0.50)
        # Quantum
        q = 0.50
        is_bull = "BULL" in mi.direction
        if mi.hurst > 0.55: q += 0.12 if is_bull else -0.12
        if mi.kaufman_er > 0.6: q += 0.04 if is_bull else -0.04
        z = mi.zscore
        if z < -2: q += 0.10  # mean reversion → bullish
        elif z > 2: q -= 0.10
        scores["quantum"] = max(0.0, min(1.0, q))
        # Structure
        st = 0.50
        if mi.sr_zone == "NEAR SUPPORT":    st += 0.12
        elif mi.sr_zone == "NEAR RESISTANCE": st -= 0.12
        bull_obs = sum(1 for ob in mi.order_blocks if "BULL" in ob.get("type",""))
        bear_obs = sum(1 for ob in mi.order_blocks if "BEAR" in ob.get("type",""))
        st += (bull_obs - bear_obs) * 0.03
        if mi.vwap_signal and "ABOVE VWAP" in mi.vwap_signal: st += 0.05
        elif mi.vwap_signal and "BELOW VWAP" in mi.vwap_signal: st -= 0.05
        scores["structure"] = max(0.0, min(1.0, st))
        # Sentiment
        se = mi.macro_sentiment_score / 100
        if "BULLISH" in mi.ichimoku_signal: se = min(1.0, se + 0.08)
        elif "BEARISH" in mi.ichimoku_signal: se = max(0.0, se - 0.08)
        scores["sentiment"] = se
        # Session
        sess_w = {"EXTREME":0.62,"HIGH":0.57,"MEDIUM-HIGH":0.53,
                  "MEDIUM":0.50,"LOW":0.43}.get(mi.session_liquidity, 0.50)
        scores["session"] = sess_w
        # Weighted composite
        bull_pct = round(sum(W[k] * scores[k] for k in W) * 100, 1)
        label = ("STRONGLY BULLISH" if bull_pct >= 72 else "BULLISH"  if bull_pct >= 60 else
                 "NEUTRAL"          if bull_pct >= 40 else "BEARISH"  if bull_pct >= 28 else
                 "STRONGLY BEARISH")
        return bull_pct, label

    # ── Multi-Timeframe Confluence (v11) ──────────────────────────────────────

    @staticmethod
    def _calc_mtf(cfg: AssetConfig) -> Tuple[Dict[str, Dict], str, int, int]:
        """Fetch 4 timeframes, compute quick signals. Returns (signals, confluence, bull_cnt, bear_cnt)."""
        tf_map = {"5m":("5m","2d"), "15m":("15m","5d"), "1h":("1h","30d"), "4h":("4h","60d")}
        results: Dict[str, Dict] = {}
        for tf_label, (interval, period) in tf_map.items():
            try:
                import yfinance as yf
                import pandas as pd
                df = yf.download(cfg.yf_ticker, period=period, interval=interval,
                                 progress=False, auto_adjust=True)
                if df is None or df.empty or len(df) < 30:
                    results[tf_label] = {"trend":"N/A","rsi":50,"signal":"NEUTRAL","color":"#555"}
                    continue
                col = df["Close"]
                if isinstance(col, pd.DataFrame): col = col.iloc[:,0]
                arr = np.array([float(c) for c in col.dropna() if c > 0])
                if len(arr) < 30:
                    results[tf_label] = {"trend":"N/A","rsi":50,"signal":"NEUTRAL","color":"#555"}
                    continue
                rsi   = MathEngine._calc_rsi(arr)
                e9    = float(MathEngine._ema(arr, 9)[-1])
                e21   = float(MathEngine._ema(arr, 21)[-1])
                e50_a = MathEngine._ema(arr, min(50, len(arr)//2))
                e50   = float(e50_a[-1]) if not np.isnan(e50_a[-1]) else float(arr[-1])
                cur   = float(arr[-1])
                macd_l, _, macd_h = MathEngine._calc_macd(arr)
                # Trend
                if   cur > e9 > e21 > e50:   trend = "STRONG BULL"
                elif cur > e21 > e50:         trend = "BULLISH"
                elif cur < e9 < e21 < e50:   trend = "STRONG BEAR"
                elif cur < e21 < e50:         trend = "BEARISH"
                else:                         trend = "NEUTRAL"
                # Signal
                bp = sum([cur > e50, rsi < 60, macd_h > 0, e9 > e21])
                be = sum([cur < e50, rsi > 40, macd_h < 0, e9 < e21])
                signal = "BULLISH" if bp >= 3 else "BEARISH" if be >= 3 else "NEUTRAL"
                color  = "#00FF88" if signal=="BULLISH" else "#FF3131" if signal=="BEARISH" else "#888"
                results[tf_label] = {"trend":trend,"rsi":round(rsi,1),"signal":signal,
                                     "color":color,"cur":round(cur,4),"e9":round(e9,4),"e50":round(e50,4)}
            except Exception:
                results[tf_label] = {"trend":"ERR","rsi":50,"signal":"NEUTRAL","color":"#555"}

        bull = sum(1 for v in results.values() if v.get("signal") == "BULLISH")
        bear = sum(1 for v in results.values() if v.get("signal") == "BEARISH")
        if bull >= 3:   conf = "STRONG BULLISH CONFLUENCE"
        elif bull >= 2: conf = "BULLISH CONFLUENCE"
        elif bear >= 3: conf = "STRONG BEARISH CONFLUENCE"
        elif bear >= 2: conf = "BEARISH CONFLUENCE"
        else:           conf = "MIXED / NO CONFLUENCE"
        return results, conf, bull, bear

    # ── Lot Calculator ────────────────────────────────────────────────────────

    @staticmethod
    def calc_lot_size(account_bal: float, risk_pct: float, leverage: float,
                      sl_pips: float, cfg: AssetConfig,
                      current_price: float) -> Tuple[float, float, float, str]:
        if sl_pips <= 0 or account_bal <= 0:
            return 0.0, 0.0, 0.0, "Enter account data to calculate position size."
        risk_usd = account_bal * (risk_pct / 100.0)
        lots     = max(0.01, round(risk_usd / (sl_pips * cfg.pip_value_per_lot), 2))
        notional = lots * cfg.contract_size * current_price
        margin   = round(notional / max(leverage, 1), 2)
        tp_gain  = round(sl_pips * cfg.pip_value_per_lot * lots * 2.5, 2)
        expl = (f"Risk: ${risk_usd:.2f} ({risk_pct}%)  ·  Lots: {lots}"
                f"  ·  SL: {sl_pips:.0f} pips  ·  Pip val: ${cfg.pip_value_per_lot}/lot"
                f"  ·  Margin: ${margin:,.2f}  ·  Max TP: ${tp_gain:.2f}")
        return round(risk_usd,2), lots, margin, expl

    # ── Master Analysis Entry Point ───────────────────────────────────────────

    @staticmethod
    def analyze(prices: List[float], cfg: AssetConfig,
                atr_mult: float = 1.5, rr_ratio: float = 2.5,
                news_schedule: Optional[List[Dict]] = None,
                ohlcv: Optional[Dict] = None) -> Optional[MarketIntelligence]:
        if not prices or len(prices) < MathEngine.MIN_BARS:
            return None
        try:
            p   = np.array(prices, dtype=float)
            cur = float(p[-1])
            mi  = MarketIntelligence()
            mi.asset_name    = cfg.name
            mi.asset_type    = cfg.asset_type
            mi.last_update   = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
            mi.current_price = round(cur, 4)
            mi.prices        = prices[-250:]
            mi.price_change  = round(cur - float(p[-2]), 4) if len(p) >= 2 else 0.0
            mi.price_change_pct = round(mi.price_change / float(p[-2]) * 100, 3) if float(p[-2]) else 0.0

            # Extract OHLCV arrays if available
            highs   = np.array(ohlcv["high"],   dtype=float) if ohlcv else None
            lows    = np.array(ohlcv["low"],    dtype=float) if ohlcv else None
            volumes = np.array(ohlcv["volume"], dtype=float) if ohlcv else None

            # EMAs
            e9,e21,e50,e200 = [MathEngine._ema(p, n) for n in [9,21,50,200]]
            mi.ema9  = round(float(e9[-1]),4)  if not np.isnan(e9[-1])  else cur
            mi.ema21 = round(float(e21[-1]),4) if not np.isnan(e21[-1]) else cur
            mi.ema50 = round(float(e50[-1]),4) if not np.isnan(e50[-1]) else cur
            mi.ema200= round(float(e200[-1]),4)if not np.isnan(e200[-1])else cur
            mi.ema_alignment = ("BULLISH STACK" if mi.ema9>mi.ema21>mi.ema50 else
                                "BEARISH STACK" if mi.ema9<mi.ema21<mi.ema50 else "MIXED")

            # RSI
            mi.rsi = MathEngine._calc_rsi(p)
            mi.rsi_signal = ("OVERBOUGHT" if mi.rsi>70 else "OVERSOLD" if mi.rsi<30 else "NEUTRAL")
            mi.rsi_explanation = (f"RSI overbought at {mi.rsi:.1f} — reversal likely." if mi.rsi>70 else
                                   f"RSI oversold at {mi.rsi:.1f} — bounce zone."       if mi.rsi<30 else
                                   f"RSI neutral at {mi.rsi:.1f} — no extreme reading.")

            # MACD
            mi.macd_line, mi.macd_signal, mi.macd_hist = MathEngine._calc_macd(p)
            mi.macd_cross = "BULLISH" if mi.macd_hist>0 else "BEARISH" if mi.macd_hist<0 else "NEUTRAL"

            # Stochastic
            mi.stoch_k, mi.stoch_d = MathEngine._calc_stoch(p)
            mi.stoch_signal = ("OVERBOUGHT" if mi.stoch_k>80 else "OVERSOLD" if mi.stoch_k<20 else "NEUTRAL")

            # Bollinger Bands
            mi.bb_upper, mi.bb_mid, mi.bb_lower, mi.bb_width = MathEngine._calc_bb(p)
            mi.bb_position = ("ABOVE UPPER" if cur>=mi.bb_upper else "BELOW LOWER" if cur<=mi.bb_lower else
                              "UPPER HALF" if cur>mi.bb_mid else "LOWER HALF")
            mi.bb_squeeze = mi.bb_width < 1.5

            # Keltner
            mi.kc_upper, mi.kc_mid, mi.kc_lower = MathEngine._calc_keltner(p)

            # TTM Squeeze
            mi.ttm_squeeze_active, mi.ttm_squeeze_label, mi.ttm_momentum = MathEngine._calc_ttm_squeeze(p)

            # ADX
            mi.adx_value, mi.adx_di_plus, mi.adx_di_minus = MathEngine._calc_adx(p)
            mi.adx_signal = ("STRONG" if mi.adx_value>25 else "MODERATE" if mi.adx_value>18 else "WEAK")

            # Williams %R
            mi.williams_r = MathEngine._calc_williams_r(p)
            mi.williams_signal = ("OVERBOUGHT" if mi.williams_r>-20 else "OVERSOLD" if mi.williams_r<-80 else "NEUTRAL")

            # CCI
            mi.cci_value = MathEngine._calc_cci(p)
            mi.cci_signal = ("OVERBOUGHT" if mi.cci_value>100 else "OVERSOLD" if mi.cci_value<-100 else "NEUTRAL")

            # OBV
            mi.obv_value, mi.obv_trend = MathEngine._calc_obv(p, volumes)

            # Ichimoku
            mi.ichimoku_signal, mi.tenkan, mi.kijun = MathEngine._calc_ichimoku(p)

            # ATR & Stops
            mi.atr_14 = round(MathEngine._calc_atr(p, 14, highs, lows), 4)
            mi.atr_multiplier = atr_mult; mi.rr_ratio = rr_ratio
            mi.sl_buy, mi.sl_sell, mi.tp_buy, mi.tp_sell, mi.sl_pips, mi.atr_explanation = \
                MathEngine._build_stops(cur, mi.atr_14, atr_mult, rr_ratio, cfg)

            # Supertrend (v11)
            mi.supertrend_value, mi.supertrend_signal, _ = \
                MathEngine._calc_supertrend(p, highs, lows)
            mi.supertrend_direction = mi.supertrend_signal

            # VWAP (v11)
            mi.vwap, mi.vwap_upper, mi.vwap_lower, mi.vwap_signal = \
                MathEngine._calc_vwap(p, volumes)

            # Pivot Points (v11)
            mi.pivot_points = MathEngine._calc_pivot_points(p, highs, lows)
            if mi.pivot_points:
                all_levels = {k:v for k,v in mi.pivot_points.items()}
                nearest = min(all_levels.items(), key=lambda x: abs(x[1]-cur), default=("PP",cur))
                mi.nearest_pivot_level = nearest[0]
                mi.nearest_pivot_dist  = round(abs(nearest[1]-cur)/cur*100, 3)

            # Z-Score
            mi.zscore, mi.zscore_signal = MathEngine._calc_zscore(p)

            # Quantum Metrics
            mi.hurst, mi.regime         = MathEngine._calc_hurst(p)
            mi.shannon_entropy           = MathEngine._calc_entropy(p)
            mi.kaufman_er                = MathEngine._calc_ker(p)
            mi.fractal_dim               = MathEngine._calc_fractal_dim(p)
            returns = np.diff(p)/(p[:-1]+1e-10)*100
            mi.realized_vol  = round(float(np.std(returns)*math.sqrt(252*78)),2)
            mi.vol_regime    = ("EXTREME" if mi.realized_vol>40 else "HIGH" if mi.realized_vol>20 else
                                "NORMAL"  if mi.realized_vol>8  else "LOW")
            mi.kurtosis  = round(float(sp_kurtosis(returns)),4) if len(returns)>8 else 0.0
            mi.skewness  = round(float(sp_skew(returns)),4)     if len(returns)>8 else 0.0
            mi.tail_risk = ("EXTREME" if abs(mi.kurtosis)>7 else "HIGH" if abs(mi.kurtosis)>4 else "NORMAL")
            mi.autocorr_lag1 = (round(float(np.corrcoef(returns[:-1],returns[1:])[0,1]),4)
                                if len(returns)>4 else 0.0)
            mi.stability_index = min(100, int(
                (max(0,40-mi.realized_vol)/40*30) + (min(mi.adx_value,50)/50*30) +
                (mi.kaufman_er*25) + (abs(mi.hurst-0.5)/0.5*15)))

            # Advanced Regime (v11)
            mi.regime_advanced = MathEngine._detect_regime_advanced(
                p, mi.hurst, mi.adx_value, mi.vol_regime, mi.bb_width)

            # S/R
            mi.supports, mi.resistances, mi.nearest_support, mi.nearest_resist, mi.sr_zone = \
                MathEngine._calc_sr(p, cur)

            # Elliott Wave
            wave = MathEngine._detect_elliott(p)
            mi.wave_position, mi.wave_confidence = wave.get("position","UNKNOWN"), wave.get("confidence",0.0)
            mi.wave_target, mi.wave_trend         = wave.get("target"), wave.get("trend","NEUTRAL")

            # Fibonacci
            mi.fib_retracements, mi.fib_extensions, mi.fib_zone, mi.fib_strength, mi.fib_explanation = \
                MathEngine._calc_fib(p, cur)

            # Smart Money
            mi.order_blocks     = MathEngine._detect_obs(p, cur)
            mi.fair_value_gaps  = MathEngine._detect_fvgs(p, cur)
            mi.liquidity_sweeps = MathEngine._detect_liquidity_sweeps(p, cur)
            bull_obs  = sum(1 for ob in mi.order_blocks if "BULL" in ob.get("type",""))
            bear_obs  = sum(1 for ob in mi.order_blocks if "BEAR" in ob.get("type",""))
            bull_swp  = sum(1 for sw in mi.liquidity_sweeps if sw.get("bias")=="BUY")
            bear_swp  = sum(1 for sw in mi.liquidity_sweeps if sw.get("bias")=="SELL")
            smc_bull  = bull_obs + bull_swp; smc_bear = bear_obs + bear_swp
            mi.smc_bias = ("BULLISH" if smc_bull>smc_bear+1 else "BEARISH" if smc_bear>smc_bull+1 else "NEUTRAL")
            mi.smc_explanation = (f"SMC: {bull_obs} bull OBs, {bear_obs} bear OBs, "
                                   f"{bull_swp} bull sweeps, {bear_swp} bear sweeps → {mi.smc_bias} bias")

            # ── Divergence Engine ─────────────────────────────────────────────
            mi.rsi_divergence, mi.macd_divergence, mi.divergence_signal, mi.divergence_strength = \
                MathEngine._detect_divergence(p)

            # ── Candlestick Pattern Detection ─────────────────────────────────
            mi.candle_pattern, mi.candle_strength, mi.candle_direction, mi.candle_explanation = \
                MathEngine._detect_candle_patterns(p)

            # Session
            mi.trading_session, mi.session_liquidity, mi.session_warning, mi.session_explanation = \
                MathEngine._get_session(cfg)

            # News lock
            if news_schedule:
                locked, ev_name, reason, upcoming = NewsEngine._check_news_lock(news_schedule)
                mi.news_lock_active = locked; mi.news_lock_event = ev_name
                mi.news_lock_reason = reason; mi.upcoming_news   = upcoming

            # ── Bull / Bear Scoring ────────────────────────────────────────────
            bull, bear = 0, 0
            # Trend
            if cur > mi.ema50: bull += 2; 
            else: bear += 2
            if cur > mi.ema200: bull += 2
            else: bear += 2
            if mi.ema_alignment == "BULLISH STACK": bull += 3
            elif mi.ema_alignment == "BEARISH STACK": bear += 3
            if mi.supertrend_signal == "BULLISH": bull += 3
            elif mi.supertrend_signal == "BEARISH": bear += 3
            # Momentum
            if mi.rsi < 30: bull += 2
            elif mi.rsi > 70: bear += 2
            if mi.macd_hist > 0: bull += 2
            elif mi.macd_hist < 0: bear += 2
            if mi.stoch_k < 20: bull += 2
            elif mi.stoch_k > 80: bear += 2
            # BB
            if cur <= mi.bb_lower: bull += 2
            elif cur >= mi.bb_upper: bear += 2
            # ADX
            if mi.adx_value > 25:
                if mi.adx_di_plus > mi.adx_di_minus: bull += 3
                else: bear += 3
            # Williams + CCI
            if mi.williams_r < -80: bull += 1
            elif mi.williams_r > -20: bear += 1
            if mi.cci_value < -100: bull += 1
            elif mi.cci_value > 100: bear += 1
            # Ichimoku
            if "BULLISH" in mi.ichimoku_signal: bull += 2
            elif "BEARISH" in mi.ichimoku_signal: bear += 2
            # Hurst regime
            if mi.regime == "TRENDING" and mi.hurst > 0.55:
                bull += 2 if mi.ema_alignment == "BULLISH STACK" else 0
                bear += 2 if mi.ema_alignment == "BEARISH STACK" else 0
            # OBV + VWAP + Supertrend + SMC
            if mi.obv_trend == "BULLISH": bull += 1
            elif mi.obv_trend == "BEARISH": bear += 1
            if "ABOVE VWAP" in mi.vwap_signal: bull += 1
            elif "BELOW VWAP" in mi.vwap_signal: bear += 1
            if mi.smc_bias == "BULLISH": bull += 2
            elif mi.smc_bias == "BEARISH": bear += 2
            mi.bull_score = bull; mi.bear_score = bear
            total    = bull + bear
            bull_pct = bull/total*100 if total > 0 else 50

            # ── Kelly Criterion (must run AFTER bull/bear scores are set) ─────
            total_raw    = mi.bull_score + mi.bear_score
            win_prob_raw = (mi.bull_score / total_raw) if total_raw > 0 else 0.5
            mi.kelly_fraction, mi.kelly_recommendation = \
                MathEngine._calc_kelly(win_prob_raw, rr_ratio)

            # ── Safety Signal ───────────────────────────────────────────────────
            if mi.news_lock_active:
                mi.safety_signal = "HIGH RISK — NEWS LOCK"; mi.signal_color = "#FF3131"
                mi.signal_strength = 0; mi.direction = "NEUTRAL"
                mi.entry_quality = "BLOCKED"
                mi.entry_explanation = f"Trading suspended: {mi.news_lock_reason}"
            elif mi.session_liquidity == "LOW":
                mi.safety_signal = "WAIT — LOW LIQUIDITY"; mi.signal_color = "#FFD600"
                mi.signal_strength = 20; mi.direction = "NEUTRAL"
                mi.entry_quality = "POOR"
                mi.entry_explanation = "Off-hours — insufficient volume for reliable entries."
            elif bull_pct >= 70 and mi.adx_value > 20 and not mi.ttm_squeeze_active:
                mi.safety_signal = "BUY SAFE"; mi.signal_color = "#00FF88"
                mi.signal_strength = int(bull_pct); mi.direction = "BULLISH"
                mi.entry_quality = "EXCELLENT" if bull_pct >= 80 else "GOOD"
                mi.entry_explanation = (f"Bullish confluence: {bull}/{total} signals aligned. "
                                        f"EMA: {mi.ema_alignment}. Supertrend: {mi.supertrend_signal}. "
                                        f"ADX: {mi.adx_value:.1f}. Session: {mi.trading_session}.")
            elif bull_pct <= 30 and mi.adx_value > 20 and not mi.ttm_squeeze_active:
                mi.safety_signal = "SELL SAFE"; mi.signal_color = "#FF3131"
                mi.signal_strength = int(100-bull_pct); mi.direction = "BEARISH"
                mi.entry_quality = "EXCELLENT" if bull_pct <= 20 else "GOOD"
                mi.entry_explanation = (f"Bearish confluence: {bear}/{total} signals aligned. "
                                        f"EMA: {mi.ema_alignment}. Supertrend: {mi.supertrend_signal}. "
                                        f"ADX: {mi.adx_value:.1f}. Regime: {mi.regime_advanced}.")
            elif mi.ttm_squeeze_active:
                mi.safety_signal = "WAIT — TTM SQUEEZE"; mi.signal_color = "#FF9800"
                mi.signal_strength = 35; mi.direction = "NEUTRAL"
                mi.entry_quality = "FAIR"
                mi.entry_explanation = "TTM Squeeze ON — explosive move imminent. Wait for breakout candle direction."
            elif 45 <= bull_pct <= 55:
                mi.safety_signal = "WAIT — NO CONFLUENCE"; mi.signal_color = "#666666"
                mi.signal_strength = 0; mi.direction = "NEUTRAL"; mi.entry_quality = "POOR"
                mi.entry_explanation = f"Mixed signals ({bull} bull / {bear} bear). No statistical edge."
            else:
                mi.safety_signal = "WAIT"; mi.signal_color = "#FFD600"
                mi.signal_strength = int(abs(bull_pct-50))
                mi.direction = "BULLISH" if bull_pct > 50 else "BEARISH"; mi.entry_quality = "FAIR"
                mi.entry_explanation = f"Weak confluence ({bull} bull / {bear} bear). Wait for confirmation."

            # ── Probability Score (v11) ─────────────────────────────────────────
            mi.probability_bull, mi.probability_label = MathEngine._calc_probability(mi)

            return mi
        except Exception:
            traceback.print_exc()
            return None

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 7 — TRADE PLAN GENERATOR (v11)
# ══════════════════════════════════════════════════════════════════════════════

def generate_trade_plan(mi: MarketIntelligence, cfg: AssetConfig) -> Dict:
    """Generate a complete institutional-grade trade plan from MarketIntelligence."""
    cur = mi.current_price; atr = mi.atr_14
    if mi.direction not in ("BULLISH", "BEARISH") or atr == 0:
        return {"valid": False, "reason": "No directional signal — wait for confluence."}

    is_bull = mi.direction == "BULLISH"
    # Stops
    sl  = mi.sl_buy  if is_bull else mi.sl_sell
    tp1 = mi.tp_buy  if is_bull else mi.tp_sell
    if sl is None: sl  = (cur - atr*mi.atr_multiplier) if is_bull else (cur + atr*mi.atr_multiplier)
    if tp1 is None: tp1 = (cur + atr*mi.rr_ratio*mi.atr_multiplier) if is_bull else (cur - atr*mi.rr_ratio*mi.atr_multiplier)

    risk = abs(cur - sl)
    tp2  = (cur + risk*3.5) if is_bull else (cur - risk*3.5)
    tp3  = (cur + risk*5.5) if is_bull else (cur - risk*5.5)
    rr1  = round(abs(tp1-cur)/risk, 2) if risk > 0 else 0.0
    rr2  = round(abs(tp2-cur)/risk, 2) if risk > 0 else 0.0

    # Confidence
    total = mi.bull_score + mi.bear_score
    raw   = (mi.bull_score/total*100 if is_bull else mi.bear_score/total*100) if total > 0 else 50.0
    if mi.adx_value > 25:         raw = min(95, raw + 5)
    if mi.ttm_squeeze_active:     raw = min(95, raw + 3)
    if mi.news_lock_active:       raw = max(10, raw - 30)
    if mi.session_liquidity=="LOW": raw = max(10, raw - 15)
    if mi.regime_advanced in ("CRISIS VOLATILITY","CHOPPY"): raw = max(20, raw - 10)
    quality = ("EXCELLENT" if raw>=80 else "GOOD" if raw>=68 else "FAIR" if raw>=55 else "POOR")

    # Reasoning
    r = []
    if mi.ema_alignment=="BULLISH STACK" and is_bull:    r.append("EMA 9/21/50 bullish alignment ✓")
    if mi.ema_alignment=="BEARISH STACK" and not is_bull: r.append("EMA 9/21/50 bearish alignment ✓")
    if mi.supertrend_signal=="BULLISH" and is_bull:      r.append(f"Supertrend bullish (${mi.supertrend_value:,.4f}) ✓")
    if mi.supertrend_signal=="BEARISH" and not is_bull:  r.append(f"Supertrend bearish (${mi.supertrend_value:,.4f}) ✓")
    if mi.rsi < 35 and is_bull:  r.append(f"RSI oversold at {mi.rsi:.1f} ✓")
    if mi.rsi > 65 and not is_bull: r.append(f"RSI overbought at {mi.rsi:.1f} ✓")
    if mi.adx_value > 25:        r.append(f"ADX strong trend ({mi.adx_value:.1f}) ✓")
    if mi.hurst > 0.55:          r.append(f"Hurst trending ({mi.hurst:.3f}) ✓")
    if mi.zscore_signal in ("OVERSOLD","EXTREME OVERSOLD") and is_bull:
        r.append(f"Z-Score mean reversion ({mi.zscore:+.2f}σ) ✓")
    if mi.zscore_signal in ("OVERBOUGHT","EXTREME OVERBOUGHT") and not is_bull:
        r.append(f"Z-Score mean reversion ({mi.zscore:+.2f}σ) ✓")
    if mi.ttm_squeeze_active:    r.append("TTM Squeeze breakout energy ✓")
    if "ABOVE VWAP" in mi.vwap_signal and is_bull:  r.append("Price above VWAP ✓")
    if "BELOW VWAP" in mi.vwap_signal and not is_bull: r.append("Price below VWAP ✓")
    if mi.order_blocks:          r.append(f"{len(mi.order_blocks)} Order Block(s) near price ✓")
    if mi.liquidity_sweeps:      r.append("Liquidity sweep confirmation ✓")
    if mi.fib_zone in ("STRONG_SUPPORT","STRONG_RESISTANCE"): r.append(f"Fibonacci golden zone ✓")
    if mi.mtf_confluence and "STRONG" in mi.mtf_confluence:   r.append(f"MTF: {mi.mtf_confluence} ✓")
    reasoning = " | ".join(r) if r else "Multiple indicators aligned — no single dominant reason."
    invalidation = (f"Bearish close below SL ${sl:,.4f} invalidates bull thesis." if is_bull else
                    f"Bullish close above SL ${sl:,.4f} invalidates bear thesis.")

    # Position sizing hint
    position_size_note = (
        f"Enter Account data in sidebar for precise lot sizing. "
        f"Risk ${risk:,.4f} per unit ({round(risk/cfg.pip_size)} pips)."
    )

    return {
        "valid":          True,
        "direction":      mi.direction,
        "entry":          round(cur,   4),
        "sl":             round(sl,    4),
        "tp1":            round(tp1,   4),
        "tp2":            round(tp2,   4),
        "tp3":            round(tp3,   4),
        "risk_per_unit":  round(risk,  4),
        "risk_pips":      round(risk / cfg.pip_size, 1),
        "rr1":            rr1,
        "rr2":            rr2,
        "confidence":     round(raw,   1),
        "quality":        quality,
        "reasoning":      reasoning,
        "invalidation":   invalidation,
        "session":        mi.trading_session,
        "regime":         mi.regime_advanced,
        "news_risk":      "HIGH" if mi.news_lock_active else "NORMAL",
        "prob_score":     mi.probability_bull,
        "mtf":            mi.mtf_confluence,
        "position_note":  position_size_note,
    }

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 8 — CORRELATION ENGINE (v11)
# ══════════════════════════════════════════════════════════════════════════════

def get_correlation_matrix() -> Dict[str, Dict[str, float]]:
    """
    30-day daily return correlation across all 5 assets.
    Returns nested dict: corr[sym1][sym2] = float.
    """
    try:
        import yfinance as yf
        import pandas as pd

        tickers = {cfg.symbol: cfg.yf_ticker for cfg in ALL_ASSETS}
        data: Dict[str, Any] = {}
        for sym, ticker in tickers.items():
            df = yf.download(ticker, period="30d", interval="1d",
                             progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                col = df["Close"]
                if isinstance(col, pd.DataFrame): col = col.iloc[:,0]
                data[sym] = col.pct_change().dropna()

        if len(data) < 2:
            return {}
        df_c = pd.DataFrame(data).corr()
        return {
            sym1: {sym2: round(float(df_c.loc[sym1, sym2]), 3)
                   for sym2 in df_c.columns if sym2 in df_c.index}
            for sym1 in df_c.index
        }
    except Exception:
        return {}

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 9 — MASTER ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

def run_analysis(cfg: AssetConfig,
                 atr_mult: float = 1.5,
                 rr_ratio: float = 2.5,
                 run_mtf:  bool  = False
                 ) -> Tuple[Optional[MarketIntelligence], List[NewsItem], str]:
    """
    Orchestrates: price fetch → news fetch → analysis → trade plan.
    Returns (MarketIntelligence | None, [NewsItem], data_source_string)
    """
    prices, source, ohlcv = PriceFeed.get(cfg)
    news_items, calendar  = NewsEngine.fetch(cfg)

    mi = MathEngine.analyze(
        prices        = prices,
        cfg           = cfg,
        atr_mult      = atr_mult,
        rr_ratio      = rr_ratio,
        news_schedule = calendar,
        ohlcv         = ohlcv,
    )

    if mi:
        mi.data_source = source
        # Macro sentiment
        score, label, bull_h, bear_h = NewsEngine.calc_macro_sentiment(news_items)
        mi.macro_sentiment_score = score
        mi.macro_sentiment_label = label
        mi.macro_bull_hits       = bull_h
        mi.macro_bear_hits       = bear_h

        # Multi-timeframe (optional — heavier, use only when needed)
        if run_mtf:
            mi.mtf_signals, mi.mtf_confluence, mi.mtf_bull_count, mi.mtf_bear_count = \
                MathEngine._calc_mtf(cfg)
        else:
            mi.mtf_signals    = {}
            mi.mtf_confluence = "NOT LOADED — enable in settings"
            mi.mtf_bull_count = 0
            mi.mtf_bear_count = 0

        # Trade Plan
        mi.trade_plan = generate_trade_plan(mi, cfg)

    return mi, news_items, source


# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 10 — DUAL-FREQUENCY DEEP QUANTUM DECISION (120s)
# ══════════════════════════════════════════════════════════════════════════════

@dataclass
class DeepQuantumDecision:
    symbol: str
    decision: str                 # BUY | SELL | HOLD
    ts_epoch: float               # when computed
    next_epoch: float             # next decision time
    price: float
    source: str
    rsi_14: float
    vol_pct: float                # std of returns in percent
    trend_slope_pct: float        # per-bar slope as percent of price
    trend_strength: float         # slope / vol (dimensionless)


def _rsi_14(prices: np.ndarray) -> float:
    """Classic RSI(14) computed from close series."""
    if prices is None or len(prices) < 16:
        return 50.0
    delta = np.diff(prices)
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)
    n = 14
    avg_g = np.mean(gain[-n:]) if len(gain) >= n else np.mean(gain)
    avg_l = np.mean(loss[-n:]) if len(loss) >= n else np.mean(loss)
    if avg_l <= 1e-12:
        return 100.0 if avg_g > 0 else 50.0
    rs = avg_g / avg_l
    return float(100.0 - (100.0 / (1.0 + rs)))


def _trend_slope(prices: np.ndarray, lookback: int = 60) -> float:
    """
    Linear regression slope on last N bars.
    Returns slope in 'price units per bar'.
    """
    if prices is None or len(prices) < max(lookback, 10):
        return 0.0
    y = prices[-lookback:]
    x = np.arange(len(y), dtype=float)
    x = x - np.mean(x)
    y0 = y - np.mean(y)
    den = float(np.dot(x, x)) + 1e-12
    return float(np.dot(x, y0) / den)


def deep_quantum_decision(cfg: AssetConfig,
                          bars: int = 240) -> DeepQuantumDecision:
    """
    Heavy decision logic intended to run on a 120s cadence in the UI layer.
    Uses volatility + trend strength to output BUY/SELL/HOLD.
    """
    prices, src = PriceFeed.get_fast_series(cfg, bars=bars)
    p = np.asarray(prices, dtype=float)
    price = float(p[-1]) if len(p) else 0.0

    # Volatility (std of percent returns)
    rets = np.diff(p) / (p[:-1] + 1e-12) * 100.0 if len(p) >= 3 else np.array([0.0])
    vol = float(np.std(rets[-120:])) if len(rets) else 0.0

    # Trend strength (slope normalized by volatility)
    slope = _trend_slope(p, lookback=min(60, max(10, len(p) // 3)))
    slope_pct = (slope / (price + 1e-12)) * 100.0
    strength = abs(slope_pct) / (vol + 1e-9)

    rsi = _rsi_14(p)

    # Decision thresholds: trend must be meaningful vs volatility.
    # Keep conservative defaults to avoid flip-flopping on noise.
    decision = "HOLD"
    if strength >= 1.35:
        if slope_pct > 0 and rsi <= 72:
            decision = "BUY"
        elif slope_pct < 0 and rsi >= 28:
            decision = "SELL"

    now = time.time()
    return DeepQuantumDecision(
        symbol=cfg.symbol,
        decision=decision,
        ts_epoch=now,
        next_epoch=now + 120.0,
        price=price,
        source=src,
        rsi_14=round(float(rsi), 2),
        vol_pct=round(float(vol), 3),
        trend_slope_pct=round(float(slope_pct), 4),
        trend_strength=round(float(strength), 3),
    )