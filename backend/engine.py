# ============================================================================
#  NEXUS v13.11 — QUANTUM INSTITUTIONAL ENGINE (engine.py)
#  ✅ ALL INDICATOR FORMULAS PRESERVED (only safety guards added, no maths changed)
#  ✅ STRICT TIMEFRAME INTEGRITY: M1/M5/M15 data is NEVER substituted with daily data
#  ✅ SANITIZED OHLCV: every fetcher returns row-aligned, finite, positive Python floats
#  ✅ NaN/Inf-SAFE MathEngine + JSON-safe MarketIntelligence output
#  ✅ GRACEFUL DEGRADATION: insufficient data -> NEUTRAL / "WAIT" / "INSUFFICIENT DATA"
#
#  Every change is tagged in the comments as  FIX[n]:
#    FIX[1] strict timeframe integrity        FIX[2] OHLCV sanitization
#    FIX[3] MathEngine NaN / short-array      FIX[4] graceful degradation
#    FIX[5] dangerous / redundant fallbacks removed
# ============================================================================

import math
import os
import time
import logging
import requests
import json
import asyncio
import threading
import warnings
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, fields, is_dataclass
from typing import Optional, Tuple, List, Dict, Any
from datetime import datetime, timezone, timedelta
from enum import Enum

import numpy as np
from scipy.stats import kurtosis as sp_kurtosis, skew as sp_skew
from scipy.signal import argrelextrema

# ── Suppress benign warnings ──────────────
warnings.filterwarnings('ignore', category=UserWarning, module='yfinance')
warnings.filterwarnings('ignore', message='possibly delisted')
warnings.filterwarnings('ignore', message='.*delisted.*')
logging.getLogger('yfinance').setLevel(logging.CRITICAL)

logger = logging.getLogger("NEXUS-ENGINE")

# Minimum number of VALID candles required before ANY analysis is attempted.
MIN_BARS = 60
# The multi-layer confluence engine needs more history than the basic indicators.
MULTILAYER_MIN_BARS = 100
INSUFFICIENT_DATA = "INSUFFICIENT DATA"

# ============================================
# SECTION 0 — SMART CACHE & LIVE RAM
# ============================================

class SmartCache:
    # FIX[2]: the store holds arbitrary objects (floats, dicts, tuples); typed as Any.
    _store: Dict[str, Tuple[Any, float, str]] = {}
    # FIX[2]: price feed runs in a ThreadPoolExecutor -> protect the shared dict.
    _lock = threading.RLock()

    @staticmethod
    def get(key: str, ttl: float) -> Optional[Tuple[float, str]]:
        """Returns (value, source) for scalar entries stored with set()."""
        with SmartCache._lock:
            item = SmartCache._store.get(key)
            if item and (time.time() - item[1]) < ttl:
                return item[0], item[2]
        return None

    @staticmethod
    def set(key: str, value: float, source: str):
        with SmartCache._lock:
            SmartCache._store[key] = (value, time.time(), source)
            if len(SmartCache._store) > 500:
                SmartCache._store.clear()

    @staticmethod
    def get_obj(key: str, ttl: float) -> Optional[Any]:
        """FIX[2]: returns the stored OBJECT only (no tuple-wrapping confusion)."""
        with SmartCache._lock:
            item = SmartCache._store.get(key)
            if item and (time.time() - item[1]) < ttl:
                return item[0]
        return None

    @staticmethod
    def set_obj(key: str, obj: Any, source: str = "Cache"):
        with SmartCache._lock:
            SmartCache._store[key] = (obj, time.time(), source)
            if len(SmartCache._store) > 500:
                SmartCache._store.clear()


LIVE_PRICES: Dict[str, float] = {}
LIVE_PRICE_TS: Dict[str, float] = {}      # FIX[5]: timestamp of each live tick
LIVE_PRICE_MAX_AGE = 30.0                 # FIX[5]: ignore WS prices older than 30s (stale after disconnect)

# FIX[1]: single source of truth for timeframes.
#   "yf"       = (period, interval) that Yahoo can serve NATIVELY for that timeframe
#   "resample" = optional pandas rule used to AGGREGATE same-or-finer data (e.g. 1h -> 4h).
#                Aggregating finer candles into a coarser one is legitimate;
#                substituting a COARSER timeframe for a finer one is not.
TF_MAP = {
    "M1":  {"ccxt": "1m",  "yf": ("5d",  "1m"),  "resample": None},
    "M5":  {"ccxt": "5m",  "yf": ("5d",  "5m"),  "resample": None},
    "M15": {"ccxt": "15m", "yf": ("5d",  "15m"), "resample": None},
    "H1":  {"ccxt": "1h",  "yf": ("1mo", "1h"),  "resample": None},
    "H4":  {"ccxt": "4h",  "yf": ("3mo", "1h"),  "resample": "4h"},
    "D1":  {"ccxt": "1d",  "yf": ("1y",  "1d"),  "resample": None},
}

# ============================================
# SECTION 1 & 2 — ENUMS & DATA STRUCTURES (UNCHANGED)
# ============================================

class MarketRegime(Enum):
    STRONG_UPTREND = "strong_uptrend"; WEAK_UPTREND = "weak_uptrend"
    STRONG_DOWNTREND = "strong_downtrend"; WEAK_DOWNTREND = "weak_downtrend"
    RANGING_BULLISH = "ranging_bullish"; RANGING_BEARISH = "ranging_bearish"
    HIGH_VOLATILITY = "high_volatility"; LOW_VOLATILITY = "low_volatility"
    MEAN_REVERTING = "mean_reverting"; CHOPPY = "choppy"; CRISIS_VOLATILITY = "crisis_volatility"

class SignalDirection(Enum):
    STRONG_BUY = "strong_buy"; BUY = "buy"; WEAK_BUY = "weak_buy"
    NEUTRAL = "neutral"; WEAK_SELL = "weak_sell"; SELL = "sell"; STRONG_SELL = "strong_sell"

@dataclass
class AssetConfig:
    name: str; symbol: str; yf_ticker: str; ccxt_symbol: Optional[str]
    asset_type: str; pip_size: float; pip_value_per_lot: float; contract_size: float
    price_lo: float; price_hi: float; is_24_7: bool; color: str; emoji: str
    tick_size: float = 0.01; tick_value: float = 1.0; min_lot: float = 0.01
    max_lot: float = 100.0; lot_step: float = 0.01; leverage: int = 100
    spread_pips: float = 2.0; oanda_symbol: Optional[str] = None

@dataclass
class InstrumentSpec:
    symbol: str; contract_size: float; tick_size: float; tick_value: float
    pip_size: float; min_lot: float; max_lot: float; lot_step: float
    leverage: int; spread_pips: float = 2.0

@dataclass
class MonteCarloStats:
    expected_final_balance: float; var_95: float; var_99: float
    expected_max_drawdown: float; probability_of_ruin: float; simulations_run: int = 1000

@dataclass
class VolumeProfileStats:
    poc_price: float; value_area_high: float; value_area_low: float
    bullish_order_block: Optional[float] = None; bearish_order_block: Optional[float] = None

@dataclass
class MTFAnalysis:
    confluence: str; weight: float; daily_bias: str; h4_setup: str; h1_entry: str

@dataclass
class SignalRecord:
    timestamp: str; symbol: str; timeframe: str; direction: str; entry: float
    sl: float; tp1: float; tp2: float; confidence: float; regime: str
    outcome: str = "PENDING"; mfe: float = 0.0; mae: float = 0.0

@dataclass
class MarketIntelligence:
    asset_name: str = ""; asset_type: str = ""; last_update: str = ""; data_source: str = ""
    current_price: float = 0.0; price_change: float = 0.0; price_change_pct: float = 0.0
    prices: List[float] = field(default_factory=list); safety_signal: str = "WAIT"
    signal_color: str = "#FFD600"; signal_strength: int = 0; direction: str = "NEUTRAL"
    bull_score: int = 0; bear_score: int = 0; entry_quality: str = "POOR"; entry_explanation: str = ""
    signal_confidence: float = 50.0; confidence_label: str = "NEUTRAL"; signal_reasons: List[str] = field(default_factory=list)
    probability_bull: float = 50.0; probability_label: str = "NEUTRAL"
    ema9: float = 0.0; ema21: float = 0.0; ema50: float = 0.0; ema200: float = 0.0; ema_alignment: str = "NEUTRAL"
    rsi: float = 50.0; rsi_signal: str = "NEUTRAL"; rsi_explanation: str = ""
    macd_line: float = 0.0; macd_signal: float = 0.0; macd_hist: float = 0.0; macd_cross: str = "NEUTRAL"
    stoch_k: float = 50.0; stoch_d: float = 50.0; stoch_signal: str = "NEUTRAL"
    bb_upper: float = 0.0; bb_mid: float = 0.0; bb_lower: float = 0.0; bb_width: float = 0.0; bb_position: str = "MIDDLE"; bb_squeeze: bool = False
    kc_upper: float = 0.0; kc_mid: float = 0.0; kc_lower: float = 0.0
    ttm_squeeze_active: bool = False; ttm_squeeze_label: str = "SQUEEZE OFF"; ttm_momentum: float = 0.0
    supertrend_value: float = 0.0; supertrend_signal: str = "NEUTRAL"; supertrend_direction: str = "NEUTRAL"
    vwap: float = 0.0; vwap_upper: float = 0.0; vwap_lower: float = 0.0; vwap_signal: str = "NEUTRAL"
    pivot_points: Dict[str, float] = field(default_factory=dict); nearest_pivot_level: str = ""; nearest_pivot_dist: float = 0.0
    zscore: float = 0.0; zscore_signal: str = "NEUTRAL"
    adx_value: float = 0.0; adx_signal: str = "WEAK"; adx_di_plus: float = 0.0; adx_di_minus: float = 0.0
    williams_r: float = -50.0; williams_signal: str = "NEUTRAL"
    cci_value: float = 0.0; cci_signal: str = "NEUTRAL"
    obv_trend: str = "NEUTRAL"; obv_value: float = 0.0
    ichimoku_signal: str = "NEUTRAL"; tenkan: float = 0.0; kijun: float = 0.0
    atr_14: float = 0.0; sl_buy: Optional[float] = None; sl_sell: Optional[float] = None; tp_buy: Optional[float] = None; tp_sell: Optional[float] = None
    sl_pips: float = 0.0; atr_explanation: str = ""; atr_multiplier: float = 1.5; rr_ratio: float = 2.5
    hurst: float = 0.5; regime: str = "RANDOM"; regime_advanced: str = "CHOPPY"
    shannon_entropy: float = 0.0; kaufman_er: float = 0.0; fractal_dim: float = 1.5
    realized_vol: float = 0.0; vol_regime: str = "NORMAL"; kurtosis: float = 0.0; skewness: float = 0.0
    tail_risk: str = "NORMAL"; autocorr_lag1: float = 0.0; stability_index: int = 50
    supports: List[float] = field(default_factory=list); resistances: List[float] = field(default_factory=list)
    nearest_support: float = 0.0; nearest_resist: float = 0.0; sr_zone: str = "MIDDLE"
    wave_position: str = "UNKNOWN"; wave_confidence: float = 0.0; wave_target: Optional[float] = None; wave_trend: str = "NEUTRAL"
    fib_retracements: Dict[str, float] = field(default_factory=dict); fib_extensions: Dict[str, float] = field(default_factory=dict)
    fib_zone: str = "NEUTRAL"; fib_strength: float = 0.0; fib_explanation: str = ""
    order_blocks: List[Dict] = field(default_factory=list); fair_value_gaps: List[Dict] = field(default_factory=list); liquidity_sweeps: List[Dict] = field(default_factory=list)
    smc_bias: str = "NEUTRAL"; smc_explanation: str = ""
    rsi_divergence: str = "NONE"; macd_divergence: str = "NONE"; obv_divergence: str = "NEUTRAL"; divergence_signal: str = "NONE"; divergence_strength: float = 0.0
    candle_pattern: str = "NONE"; candle_strength: float = 0.0; candle_direction: str = "NEUTRAL"; candle_explanation: str = ""
    kelly_fraction: float = 0.0; kelly_recommendation: str = ""
    trading_session: str = "OFF-HOURS"; session_liquidity: str = "LOW"; session_warning: str = ""; session_explanation: str = ""
    news_lock_active: bool = False; news_lock_event: str = ""; news_lock_reason: str = ""
    upcoming_news: List[Dict] = field(default_factory=list)
    macro_sentiment_score: int = 50; macro_sentiment_label: str = "NEUTRAL"; macro_bull_hits: int = 0; macro_bear_hits: int = 0
    mtf_signals: Dict[str, Dict] = field(default_factory=dict); mtf_confluence: str = "NEUTRAL"; mtf_bull_count: int = 0; mtf_bear_count: int = 0
    trade_plan: Dict = field(default_factory=dict)
    risk_dollars: float = 0.0; recommended_lots: float = 0.0; lot_explanation: str = ""; required_margin: float = 0.0
    monte_carlo: Optional[MonteCarloStats] = None; volume_profile: Optional[VolumeProfileStats] = None; mtf_analysis: Optional[MTFAnalysis] = None
    layer_scores: Dict[str, float] = field(default_factory=dict); confluence_bull_layers: int = 0; confluence_bear_layers: int = 0
    volatility_percentile: float = 50.0; estimated_win_rate: float = 0.50; timeframe: str = "M5"

@dataclass
class NewsItem:
    title: str; source: str; published: str; url: str; category: str
    nexus_comment: str; quant_action: str; sentiment_score: float = 0.0
    affected_assets: List[str] = field(default_factory=list)

# ============================================
# SECTION 3 — ASSET CONFIGURATIONS (UNCHANGED)
# ============================================

GOLD_CFG = AssetConfig(name="GOLD (XAU/USD)", symbol="XAUUSD", yf_ticker="GC=F", ccxt_symbol=None, asset_type="commodity", pip_size=0.01, pip_value_per_lot=10.0, contract_size=100, price_lo=1000.0, price_hi=9000.0, is_24_7=False, color="#D4AF37", emoji="⚡", tick_size=0.01, tick_value=1.0, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=3.0, oanda_symbol="XAU_USD")
SILVER_CFG = AssetConfig(name="SILVER (XAG/USD)", symbol="XAGUSD", yf_ticker="SI=F", ccxt_symbol=None, asset_type="commodity", pip_size=0.01, pip_value_per_lot=50.0, contract_size=5000, price_lo=10.0, price_hi=100.0, is_24_7=False, color="#C0C0C0", emoji="🥈", tick_size=0.001, tick_value=50.0, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=3.5, oanda_symbol="XAG_USD")
BTC_CFG = AssetConfig(name="BITCOIN (BTC/USD)", symbol="BTCUSD", yf_ticker="BTC-USD", ccxt_symbol="BTC/USDT", asset_type="crypto", pip_size=0.10, pip_value_per_lot=0.10, contract_size=1.0, price_lo=5000.0, price_hi=500000.0, is_24_7=True, color="#F7931A", emoji="₿", tick_size=0.01, tick_value=1.0, min_lot=0.001, max_lot=10.0, lot_step=0.001, leverage=20, spread_pips=50.0, oanda_symbol="BTC_USD")
ETH_CFG = AssetConfig(name="ETHEREUM (ETH/USD)", symbol="ETHUSD", yf_ticker="ETH-USD", ccxt_symbol="ETH/USDT", asset_type="crypto", pip_size=0.01, pip_value_per_lot=0.01, contract_size=1.0, price_lo=50.0, price_hi=50000.0, is_24_7=True, color="#627EEA", emoji="Ξ", tick_size=0.01, tick_value=1.0, min_lot=0.01, max_lot=50.0, lot_step=0.01, leverage=20, spread_pips=40.0, oanda_symbol="ETH_USD")
SOL_CFG = AssetConfig(name="SOLANA (SOL/USD)", symbol="SOLUSD", yf_ticker="SOL-USD", ccxt_symbol="SOL/USDT", asset_type="crypto", pip_size=0.01, pip_value_per_lot=0.01, contract_size=1.0, price_lo=5.0, price_hi=2000.0, is_24_7=True, color="#9945FF", emoji="💜", tick_size=0.01, tick_value=1.0, min_lot=0.1, max_lot=100.0, lot_step=0.1, leverage=20, spread_pips=30.0, oanda_symbol=None)
SPX_CFG = AssetConfig(name="S&P 500", symbol="SPX500", yf_ticker="^GSPC", ccxt_symbol=None, asset_type="index", pip_size=0.01, pip_value_per_lot=10.0, contract_size=50, price_lo=500.0, price_hi=15000.0, is_24_7=False, color="#00BCD4", emoji="📊", tick_size=0.01, tick_value=5.0, min_lot=0.01, max_lot=10.0, lot_step=0.01, leverage=50, spread_pips=1.0, oanda_symbol="SPX500_USD")
NAS_CFG = AssetConfig(name="NASDAQ 100", symbol="NAS100", yf_ticker="^NDX", ccxt_symbol=None, asset_type="index", pip_size=0.01, pip_value_per_lot=20.0, contract_size=10, price_lo=1000.0, price_hi=50000.0, is_24_7=False, color="#7C3AED", emoji="🚀", tick_size=0.01, tick_value=2.0, min_lot=0.01, max_lot=10.0, lot_step=0.01, leverage=50, spread_pips=1.5, oanda_symbol="NAS100_USD")
EURUSD_CFG = AssetConfig(name="EUR/USD", symbol="EURUSD", yf_ticker="EURUSD=X", ccxt_symbol=None, asset_type="forex", pip_size=0.0001, pip_value_per_lot=10.0, contract_size=100000, price_lo=0.50, price_hi=2.50, is_24_7=False, color="#4CAF50", emoji="💱", tick_size=0.00001, tick_value=1.0, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=1.5, oanda_symbol="EUR_USD")
GBPUSD_CFG = AssetConfig(name="GBP/USD", symbol="GBPUSD", yf_ticker="GBPUSD=X", ccxt_symbol=None, asset_type="forex", pip_size=0.0001, pip_value_per_lot=10.0, contract_size=100000, price_lo=0.80, price_hi=2.50, is_24_7=False, color="#E91E63", emoji="💷", tick_size=0.00001, tick_value=1.0, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=2.0, oanda_symbol="GBP_USD")
USDJPY_CFG = AssetConfig(name="USD/JPY", symbol="USDJPY", yf_ticker="JPY=X", ccxt_symbol=None, asset_type="forex", pip_size=0.01, pip_value_per_lot=9.0, contract_size=100000, price_lo=80.0, price_hi=200.0, is_24_7=False, color="#FF5722", emoji="💴", tick_size=0.001, tick_value=0.9, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=1.8, oanda_symbol="USD_JPY")

ALL_ASSETS: List[AssetConfig] = [GOLD_CFG, SILVER_CFG, BTC_CFG, ETH_CFG, SOL_CFG, SPX_CFG, NAS_CFG, EURUSD_CFG, GBPUSD_CFG, USDJPY_CFG]
ASSET_MAP: Dict[str, AssetConfig] = {a.symbol: a for a in ALL_ASSETS}

INSTRUMENT_SPECS: Dict[str, InstrumentSpec] = {
    "XAUUSD": InstrumentSpec(symbol="XAUUSD", contract_size=100, tick_size=0.01, tick_value=1.0, pip_size=0.01, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=3.0),
    "XAGUSD": InstrumentSpec(symbol="XAGUSD", contract_size=5000, tick_size=0.001, tick_value=50.0, pip_size=0.01, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=3.5),
    "BTCUSD": InstrumentSpec(symbol="BTCUSD", contract_size=1, tick_size=0.01, tick_value=1.0, pip_size=1.0, min_lot=0.001, max_lot=10.0, lot_step=0.001, leverage=20, spread_pips=50.0),
    "ETHUSD": InstrumentSpec(symbol="ETHUSD", contract_size=1, tick_size=0.01, tick_value=1.0, pip_size=0.01, min_lot=0.01, max_lot=50.0, lot_step=0.01, leverage=20, spread_pips=40.0),
    "SOLUSD": InstrumentSpec(symbol="SOLUSD", contract_size=1, tick_size=0.01, tick_value=1.0, pip_size=0.01, min_lot=0.1, max_lot=100.0, lot_step=0.1, leverage=20, spread_pips=30.0),
    "SPX500": InstrumentSpec(symbol="SPX500", contract_size=50, tick_size=0.01, tick_value=5.0, pip_size=0.01, min_lot=0.01, max_lot=10.0, lot_step=0.01, leverage=50, spread_pips=1.0),
    "NAS100": InstrumentSpec(symbol="NAS100", contract_size=10, tick_size=0.01, tick_value=2.0, pip_size=0.01, min_lot=0.01, max_lot=10.0, lot_step=0.01, leverage=50, spread_pips=1.5),
    "EURUSD": InstrumentSpec(symbol="EURUSD", contract_size=100000, tick_size=0.00001, tick_value=1.0, pip_size=0.0001, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=1.5),
    "GBPUSD": InstrumentSpec(symbol="GBPUSD", contract_size=100000, tick_size=0.00001, tick_value=1.0, pip_size=0.0001, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=2.0),
    "USDJPY": InstrumentSpec(symbol="USDJPY", contract_size=100000, tick_size=0.001, tick_value=0.9, pip_size=0.01, min_lot=0.01, max_lot=100.0, lot_step=0.01, leverage=100, spread_pips=1.8),
}

# ============================================
# SECTION 4 — SAFETY HELPERS (NEW)
# ============================================

def _clean_value(v: Any) -> Any:
    """
    FIX[3]: Recursively converts a value into plain, JSON-safe Python types.
      - NaN / +-Inf floats  -> 0.0   (FastAPI/Starlette JSON encoding REJECTS NaN)
      - numpy scalars/arrays -> int / float / bool / list
      - dataclass instances  -> cleaned IN PLACE (MonteCarloStats, MarketIntelligence, ...)
    """
    if v is None or isinstance(v, str):
        return v
    if isinstance(v, (bool, np.bool_)):          # bool BEFORE int (bool is an int subclass)
        return bool(v)
    if isinstance(v, (int, np.integer)):
        return int(v)
    if isinstance(v, (float, np.floating)):
        f = float(v)
        return f if math.isfinite(f) else 0.0
    if isinstance(v, np.ndarray):
        return [_clean_value(x) for x in v.tolist()]
    if isinstance(v, dict):
        return {str(k): _clean_value(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_clean_value(x) for x in v]
    if is_dataclass(v) and not isinstance(v, type):
        for fld in fields(v):
            setattr(v, fld.name, _clean_value(getattr(v, fld.name)))
        return v
    return v


def _safe_mi(cfg: Optional[AssetConfig], timeframe: str, reason: str) -> "MarketIntelligence":
    """
    FIX[4]: A fully-populated, harmless MarketIntelligence used whenever data is missing
    or an internal error occurs. The UI shows "WAIT" instead of a false signal or a crash.
    """
    mi = MarketIntelligence()
    if cfg is not None:
        mi.asset_name, mi.asset_type = cfg.name, cfg.asset_type
    mi.last_update = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    mi.timeframe = timeframe
    mi.data_source = INSUFFICIENT_DATA
    mi.direction = "NEUTRAL"
    mi.safety_signal = "WAIT"
    mi.signal_color = "#666666"
    mi.signal_strength = 0
    mi.signal_confidence = 0.0
    mi.confidence_label = "NEUTRAL"
    mi.entry_quality = "POOR"
    mi.entry_explanation = reason
    mi.signal_reasons = [reason]
    mi.trade_plan = {"valid": False, "direction": "NEUTRAL", "directionRaw": "NEUTRAL",
                     "confidence": 0.0, "quality": "POOR", "reasoning": reason,
                     "newsRisk": "NORMAL", "mtf": "NEUTRAL"}
    return mi


def sanitize_ohlcv(raw: Optional[Dict[str, Any]], min_bars: int = MIN_BARS, max_bars: int = 300) -> Optional[Dict[str, List[float]]]:
    """
    FIX[2]: The ONE gate every data source must pass through.

    Guarantees on the returned dict (or None if it cannot be guaranteed):
      * keys open/high/low/close/volume, all plain Python `float` lists
      * all five lists have IDENTICAL length and are row-aligned
        (the old code did dropna() per column, which silently shifted columns apart)
      * no None / NaN / Inf, no non-positive O/H/L/C
      * high >= max(o,c,l) and low <= min(o,c,h)
      * volume is > 0 (missing/zero volume -> 1.0, same convention as before)
      * at least `min_bars` valid candles remain, otherwise None
    """
    try:
        if not raw:
            return None
        keys = ("open", "high", "low", "close", "volume")
        if any(k not in raw or raw[k] is None for k in keys):
            return None
        n = min(len(raw[k]) for k in keys)
        if n < min_bars:
            return None

        def _col(k: str) -> np.ndarray:
            out = np.empty(n, dtype=float)
            for i, x in enumerate(list(raw[k])[-n:]):
                try:
                    out[i] = float(x)
                except (TypeError, ValueError):
                    out[i] = np.nan
            return out

        o, h, l, c, v = (_col(k) for k in keys)
        ok = (np.isfinite(o) & np.isfinite(h) & np.isfinite(l) & np.isfinite(c)
              & (o > 0) & (h > 0) & (l > 0) & (c > 0))
        v = np.where(np.isfinite(v) & (v > 0), v, 1.0)
        o, h, l, c, v = o[ok], h[ok], l[ok], c[ok], v[ok]
        if len(c) < min_bars:
            return None
        h2 = np.maximum.reduce([o, h, l, c])
        l2 = np.minimum.reduce([o, h, l, c])
        return {"open": o[-max_bars:].tolist(), "high": h2[-max_bars:].tolist(),
                "low": l2[-max_bars:].tolist(), "close": c[-max_bars:].tolist(),
                "volume": v[-max_bars:].tolist()}
    except Exception as e:
        logger.debug(f"sanitize_ohlcv failed: {e}")
        return None

# ============================================
# SECTION 5 — STRICT-TIMEFRAME PRICE FEED
# ============================================

class PriceFeed:
    BARS = 300
    OHLCV_TTL = 120.0
    LATEST_TTL = 60.0
    NEWS_TTL = 300.0

    _exchanges: Dict[str, Any] = {}
    _ex_lock = threading.Lock()

    # ── CCXT ────────────────────────────────────────────────────────────
    @staticmethod
    def _get_exchange(ex_id: str):
        """FIX[2]: exchange objects are cached (building one per call is slow and rate-limit hostile)."""
        with PriceFeed._ex_lock:
            ex = PriceFeed._exchanges.get(ex_id)
            if ex is not None:
                return ex
            try:
                import ccxt
                opts: Dict[str, Any] = {"enableRateLimit": True, "timeout": 10000}
                if ex_id == "binance":
                    opts["options"] = {"defaultType": "spot"}
                ex = getattr(ccxt, ex_id)(opts)
                PriceFeed._exchanges[ex_id] = ex
                return ex
            except Exception as e:
                logger.debug(f"ccxt exchange {ex_id} unavailable: {e}")
                return None

    @staticmethod
    def _ccxt_candidates(cfg: AssetConfig) -> List[Tuple[str, str]]:
        """
        Ordered (exchange, symbol) pairs. For crypto, Kraken is a SAME-TIMEFRAME backup for
        Binance (e.g. when Binance geo-blocks you). Falling back between exchanges keeps the
        candle size identical, so it is safe — unlike falling back to daily candles.
        """
        if cfg.asset_type == "crypto" and cfg.ccxt_symbol:
            base = cfg.ccxt_symbol.split("/")[0]
            return [("binance", f"{base}/USDT"), ("kraken", f"{base}/USD")]
        if cfg.asset_type == "forex":
            return [("kraken", f"{cfg.symbol[:3]}/{cfg.symbol[3:]}")]
        return []

    @staticmethod
    def _from_ccxt_latest(cfg: AssetConfig) -> Optional[Tuple[float, str]]:
        for ex_id, sym in PriceFeed._ccxt_candidates(cfg):
            try:
                ex = PriceFeed._get_exchange(ex_id)
                if not ex:
                    continue
                ticker = ex.fetch_ticker(sym)
                price = float(ticker.get("last") or ticker.get("close") or 0.0)
                if math.isfinite(price) and price > 0:
                    return price, f"{ex_id.capitalize()} (CCXT)"
            except Exception:
                continue
        return None

    @staticmethod
    def _from_ccxt_ohlcv(cfg: AssetConfig, timeframe: str) -> Optional[Tuple[Dict[str, List[float]], str]]:
        """Returns (sanitized_ohlcv, source) for EXACTLY the requested timeframe, else None."""
        tf = TF_MAP.get(timeframe)
        if tf is None:
            return None
        for ex_id, sym in PriceFeed._ccxt_candidates(cfg):
            try:
                ex = PriceFeed._get_exchange(ex_id)
                if not ex:
                    continue
                raw = ex.fetch_ohlcv(sym, timeframe=tf["ccxt"], limit=PriceFeed.BARS)
                if not raw:
                    continue
                clean = sanitize_ohlcv({
                    "open":   [b[1] for b in raw], "high":   [b[2] for b in raw],
                    "low":    [b[3] for b in raw], "close":  [b[4] for b in raw],
                    "volume": [b[5] for b in raw],
                })
                if clean:
                    return clean, f"{ex_id.capitalize()} (CCXT)"
            except Exception:
                continue
        return None

    # ── CoinGecko (latest PRICE only — never used for candles) ───────────
    @staticmethod
    def _from_coingecko_latest(cfg: AssetConfig) -> Optional[float]:
        """Free backup for crypto spot price if Binance/Kraken are unreachable."""
        if cfg.asset_type != "crypto":
            return None
        coin_map = {"BTCUSD": "bitcoin", "ETHUSD": "ethereum", "SOLUSD": "solana"}
        coin_id = coin_map.get(cfg.symbol)
        if not coin_id:
            return None
        try:
            url = f"https://api.coingecko.com/api/v3/simple/price?ids={coin_id}&vs_currencies=usd"
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if coin_id in data and "usd" in data[coin_id]:
                    return float(data[coin_id]["usd"])
            return None
        except Exception:
            return None

    # ── Yahoo Finance ────────────────────────────────────────────────────
    @staticmethod
    def _from_yfinance_latest(ticker: str) -> Optional[float]:
        """Latest PRICE only (a daily close is fine as a 'last price'; it is never used for candles)."""
        ck = f"yfp:{ticker}"
        hit = SmartCache.get(ck, PriceFeed.LATEST_TTL)
        if hit:
            return float(hit[0])          # FIX[2]: old code returned the (price, source) TUPLE -> TypeError downstream

        try:
            import yfinance as yf
            tickers_to_try = [ticker]
            if ticker == "SI=F": tickers_to_try.append("SILVER=X")
            if ticker == "GC=F": tickers_to_try.append("GOLD=X")

            for t_sym in tickers_to_try:
                try:
                    t = yf.Ticker(t_sym)
                    try:
                        fi = t.fast_info
                        lp = getattr(fi, "last_price", None) if fi is not None else None
                        if lp is not None and math.isfinite(float(lp)) and float(lp) > 0:
                            price = float(lp)
                            SmartCache.set(ck, price, "Yahoo")
                            return price
                    except Exception:
                        pass

                    # FIX[2]: Ticker.history() has no `progress` kwarg -> it raised and skipped this branch.
                    hist = t.history(period="5d", interval="1d", timeout=15)
                    if hist is not None and not hist.empty:
                        price = float(hist["Close"].dropna().iloc[-1])
                        if math.isfinite(price) and price > 0:
                            SmartCache.set(ck, price, "Yahoo")
                            return price
                except Exception:
                    continue
            return None
        except Exception:
            return None

    @staticmethod
    def _from_yfinance_ohlcv(ticker: str, period: str, interval: str,
                             resample: Optional[str] = None) -> Optional[Dict[str, List[float]]]:
        """
        FIX[1]: Fetches EXACTLY (period, interval). The old fallback
                `yf.download(ticker, period="1mo", interval="1d")` is GONE — it fed daily
                candles into M1/M5/M15 analysis. If Yahoo cannot serve the requested
                interval we return None and the UI shows WAIT / NO DATA.
        `resample` only aggregates finer candles into a coarser requested timeframe (1h -> 4h).
        """
        ck = f"yfo:{ticker}:{period}:{interval}:{resample}"
        cached = SmartCache.get_obj(ck, PriceFeed.OHLCV_TTL)
        if cached is not None:
            return cached
        try:
            import yfinance as yf
            df = yf.download(ticker, period=period, interval=interval, progress=False,
                             auto_adjust=True, timeout=15)
            if df is None or df.empty:
                return None

            # Newer yfinance returns MultiIndex columns (Price, Ticker) even for one ticker.
            if getattr(df.columns, "nlevels", 1) > 1:
                df.columns = df.columns.get_level_values(0)

            if resample:
                agg = {"Open": "first", "High": "max", "Low": "min", "Close": "last"}
                if "Volume" in df.columns:
                    agg["Volume"] = "sum"
                df = df.resample(resample).agg(agg).dropna(subset=["Open", "High", "Low", "Close"])
                if df.empty:
                    return None

            for col in ("Open", "High", "Low", "Close"):
                if col not in df.columns:
                    return None
            vol = df["Volume"].tolist() if "Volume" in df.columns else [1.0] * len(df)

            # FIX[2]: row-aligned extraction + sanitization (no per-column dropna misalignment)
            result = sanitize_ohlcv({
                "open": df["Open"].tolist(), "high": df["High"].tolist(),
                "low": df["Low"].tolist(), "close": df["Close"].tolist(), "volume": vol,
            })
            if result:
                SmartCache.set_obj(ck, result, "Yahoo")
            return result
        except Exception:
            return None

    # ── Latest price ─────────────────────────────────────────────────────
    @staticmethod
    def get_latest_price(cfg: AssetConfig) -> Tuple[float, str]:
        cached = SmartCache.get(f"price_{cfg.symbol}", ttl=PriceFeed.LATEST_TTL)
        if cached:
            return cached

        # FIX[5]: WS price is only trusted while it is FRESH (it used to live forever after a disconnect).
        live = LIVE_PRICES.get(cfg.symbol, 0.0)
        if (live > 0 and (time.time() - LIVE_PRICE_TS.get(cfg.symbol, 0.0)) <= LIVE_PRICE_MAX_AGE
                and cfg.price_lo < live < cfg.price_hi):
            SmartCache.set(f"price_{cfg.symbol}", live, "Binance Live WS")
            return live, "Binance Live WS"

        if cfg.asset_type in ("crypto", "forex"):
            got = PriceFeed._from_ccxt_latest(cfg)
            if got and cfg.price_lo < got[0] < cfg.price_hi:
                SmartCache.set(f"price_{cfg.symbol}", got[0], got[1])
                return got

        if cfg.asset_type == "crypto":
            cg_price = PriceFeed._from_coingecko_latest(cfg)
            if cg_price and cfg.price_lo < cg_price < cfg.price_hi:
                SmartCache.set(f"price_{cfg.symbol}", cg_price, "CoinGecko")
                return cg_price, "CoinGecko (Free API)"

        yahoo_price = PriceFeed._from_yfinance_latest(cfg.yf_ticker)
        if yahoo_price and cfg.price_lo < yahoo_price < cfg.price_hi:
            SmartCache.set(f"price_{cfg.symbol}", yahoo_price, "Yahoo Finance")
            return yahoo_price, "Yahoo Finance (Delayed)"

        logger.warning(f"⚠️ NO DATA for {cfg.symbol}")
        return 0.0, "NO DATA"

    @staticmethod
    def get_latest_prices(cfgs: List[AssetConfig]) -> Dict[str, Tuple[float, str]]:
        out: Dict[str, Tuple[float, str]] = {}
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {executor.submit(PriceFeed.get_latest_price, cfg): cfg for cfg in cfgs}
            for future in as_completed(futures):
                cfg = futures[future]
                try:
                    out[cfg.symbol] = future.result(timeout=15)
                except Exception:
                    out[cfg.symbol] = (0.0, "ERROR")
        return out

    # ── Candles ──────────────────────────────────────────────────────────
    @staticmethod
    def get(cfg: AssetConfig, timeframe: str = "M5") -> Tuple[List[float], str, Optional[Dict]]:
        """
        Returns (closes, source, ohlcv) for EXACTLY `timeframe`, or ([], reason, None).

        FIX[1]/FIX[5]: no timeframe substitution of any kind:
          * unknown timeframe  -> NO DATA (used to silently become M5)
          * H4 / D1            -> supported natively (used to silently become M5)
          * < MIN_BARS candles -> NO DATA (never padded with daily candles)
        """
        tf = TF_MAP.get(timeframe)
        if tf is None:
            logger.error(f"❌ Unsupported timeframe '{timeframe}' for {cfg.symbol}")
            return [], f"UNSUPPORTED TIMEFRAME ({timeframe})", None

        ck = f"get:{cfg.symbol}:{timeframe}"
        cached = SmartCache.get_obj(ck, PriceFeed.OHLCV_TTL)
        if cached is not None:
            return cached

        result: Optional[Tuple[List[float], str, Dict]] = None

        if cfg.asset_type in ("crypto", "forex"):
            got = PriceFeed._from_ccxt_ohlcv(cfg, timeframe)
            if got:
                ohlcv, source = got
                result = (ohlcv["close"], source, ohlcv)

        if result is None:
            period, interval = tf["yf"]
            ohlcv = PriceFeed._from_yfinance_ohlcv(cfg.yf_ticker, period, interval, tf.get("resample"))
            if ohlcv:
                result = (ohlcv["close"], "Yahoo Finance", ohlcv)

        if result is None:
            logger.warning(f"⚠️ NO REAL {timeframe} DATA available for {cfg.symbol}")
            return [], "NO REAL DATA AVAILABLE", None

        SmartCache.set_obj(ck, result, "Cache")
        return result

# ============================================
# SECTIONS 6 to 19 — ANALYSIS (FORMULAS PRESERVED, SAFETY GUARDS ADDED)
# ============================================

class NewsEngine:
    _KEYWORD_MAP = {
        "CPI": {"cat": "CRITICAL", "risk": "EXTREME", "action": "TRADING SUSPENDED"},
        "FOMC": {"cat": "CRITICAL", "risk": "EXTREME", "action": "TRADING SUSPENDED"},
        "NFP": {"cat": "CRITICAL", "risk": "EXTREME", "action": "TRADING SUSPENDED"},
        "inflation": {"cat": "CRITICAL", "risk": "HIGH", "action": "AVOID ENTRY"},
        "interest rate": {"cat": "CRITICAL", "risk": "HIGH", "action": "AVOID ENTRY"},
        "GDP": {"cat": "HIGH", "risk": "HIGH", "action": "AVOID ENTRY"},
        "default": {"cat": "LOW", "risk": "LOW", "action": "IGNORE"},
    }

    @staticmethod
    def _vader_score(text: str) -> float:
        try:
            from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
            return float(SentimentIntensityAnalyzer().polarity_scores(text)["compound"])
        except Exception:
            return 0.0

    @staticmethod
    def calc_macro_sentiment(news_items: List[NewsItem]) -> Tuple[int, str, int, int]:
        if not news_items: return 50, "NEUTRAL", 0, 0
        BULL_KW = ["rate cut", "dovish", "growth", "rally", "recovery", "stimulus", "bullish"]
        BEAR_KW = ["rate hike", "hawkish", "inflation", "war", "recession", "crash", "bearish"]
        vader_scores, bull_hits, bear_hits = [], 0, 0
        for item in news_items:
            t = item.title.lower()
            for kw in BULL_KW:
                if kw in t: bull_hits += 1
            for kw in BEAR_KW:
                if kw in t: bear_hits += 1
            vader_scores.append(NewsEngine._vader_score(item.title))
        vader_avg = float(np.mean(vader_scores)) if vader_scores else 0.0
        kw_delta = (bull_hits - bear_hits) / max(len(news_items), 1)
        combined = 0.6 * vader_avg + 0.4 * kw_delta
        score = int(min(100, max(0, 50 + combined * 35)))
        label = "VERY BULLISH" if score >= 70 else "BULLISH" if score >= 58 else "NEUTRAL" if score >= 42 else "BEARISH" if score >= 30 else "VERY BEARISH"
        return score, label, bull_hits, bear_hits

    @staticmethod
    def check_macro_event_risk(upcoming_events: List[Dict], hours_ahead: int = 2) -> Dict[str, Any]:
        HIGH_IMPACT_KEYWORDS = ["NFP", "CPI", "FOMC", "FED RATE", "GDP", "NON-FARM", "INFLATION", "PPI"]
        for event in upcoming_events:
            event_time_str = event.get("datetime")
            if not event_time_str: continue
            try:
                event_time = datetime.strptime(event_time_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
                title = event.get("event", "").upper()
                if any(kw in title for kw in HIGH_IMPACT_KEYWORDS):
                    time_diff = (event_time - datetime.now(timezone.utc)).total_seconds() / 3600
                    if 0 <= time_diff <= hours_ahead:
                        return {"risk_level": "EXTREME", "action": "AVOID_ENTRY_OR_REDUCE_SIZE_BY_80%",
                                "reason": f"High-impact macro event '{event.get('event')}' in {time_diff:.1f} hours"}
            except Exception:
                title = event.get("event", "").upper()
                if any(kw in title for kw in HIGH_IMPACT_KEYWORDS):
                    return {"risk_level": "EXTREME", "action": "AVOID_ENTRY_OR_REDUCE_SIZE_BY_80%",
                            "reason": f"High-impact macro event '{event.get('event')}' detected"}
        return {"risk_level": "NORMAL", "action": "NORMAL_TRADING", "reason": "No major macro events"}


class MathEngine:
    MIN_BARS = MIN_BARS
    VERSION = "13.11"

    # ── FIX[3]: NaN / Inf / short-array helpers ─────────────────────────
    @staticmethod
    def _clean(arr) -> np.ndarray:
        """
        float64 1-D copy with every NaN/Inf replaced by the previous finite value
        (leading gaps take the first finite value). Returns an EMPTY array if nothing is finite.
        This is gap-filling, not invention: no value that was not already in the series is created.
        """
        a = np.asarray(arr, dtype=float).ravel()
        if a.size == 0:
            return a
        ok = np.isfinite(a)
        if ok.all():
            return a
        if not ok.any():
            return np.array([], dtype=float)
        idx = np.where(ok, np.arange(a.size), 0)
        np.maximum.accumulate(idx, out=idx)
        a = a[idx]
        first = int(np.argmax(ok))
        a[:first] = a[first]
        return a

    @staticmethod
    def _last_finite(arr, default: float) -> float:
        """Last element of arr if it exists and is finite, else `default` (never raises IndexError)."""
        try:
            if arr is None or len(arr) == 0:
                return default
            v = float(arr[-1])
            return v if math.isfinite(v) else default
        except Exception:
            return default

    # ── Indicators ──────────────────────────────────────────────────────
    @staticmethod
    def _ema(arr: np.ndarray, period: int) -> np.ndarray:
        a = MathEngine._clean(arr)                       # FIX[3]
        n = len(a)
        out = np.full(n, np.nan)
        if period < 1 or n < period: return out          # FIX[3]: short-array guard
        k = 2.0 / (period + 1)
        out[period-1] = np.mean(a[:period])
        for i in range(period, n):
            out[i] = a[i] * k + out[i-1] * (1 - k)
        return out

    @staticmethod
    def _wilder_smooth(arr: np.ndarray, period: int) -> np.ndarray:
        a = np.nan_to_num(np.asarray(arr, dtype=float), nan=0.0, posinf=0.0, neginf=0.0)   # FIX[3]
        out = np.full(len(a), np.nan)
        if period < 1 or len(a) < period: return out
        out[period-1] = np.mean(a[:period])
        for i in range(period, len(a)):
            out[i] = (out[i-1] * (period - 1) + a[i]) / period
        return out

    @staticmethod
    def _rsi_series(prices: np.ndarray, period: int = 14) -> np.ndarray:
        p = MathEngine._clean(prices)                    # FIX[3]
        n = len(p)
        out = np.full(n, 50.0)
        if n < period + 2: return out
        d = np.diff(p)
        up = np.where(d > 0, d, 0.0)
        dn = np.where(d < 0, -d, 0.0)
        # FIX[3]: was np.empty() -> the first (period-1) slots held UNINITIALISED MEMORY,
        # which caused the "overflow encountered" RuntimeWarning and random garbage RSI values.
        au = np.full(n - 1, np.nan)
        al = np.full(n - 1, np.nan)
        au[period-1] = np.mean(up[:period])
        al[period-1] = np.mean(dn[:period])
        for i in range(period, n - 1):
            au[i] = (au[i-1] * (period - 1) + up[i]) / period
            al[i] = (al[i-1] * (period - 1) + dn[i]) / period
        rsi = np.full(n - 1, 50.0)
        with np.errstate(divide='ignore', invalid='ignore', over='ignore'):
            valid = np.isfinite(au) & np.isfinite(al) & (al > 0)
            rsi[valid] = 100 - 100 / (1 + au[valid] / np.maximum(al[valid], 1e-10))
        out[1:] = rsi
        return out

    @staticmethod
    def _calc_atr(prices: np.ndarray, period: int = 14, highs: Optional[np.ndarray] = None, lows: Optional[np.ndarray] = None) -> float:
        p = MathEngine._clean(prices)                    # FIX[3]
        if len(p) < period + 2: return 0.0
        tr = None
        if highs is not None and lows is not None:
            h, l = MathEngine._clean(highs), MathEngine._clean(lows)
            if len(h) == len(p) and len(l) == len(p):
                tr = np.maximum(h[1:] - l[1:], np.maximum(np.abs(h[1:] - p[:-1]), np.abs(l[1:] - p[:-1])))
        if tr is None:
            tr = np.abs(np.diff(p)) * 1.5
        tr = np.nan_to_num(tr, nan=0.0, posinf=0.0, neginf=0.0)
        s = MathEngine._wilder_smooth(tr, period)
        v = MathEngine._last_finite(s, float("nan"))
        if not math.isfinite(v):
            v = float(np.mean(tr[-period:])) if len(tr) else 0.0
        return max(0.0, v)

    @staticmethod
    def _calc_rsi(prices: np.ndarray, period: int = 14) -> float:
        p = MathEngine._clean(prices)
        if len(p) < period + 2: return 50.0
        return round(float(MathEngine._rsi_series(p, period)[-1]), 2)

    @staticmethod
    def _calc_macd(prices: np.ndarray) -> Tuple[float, float, float]:
        p = MathEngine._clean(prices)                    # FIX[3]
        if len(p) < 35: return 0.0, 0.0, 0.0
        e12, e26 = MathEngine._ema(p, 12), MathEngine._ema(p, 26)
        diff = e12 - e26
        valid = diff[np.isfinite(diff)]
        if len(valid) < 9: return 0.0, 0.0, 0.0
        sig = MathEngine._ema(valid, 9)
        line = float(valid[-1])
        sigv = MathEngine._last_finite(sig, 0.0)
        return round(line, 5), round(sigv, 5), round(line - sigv, 5)

    @staticmethod
    def _calc_stoch(prices: np.ndarray, k: int = 14, d: int = 3) -> Tuple[float, float]:
        if len(prices) < k + d: return 50.0, 50.0
        raw_k = [100.0 * (prices[i+k-1] - np.min(prices[i:i+k])) / (np.max(prices[i:i+k]) - np.min(prices[i:i+k])) if np.max(prices[i:i+k]) > np.min(prices[i:i+k]) else 50.0 for i in range(len(prices) - k + 1)]
        raw_k = np.array(raw_k)
        kv = float(np.mean(raw_k[-d:])) if len(raw_k) >= d else float(raw_k[-1])
        dv = float(np.mean(raw_k[-d*2+1:])) if len(raw_k) >= d*2 else kv
        return round(kv, 2), round(dv, 2)

    @staticmethod
    def _calc_bb(prices: np.ndarray, period: int = 20, std: float = 2.0) -> Tuple[float, float, float, float]:
        if len(prices) < period:
            p = float(prices[-1]); return p, p, p, 0.0
        w = prices[-period:]
        mid, s = float(np.mean(w)), float(np.std(w))
        return round(mid + std * s, 4), round(mid, 4), round(mid - std * s, 4), round((2 * std * s) / mid * 100 if mid else 0.0, 4)

    @staticmethod
    def _calc_keltner(prices: np.ndarray, period: int = 20, mult: float = 1.5) -> Tuple[float, float, float]:
        if len(prices) < period:
            p = float(prices[-1]); return p, p, p
        e = MathEngine._ema(prices, period)
        mid = MathEngine._last_finite(e, float(np.mean(prices[-period:])))
        atr = MathEngine._calc_atr(prices, period)
        return round(mid + mult * atr, 4), round(mid, 4), round(mid - mult * atr, 4)

    @staticmethod
    def _calc_ttm_squeeze(prices: np.ndarray) -> Tuple[bool, str, float]:
        if len(prices) < 22: return False, "SQUEEZE OFF", 0.0
        bbu, _, bbl, _ = MathEngine._calc_bb(prices)
        kcu, _, kcl = MathEngine._calc_keltner(prices)
        squeeze = bool((bbu < kcu) and (bbl > kcl))
        sma20 = float(np.mean(prices[-20:]))
        delta = float(np.mean(prices[-5:])) - sma20
        label = "🔴 SQUEEZE ON — BREAKOUT IMMINENT" if squeeze else "🟢 SQUEEZE OFF — TREND IN MOTION"
        return squeeze, label, round(delta, 4)

    @staticmethod
    def _calc_supertrend(prices: np.ndarray, highs: Optional[np.ndarray] = None, lows: Optional[np.ndarray] = None, period: int = 10, mult: float = 3.0) -> Tuple[float, str, str]:
        if len(prices) < period + 5: return float(prices[-1]), "NEUTRAL", "#888888"
        atr = MathEngine._calc_atr(prices, period, highs, lows)
        cur = float(prices[-1])
        hl2 = (highs + lows) / 2 if highs is not None and lows is not None else prices
        basic_upper, basic_lower = float(hl2[-1]) + mult * atr, float(hl2[-1]) - mult * atr
        direction = "BULLISH" if cur > basic_lower else "BEARISH" if cur < basic_upper else "NEUTRAL"
        if direction == "BULLISH": st_line, color = basic_lower, "#00FF88"
        elif direction == "BEARISH": st_line, color = basic_upper, "#FF3131"
        else: st_line, color = float(np.mean([basic_upper, basic_lower])), "#FFD600"
        return round(st_line, 4), direction, color

    @staticmethod
    def _calc_vwap(prices: np.ndarray, volumes: Optional[np.ndarray] = None) -> Tuple[float, float, float, str]:
        if len(prices) < 20:
            p = float(prices[-1]); return p, p * 1.002, p * 0.998, "NEUTRAL"
        if volumes is not None and len(volumes) == len(prices) and np.sum(volumes) > 0:
            vol = np.array(volumes, dtype=float)
        else:
            chg = np.abs(np.diff(prices, prepend=prices[0]))
            vol = chg / (np.sum(chg) + 1e-10) * len(prices)
        tp = prices.copy()
        vwap = float(np.sum(tp * vol) / (np.sum(vol) + 1e-10))
        dev = float(np.sqrt(np.sum(vol * (tp - vwap) ** 2) / (np.sum(vol) + 1e-10)))
        up, lo = vwap + 2 * dev, vwap - 2 * dev
        cur = float(prices[-1])
        if cur > up: signal = "FAR ABOVE VWAP — OVERBOUGHT"
        elif cur > vwap: signal = "ABOVE VWAP — BULLISH"
        elif cur < lo: signal = "FAR BELOW VWAP — OVERSOLD"
        else: signal = "BELOW VWAP — BEARISH"
        return round(vwap, 4), round(up, 4), round(lo, 4), signal

    @staticmethod
    def _calc_pivot_points(prices: np.ndarray, highs: Optional[np.ndarray] = None, lows: Optional[np.ndarray] = None) -> Dict[str, float]:
        n = min(len(prices), 20)
        H = float(np.max(highs[-n:])) if highs is not None else float(np.max(prices[-n:]))
        L = float(np.min(lows[-n:])) if lows is not None else float(np.min(prices[-n:]))
        C = float(prices[-1])
        PP = round((H + L + C) / 3, 4)
        R = H - L
        return {"PP": PP, "R1": round(2*PP - L, 4), "R2": round(PP + R, 4), "R3": round(H + 2*(PP-L), 4),
                "S1": round(2*PP - H, 4), "S2": round(PP - R, 4), "S3": round(L - 2*(H-PP), 4),
                "FR1": round(PP + 0.382*R, 4), "FR2": round(PP + 0.618*R, 4),
                "FS1": round(PP - 0.382*R, 4), "FS2": round(PP - 0.618*R, 4)}

    @staticmethod
    def _calc_zscore(prices: np.ndarray, period: int = 50) -> Tuple[float, str]:
        if len(prices) < period: return 0.0, "NEUTRAL"
        w = prices[-period:]
        std = float(np.std(w))
        if std < 1e-10: return 0.0, "NEUTRAL"
        z = (float(prices[-1]) - float(np.mean(w))) / std
        sig = "EXTREME OVERBOUGHT" if z > 3 else "OVERBOUGHT" if z > 2 else "EXTREME OVERSOLD" if z < -3 else "OVERSOLD" if z < -2 else "NEUTRAL"
        return round(z, 3), sig

    @staticmethod
    def _calc_adx(prices: np.ndarray, period: int = 14) -> Tuple[float, float, float]:
        if len(prices) < period * 2 + 2: return 0.0, 0.0, 0.0
        highs, lows = prices * 1.0005, prices * 0.9995
        tr = np.abs(np.diff(prices)) * 1.5
        dm_p = np.where(np.diff(highs) > -np.diff(lows), np.maximum(np.diff(highs), 0.0), 0.0)
        dm_m = np.where(-np.diff(lows) > np.diff(highs), np.maximum(-np.diff(lows), 0.0), 0.0)
        atr_s = MathEngine._wilder_smooth(tr, period)
        di_ps, di_ms = MathEngine._wilder_smooth(dm_p, period), MathEngine._wilder_smooth(dm_m, period)
        if np.isnan(atr_s[-1]) or atr_s[-1] == 0: return 0.0, 0.0, 0.0
        dip, dim = 100 * di_ps[-1] / atr_s[-1], 100 * di_ms[-1] / atr_s[-1]
        dx_d = abs(dip + dim)
        dx = 100 * abs(dip - dim) / dx_d if dx_d > 0 else 0.0
        adx_a = np.full(len(tr), np.nan)
        start = period * 2 - 2
        if start < len(tr):
            adx_a[start] = 25.0
            for i in range(start+1, len(tr)):
                if not np.isnan(adx_a[i-1]): adx_a[i] = (adx_a[i-1] * (period-1) + dx) / period
        valid = adx_a[~np.isnan(adx_a)]
        return round(float(valid[-1]) if len(valid) else 25.0, 2), round(dip, 2), round(dim, 2)

    @staticmethod
    def _calc_williams_r(prices: np.ndarray, period: int = 14) -> float:
        if len(prices) < period: return -50.0
        w = prices[-period:]; hi, lo = np.max(w), np.min(w)
        return round(-100 * (hi - prices[-1]) / (hi - lo), 2) if hi > lo else -50.0

    @staticmethod
    def _calc_cci(prices: np.ndarray, period: int = 14) -> float:
        if len(prices) < period: return 0.0
        tp = prices[-period:]
        m = float(np.mean(tp))
        md = float(np.mean(np.abs(tp - m)))
        return round((prices[-1] - m) / (0.015 * md), 2) if md else 0.0

    @staticmethod
    def _calc_obv(prices: np.ndarray, volumes: Optional[np.ndarray] = None) -> Tuple[float, str]:
        if len(prices) < 20: return 0.0, "NEUTRAL"
        obv = 0.0; recent = []
        for i in range(1, len(prices)):
            vol = float(volumes[i]) if volumes is not None and len(volumes) == len(prices) else abs(prices[i]-prices[i-1]) * 1000
            obv += vol if prices[i] > prices[i-1] else (-vol if prices[i] < prices[i-1] else 0)
            recent.append(obv)
        half = max(5, len(recent)//4)
        first, last = np.mean(recent[:half]), np.mean(recent[-half:])
        trend = "BULLISH" if last > first * 1.01 else "BEARISH" if last < first * 0.99 else "NEUTRAL"
        return round(obv, 0), trend

    @staticmethod
    def _calc_ichimoku(prices: np.ndarray) -> Tuple[str, float, float]:
        if len(prices) < 52: return "NEUTRAL", 0.0, 0.0
        tenkan = (np.max(prices[-9:]) + np.min(prices[-9:])) / 2
        kijun = (np.max(prices[-26:]) + np.min(prices[-26:])) / 2
        senkou_a, senkou_b = (tenkan + kijun) / 2, (np.max(prices[-52:]) + np.min(prices[-52:])) / 2
        cur = prices[-1]
        above, below = cur > max(senkou_a, senkou_b), cur < min(senkou_a, senkou_b)
        tk_bull = tenkan > kijun
        if above and tk_bull: sig = "STRONG BULLISH"
        elif above: sig = "BULLISH"
        elif below and not tk_bull: sig = "STRONG BEARISH"
        elif below: sig = "BEARISH"
        else: sig = "NEUTRAL (in cloud)"
        return sig, round(float(tenkan), 4), round(float(kijun), 4)

    @staticmethod
    def _calc_hurst(prices: np.ndarray) -> Tuple[float, str]:
        if len(prices) < 60: return 0.5, "RANDOM"
        try:
            lags = list(range(2, min(40, len(prices)//3)))
            tau_all = [np.std(np.subtract(prices[lag:], prices[:-lag])) for lag in lags]
            # FIX[3]: keep (lag, tau) PAIRED. The old code filtered tau but sliced lags by length,
            # misaligning the regression whenever a std was 0.
            pairs = [(lag, t) for lag, t in zip(lags, tau_all) if t > 0 and np.isfinite(t)]
            if len(pairs) < 4: return 0.5, "RANDOM"
            m = np.polyfit(np.log([p[0] for p in pairs]), np.log([p[1] for p in pairs]), 1)
            h = round(float(m[0]), 4)
            regime = "TRENDING" if h > 0.55 else "MEAN-REVERTING" if h < 0.45 else "RANDOM"
            return max(0.0, min(1.0, h)), regime
        except Exception:
            return 0.5, "RANDOM"

    @staticmethod
    def _detect_regime_advanced(prices: np.ndarray, hurst: float, adx: float, vol_regime: str, bb_width: float) -> str:
        cur = float(prices[-1])
        if len(prices) < 30: return "CHOPPY"
        ema50_arr = MathEngine._ema(prices, min(50, len(prices)//2))
        ema50 = MathEngine._last_finite(ema50_arr, cur)
        returns = np.diff(prices[-20:]) / (prices[-20:-1] + 1e-10)
        rv = float(np.std(returns)) * math.sqrt(252 * 78)
        if vol_regime == "EXTREME" or rv > 60: return "CRISIS VOLATILITY"
        if hurst > 0.57 and adx > 25 and cur > ema50 and bb_width > 2.0: return "BULL TREND"
        if hurst > 0.57 and adx > 25 and cur < ema50 and bb_width > 2.0: return "BEAR TREND"
        if hurst < 0.45 and bb_width < 2.5: return "MEAN-REVERTING"
        if bb_width < 1.5 or adx < 15: return "CHOPPY"
        return "CHOPPY"

    @staticmethod
    def _calc_entropy(prices: np.ndarray) -> float:
        if len(prices) < 20: return 0.0
        try:
            returns = np.diff(prices) / (prices[:-1] + 1e-10)
            hist, _ = np.histogram(returns, bins=20, density=True)
            hist = hist[hist > 0]
            return round(float(-np.sum(hist * np.log(hist + 1e-12))), 4)
        except Exception:
            return 0.0

    @staticmethod
    def _calc_ker(prices: np.ndarray, period: int = 20) -> float:
        if len(prices) < period + 1: return 0.0
        net = abs(prices[-1] - prices[-period-1])
        noise = np.sum(np.abs(np.diff(prices[-period-1:])))
        return round(float(net / noise), 4) if noise > 0 else 0.0

    @staticmethod
    def _calc_fractal_dim(prices: np.ndarray) -> float:
        if len(prices) < 20: return 1.5
        n = min(len(prices), 60); p = prices[-n:]
        hi, lo = np.max(p), np.min(p); rng = hi - lo
        if rng == 0: return 1.5
        path = np.sum(np.abs(np.diff(p)))
        fd = 1.0 + math.log(path/rng) / math.log(n)
        return round(max(1.0, min(2.0, fd)), 4)

    @staticmethod
    def _calc_sr(prices: np.ndarray, cur: float) -> Tuple[List, List, float, float, str]:
        if len(prices) < 30: return [], [], cur, cur, "MIDDLE"
        order = max(3, len(prices)//30)
        ri = argrelextrema(prices, np.greater, order=order)[0]
        si = argrelextrema(prices, np.less, order=order)[0]
        rests = sorted([round(float(prices[i]), 4) for i in ri], reverse=True)[:6]
        supps = sorted([round(float(prices[i]), 4) for i in si])[:6]
        nr = next((r for r in rests if r > cur), cur)
        ns = next((s for s in reversed(supps) if s < cur), cur)
        rng = nr - ns
        if rng < 1e-6: zone = "MIDDLE"
        else:
            pct = (cur - ns) / rng
            zone = "NEAR RESISTANCE" if pct > 0.75 else "NEAR SUPPORT" if pct < 0.25 else "MIDDLE"
        return supps, rests, round(ns, 4), round(nr, 4), zone

    @staticmethod
    def _detect_obs(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 20: return []
        obs = []; r = prices[-min(100, len(prices)-1):]
        for i in range(2, len(r) - 3):
            move_after = r[i+3] - r[i+1]
            candle_size = r[i] - r[i-1]
            if abs(candle_size) < 1e-10: continue
            strength = round(min(100, abs(move_after)/abs(candle_size)*20), 1)
            if candle_size < 0 and move_after > abs(candle_size) * 2:
                obs.append({"type": "BULLISH OB", "high": round(float(max(r[i-1], r[i])), 4), "low": round(float(min(r[i-1], r[i])), 4),
                            "strength": strength, "dist_pct": round(abs(cur-min(r[i-1], r[i]))/(cur+1e-10)*100, 2),
                            "tip": "Price returning here = potential BUY zone"})
            elif candle_size > 0 and -move_after > candle_size * 2:
                obs.append({"type": "BEARISH OB", "high": round(float(max(r[i-1], r[i])), 4), "low": round(float(min(r[i-1], r[i])), 4),
                            "strength": strength, "dist_pct": round(abs(cur-max(r[i-1], r[i]))/(cur+1e-10)*100, 2),
                            "tip": "Price returning here = potential SELL zone"})
        obs.sort(key=lambda x: x["dist_pct"])
        return obs[:5]

    @staticmethod
    def _detect_fvgs(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 10: return []
        fvgs = []; r = prices[-min(80, len(prices)):]
        atr = float(np.mean(np.abs(np.diff(r[-20:])))) if len(r) >= 20 else 1.0
        for i in range(len(r) - 2):
            gu, gd = r[i+2] - r[i], r[i] - r[i+2]
            if gu > atr * 1.5:
                fh, fl = r[i+2], r[i]
                fvgs.append({"type": "BULLISH FVG", "high": round(float(fh), 4), "low": round(float(fl), 4),
                             "filled": bool(any(fl <= r[j] <= fh for j in range(i+3, len(r)))),
                             "dist_pct": round(abs(cur-fl)/(cur+1e-10)*100, 2), "tip": "BUY magnet — unfilled gap pulls price back"})
            elif gd > atr * 1.5:
                fh, fl = r[i], r[i+2]
                fvgs.append({"type": "BEARISH FVG", "high": round(float(fh), 4), "low": round(float(fl), 4),
                             "filled": bool(any(fl <= r[j] <= fh for j in range(i+3, len(r)))),
                             "dist_pct": round(abs(cur-fh)/(cur+1e-10)*100, 2), "tip": "SELL magnet — unfilled gap pulls price back"})
        fvgs = [f for f in fvgs if not f["filled"]]
        fvgs.sort(key=lambda x: x["dist_pct"])
        return fvgs[:4]

    @staticmethod
    def _detect_liquidity_sweeps(prices: np.ndarray, cur: float) -> List[Dict]:
        if len(prices) < 30: return []
        r = prices[-min(100, len(prices)):]
        sweeps = []; lookback = 12
        for i in range(lookback, len(r) - 2):
            sh, sl = float(np.max(r[i-lookback:i])), float(np.min(r[i-lookback:i]))
            if r[i] > sh * 1.0002 and r[i+1] < sh:
                sweeps.append({"type": "BEARISH SWEEP (Stop Hunt High)", "swept_level": round(sh, 4),
                               "sweep_price": round(float(r[i]), 4), "close_back": round(float(r[i+1]), 4),
                               "dist_pct": round(abs(cur-sh)/(cur+1e-10)*100, 2),
                               "tip": "Whales ran stops above high — look for SELL reversal", "bias": "SELL"})
            elif r[i] < sl * 0.9998 and r[i+1] > sl:
                sweeps.append({"type": "BULLISH SWEEP (Stop Hunt Low)", "swept_level": round(sl, 4),
                               "sweep_price": round(float(r[i]), 4), "close_back": round(float(r[i+1]), 4),
                               "dist_pct": round(abs(cur-sl)/(cur+1e-10)*100, 2),
                               "tip": "Whales raided stops below low — look for BUY reversal", "bias": "BUY"})
        sweeps.sort(key=lambda x: x["dist_pct"])
        return sweeps[:5]

    @staticmethod
    def _detect_elliott(prices: np.ndarray) -> Dict:
        if len(prices) < 50: return {"detected": False, "position": "INSUFFICIENT DATA", "confidence": 0.0}
        try:
            order = max(3, len(prices)//20)
            hi_ix = argrelextrema(prices, np.greater, order=order)[0]
            lo_ix = argrelextrema(prices, np.less, order=order)[0]
            all_p = sorted([(i, prices[i]) for i in hi_ix] + [(i, prices[i]) for i in lo_ix], key=lambda x: x[0])
            if len(all_p) < 5: return {"detected": False, "position": "TOO FEW PIVOTS", "confidence": 0.0}
            wc = len(all_p); recent = all_p[-8:]
            is_up = prices[-1] > np.mean(prices[-20:])
            pos, conf, tgt = "EARLY WAVE", 35.0, None
            if wc >= 5:
                vals = [float(p[1]) for p in recent[:6]]
                if wc == 5:
                    pos, conf = "WAVE 5 FORMING", 60.0
                    tgt = vals[4] + abs(vals[0]-vals[1]) if len(vals) >= 5 else None
                elif wc == 6:
                    pos, conf = "WAVE 5 COMPLETE — REVERSAL EXPECTED", 70.0
                    tgt = vals[5] - (vals[5]-vals[0]) * 0.382 if len(vals) >= 6 else None
                elif wc >= 7:
                    pos, conf = "ABC CORRECTION", 55.0
                    a_len = abs(vals[6]-vals[5]) if len(vals) >= 7 else 0
                    tgt = (vals[6] - a_len) if is_up else (vals[6] + a_len)
            return {"detected": True, "position": pos, "confidence": round(conf, 1), "wave_count": wc,
                    "trend": "BULLISH" if is_up else "BEARISH", "target": round(float(tgt), 4) if tgt else None}
        except Exception:
            return {"detected": False, "position": "COMPUTE ERROR", "confidence": 0.0}

    @staticmethod
    def _calc_fib(prices: np.ndarray, cur: float) -> Tuple[Dict, Dict, str, float, str]:
        if len(prices) < 30: return {}, {}, "NEUTRAL", 0.0, ""
        r = prices[-min(100, len(prices)):]
        sh, sl = float(np.max(r)), float(np.min(r)); d = sh - sl
        if d < 0.01: return {}, {}, "NEUTRAL", 0.0, "Flat range."
        is_up = cur > float(np.mean(r))
        def _r(pct): return round((sh - d*pct) if is_up else (sl + d*pct), 4)
        rets = {"0.0%": _r(0), "23.6%": _r(.236), "38.2%": _r(.382), "50.0%": _r(.5),
                "61.8%": _r(.618), "78.6%": _r(.786), "100.0%": _r(1)}
        exts = {"127.2%": round((sl+d*1.272) if is_up else (sh-d*1.272), 4),
                "161.8%": round((sl+d*1.618) if is_up else (sh-d*1.618), 4),
                "200.0%": round((sl+d*2.000) if is_up else (sh-d*2.000), 4)}
        tol = d * 0.015; zone, strength, expl = "NEUTRAL", 0.0, ""
        for name, price in rets.items():
            if abs(cur-price) < tol:
                if name in ("38.2%", "50.0%", "61.8%"):
                    zone, strength, expl = ("STRONG_SUPPORT" if is_up else "STRONG_RESISTANCE"), 80.0, f"AT {name} GOLDEN ZONE (${price:,.4f})"
                elif name in ("23.6%", "78.6%"):
                    zone, strength, expl = "MINOR_LEVEL", 45.0, f"Near {name} Fib (${price:,.4f})"
                break
        if not expl:
            near = min(rets, key=lambda k: abs(rets[k]-cur))
            expl = f"Nearest Fib: {near} @ ${rets[near]:,.4f}"
        return rets, exts, zone, strength, expl

    @staticmethod
    def _get_session(cfg: AssetConfig) -> Tuple[str, str, str, str]:
        try:
            from zoneinfo import ZoneInfo
            ny_now = datetime.now(ZoneInfo("America/New_York"))
            london_now = datetime.now(ZoneInfo("Europe/London"))
        except Exception:
            utc_now = datetime.now(timezone.utc)
            ny_now = utc_now - timedelta(hours=5)
            london_now = utc_now

        ny_min = ny_now.hour * 60 + ny_now.minute
        london_min = london_now.hour * 60 + london_now.minute
        warn = ""
        ny_open = 9 * 60 + 30
        if 0 < (ny_open - ny_min) <= 15:
            warn = f"⚡ NEW YORK OPEN in {ny_open - ny_min} min — volatility spike imminent!"
        lon_open = 8 * 60
        if 0 < (lon_open - london_min) <= 15:
            warn = f"⚡ LONDON OPEN in {lon_open - london_min} min — volatility spike imminent!"

        if cfg.is_24_7:
            if 9*60 + 30 <= ny_min < 16*60: sess, liq, expl = "NY TRADING HOURS", "HIGH", "Wall St open."
            elif 3*60 <= ny_min < 9*60 + 30: sess, liq, expl = "LONDON HOURS", "MEDIUM-HIGH", "European session."
            elif 19*60 <= ny_min < 24*60 or 0 <= ny_min < 3*60: sess, liq, expl = "ASIAN HOURS", "MEDIUM", "Asian session."
            else: sess, liq, expl = "LATE NY/OVERNIGHT", "LOW", "Thin liquidity."
        else:
            if 9*60 + 30 <= ny_min < 12*60: sess, liq, expl = "OVERLAP (Ldn+NY)", "EXTREME", "Both sessions open."
            elif 9*60 + 30 <= ny_min < 17*60: sess, liq, expl = "NEW YORK", "HIGH", "NY session."
            elif 3*60 <= ny_min < 9*60 + 30: sess, liq, expl = "LONDON", "HIGH", "London session."
            elif 19*60 <= ny_min < 24*60 or 0 <= ny_min < 3*60: sess, liq, expl = "ASIAN", "MEDIUM", "Range-bound likely."
            else: sess, liq, expl = "OFF-HOURS", "LOW", "Minimal participation."
        return sess, liq, warn, expl

    @staticmethod
    def _detect_divergence(prices: np.ndarray) -> Tuple[str, str, str, float]:
        if len(prices) < 50: return "NONE", "NONE", "NONE", 0.0
        try:
            rsi_arr = MathEngine._rsi_series(prices[-50:])
            price_hi1, price_hi2 = float(np.max(prices[-20:-10])), float(np.max(prices[-10:]))
            price_lo1, price_lo2 = float(np.min(prices[-20:-10])), float(np.min(prices[-10:]))
            rsi_hi1 = float(np.max(rsi_arr[-20:-10])) if len(rsi_arr) >= 20 else 50.0
            rsi_hi2 = float(np.max(rsi_arr[-10:])) if len(rsi_arr) >= 10 else 50.0
            rsi_lo1 = float(np.min(rsi_arr[-20:-10])) if len(rsi_arr) >= 20 else 50.0
            rsi_lo2 = float(np.min(rsi_arr[-10:])) if len(rsi_arr) >= 10 else 50.0
            rsi_div = "BEARISH" if price_hi2 > price_hi1 * 1.001 and rsi_hi2 < rsi_hi1 - 2 else \
                      "BULLISH" if price_lo2 < price_lo1 * 0.999 and rsi_lo2 > rsi_lo1 + 2 else "NONE"
            macd_div = "NONE"
            if len(prices) >= 60:
                m1, _, h1 = MathEngine._calc_macd(prices[-60:-10])
                m2, _, h2 = MathEngine._calc_macd(prices[-40:])
                if price_hi2 > price_hi1 * 1.001 and h2 < h1 - 0.0001: macd_div = "BEARISH"
                elif price_lo2 < price_lo1 * 0.999 and h2 > h1 + 0.0001: macd_div = "BULLISH"
            if rsi_div == "BULLISH" and macd_div == "BULLISH": signal, strength = "STRONG BULLISH DIVERGENCE", 85.0
            elif rsi_div == "BEARISH" and macd_div == "BEARISH": signal, strength = "STRONG BEARISH DIVERGENCE", 85.0
            elif rsi_div == "BULLISH" or macd_div == "BULLISH": signal, strength = "BULLISH DIVERGENCE", 60.0
            elif rsi_div == "BEARISH" or macd_div == "BEARISH": signal, strength = "BEARISH DIVERGENCE", 60.0
            else: signal, strength = "NONE", 0.0
            return rsi_div, macd_div, signal, round(strength, 1)
        except Exception:
            return "NONE", "NONE", "NONE", 0.0

    @staticmethod
    def _detect_candle_patterns(prices: np.ndarray) -> Tuple[str, float, str, str]:
        if len(prices) < 10: return "NONE", 0.0, "NEUTRAL", ""
        try:
            r = prices[-10:]
            avg_body = float(np.mean(np.abs(np.diff(r[-6:])))) + 1e-10
            b1, b2 = abs(r[-2] - r[-3]), abs(r[-1] - r[-2])
            if b1 > 0 and b2 > b1 * 1.4 and r[-1] > r[-2] and r[-2] < r[-3]:
                return "BULLISH ENGULFING", 78.0, "BULLISH", "Last candle fully engulfs prior bearish candle."
            if b1 > 0 and b2 > b1 * 1.4 and r[-1] < r[-2] and r[-2] > r[-3]:
                return "BEARISH ENGULFING", 78.0, "BEARISH", "Last candle fully engulfs prior bullish candle."
            if abs(r[-1] - r[-2]) < avg_body * 0.18:
                return "DOJI", 52.0, "NEUTRAL", "Near-equal open/close — indecision."
            return "NONE", 0.0, "NEUTRAL", "No significant pattern."
        except Exception:
            return "NONE", 0.0, "NEUTRAL", ""

    @staticmethod
    def _calc_kelly(win_prob: float, rr_ratio: float) -> Tuple[float, str]:
        if win_prob <= 0 or rr_ratio <= 0: return 0.0, "Cannot compute."
        try:
            full_kelly = win_prob - (1.0 - win_prob) / rr_ratio
            half_kelly = max(0.0, min(0.25, full_kelly * 0.5))
            if half_kelly <= 0: rec = "Negative Kelly — edge too small."
            elif half_kelly < 0.02: rec = f"Very small edge ({half_kelly*100:.1f}%)."
            elif half_kelly < 0.08: rec = f"Moderate edge ({half_kelly*100:.1f}%)."
            else: rec = f"Good edge ({half_kelly*100:.1f}%)."
            return round(half_kelly, 4), rec
        except Exception:
            return 0.0, "Calculation error."

    @staticmethod
    def _build_stops(price: float, atr: float, atr_mult: float, rr: float, cfg: AssetConfig) -> Tuple:
        if atr == 0: return None, None, None, None, 0.0, "ATR=0"
        sl_dist, tp_dist = atr * atr_mult, atr * atr_mult * rr
        sl_pips = round(sl_dist / cfg.pip_size, 1)
        expl = f"ATR(14)=${atr:.4f}  SL={atr_mult}×ATR=${sl_dist:.4f}  TP={rr}×SL=${tp_dist:.4f}  ({sl_pips:.0f} pips)"
        return round(price - sl_dist, 4), round(price + sl_dist, 4), round(price + tp_dist, 4), round(price - tp_dist, 4), sl_pips, expl

    @staticmethod
    def calc_lot_size(account_bal: float, risk_pct: float, leverage: float, sl_pips: float, cfg: AssetConfig, current_price: float) -> Tuple[float, float, float, str]:
        if sl_pips <= 0 or account_bal <= 0: return 0.0, 0.0, 0.0, "Enter account data."
        risk_usd = account_bal * (risk_pct / 100.0)
        lots = max(0.01, round(risk_usd / (sl_pips * cfg.pip_value_per_lot), 2))
        notional = lots * cfg.contract_size * current_price
        margin = round(notional / max(leverage, 1), 2)
        tp_gain = round(sl_pips * cfg.pip_value_per_lot * lots * 2.5, 2)
        expl = f"Risk: ${risk_usd:.2f} ({risk_pct}%)  ·  Lots: {lots}  ·  Margin: ${margin:,.2f}  ·  Max TP: ${tp_gain:.2f}"
        return round(risk_usd, 2), lots, margin, expl

    @staticmethod
    def calculate_expectancy(win_rate: float, avg_win: float, avg_loss: float) -> float:
        loss_rate = 1.0 - win_rate
        return round((win_rate * avg_win) - (loss_rate * avg_loss), 4)

    @staticmethod
    def volatility_adjusted_risk(base_risk_pct: float, current_atr: float, avg_atr: float) -> float:
        if avg_atr <= 0 or current_atr <= 0: return base_risk_pct      # FIX[3]: sqrt(0) -> div-by-zero guard
        vol_ratio = current_atr / avg_atr
        adjusted = base_risk_pct / math.sqrt(vol_ratio)
        return round(max(0.25, min(2.0, adjusted)), 2)

    @staticmethod
    def estimate_proxy_delta(opens: np.ndarray, highs: np.ndarray, lows: np.ndarray, closes: np.ndarray, volumes: np.ndarray) -> Dict[str, Any]:
        if volumes is None or len(closes) < 20 or len(volumes) != len(closes):
            return {"delta_signal": "NEUTRAL", "buying_pressure": 50.0}
        recent_closes, recent_highs, recent_lows, recent_volumes = closes[-3:], highs[-3:], lows[-3:], volumes[-3:]
        avg_vol = float(np.mean(volumes[-20:])) if len(volumes) >= 20 else 1.0
        buying_score = 50.0
        for i in range(3):
            candle_range = recent_highs[i] - recent_lows[i]
            if candle_range == 0: continue
            close_pos = (recent_closes[i] - recent_lows[i]) / candle_range
            vol_ratio = recent_volumes[i] / (avg_vol + 1e-10)
            if close_pos > 0.7 and vol_ratio > 1.2: buying_score += 15
            elif close_pos < 0.3 and vol_ratio > 1.2: buying_score -= 15
        buying_score = max(0.0, min(100.0, buying_score))
        if buying_score >= 70: signal = "STRONG_BUYING_PRESSURE"
        elif buying_score <= 30: signal = "STRONG_SELLING_PRESSURE"
        else: signal = "NEUTRAL"
        return {"delta_signal": signal, "buying_pressure": round(buying_score, 1)}


class VolumeProfileAnalyzer:
    @staticmethod
    def calculate_volume_profile(prices: np.ndarray, volumes: np.ndarray, bins: int = 20) -> dict:
        n = min(len(prices), len(volumes))
        prices, volumes = prices[-n:], volumes[-n:]
        hist, bin_edges = np.histogram(prices, bins=bins, weights=volumes)
        poc_index = np.argmax(hist)
        poc_price = float((bin_edges[poc_index] + bin_edges[poc_index + 1]) / 2)
        total_volume = np.sum(hist)
        sorted_indices = np.argsort(hist)[::-1]
        value_area_volume, value_area_indices = 0, []
        for idx in sorted_indices:
            value_area_volume += hist[idx]
            value_area_indices.append(idx)
            if value_area_volume >= total_volume * 0.70: break
        value_area_prices = [float((bin_edges[i] + bin_edges[i+1]) / 2) for i in sorted(value_area_indices)]
        return {"poc_price": poc_price,
                "value_area_high": max(value_area_prices) if value_area_prices else poc_price,
                "value_area_low": min(value_area_prices) if value_area_prices else poc_price}

    @staticmethod
    def detect_order_blocks(opens: np.ndarray, highs: np.ndarray, lows: np.ndarray, closes: np.ndarray, lookback: int = 50) -> dict:
        bullish_ob, bearish_ob = None, None
        start_idx = max(0, len(closes) - lookback)
        for i in range(start_idx, len(closes) - 1):
            if closes[i] < opens[i] and closes[i+1] > opens[i+1] and (closes[i+1] - opens[i+1]) > (opens[i] - closes[i]):
                bullish_ob = float((highs[i] + lows[i]) / 2)
            if closes[i] > opens[i] and closes[i+1] < opens[i+1] and (opens[i+1] - closes[i+1]) > (closes[i] - opens[i]):
                bearish_ob = float((highs[i] + lows[i]) / 2)
        return {"bullish_order_block": bullish_ob, "bearish_order_block": bearish_ob}


class MonteCarloRiskEngine:
    @staticmethod
    def simulate_trades(win_rate: float, rr_ratio: float, risk_amount: float, initial_balance: float,
                        num_trades: int = 100, simulations: int = 1000) -> MonteCarloStats:
        avg_win, avg_loss = risk_amount * rr_ratio, risk_amount
        wins = np.random.rand(simulations, num_trades) < win_rate
        pnl = np.where(wins, avg_win, -avg_loss)
        equity = initial_balance + np.cumsum(pnl, axis=1)
        final_balances = equity[:, -1]
        peak = np.maximum.accumulate(equity, axis=1)
        drawdown = (peak - equity) / (peak + 1e-9)
        max_drawdowns = drawdown.max(axis=1) * 100
        return MonteCarloStats(
            expected_final_balance=float(np.mean(final_balances)),
            var_95=float(np.percentile(final_balances, 5)),
            var_99=float(np.percentile(final_balances, 1)),
            expected_max_drawdown=float(np.mean(max_drawdowns)),
            probability_of_ruin=float(np.mean(final_balances < initial_balance * 0.5) * 100),
            simulations_run=simulations)


class MultiTimeframeEngine:
    @staticmethod
    def analyze_mtf(data_1h: dict, data_4h: dict, data_1d: dict) -> MTFAnalysis:
        def get_regime(data):
            if len(data['closes']) < 50: return MarketRegime.RANGING_BULLISH
            prices = np.array(data['closes'])
            ema_20, ema_50 = MathEngine._ema(prices, 20), MathEngine._ema(prices, 50)
            trend_strength = min(np.abs(ema_20[-1] - ema_50[-1]) / prices[-1] * 100, 100)
            p_ema20, p_ema50, ema_trend = prices[-1] > ema_20[-1], prices[-1] > ema_50[-1], ema_20[-1] > ema_50[-1]
            if p_ema20 and p_ema50 and ema_trend:
                return MarketRegime.STRONG_UPTREND if trend_strength > 60 else MarketRegime.WEAK_UPTREND
            elif not p_ema20 and not p_ema50 and not ema_trend:
                return MarketRegime.STRONG_DOWNTREND if trend_strength > 60 else MarketRegime.WEAK_DOWNTREND
            else:
                return MarketRegime.RANGING_BULLISH if p_ema50 else MarketRegime.RANGING_BEARISH
        r_1d, r_4h, r_1h = get_regime(data_1d), get_regime(data_4h), get_regime(data_1h)
        bullish_tfs = sum(1 for r in [r_1d, r_4h, r_1h] if r in [MarketRegime.STRONG_UPTREND, MarketRegime.WEAK_UPTREND])
        bearish_tfs = sum(1 for r in [r_1d, r_4h, r_1h] if r in [MarketRegime.STRONG_DOWNTREND, MarketRegime.WEAK_DOWNTREND])
        if bullish_tfs == 3: confluence, weight = "STRONG_BULLISH", 1.0
        elif bullish_tfs == 2: confluence, weight = "MODERATE_BULLISH", 0.7
        elif bearish_tfs == 3: confluence, weight = "STRONG_BEARISH", 1.0
        elif bearish_tfs == 2: confluence, weight = "MODERATE_BEARISH", 0.7
        else: confluence, weight = "MIXED", 0.3
        return MTFAnalysis(confluence=confluence, weight=weight, daily_bias=r_1d.value, h4_setup=r_4h.value, h1_entry=r_1h.value)


def calculate_position_size(balance: float, risk_percentage: float, entry_price: float, stop_loss_price: float, symbol: str) -> dict:
    spec = INSTRUMENT_SPECS.get(symbol.upper())
    if not spec: return {"error": f"Instrument {symbol} not found in database"}
    risk_amount = balance * (risk_percentage / 100)
    sl_distance = abs(entry_price - stop_loss_price)
    if sl_distance == 0: return {"error": "Stop loss equals entry price"}
    raw_lot = risk_amount / (sl_distance * spec.contract_size)
    adjusted_lot = round(raw_lot / spec.lot_step) * spec.lot_step
    if adjusted_lot < spec.min_lot:
        return {"error": f"Calculated lot ({adjusted_lot}) is below broker minimum ({spec.min_lot})",
                "suggestion": f"Minimum lot would risk {((spec.min_lot * sl_distance * spec.contract_size) / balance) * 100:.2f}% instead of {risk_percentage}%",
                "min_lot": spec.min_lot}
    if adjusted_lot > spec.max_lot: adjusted_lot = spec.max_lot
    margin_required = (adjusted_lot * spec.contract_size * entry_price) / spec.leverage
    return {"success": True, "symbol": symbol, "lot_size": round(adjusted_lot, 3),
            "risk_amount_usd": round(risk_amount, 2), "sl_distance": round(sl_distance, 4),
            "margin_required": round(margin_required, 2), "leverage": spec.leverage,
            "risk_percentage_actual": round((sl_distance * spec.contract_size * adjusted_lot) / balance * 100, 2)}


class ConfluenceEngine:
    BASE_WEIGHTS = {"trend": 0.18, "structure": 0.15, "momentum": 0.17, "smc": 0.20,
                    "volume": 0.12, "divergence": 0.10, "pattern": 0.08}

    @staticmethod
    def gauss_decay(dist: float, sigma: float) -> float:
        if sigma <= 1e-12: return 0.0
        return math.exp(-0.5 * (abs(dist) / sigma) ** 2)

    @staticmethod
    def sigmoid(x: float, k: float = 0.08, mid: float = 40.0) -> float:
        return 100.0 / (1.0 + math.exp(-k * (x - mid)))

    @staticmethod
    def atr_percentile_rank(closes: np.ndarray, highs: np.ndarray, lows: np.ndarray, lookback: int = 120) -> float:
        n = len(closes)
        if n < 40 or highs is None or lows is None or len(highs) != n: return 50.0
        tr = np.maximum(highs[1:] - lows[1:], np.maximum(np.abs(highs[1:] - closes[:-1]), np.abs(lows[1:] - closes[:-1])))
        p = 14
        if len(tr) < p + 10: return 50.0
        atr_pct = [float(np.mean(tr[i-p:i])) / (closes[i+1] + 1e-10) * 100.0 for i in range(p, len(tr))]
        if len(atr_pct) < 10: return 50.0
        win, cur = atr_pct[-lookback:], atr_pct[-1]
        return round(float(np.mean([a <= cur for a in win])) * 100.0, 1)

    @staticmethod
    def score_trend(closes: np.ndarray, atr: float) -> Tuple[float, List[str]]:
        if len(closes) < 200 or atr <= 0: return 0.0, []
        e20, e50, e200 = MathEngine._ema(closes, 20)[-1], MathEngine._ema(closes, 50)[-1], MathEngine._ema(closes, 200)[-1]
        cur = closes[-1]; score, reasons = 0.0, []
        if e20 > e50 > e200: score += 40; reasons.append("EMA 20>50>200 bullish stack")
        elif e20 < e50 < e200: score -= 40; reasons.append("EMA 20<50<200 bearish stack")
        score += 20 if cur > e200 else -20
        e50_arr = MathEngine._ema(closes, 50)
        slope = (e50_arr[-1] - e50_arr[-11]) / (atr * 10.0)
        score += float(np.clip(slope * 40, -40, 40))
        if abs(slope) > 0.3: reasons.append(f"EMA50 slope {'up' if slope > 0 else 'down'} ({slope:.2f}×ATR/10bars)")
        return float(np.clip(score, -100, 100)), reasons

    @staticmethod
    def score_structure(closes: np.ndarray, atr: float) -> Tuple[float, List[str]]:
        if len(closes) < 60 or atr <= 0: return 0.0, []
        ri, si = argrelextrema(closes, np.greater, order=5)[0], argrelextrema(closes, np.less, order=5)[0]
        if len(ri) < 3 or len(si) < 3: return 0.0, []
        h1, h2, h3 = [float(closes[i]) for i in ri[-3:]]
        l1, l2, l3 = [float(closes[i]) for i in si[-3:]]
        score, reasons = 0.0, []
        def mag(a, b): return float(np.clip(abs(a - b) / (atr + 1e-10), 0.0, 2.0)) / 2.0
        if h3 > h2: score += 25 * (0.5 + 0.5 * mag(h3, h2)); reasons.append("Higher High")
        elif h3 < h2: score -= 25 * (0.5 + 0.5 * mag(h2, h3)); reasons.append("Lower High")
        if l3 > l2: score += 25 * (0.5 + 0.5 * mag(l3, l2)); reasons.append("Higher Low")
        elif l3 < l2: score -= 25 * (0.5 + 0.5 * mag(l2, l3)); reasons.append("Lower Low")
        cur = closes[-1]
        if cur > h3: score += 20; reasons.append("BOS: close above last swing high")
        elif cur < l3: score -= 20; reasons.append("BOS: close below last swing low")
        return float(np.clip(score, -100, 100)), reasons

    @staticmethod
    def score_momentum(closes: np.ndarray, volumes: np.ndarray, atr: float) -> Tuple[float, List[str]]:
        if len(closes) < 60 or atr <= 0: return 0.0, []
        score, reasons = 0.0, []
        rsi = MathEngine._calc_rsi(closes, 14)
        if 55 <= rsi <= 72: score += 25; reasons.append(f"RSI bullish momentum ({rsi:.0f})")
        elif 28 <= rsi <= 45: score -= 25; reasons.append(f"RSI bearish momentum ({rsi:.0f})")
        elif rsi > 78: score -= 10; reasons.append(f"RSI overbought ({rsi:.0f})")
        elif rsi < 22: score += 10; reasons.append(f"RSI oversold ({rsi:.0f})")
        _, _, hist = MathEngine._calc_macd(closes)
        hist_n = hist / (atr + 1e-10)
        score += float(np.clip(hist_n * 60, -30, 30))
        if hist_n > 0.05: reasons.append("MACD histogram positive")
        elif hist_n < -0.05: reasons.append("MACD histogram negative")
        vwap, vu, vl, _ = MathEngine._calc_vwap(closes, volumes)
        dev = (vu - vwap) / 2.0 + 1e-10
        z = (closes[-1] - vwap) / dev
        score += float(np.clip(z * 15, -25, 25))
        if z > 0.5: reasons.append("Price above VWAP")
        elif z < -0.5: reasons.append("Price below VWAP")
        k, d = MathEngine._calc_stoch(closes)
        if k > d and k < 80: score += 10
        elif k < d and k > 20: score -= 10
        roc = (closes[-1] - closes[-11]) / (atr * 10 + 1e-10)
        score += float(np.clip(roc * 20, -10, 10))
        return float(np.clip(score, -100, 100)), reasons

    @staticmethod
    def score_smc(opens: np.ndarray, highs: np.ndarray, lows: np.ndarray, closes: np.ndarray, volumes: np.ndarray, atr: float) -> Tuple[float, List[str]]:
        if len(closes) < 60 or atr <= 0: return 0.0, []
        cur = float(closes[-1]); score, reasons = 0.0, []
        for ob in MathEngine._detect_obs(closes, cur):
            mid = (ob["high"] + ob["low"]) / 2.0
            dist = cur - mid
            prox = ConfluenceEngine.gauss_decay(abs(dist), atr * 2.0)
            w = min(ob["strength"], 100) / 100.0
            if ob["type"].startswith("BULLISH") and dist > 0:
                score += 30 * w * prox
                if prox > 0.3: reasons.append("Price above fresh Bullish OB (demand)")
            elif ob["type"].startswith("BEARISH") and dist < 0:
                score -= 30 * w * prox
                if prox > 0.3: reasons.append("Price below fresh Bearish OB (supply)")
        for f in MathEngine._detect_fvgs(closes, cur):
            mid = (f["high"] + f["low"]) / 2.0
            prox = ConfluenceEngine.gauss_decay(abs(cur - mid), atr * 2.5)
            if f["type"].startswith("BULLISH") and cur > mid:
                score += 20 * prox
                if prox > 0.3: reasons.append("Unfilled Bullish FVG below price (support)")
            elif f["type"].startswith("BEARISH") and cur < mid:
                score -= 20 * prox
                if prox > 0.3: reasons.append("Unfilled Bearish FVG above price (resistance)")
        for s in MathEngine._detect_liquidity_sweeps(closes, cur):
            if s["bias"] == "BUY": score += 25; reasons.append("Recent bullish liquidity sweep (stop hunt low)")
            else: score -= 25; reasons.append("Recent bearish liquidity sweep (stop hunt high)")
        return float(np.clip(score, -100, 100)), reasons

    @staticmethod
    def score_volume(closes: np.ndarray, volumes: np.ndarray, atr: float) -> Tuple[float, List[str]]:
        if len(closes) < 40 or atr <= 0 or volumes is None or len(volumes) < 20: return 0.0, []
        vp = VolumeProfileAnalyzer.calculate_volume_profile(closes, volumes)
        cur, poc = float(closes[-1]), vp["poc_price"]
        score, reasons = 0.0, []
        d_poc = (cur - poc) / (atr + 1e-10)
        score += float(np.clip(d_poc * 20, -40, 40))
        if abs(d_poc) < 0.5: reasons.append("Price at POC — auction balance")
        elif d_poc > 0: reasons.append("Price above POC (buyer control)")
        else: reasons.append("Price below POC (seller control)")
        va_range = vp["value_area_high"] - vp["value_area_low"]
        if vp["value_area_low"] <= cur <= vp["value_area_high"] and va_range > 1e-10:
            pos = (cur - vp["value_area_low"]) / va_range
            score += float((pos - 0.5) * 40)
        else:
            score *= 0.8
        half = max(10, len(volumes) // 4)
        v1 = float(np.mean(volumes[-half:]))
        v0 = float(np.mean(volumes[-2*half:-half])) if len(volumes) >= 2*half else v1
        vtrend = (v1 - v0) / (v0 + 1e-10)
        if vtrend > 0.15 and d_poc > 0: score += 20; reasons.append("Rising volume with price above POC")
        elif vtrend > 0.15 and d_poc < 0: score -= 20; reasons.append("Rising volume with price below POC")
        return float(np.clip(score, -100, 100)), reasons

    @staticmethod
    def score_divergence(closes: np.ndarray) -> Tuple[float, List[str]]:
        rsi_d, macd_d, signal, strength = MathEngine._detect_divergence(closes)
        if signal == "NONE": return 0.0, []
        sign = 1.0 if "BULLISH" in signal else -1.0
        return float(sign * strength), [f"{signal} (strength {strength:.0f})"]

    @staticmethod
    def score_pattern(closes: np.ndarray) -> Tuple[float, List[str]]:
        pat, strength, direction, expl = MathEngine._detect_candle_patterns(closes)
        if pat == "NONE" or direction == "NEUTRAL": return 0.0, []
        sign = 1.0 if direction == "BULLISH" else -1.0
        return float(sign * strength), [f"{pat} confirmed"]

    @staticmethod
    def regime_weights(regime: MarketRegime) -> Dict[str, float]:
        if regime in (MarketRegime.STRONG_UPTREND, MarketRegime.WEAK_UPTREND, MarketRegime.STRONG_DOWNTREND, MarketRegime.WEAK_DOWNTREND):
            return {"trend": 0.22, "structure": 0.18, "momentum": 0.18, "smc": 0.16, "volume": 0.10, "divergence": 0.08, "pattern": 0.08}
        if regime in (MarketRegime.RANGING_BULLISH, MarketRegime.RANGING_BEARISH, MarketRegime.MEAN_REVERTING):
            return {"trend": 0.10, "structure": 0.10, "momentum": 0.14, "smc": 0.22, "volume": 0.20, "divergence": 0.14, "pattern": 0.10}
        return {"trend": 0.12, "structure": 0.12, "momentum": 0.16, "smc": 0.20, "volume": 0.16, "divergence": 0.12, "pattern": 0.12}


class MultiLayerSignalEngine:
    @staticmethod
    def generate_signal(opens: np.ndarray, highs: np.ndarray, lows: np.ndarray, closes: np.ndarray,
                        volumes: np.ndarray, symbol: str, initial_balance: float = 10000.0,
                        risk_per_trade: float = 1.0, mtf_data: Optional[dict] = None) -> MarketIntelligence:
        """
        FIX[4]: NEVER raises. Insufficient / invalid input, or any internal error, returns a safe
        NEUTRAL / "WAIT" / data_source="INSUFFICIENT DATA" object (the old code raised ValueError).
        """
        cfg = ASSET_MAP.get(symbol)
        try:
            arrays = [opens, highs, lows, closes, volumes]
            if any(a is None for a in arrays):
                return _safe_mi(cfg, "", "Missing OHLCV arrays")
            o, h, l, c, v = (MathEngine._clean(a) for a in arrays)       # FIX[3]
            n = min(len(o), len(h), len(l), len(c), len(v))
            if n < MULTILAYER_MIN_BARS:
                return _safe_mi(cfg, "", f"Only {n} valid candles (need {MULTILAYER_MIN_BARS})")
            o, h, l, c, v = o[-n:], h[-n:], l[-n:], c[-n:], v[-n:]
            mi = MultiLayerSignalEngine._generate_signal_impl(
                o, h, l, c, v, symbol, initial_balance, risk_per_trade, mtf_data)
            return _clean_value(mi)                                       # FIX[3]: JSON-safe output
        except Exception:
            logger.exception(f"❌ Multi-layer signal failure for {symbol}")
            return _safe_mi(cfg, "", "Signal engine error — see server log")

    @staticmethod
    def _generate_signal_impl(opens: np.ndarray, highs: np.ndarray, lows: np.ndarray, closes: np.ndarray,
                              volumes: np.ndarray, symbol: str, initial_balance: float,
                              risk_per_trade: float, mtf_data: Optional[dict]) -> MarketIntelligence:
        cur, atr = float(closes[-1]), MathEngine._calc_atr(closes, 14, highs, lows)
        if atr <= 0: atr = cur * 0.005
        vol_pctile = ConfluenceEngine.atr_percentile_rank(closes, highs, lows)
        ema_20, ema_50 = MathEngine._ema(closes, 20), MathEngine._ema(closes, 50)
        trend_strength = min(np.abs(ema_20[-1] - ema_50[-1]) / cur * 100, 100)
        p_ema20, p_ema50, ema_trend = cur > ema_20[-1], cur > ema_50[-1], ema_20[-1] > ema_50[-1]
        if vol_pctile > 85: regime = MarketRegime.HIGH_VOLATILITY
        elif vol_pctile < 20: regime = MarketRegime.LOW_VOLATILITY
        elif p_ema20 and p_ema50 and ema_trend:
            regime = MarketRegime.STRONG_UPTREND if trend_strength > 60 else MarketRegime.WEAK_UPTREND
        elif not p_ema20 and not p_ema50 and not ema_trend:
            regime = MarketRegime.STRONG_DOWNTREND if trend_strength > 60 else MarketRegime.WEAK_DOWNTREND
        else:
            regime = MarketRegime.RANGING_BULLISH if p_ema50 else MarketRegime.RANGING_BEARISH

        layer_scores: Dict[str, float] = {}
        all_reasons: List[str] = []
        s, r = ConfluenceEngine.score_trend(closes, atr); layer_scores["trend"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_structure(closes, atr); layer_scores["structure"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_momentum(closes, volumes, atr); layer_scores["momentum"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_smc(opens, highs, lows, closes, volumes, atr); layer_scores["smc"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_volume(closes, volumes, atr); layer_scores["volume"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_divergence(closes); layer_scores["divergence"] = s; all_reasons += r
        s, r = ConfluenceEngine.score_pattern(closes); layer_scores["pattern"] = s; all_reasons += r

        weights = ConfluenceEngine.regime_weights(regime)
        total = float(sum(layer_scores[k] * weights[k] for k in weights))
        bull_layers = int(sum(1 for v in layer_scores.values() if v >= 25))
        bear_layers = int(sum(1 for v in layer_scores.values() if v <= -25))
        if bull_layers >= 2 and bear_layers >= 2:
            total *= 0.6; all_reasons.append(f"Layer conflict ({bull_layers}B/{bear_layers}S) — score damped")
        if bull_layers >= 4 and total > 0:
            total = min(100.0, total * 1.2 + 5); all_reasons.append(f"{bull_layers}-layer bullish confluence bonus")
        if bear_layers >= 4 and total < 0:
            total = max(-100.0, total * 1.2 - 5); all_reasons.append(f"{bear_layers}-layer bearish confluence bonus")

        vp_data = VolumeProfileAnalyzer.calculate_volume_profile(closes, volumes)
        ob_data = VolumeProfileAnalyzer.detect_order_blocks(opens, highs, lows, closes)
        volume_profile_stats = VolumeProfileStats(
            poc_price=vp_data["poc_price"], value_area_high=vp_data["value_area_high"],
            value_area_low=vp_data["value_area_low"],
            bullish_order_block=ob_data["bullish_order_block"], bearish_order_block=ob_data["bearish_order_block"])

        mtf_stats = None
        if mtf_data:
            mtf_stats = MultiTimeframeEngine.analyze_mtf(mtf_data['1h'], mtf_data['4h'], mtf_data['1d'])
            total *= mtf_stats.weight
            if mtf_stats.confluence in ("STRONG_BULLISH", "MODERATE_BULLISH"): total += 8
            elif mtf_stats.confluence in ("STRONG_BEARISH", "MODERATE_BEARISH"): total -= 8
            all_reasons.append(f"MTF Confluence: {mtf_stats.confluence}")

        total = float(np.clip(total, -100, 100))
        if total > 55: signal = SignalDirection.STRONG_BUY
        elif total > 25: signal = SignalDirection.BUY
        elif total > 10: signal = SignalDirection.WEAK_BUY
        elif total < -55: signal = SignalDirection.STRONG_SELL
        elif total < -25: signal = SignalDirection.SELL
        elif total < -10: signal = SignalDirection.WEAK_SELL
        else: signal = SignalDirection.NEUTRAL

        confidence = round(ConfluenceEngine.sigmoid(abs(total)), 1)
        if signal == SignalDirection.NEUTRAL: confidence = min(confidence, 45.0)
        est_wr = round(float(np.clip(0.30 + 0.45 * (confidence / 100.0), 0.25, 0.72)), 3)

        is_buy = signal in (SignalDirection.STRONG_BUY, SignalDirection.BUY, SignalDirection.WEAK_BUY)
        is_sell = signal in (SignalDirection.STRONG_SELL, SignalDirection.SELL, SignalDirection.WEAK_SELL)
        entry = cur; atr_sl_dist = 1.5 * atr

        si, ri = argrelextrema(closes, np.less, order=5)[0], argrelextrema(closes, np.greater, order=5)[0]
        if is_buy:
            sl = entry - atr_sl_dist
            if len(si): sl = min(sl, float(closes[si[-1]]) - 0.3 * atr)
            risk = max(entry - sl, 1e-9); tp1, tp2 = entry + risk * 2.0, entry + risk * 3.0
        elif is_sell:
            sl = entry + atr_sl_dist
            if len(ri): sl = max(sl, float(closes[ri[-1]]) + 0.3 * atr)
            risk = max(sl - entry, 1e-9); tp1, tp2 = entry - risk * 2.0, entry - risk * 3.0
        else:
            sl, risk = entry - atr_sl_dist, atr_sl_dist; tp1, tp2 = entry + risk * 2.0, entry + risk * 3.0
        rr = round((abs(tp1 - entry) / risk), 2)

        risk_amount = initial_balance * (risk_per_trade / 100)
        proxy_delta = MathEngine.estimate_proxy_delta(opens, highs, lows, closes, volumes)
        avg_win, avg_loss = risk_amount * rr, risk_amount
        expectancy = MathEngine.calculate_expectancy(est_wr, avg_win, avg_loss)
        avg_atr = MathEngine._calc_atr(closes, 50, highs, lows)
        adj_risk = MathEngine.volatility_adjusted_risk(risk_per_trade, atr, avg_atr)
        mc_stats = MonteCarloRiskEngine.simulate_trades(win_rate=est_wr, rr_ratio=rr,
                                                        risk_amount=risk_amount, initial_balance=initial_balance)

        all_reasons.append(f"Market Regime: {regime.value}")
        all_reasons.append(f"Volatility Percentile: {vol_pctile:.0f}%")

        risk_dist = abs(entry - sl)
        tp3 = round(entry + risk_dist * 3.0, 4) if is_buy else round(entry - risk_dist * 3.0, 4)
        quality = "EXCELLENT" if confidence >= 80 and (bull_layers >= 3 or bear_layers >= 3) else \
                  "GOOD" if confidence >= 65 else "FAIR" if confidence >= 50 else "POOR"

        reasoning = f"Multi-layer confluence: {bull_layers} bullish, {bear_layers} bearish layers. "
        reasoning += f"Market regime: {regime.value}. Volatility: {vol_pctile}th percentile. "
        if proxy_delta["delta_signal"] != "NEUTRAL":
            reasoning += f"Order flow: {proxy_delta['delta_signal'].replace('_', ' ')} ({proxy_delta['buying_pressure']}% buying). "
        reasoning += " ".join(all_reasons[:3])

        invalidation = f"Price closing below {sl} invalidates the long setup." if is_buy else f"Price closing above {sl} invalidates the short setup."
        # FIX[5]: the old code built a dummy AssetConfig (is_24_7=False) here, so crypto got the wrong session label.
        _cfg = ASSET_MAP.get(symbol)
        session = MathEngine._get_session(_cfg)[0] if _cfg else "UNKNOWN"

        mi = MarketIntelligence()
        mi.current_price = round(cur, 4)
        mi.signal_confidence = round(confidence, 1)
        mi.confidence_label = "STRONG" if confidence > 70 else "MODERATE" if confidence > 50 else "WEAK" if confidence > 30 else "NEUTRAL"
        mi.direction = signal.value
        mi.signal_reasons = all_reasons
        mi.regime_advanced = regime.value
        mi.monte_carlo = mc_stats
        mi.volume_profile = volume_profile_stats
        mi.mtf_analysis = mtf_stats
        mi.layer_scores = {k: round(v, 1) for k, v in layer_scores.items()}
        mi.confluence_bull_layers = bull_layers
        mi.confluence_bear_layers = bear_layers
        mi.volatility_percentile = vol_pctile
        mi.estimated_win_rate = est_wr

        mi.trade_plan = {
            "valid": True,
            "direction": signal.value,
            "directionRaw": signal.value,
            "entry": round(entry, 4),
            "sl": round(sl, 4),
            "tp1": round(tp1, 4),
            "tp2": round(tp2, 4),
            "tp3": tp3,
            "rr1": rr,
            "rr2": round(rr * 1.5, 2),
            "confidence": round(confidence, 1),
            "quality": quality,
            "reasoning": reasoning.strip(),
            "invalidation": invalidation,
            "session": session,
            "regime": regime.value,
            "newsRisk": "NORMAL",
            "probScore": round(confidence, 1),
            "mtf": mtf_stats.confluence if mtf_stats else "NEUTRAL",
            "positionNote": "Institutional grade setup" if quality in ["EXCELLENT", "GOOD"] else "Monitor for better entry",
            "estimatedWinRate": est_wr,
            "expectancyPerDollar": round(expectancy / risk_amount, 3) if risk_amount > 0 else 0.0,
            "volatilityAdjustedRiskPct": adj_risk,
            "layerScores": {k: round(v, 1) for k, v in layer_scores.items()},
            "bullLayers": bull_layers,
            "bearLayers": bear_layers,
            "reasons": all_reasons,
            "proxyOrderFlow": proxy_delta,
            "riskPerUnit": 0.0,
            "riskPips": 0.0
        }
        return mi


def analyze(prices: List[float], cfg: AssetConfig, atr_mult: float = 1.5, rr_ratio: float = 2.5,
            news_schedule: Optional[List[Dict]] = None, ohlcv: Optional[Dict] = None,
            initial_balance: float = 10000.0, risk_per_trade: float = 1.0,
            timeframe: str = "M5") -> MarketIntelligence:
    """
    FIX[4]: ALWAYS returns a MarketIntelligence (never None, never raises).
    Missing / insufficient / corrupt data -> NEUTRAL, safety_signal="WAIT",
    data_source="INSUFFICIENT DATA".

    `ohlcv` is the single source of truth; `prices` is only used for the early length check
    (the closes are re-read from the sanitized OHLCV so all arrays are guaranteed aligned).
    """
    try:
        if ohlcv is None:
            logger.warning(f"⚠️ analyze({cfg.symbol}): no OHLCV supplied")
            return _safe_mi(cfg, timeframe, f"No {timeframe} candle data available")
        if not prices or len(prices) < MIN_BARS:
            logger.warning(f"⚠️ Not enough bars for {cfg.symbol}: {len(prices) if prices else 0}")
            return _safe_mi(cfg, timeframe, f"Only {len(prices) if prices else 0} {timeframe} candles (need {MIN_BARS})")

        # FIX[2]: defence-in-depth — even if a caller passes raw data, it is sanitized here again.
        clean = sanitize_ohlcv(ohlcv)
        if clean is None:
            return _safe_mi(cfg, timeframe, f"{timeframe} candles failed validation or fewer than {MIN_BARS} valid bars")

        opens = np.array(clean["open"], dtype=float)
        highs = np.array(clean["high"], dtype=float)
        lows = np.array(clean["low"], dtype=float)
        volumes = np.array(clean["volume"], dtype=float)
        p = np.array(clean["close"], dtype=float)
        cur = float(p[-1])

        mi = MarketIntelligence()
        mi.asset_name, mi.asset_type = cfg.name, cfg.asset_type
        mi.last_update = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        mi.current_price = round(cur, 4)
        mi.prices = p[-250:].tolist()
        mi.timeframe = timeframe
        mi.price_change = round(cur - float(p[-2]), 4)
        mi.price_change_pct = round(mi.price_change / float(p[-2]) * 100, 3) if float(p[-2]) else 0.0

        e9, e21, e50, e200 = [MathEngine._ema(p, n) for n in [9, 21, 50, 200]]
        mi.ema9 = round(MathEngine._last_finite(e9, cur), 4)
        mi.ema21 = round(MathEngine._last_finite(e21, cur), 4)
        mi.ema50 = round(MathEngine._last_finite(e50, cur), 4)
        mi.ema200 = round(MathEngine._last_finite(e200, cur), 4)
        mi.ema_alignment = "BULLISH STACK" if mi.ema9 > mi.ema21 > mi.ema50 else "BEARISH STACK" if mi.ema9 < mi.ema21 < mi.ema50 else "MIXED"
        mi.rsi = MathEngine._calc_rsi(p)
        mi.rsi_signal = "OVERBOUGHT" if mi.rsi > 70 else "OVERSOLD" if mi.rsi < 30 else "NEUTRAL"
        mi.rsi_explanation = (f"RSI(14) at {mi.rsi:.1f} on {timeframe}: " +
            ("overbought — momentum stretched, watch for pullback." if mi.rsi > 70
             else "oversold — downside stretched, watch for bounce." if mi.rsi < 30
             else "neutral zone — momentum balanced."))
        mi.macd_line, mi.macd_signal, mi.macd_hist = MathEngine._calc_macd(p)
        mi.macd_cross = "BULLISH" if mi.macd_hist > 0 else "BEARISH" if mi.macd_hist < 0 else "NEUTRAL"
        mi.stoch_k, mi.stoch_d = MathEngine._calc_stoch(p)
        mi.stoch_signal = "OVERBOUGHT" if mi.stoch_k > 80 else "OVERSOLD" if mi.stoch_k < 20 else "NEUTRAL"
        mi.bb_upper, mi.bb_mid, mi.bb_lower, mi.bb_width = MathEngine._calc_bb(p)
        mi.bb_position = "ABOVE UPPER" if cur >= mi.bb_upper else "BELOW LOWER" if cur <= mi.bb_lower else "UPPER HALF" if cur > mi.bb_mid else "LOWER HALF"
        mi.kc_upper, mi.kc_mid, mi.kc_lower = MathEngine._calc_keltner(p)
        mi.ttm_squeeze_active, mi.ttm_squeeze_label, mi.ttm_momentum = MathEngine._calc_ttm_squeeze(p)
        mi.adx_value, mi.adx_di_plus, mi.adx_di_minus = MathEngine._calc_adx(p)
        mi.adx_signal = "STRONG" if mi.adx_value > 25 else "MODERATE" if mi.adx_value > 18 else "WEAK"
        mi.williams_r = MathEngine._calc_williams_r(p)
        mi.williams_signal = "OVERBOUGHT" if mi.williams_r > -20 else "OVERSOLD" if mi.williams_r < -80 else "NEUTRAL"
        mi.cci_value = MathEngine._calc_cci(p)
        mi.cci_signal = "OVERBOUGHT" if mi.cci_value > 100 else "OVERSOLD" if mi.cci_value < -100 else "NEUTRAL"
        mi.obv_value, mi.obv_trend = MathEngine._calc_obv(p, volumes)
        mi.ichimoku_signal, mi.tenkan, mi.kijun = MathEngine._calc_ichimoku(p)
        mi.atr_14 = round(MathEngine._calc_atr(p, 14, highs, lows), 4)
        mi.atr_multiplier, mi.rr_ratio = atr_mult, rr_ratio
        mi.sl_buy, mi.sl_sell, mi.tp_buy, mi.tp_sell, mi.sl_pips, mi.atr_explanation = MathEngine._build_stops(cur, mi.atr_14, atr_mult, rr_ratio, cfg)
        mi.supertrend_value, mi.supertrend_signal, _ = MathEngine._calc_supertrend(p, highs, lows)
        mi.supertrend_direction = mi.supertrend_signal
        mi.vwap, mi.vwap_upper, mi.vwap_lower, mi.vwap_signal = MathEngine._calc_vwap(p, volumes)
        mi.pivot_points = MathEngine._calc_pivot_points(p, highs, lows)
        mi.zscore, mi.zscore_signal = MathEngine._calc_zscore(p)
        mi.hurst, mi.regime = MathEngine._calc_hurst(p)
        mi.shannon_entropy = MathEngine._calc_entropy(p)
        mi.kaufman_er = MathEngine._calc_ker(p)
        mi.fractal_dim = MathEngine._calc_fractal_dim(p)
        returns = np.diff(p) / (p[:-1] + 1e-10) * 100
        mi.realized_vol = round(float(np.std(returns) * math.sqrt(252 * 78)), 2)
        mi.vol_regime = "EXTREME" if mi.realized_vol > 40 else "HIGH" if mi.realized_vol > 20 else "NORMAL" if mi.realized_vol > 8 else "LOW"
        mi.regime_advanced = MathEngine._detect_regime_advanced(p, mi.hurst, mi.adx_value, mi.vol_regime, mi.bb_width)
        mi.supports, mi.resistances, mi.nearest_support, mi.nearest_resist, mi.sr_zone = MathEngine._calc_sr(p, cur)
        wave = MathEngine._detect_elliott(p)
        mi.wave_position, mi.wave_confidence, mi.wave_target, mi.wave_trend = wave.get("position", "UNKNOWN"), wave.get("confidence", 0.0), wave.get("target"), wave.get("trend", "NEUTRAL")
        mi.fib_retracements, mi.fib_extensions, mi.fib_zone, mi.fib_strength, mi.fib_explanation = MathEngine._calc_fib(p, cur)
        mi.order_blocks = MathEngine._detect_obs(p, cur)
        mi.fair_value_gaps = MathEngine._detect_fvgs(p, cur)
        mi.liquidity_sweeps = MathEngine._detect_liquidity_sweeps(p, cur)
        mi.rsi_divergence, mi.macd_divergence, mi.divergence_signal, mi.divergence_strength = MathEngine._detect_divergence(p)
        mi.candle_pattern, mi.candle_strength, mi.candle_direction, mi.candle_explanation = MathEngine._detect_candle_patterns(p)
        mi.trading_session, mi.session_liquidity, mi.session_warning, mi.session_explanation = MathEngine._get_session(cfg)

        bull, bear = 0, 0
        if cur > mi.ema50: bull += 2
        else: bear += 2
        if cur > mi.ema200: bull += 2
        else: bear += 2
        if mi.ema_alignment == "BULLISH STACK": bull += 3
        elif mi.ema_alignment == "BEARISH STACK": bear += 3
        if mi.supertrend_signal == "BULLISH": bull += 3
        elif mi.supertrend_signal == "BEARISH": bear += 3
        if mi.rsi < 30: bull += 2
        elif mi.rsi > 70: bear += 2
        if mi.macd_hist > 0: bull += 2
        elif mi.macd_hist < 0: bear += 2
        mi.bull_score, mi.bear_score = bull, bear
        total = bull + bear
        bull_pct = bull / total * 100 if total > 0 else 50
        mi.probability_bull = round(bull_pct, 1)
        mi.probability_label = "STRONGLY BULLISH" if bull_pct >= 72 else "BULLISH" if bull_pct >= 60 else "NEUTRAL" if bull_pct >= 40 else "BEARISH" if bull_pct >= 28 else "STRONGLY BEARISH"

        # FIX[4]: multi-layer needs >= 100 candles. With 60-99 candles the classic indicators above
        # are still valid, so we keep them and simply leave the direction NEUTRAL (old code threw
        # ValueError here and the ENTIRE analysis was lost).
        if len(p) >= MULTILAYER_MIN_BARS:
            ml = MultiLayerSignalEngine.generate_signal(
                opens, highs, lows, closes=p, volumes=volumes, symbol=cfg.symbol,
                initial_balance=initial_balance, risk_per_trade=risk_per_trade)
            if ml.data_source != INSUFFICIENT_DATA:
                mi.signal_confidence = ml.signal_confidence
                mi.confidence_label = ml.confidence_label
                mi.direction = ml.direction
                mi.signal_reasons = ml.signal_reasons
                mi.monte_carlo = ml.monte_carlo
                mi.volume_profile = ml.volume_profile
                mi.mtf_analysis = ml.mtf_analysis
                mi.layer_scores = ml.layer_scores
                mi.confluence_bull_layers = ml.confluence_bull_layers
                mi.confluence_bear_layers = ml.confluence_bear_layers
                mi.volatility_percentile = ml.volatility_percentile
                mi.estimated_win_rate = ml.estimated_win_rate
                if ml.trade_plan: mi.trade_plan = ml.trade_plan
            else:
                mi.signal_reasons = list(ml.signal_reasons)
        else:
            mi.signal_reasons = [f"Multi-layer engine skipped: {len(p)} candles (need {MULTILAYER_MIN_BARS})"]

        mi.kelly_fraction, mi.kelly_recommendation = MathEngine._calc_kelly(mi.estimated_win_rate, rr_ratio)

        buy_dir = mi.direction in ("strong_buy", "buy", "weak_buy")
        sell_dir = mi.direction in ("strong_sell", "sell", "weak_sell")
        macro_risk = NewsEngine.check_macro_event_risk(news_schedule or [])

        if macro_risk["risk_level"] == "EXTREME":
            mi.safety_signal, mi.signal_color, mi.entry_quality = f"WAIT — {macro_risk['reason']}", "#FF0000", "EXTREME_RISK"
        elif mi.session_liquidity == "LOW":
            mi.safety_signal, mi.signal_color, mi.entry_quality = "WAIT — LOW LIQUIDITY", "#FFD600", "POOR"
        elif mi.ttm_squeeze_active:
            mi.safety_signal, mi.signal_color, mi.entry_quality = "WAIT — TTM SQUEEZE", "#FF9800", "FAIR"
        elif buy_dir and mi.signal_confidence >= 65 and mi.confluence_bull_layers >= 3 and mi.adx_value > 18:
            mi.safety_signal, mi.signal_color, mi.signal_strength, mi.direction, mi.entry_quality = "BUY SAFE", "#00FF88", int(mi.signal_confidence), "BULLISH", "EXCELLENT" if mi.signal_confidence >= 80 else "GOOD"
        elif sell_dir and mi.signal_confidence >= 65 and mi.confluence_bear_layers >= 3 and mi.adx_value > 18:
            mi.safety_signal, mi.signal_color, mi.signal_strength, mi.direction, mi.entry_quality = "SELL SAFE", "#FF3131", int(mi.signal_confidence), "BEARISH", "EXCELLENT" if mi.signal_confidence >= 80 else "GOOD"
        elif 45 <= bull_pct <= 55:
            mi.safety_signal, mi.signal_color, mi.entry_quality = "WAIT — NO CONFLUENCE", "#666666", "POOR"
        else:
            mi.safety_signal, mi.signal_color, mi.entry_quality = "WAIT", "#FFD600", "FAIR"

        # FIX[3]: final guarantee — no NaN/Inf/numpy types ever leave the engine (JSON-safe).
        return _clean_value(mi)
    except Exception:
        logger.exception(f"❌ Analysis exception for {cfg.symbol}")
        return _safe_mi(cfg, timeframe, "Analysis error — see server log")


def get_correlation_matrix() -> Dict[str, Dict[str, float]]:
    # Intentionally DAILY: correlation is a long-horizon statistic, not an intraday signal.
    try:
        import yfinance as yf, pandas as pd
        tickers = {cfg.symbol: cfg.yf_ticker for cfg in ALL_ASSETS}
        data: Dict[str, Any] = {}
        for sym, ticker in tickers.items():
            df = yf.download(ticker, period="30d", interval="1d", progress=False, auto_adjust=True)
            if df is not None and not df.empty:
                col = df["Close"]
                if isinstance(col, pd.DataFrame): col = col.iloc[:, 0]
                data[sym] = col.pct_change().dropna()
        if len(data) < 2: return {}
        df_c = pd.DataFrame(data).corr()
        return {sym1: {sym2: round(float(df_c.loc[sym1, sym2]), 3) for sym2 in df_c.columns if sym2 in df_c.index} for sym1 in df_c.index}
    except Exception:
        return {}


def run_analysis(cfg: AssetConfig, atr_mult: float = 1.5, rr_ratio: float = 2.5, run_mtf: bool = False,
                 initial_balance: float = 10000.0, risk_per_trade: float = 1.0, fetch_news: bool = True,
                 timeframe: str = "M5") -> Tuple[Optional[MarketIntelligence], List[NewsItem], str]:
    """
    FIX[4]: the first element is now ALWAYS a MarketIntelligence. If the requested timeframe has no
    usable data, it is a safe NEUTRAL/"WAIT" object with data_source="INSUFFICIENT DATA";
    the third tuple element still carries the feed's reason (e.g. "NO REAL DATA AVAILABLE").
    """
    prices, source, ohlcv = PriceFeed.get(cfg, timeframe)

    if not prices or ohlcv is None or len(prices) < MIN_BARS:
        logger.warning(f"⚠️ No usable real {timeframe} data for {cfg.symbol} ({source})")
        return _safe_mi(cfg, timeframe, f"No {timeframe} data available ({source})"), [], source

    news_items: List[NewsItem] = []
    economic_calendar: List[Dict] = []
    if fetch_news:
        news_items = FinnhubNewsEngine.fetch_company_news(cfg.symbol)
        economic_calendar = FinnhubNewsEngine.fetch_economic_calendar(days_ahead=7)
        logger.info(f"📰 Fetched {len(news_items)} news + {len(economic_calendar)} events for {cfg.symbol}")

    mi = analyze(prices=prices, cfg=cfg, atr_mult=atr_mult, rr_ratio=rr_ratio, ohlcv=ohlcv,
                 initial_balance=initial_balance, risk_per_trade=risk_per_trade,
                 news_schedule=economic_calendar, timeframe=timeframe)

    if mi.data_source != INSUFFICIENT_DATA:
        mi.data_source = source
        mi.upcoming_news = economic_calendar
        score, label, bull_hits, bear_hits = NewsEngine.calc_macro_sentiment(news_items)
        mi.macro_sentiment_score = score
        mi.macro_sentiment_label = label
        mi.macro_bull_hits = bull_hits
        mi.macro_bear_hits = bear_hits

    return mi, news_items, source


class FinnhubNewsEngine:
    BASE_URL = "https://finnhub.io/api/v1"
    SYMBOL_NEWS_MAP = {
        "XAUUSD": "GLD", "XAGUSD": "SLV", "BTCUSD": "bitcoin", "ETHUSD": "ethereum",
        "SOLUSD": "solana", "SPX500": "SPY", "NAS100": "QQQ",
        "EURUSD": "UUP", "GBPUSD": "FXB", "USDJPY": "FXY",
    }

    @staticmethod
    def _get_api_key() -> str:
        return os.environ.get("FINNHUB_API_KEY", "")

    @staticmethod
    def fetch_company_news(symbol: str, days_back: int = 7) -> List[NewsItem]:
        ck = f"fhnews:{symbol}:{days_back}"
        hit = SmartCache.get_obj(ck, PriceFeed.NEWS_TTL)
        if hit is not None: return hit

        api_key = FinnhubNewsEngine._get_api_key()
        if not api_key: return []
        try:
            url = f"{FinnhubNewsEngine.BASE_URL}/news"
            params = {"category": "general", "token": api_key}
            response = requests.get(url, params=params, timeout=8)
            if response.status_code != 200: return []
            news_data = response.json()
            items: List[NewsItem] = []
            cutoff_ts = (datetime.now(timezone.utc) - timedelta(days=days_back)).timestamp()
            for item in news_data[:20]:
                title = item.get("headline", "")
                summary = item.get("summary", "")
                source = item.get("source", "Unknown")
                url_link = item.get("url", "")
                datetime_ts = item.get("datetime", 0)
                if datetime_ts < cutoff_ts: continue
                published = datetime.fromtimestamp(datetime_ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC") if datetime_ts else ""
                full_text = f"{title} {summary}"
                sentiment = NewsEngine._vader_score(full_text)
                category = "GENERAL"
                for kw in ["CPI", "FOMC", "NFP", "inflation", "rate", "Fed"]:
                    if kw.lower() in title.lower():
                        category = "CRITICAL"; break
                if sentiment > 0.3:
                    nexus_comment = f"📈 Bullish news: {title[:80]}"
                    quant_action = "BOOST_BUY_CONFIDENCE"
                elif sentiment < -0.3:
                    nexus_comment = f"📉 Bearish news: {title[:80]}"
                    quant_action = "BOOST_SELL_CONFIDENCE"
                else:
                    nexus_comment = f"ℹ️ Market news: {title[:80]}"
                    quant_action = "MONITOR"
                items.append(NewsItem(title=title, source=source, published=published, url=url_link,
                    category=category, nexus_comment=nexus_comment, quant_action=quant_action,
                    sentiment_score=round(sentiment, 3), affected_assets=[symbol]))
                if len(items) >= 15: break
            SmartCache.set_obj(ck, items, "News")
            return items
        except Exception as e:
            logger.error(f"❌ Finnhub news error: {e}")
            return []

    @staticmethod
    def fetch_economic_calendar(days_ahead: int = 7) -> List[Dict]:
        ck = f"fhcal:{days_ahead}"
        hit = SmartCache.get_obj(ck, PriceFeed.NEWS_TTL)
        if hit is not None: return hit

        api_key = FinnhubNewsEngine._get_api_key()
        if not api_key: return []
        try:
            from_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            to_date = (datetime.now(timezone.utc) + timedelta(days=days_ahead)).strftime("%Y-%m-%d")
            url = f"{FinnhubNewsEngine.BASE_URL}/calendar/economic"
            params = {"from": from_date, "to": to_date, "token": api_key}
            response = requests.get(url, params=params, timeout=8)
            if response.status_code != 200: return []
            data = response.json()
            events = data.get("economicCalendar", [])
            HIGH_IMPACT_KEYWORDS = ["NFP", "Nonfarm", "CPI", "FOMC", "Fed", "GDP", "PPI", "Employment", "ISM"]
            filtered = []
            for event in events:
                event_name = event.get("event", "")
                country = event.get("country", "")
                if country != "US": continue
                if any(kw.lower() in event_name.lower() for kw in HIGH_IMPACT_KEYWORDS):
                    filtered.append({"event": event_name, "datetime": event.get("time", ""),
                                     "country": country, "actual": event.get("actual", ""),
                                     "estimate": event.get("estimate", ""), "prev": event.get("prev", ""),
                                     "impact": event.get("impact", 0)})
            filtered.sort(key=lambda x: x.get("datetime", ""))
            result = filtered[:10]
            SmartCache.set_obj(ck, result, "Calendar")
            return result
        except Exception as e:
            logger.error(f"❌ Finnhub calendar error: {e}")
            return []

# ============================================
# LIVE CRYPTO WEBSOCKET
# ============================================

_WS_SYMBOLS = {"BTCUSDT": "BTCUSD", "ETHUSDT": "ETHUSD", "SOLUSDT": "SOLUSD"}
_WS_STARTED = False

async def _binance_ws_stream():
    streams = "btcusdt@trade/ethusdt@trade/solusdt@trade"
    url = f"wss://stream.binance.com:9443/stream?streams={streams}"
    while True:
        try:
            import websockets
            async with websockets.connect(url, ping_interval=20, ping_timeout=20) as ws:
                async for message in ws:
                    data = json.loads(message)
                    if 'data' in data:
                        sym = _WS_SYMBOLS.get(data['data'].get('s', ''))
                        price = float(data['data'].get('p', 0))
                        if sym and math.isfinite(price) and price > 0:
                            LIVE_PRICES[sym] = price
                            LIVE_PRICE_TS[sym] = time.time()      # FIX[5]: freshness stamp
        except Exception as e:
            logger.debug(f"Binance WS disconnected: {e}")
            await asyncio.sleep(2)

def _run_ws_loop():
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(_binance_ws_stream())
    except Exception as e:
        logger.debug(f"WS loop error: {e}")

def start_real_time_streams():
    """Idempotent. Set env NEXUS_DISABLE_WS=1 to skip (unit tests, CI, multi-worker deployments)."""
    global _WS_STARTED
    if _WS_STARTED or os.environ.get("NEXUS_DISABLE_WS") == "1":
        return
    try:
        import websockets  # noqa: F401
        thread = threading.Thread(target=_run_ws_loop, daemon=True)
        thread.start()
        _WS_STARTED = True
        logger.info("🚀 Binance WebSocket started for Crypto")
    except ImportError:
        logger.warning("⚠️ websockets not installed. Run: pip install websockets")

start_real_time_streams()

# ============================================
# UNIT TESTS
# ============================================

if __name__ == "__main__":
    from dataclasses import asdict

    print("=" * 70)
    print("🚀 NEXUS v13.11 — QUANTUM INSTITUTIONAL ENGINE — UNIT TESTS")
    print("=" * 70)
    print("\n📋 [TEST 1] Instrument Specifications Database")
    for symbol, spec in INSTRUMENT_SPECS.items():
        print(f"  ✓ {symbol}: Min Lot={spec.min_lot}, Max Lot={spec.max_lot}, Leverage={spec.leverage}")
    print("\n📐 [TEST 2] Position Sizing Engine")
    print(f"  {calculate_position_size(balance=1000, risk_percentage=1.0, entry_price=2000.0, stop_loss_price=1990.0, symbol='XAUUSD')}")
    print("\n🎲 [TEST 3] Monte Carlo (VECTORIZED)")
    t0 = time.time()
    mc_result = MonteCarloRiskEngine.simulate_trades(win_rate=0.60, rr_ratio=2.0, risk_amount=100, initial_balance=10000)
    print(f"  Done in {(time.time()-t0)*1000:.0f}ms | Final: ${mc_result.expected_final_balance:,.2f} | VaR95: ${mc_result.var_95:,.2f} | Ruin: {mc_result.probability_of_ruin:.2f}%")

    np.random.seed(42)
    N = 250
    t_close = np.cumsum(np.random.randn(N)) + 2000
    t_open = t_close + np.random.randn(N) * 0.5
    t_high = np.maximum(t_open, t_close) + np.random.rand(N) * 2
    t_low = np.minimum(t_open, t_close) - np.random.rand(N) * 2
    t_vol = np.random.randint(1000, 10000, N).astype(float)

    print("\n🧠 [TEST 4] Multi-Layer Signal Engine")
    sig = MultiLayerSignalEngine.generate_signal(t_open, t_high, t_low, t_close, t_vol, "XAUUSD")
    print(f"  Signal: {sig.direction} | Confidence: {sig.signal_confidence:.1f} | Regime: {sig.regime_advanced}")
    print(f"  Layers: {sig.confluence_bull_layers}B / {sig.confluence_bear_layers}S")
    assert sig.data_source != INSUFFICIENT_DATA

    print("\n🧼 [TEST 5] OHLCV sanitization (None / NaN / Inf / negative / strings)")
    dirty = {"open": list(t_open), "high": list(t_high), "low": list(t_low), "close": list(t_close), "volume": list(t_vol)}
    dirty["close"][10] = None; dirty["open"][20] = float("nan"); dirty["high"][30] = float("inf")
    dirty["low"][40] = -5.0; dirty["volume"][50] = float("nan"); dirty["close"][60] = "bad"
    clean = sanitize_ohlcv(dirty)
    assert clean is not None
    lens = {len(v) for v in clean.values()}
    assert len(lens) == 1, "columns must stay row-aligned"
    assert all(isinstance(x, float) and math.isfinite(x) for k in clean for x in clean[k])
    print(f"  ✓ {N} dirty rows -> {lens.pop()} clean rows, all finite floats, aligned")
    assert sanitize_ohlcv({k: v[:30] for k, v in dirty.items()}) is None
    print("  ✓ <60 candles -> None")

    print("\n⏱️  [TEST 6] Strict timeframe integrity")
    px, src, oh = PriceFeed.get(GOLD_CFG, "H2")          # unsupported -> must NOT silently become M5
    assert px == [] and oh is None
    print(f"  ✓ unsupported timeframe -> '{src}'")

    print("\n🛡️  [TEST 7] Graceful degradation (never raises, never fabricates a signal)")
    for label, args in {"no ohlcv": ([], None), "30 bars": (list(t_close[:30]), {k: v[:30] for k, v in dirty.items()})}.items():
        mi = analyze(prices=args[0], cfg=GOLD_CFG, ohlcv=args[1], timeframe="M5")
        assert mi.direction == "NEUTRAL" and mi.safety_signal == "WAIT" and mi.data_source == INSUFFICIENT_DATA
        print(f"  ✓ {label}: {mi.direction} / {mi.safety_signal} / {mi.data_source}")

    print("\n🧪 [TEST 8] Full analysis on dirty data -> JSON-safe, no NaN")
    mi = analyze(prices=list(t_close), cfg=GOLD_CFG, ohlcv=dirty, timeframe="M5")
    json.dumps(asdict(mi), allow_nan=False)               # raises ValueError if any NaN/Inf survived
    print(f"  ✓ {mi.safety_signal} | RSI={mi.rsi} | ATR={mi.atr_14} | JSON strict-encodable")

    print("\n🧮 [TEST 9] MathEngine short / NaN arrays")
    assert MathEngine._calc_rsi(np.array([1.0, 2.0])) == 50.0
    assert len(MathEngine._ema(np.array([np.nan, np.nan]), 9)) == 0
    assert MathEngine._calc_macd(np.array([1.0] * 10)) == (0.0, 0.0, 0.0)
    r = MathEngine._rsi_series(np.concatenate([[np.nan], t_close[:100]]))
    assert np.all(np.isfinite(r))
    print("  ✓ all guards hold")

    print("\n" + "=" * 70)
    print("✅ ALL TESTS PASSED — NEXUS v13.11 READY")
    print("=" * 70)