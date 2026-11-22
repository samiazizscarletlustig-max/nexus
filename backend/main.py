"""
╔═══════════════════════════════════════════════════════════════════════════════╗
║  NEXUS v13.10 ULTIMATE — PRO FASTAPI BACKEND (main.py)                        ║
║  Architecture: FastAPI + Engine (Binance WS + OANDA) | Zero Latency           ║
║  Focus: Broker-Grade Chart Precision, Sub-100ms Responses, WebSocket Live     ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""
import os
import json
import math
import random
import asyncio
import statistics
import time
import re
import logging
from collections import deque
from datetime import datetime, timezone, timedelta
from dataclasses import asdict
from typing import Dict, List, Any, Optional, Set, Tuple

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

# ── Engine import with graceful SIM fallback ───────────────────────────────
ENGINE_OK = False
LIVE_PRICES: Dict[str, float] = {}  # Fallback for SIM mode

try:
    from engine import (
        run_analysis, calculate_position_size, ASSET_MAP, ALL_ASSETS,
        INSTRUMENT_SPECS, PriceFeed, MarketIntelligence, get_correlation_matrix,
        AssetConfig, FinnhubNewsEngine, NewsItem, LIVE_PRICES  # <-- Added LIVE_PRICES
    )
    ENGINE_OK = True
except Exception as e:
    print(f"⚠️  engine.py unavailable ({e}) — running in SIMULATED mode.")

try:
    import ai_planner
except Exception:
    ai_planner = None
    print("⚠️  ai_planner.py unavailable — AI endpoint will use built-in fallback.")

# ═══ v13.10 — CLEAN CONSOLE (Hide 429 & Network Spam) ═══
class _CleanConsoleFilter(logging.Filter):
    def filter(self, record):
        msg = record.getMessage().lower()
        if "429" in msg or "twelve data" in msg or "connection error" in msg:
            return False
        return True

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-8s | %(message)s", datefmt="%H:%M:%S")
logging.getLogger().addFilter(_CleanConsoleFilter())
logger = logging.getLogger("NEXUS-API")
logger.addFilter(_CleanConsoleFilter())

# ════════════════════════════════════════════════════════════════════════════
#  SIMULATED MODE ASSETS (Fallback only)
# ════════════════════════════════════════════════════════════════════════════
if not ENGINE_OK:
    from dataclasses import dataclass

    @dataclass
    class AssetConfig:
        symbol: str
        name: str
        asset_type: str
        yf_ticker: str
        emoji: str = ""
        color: str = "#FFFFFF"
        base_price: float = 100.0
        price_hi: float = 10000.0
        contract_size: float = 100.0
        pip_size: float = 0.01
        tick_size: float = 0.01
        tick_value: float = 1.0
        min_lot: float = 0.01
        max_lot: float = 100.0
        lot_step: float = 0.01
        leverage: float = 100.0
        spread_pips: float = 2.0
        is_24_7: bool = False

    ALL_ASSETS = [
        AssetConfig("XAUUSD", "Gold", "commodity", "GC=F", "⚡", "#FFD700", 2385.0, 3000, 100, 0.1, 0.1, 10, 0.01, 500, 0.01, 500, 2, False),
        AssetConfig("XAGUSD", "Silver", "commodity", "SI=F", "🥈", "#C0C0C0", 29.1, 60, 5000, 0.01, 0.01, 10, 0.01, 500, 0.01, 500, 3, False),
        AssetConfig("BTCUSD", "Bitcoin", "crypto", "BTC-USD", "₿", "#F7931A", 64250.0, 120000, 1, 0.01, 0.01, 10, 0.001, 100, 0.001, 100, 5, True),
        AssetConfig("ETHUSD", "Ethereum", "crypto", "ETH-USD", "Ξ", "#627EEA", 3450.0, 6000, 1, 0.01, 0.01, 10, 0.01, 100, 0.01, 100, 5, True),
        AssetConfig("SOLUSD", "Solana", "crypto", "SOL-USD", "💜", "#9945FF", 148.5, 300, 1, 0.01, 0.01, 10, 0.01, 100, 0.01, 100, 5, True),
        AssetConfig("SPX500", "S&P 500", "index", "^GSPC", "📊", "#4CAF50", 5420.0, 7000, 100, 0.25, 0.25, 10, 0.01, 100, 0.01, 500, 2, False),
        AssetConfig("NAS100", "NASDAQ 100", "index", "^NDX", "🚀", "#2196F3", 18950.0, 25000, 100, 0.25, 0.25, 10, 0.01, 100, 0.01, 500, 2, False),
        AssetConfig("EURUSD", "EUR/USD", "forex", "EURUSD=X", "💱", "#1565C0", 1.0845, 2, 100000, 0.0001, 0.0001, 10, 0.01, 500, 0.01, 500, 1, False),
        AssetConfig("GBPUSD", "GBP/USD", "forex", "GBPUSD=X", "💷", "#8E24AA", 1.2730, 2, 100000, 0.0001, 0.0001, 10, 0.01, 500, 0.01, 500, 2, False),
        AssetConfig("USDJPY", "USD/JPY", "forex", "USDJPY=X", "💴", "#EF5350", 156.4, 200, 100000, 0.01, 0.01, 10, 0.01, 500, 0.01, 500, 2, False),
    ]
    ASSET_MAP = {a.symbol: a for a in ALL_ASSETS}
    INSTRUMENT_SPECS = ASSET_MAP
    SIM_PRICE: Dict[str, float] = {a.symbol: a.base_price for a in ALL_ASSETS}

    def _sim_tick(cfg) -> float:
        p = SIM_PRICE[cfg.symbol]
        p *= 1 + random.uniform(-0.0008, 0.0008)
        SIM_PRICE[cfg.symbol] = p
        return p

    class PriceFeed:
        @staticmethod
        def get_latest_price(cfg):
            return _sim_tick(cfg), "SIM"

        @staticmethod
        def get_latest_prices(cfgs):
            return {c.symbol: (_sim_tick(c), "SIM") for c in cfgs}

        @staticmethod
        def get(cfg, timeframe="M5"):
            p = _sim_tick(cfg)
            return [p], "SIM", {"open": [p], "high": [p], "low": [p], "close": [p], "volume": [1000]}

    def calculate_position_size(balance, risk_percentage, entry_price, stop_loss_price, symbol=""):
        risk_amt = balance * risk_percentage / 100.0
        dist = abs(entry_price - stop_loss_price) or 1e-9
        lots = risk_amt / (dist * 10)
        return {"lots": round(max(0.01, min(lots, 100.0)), 2), "risk_amount": round(risk_amt, 2), "distance": round(dist, 5)}

    def get_correlation_matrix():
        return {}

    def run_analysis(cfg, **kw):
        return _SimIntel(cfg, kw.get('timeframe', 'M15')).obj(), [], "NEXUS Simulated Feed"

    class _SimIntel:
        def __init__(self, cfg, tf):
            R = random.Random()
            self.cfg = cfg
            self.tf = tf
            self.p = SIM_PRICE.get(cfg.symbol, cfg.base_price)
            self.bull = R.random() > 0.45
            self.R = R

        def obj(self):
            R, p, bull, cfg = self.R, self.p, self.bull, self.cfg
            atr = p * R.uniform(0.004, 0.012)
            strength = R.randint(62, 94)
            direction = "BULLISH" if bull else "BEARISH"
            now = datetime.now(timezone.utc)
            return dict(
                asset_name=cfg.name, asset_type=cfg.asset_type, last_update=now.isoformat(), data_source="SIM",
                current_price=round(p, 6), safety_signal="BUY" if bull else "SELL", signal_color="#00FF88" if bull else "#FF3131",
                signal_strength=strength, direction=direction, probability_bull=round(strength if bull else 100-strength, 1),
                ema9=p, ema21=p, ema50=p, ema200=p, ema_alignment="BULLISH" if bull else "BEARISH",
                rsi=60.0 if bull else 40.0, rsi_signal="BULLISH" if bull else "BEARISH", rsi_explanation="Sim",
                macd_line=0.0, macd_signal=0.0, macd_hist=0.0, macd_cross="BULLISH" if bull else "BEARISH",
                stoch_k=50.0, stoch_d=50.0, stoch_signal="NEUTRAL", bb_upper=p+10, bb_mid=p, bb_lower=p-10, bb_width=1.0, bb_position="MID",
                kc_upper=p+10, kc_mid=p, kc_lower=p-10, ttm_squeeze_active=False, ttm_squeeze_label="OFF", ttm_momentum=0.0,
                supertrend_value=p, supertrend_signal="BULLISH" if bull else "BEARISH", supertrend_direction="UP" if bull else "DOWN",
                vwap=p, vwap_upper=p+5, vwap_lower=p-5, vwap_signal="ABOVE" if bull else "BELOW",
                pivot_points={"PP": p, "R1": p+5, "S1": p-5}, nearest_pivot_level="PP", nearest_pivot_dist=0.0,
                zscore=0.0, zscore_signal="NEUTRAL", adx_value=25.0, adx_signal="STRONG", adx_di_plus=20.0, adx_di_minus=20.0,
                williams_r=-50.0, williams_signal="NEUTRAL", cci_value=0.0, cci_signal="NEUTRAL", obv_trend="RISING" if bull else "FALLING", obv_value=1000.0,
                ichimoku_signal="BULLISH" if bull else "BEARISH", tenkan=p, kijun=p, atr14=atr,
                sl_buy=p-atr, sl_sell=p+atr, tp_buy=p+atr*2, tp_sell=p-atr*2, sl_pips=10.0, atr_explanation="Sim ATR",
                hurst=0.5, regime="TRENDING", regime_advanced="TREND", shannon_entropy=0.5, kaufman_er=0.5, fractal_dim=1.5,
                realized_vol=0.1, vol_regime="NORMAL", kurtosis=3.0, skewness=0.0, tail_risk="NORMAL", autocorr_lag_1=0.0, stability_index=50,
                supports=[p-10], resistances=[p+10], nearest_support=p-10, nearest_resist=p+10, sr_zone="MID",
                wave_position="WAVE 3", wave_confidence=50.0, wave_target=p+20, wave_trend=direction,
                fib_retracements={}, fib_extensions={}, fib_zone="MID", fib_strength=50.0, fib_explanation="Sim",
                order_blocks=[], fair_value_gaps=[], liquidity_sweeps=[], smc_bias=direction, smc_explanation="Sim",
                rsi_divergence="NONE", macd_divergence="NONE", obv_divergence="NONE", divergence_signal="NONE", divergence_strength=0.0,
                candle_pattern="NONE", candle_strength=0.0, candle_direction="NEUTRAL", candle_explanation="Sim",
                kelly_fraction=0.05, kelly_recommendation="Sim", trading_session="LONDON", session_liquidity="HIGH", session_warning="", session_explanation="Sim",
                news_lock_active=False, news_lock_event="", news_lock_reason="", macro_sentiment_score=50, macro_sentiment_label="NEUTRAL",
                macro_bull_hits=0, macro_bear_hits=0, mtf_signals={}, mtf_confluence="NEUTRAL", mtf_bull_count=0, mtf_bear_count=0,
                trade_plan=dict(valid=True, direction=direction, entry=p, sl=p-atr, tp1=p+atr*2, tp2=p+atr*3, tp3=p+atr*4, rr1=2.0, rr2=3.0, confidence=strength, quality="A", reasoning="Sim", invalidation="Sim", session="LONDON", regime="TREND", news_risk="LOW", prob_score=strength, mtf="ALIGNED", layer_scores={}, proxy_order_flow={"delta_signal":"NEUTRAL", "buying_pressure":50.0}, expectancy_per_dollar=0.5, volatility_adjusted_risk_pct=1.0, bull_layers=3, bear_layers=0, estimated_win_rate=0.6),
                risk_dollars=100.0, recommended_lots=0.1, lot_explanation="Sim", required_margin=50.0,
                crypto_metrics=None, forex_metrics=None, chart_metadata={}, signal_reasons=["Sim"],
                monte_carlo=dict(expected_final_balance=11000, var95=9000, var99=8000, expected_max_drawdown=10.0, probability_of_ruin=2.0, simulations_run=1000),
                volume_profile=dict(poc_price=p, value_area_high=p+5, value_area_low=p-5), upcoming_news=[], volatility_percentile=50.0, estimated_win_rate=0.6
            )

# ════════════════════════════════════════════════════════════════════════════
#  APP + CONFIG
# ════════════════════════════════════════════════════════════════════════════
app = FastAPI(title="NEXUS Quantum Terminal", version="13.10.0", docs_url="/docs", redoc_url="/redoc")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"]
)

_ARCHIVE_MAX = int(os.getenv("ARCHIVE_MAX_RECORDS", "500"))
_WS_PRICE_SEC = int(os.getenv("WS_PRICE_INTERVAL_SEC", "1"))
_WS_HB_SEC = int(os.getenv("WS_HEARTBEAT_INTERVAL_SEC", "30"))
_CRYPTO_TYPES = {"crypto", "cryptocurrency", "digital"}
_GOLD = {"XAUUSD", "XAGUSD"}
_signal_archive: deque = deque(maxlen=_ARCHIVE_MAX)
_prev_prices: Dict[str, float] = {}
_prev_signals: Dict[str, dict] = {}
_analysis_cache: Dict[str, Tuple[float, dict]] = {}
_USERS: Dict[str, dict] = {}
_resp_cache: Dict[str, Tuple[float, Any]] = {}

def _cget(key: str, ttl: float):
    h = _resp_cache.get(key)
    if h and (time.time() - h[0]) < ttl:
        return h[1]
    return None

def _cset(key: str, val: Any):
    _resp_cache[key] = (time.time(), val)

class AnalyzeRequest(BaseModel):
    symbol: str
    balance: float = Field(10000.0, ge=100.0)
    risk_percentage: float = Field(1.0, ge=0.1, le=10.0)
    timeframe: str = Field("M15", pattern="^(?i)(M1|M5|M15|H1|H4|D1|1m|5m|15m|1h|4h|1d)$")
    run_mtf: bool = True
    atr_mult: float = Field(1.5, ge=1.0, le=3.0)
    rr_ratio: float = Field(2.5, ge=1.0, le=5.0)

class PositionSizeRequest(BaseModel):
    symbol: str
    balance: float
    risk_percentage: float
    entry_price: float
    stop_loss_price: float

class AuthRequest(BaseModel):
    email: str
    password: str
    name: str = ""

# ════════════════════════════════════════════════════════════════════════════
#  WEBSOCKET MANAGER (High-Frequency Ticks)
# ════════════════════════════════════════════════════════════════════════════
class ConnectionManager:
    def __init__(self):
        self._clients: Dict[WebSocket, Set[str]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, ws):
        await ws.accept()
        async with self._lock:
            self._clients[ws] = set()

    async def disconnect(self, ws):
        async with self._lock:
            self._clients.pop(ws, None)

    async def set_filter(self, ws, symbols):
        async with self._lock:
            if ws in self._clients:
                self._clients[ws] = {s.upper() for s in symbols}

    async def broadcast(self, frame):
        dead = []
        async with self._lock:
            snap = list(self._clients.items())
        for ws, _f in snap:
            try:
                await ws.send_text(json.dumps(frame))
            except Exception:
                dead.append(ws)
        for ws in dead:
            await self.disconnect(ws)

    @property
    def active_count(self):
        return len(self._clients)

_ws_manager = ConnectionManager()

# ═══ WEBSOCKET BROADCAST (ULTRA-FAST v13.10) ═══
async def _ws_broadcast_loop():
    """تبث الأسعار كل ثانية، مع إعطاء الأولوية القصوى للذاكرة الحية (RAM)"""
    hb = 0
    while True:
        await asyncio.sleep(_WS_PRICE_SEC)
        if _ws_manager.active_count == 0:
            hb += _WS_PRICE_SEC
            continue
        
        ticks, ts = {}, datetime.now(timezone.utc).isoformat()
        for cfg in ALL_ASSETS:
            try:
                # 🚀 PRIORITY 1: Check RAM for live WebSocket price (Instant, <1ms)
                if cfg.symbol in LIVE_PRICES and LIVE_PRICES[cfg.symbol] > 0:
                    price = LIVE_PRICES[cfg.symbol]
                else:
                    # PRIORITY 2: Fallback to REST API fetch
                    price_val, _ = await asyncio.to_thread(PriceFeed.get_latest_price, cfg)
                    price = float(price_val)
                
                prev = _prev_prices.get(cfg.symbol, price)
                pct = ((price - prev) / prev * 100) if prev else 0.0
                ticks[cfg.symbol] = {
                    "price": round(price, 5 if _is_forex(cfg) else (3 if "JPY" in cfg.symbol else 2)), 
                    "changePct": round(pct, 3),
                    "direction": "UP" if price > prev else "DOWN" if price < prev else "FLAT", 
                    "glowIntensity": round(min(abs(pct) / 0.5, 1.0), 4)
                }
                _prev_prices[cfg.symbol] = price
            except Exception:
                pass
                
        if ticks:
            await _ws_manager.broadcast({"type": "price_tick", "ts": ts, "data": ticks})
            
        hb += _WS_PRICE_SEC
        if hb >= _WS_HB_SEC:
            hb = 0
            await _ws_manager.broadcast({"type": "heartbeat", "ts": ts, "activeClients": _ws_manager.active_count})

# ═══ SMART PREWARM (Concurrent + Fallbacks = 5s load time) ═══
async def _prewarm_loop():
    await asyncio.sleep(3.0)
    logger.info("🔥 Prewarm started (Smart Concurrency + Fallbacks)")
    sem = asyncio.Semaphore(4)
    
    async def fetch_with_sem(cfg, tf):
        async with sem:
            try:
                await asyncio.to_thread(PriceFeed.get, cfg, tf)
            except Exception:
                pass

    while True:
        tasks = []
        for cfg in ALL_ASSETS:
            for tf in ("M15", "H1"):
                tasks.append(fetch_with_sem(cfg, tf))
        if tasks:
            await asyncio.gather(*tasks)
        await asyncio.sleep(300)

@app.on_event("startup")
async def _startup():
    asyncio.create_task(_ws_broadcast_loop())
    asyncio.create_task(_prewarm_loop())
    logger.info(f"🚀 NEXUS v13.10 ULTIMATE — All systems started. [ENGINE={'REAL' if ENGINE_OK else 'SIM'}]")
    logger.info(f"📊 Monitoring {len(ALL_ASSETS)} assets | 🤖 AI: {'READY' if ai_planner else 'DISABLED'}")

# ════════════════════════════════════════════════════════════════════════════
#  UTILITIES & CHART METADATA (Institutional Precision)
# ════════════════════════════════════════════════════════════════════════════
def sanitize_float(o):
    if isinstance(o, float):
        return None if (math.isnan(o) or math.isinf(o)) else o
    if isinstance(o, dict):
        return {k: sanitize_float(v) for k, v in o.items()}
    if isinstance(o, list):
        return [sanitize_float(v) for v in o]
    return o

_CAMEL = re.compile(r"_([a-z])")
def to_camel_case(o):
    if isinstance(o, dict):
        return {_CAMEL.sub(lambda m: m.group(1).upper(), k): to_camel_case(v) for k, v in o.items()}
    if isinstance(o, list):
        return [to_camel_case(v) for v in o]
    return o

def get_config(symbol: str):
    sym = symbol.upper().strip()
    if sym in ASSET_MAP:
        return ASSET_MAP[sym]
    raise HTTPException(404, f"Asset '{symbol}' not supported.")

def _is_forex(cfg):
    return getattr(cfg, "asset_type", "").lower() == "forex"

def _is_crypto_symbol(sym, cfg):
    s = sym.upper()
    if s in _GOLD:
        return False
    if getattr(cfg, "asset_type", "").lower() in _CRYPTO_TYPES:
        return True
    return any(t in s for t in ("BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE"))

def _dp_for(cfg):
    """Institutional_precision: Forex=5, JPY=3, Gold=2, Crypto=2/6, Indices=2"""
    sym = cfg.symbol.upper()
    at = getattr(cfg, "asset_type", "").lower()
    if at == "forex":
        return 3 if "JPY" in sym else 5
    if at == "crypto":
        return 2 if sym in ("BTCUSD", "ETHUSD", "BNBUSD", "SOLUSD") else 6
    if sym in ("XAUUSD", "XAGUSD"):
        return 2
    if at == "index":
        return 2
    return 2

def _build_chart_metadata(cfg):
    dp = _dp_for(cfg)
    tick = 0.001 if (_is_forex(cfg) and "JPY" in cfg.symbol) else (0.00001 if _is_forex(cfg) else (0.01 if cfg.symbol in _GOLD else (0.01 if getattr(cfg, "price_hi", 0) > 10000 else 0.0001)))
    now = datetime.now(timezone.utc)
    hr = now.hour + now.minute / 60
    if _is_crypto_symbol(cfg.symbol, cfg):
        st, sl_ = "24_7", "24/7 CRYPTO MARKET"
    elif now.weekday() >= 5:
        st, sl_ = "CLOSED", "WEEKEND — MARKET CLOSED"
    else:
        st, sl_ = "OPEN", ("LONDON–NY OVERLAP" if (7 <= hr < 16 and 12 <= hr < 21) else "LONDON SESSION" if 7 <= hr < 16 else "NEW YORK SESSION" if 12 <= hr < 21 else "OFF-HOURS")
    return {
        "decimalPlaces": dp, "tickSize": tick, "rightViewportPaddingPct": 5.0, 
        "marketStatus": st, "sessionLabel": sl_, "is24h": _is_crypto_symbol(cfg.symbol, cfg), 
        "isOverlap": (7 <= hr < 16 and 12 <= hr < 21), "assetColor": getattr(cfg, "color", "#FFFFFF"), 
        "priceFormat": f"#,##0.{'0' * dp}"
    }

def _enrich_news_item(raw, asset_type):
    return {
        **raw, 
        "imageUrl": raw.get("imageUrl") or raw.get("image_url") or "", 
        "sourceLogoUrl": raw.get("sourceLogoUrl") or "", 
        "sentimentLabel": raw.get("sentimentLabel") or ("BULLISH" if raw.get("sentimentScore", 0) > 0.1 else "BEARISH" if raw.get("sentimentScore", 0) < -0.1 else "NEUTRAL")
    }

def _sim_news(cfg):
    return [{"title": f"Institutional flows detected in {cfg.name}", "source": "NEXUS Desk", "published": datetime.now(timezone.utc).isoformat(), "url": "#", "category": "HIGH", "nexusComment": "Smart-money accumulation visible.", "quantAction": "MONITOR", "sentimentScore": 0.5, "impactPercentage": 80}]

def _sim_calendar():
    base = datetime.now(timezone.utc)
    return [{"event": "FOMC Rate Decision", "datetime": (base + timedelta(days=2)).isoformat(), "country": "US", "impact": 3, "estimate": "5.50%", "prev": "5.50%", "actual": ""}]

def _fallback_ai_plan(sym, mi):
    return {"source": "quant-fallback", "summary": f"{sym} analysis.", "scenarios": [], "risk_note": "Simulated plan."}

def _push_to_archive(sym, mi, source):
    try:
        _signal_archive.appendleft({
            "id": f"{sym}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}", 
            "symbol": sym, "timestamp": datetime.now(timezone.utc).isoformat(), 
            "signal": mi.get("safetySignal"), "direction": mi.get("direction"), 
            "confidence": mi.get("signalStrength"), "price": mi.get("currentPrice"), "source": source
        })
    except Exception:
        pass

def _normalize_tf(tf: str) -> str:
    if not tf:
        return "M15"
    tf = tf.upper().strip()
    mapping = {"1M": "M1", "M1": "M1", "5M": "M5", "M5": "M5", "15M": "M15", "M15": "M15", "1H": "H1", "H1": "H1", "4H": "H4", "H4": "H4", "1D": "D1", "D1": "D1"}
    return mapping.get(tf, "M15")

_INT_MIN = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240, "D1": 1440}

def _format_candles(ohlcv: dict, cfg, interval_mins: int) -> list:
    if not ohlcv or not ohlcv.get("close"):
        return []
    opens = ohlcv.get("open", [])
    highs = ohlcv.get("high", [])
    lows = ohlcv.get("low", [])
    closes = ohlcv.get("close", [])
    volumes = ohlcv.get("volume", [])
    n = min(len(opens), len(highs), len(lows), len(closes))
    if n == 0:
        return []
    now = datetime.now(timezone.utc)
    candles = []
    for i in range(n):
        try:
            o = float(opens[i])
            h = float(highs[i])
            l = float(lows[i])
            c = float(closes[i])
            v = float(volumes[i]) if i < len(volumes) else 1000.0
            if any(math.isnan(x) or math.isinf(x) or x <= 0 for x in (o, h, l, c)):
                continue
            candles.append({
                "timestamp": (now - timedelta(minutes=interval_mins * (n - 1 - i))).isoformat(), 
                "open": round(o, 8), "high": round(h, 8), "low": round(l, 8), "close": round(c, 8), 
                "volume": round(v, 2), "decimalPlaces": _dp_for(cfg), "assetType": cfg.asset_type
            })
        except Exception:
            continue
    return candles

def _sim_candles(cfg, tf):
    mins = _INT_MIN.get(tf, 15)
    base = getattr(cfg, 'base_price', 100.0)
    p = SIM_PRICE.get(cfg.symbol, base) if not ENGINE_OK else base
    n, now = 300, datetime.now(timezone.utc)
    candles, price = [], p
    vols = p * 0.0035 * math.sqrt(mins / 15)
    for i in range(n, 0, -1):
        o = price
        c = o + random.gauss(0, vols)
        h = max(o, c) + abs(random.gauss(0, vols * 0.5))
        l = min(o, c) - abs(random.gauss(0, vols * 0.5))
        candles.append({
            "timestamp": (now - timedelta(minutes=mins * i)).isoformat(), 
            "open": round(o, 8), "high": round(h, 8), "low": round(l, 8), "close": round(c, 8), 
            "volume": round(random.uniform(500, 50000), 2), "decimalPlaces": _dp_for(cfg), "assetType": cfg.asset_type
        })
        price = c
    return candles

# ════════════════════════════════════════════════════════════════════════════
#  ENDPOINTS (Sub-100ms Responses)
# ════════════════════════════════════════════════════════════════════════════
@app.get("/")
async def root():
    return {"status": "ONLINE", "system": "NEXUS QUANTUM v13.10", "engine": "REAL" if ENGINE_OK else "SIMULATED", "ai_planner": ai_planner is not None}

@app.get("/api/health")
async def health():
    return {"status": "ok", "engine_loaded": ENGINE_OK, "ws_clients": _ws_manager.active_count, "version": "13.10.0"}

@app.get("/api/assets")
async def get_assets():
    return {"assets": [
        {
            "symbol": c.symbol, "name": c.name, "type": c.asset_type, "contract_size": c.contract_size, 
            "pip_size": c.pip_size, "tick_size": c.tick_size, "tick_value": c.tick_value, "min_lot": c.min_lot, 
            "max_lot": c.max_lot, "lot_step": c.lot_step, "leverage": c.leverage, "spread_pips": c.spread_pips, 
            "is_24_7": getattr(c, "is_24_7", c.asset_type in _CRYPTO_TYPES), "emoji": getattr(c, "emoji", ""), 
            "color": getattr(c, "color", "#FFFFFF")
        } for c in ALL_ASSETS
    ]}

@app.get("/api/watchlist")
async def watchlist():
    cached = _cget("watchlist", 2.0)
    if cached is not None:
        return cached
        
    out = []
    if ENGINE_OK and hasattr(PriceFeed, 'get_latest_prices'):
        try:
            prices_dict = await asyncio.to_thread(PriceFeed.get_latest_prices, ALL_ASSETS)
            for cfg in ALL_ASSETS:
                last, source = prices_dict.get(cfg.symbol, (0.0, "Unknown"))
                prev = _prev_prices.get(cfg.symbol, last)
                out.append({
                    "symbol": cfg.symbol, "name": cfg.name, "type": cfg.asset_type, 
                    "price": round(float(last), 5 if _is_forex(cfg) else (3 if "JPY" in cfg.symbol else 2)), 
                    "changePct": round(((float(last) - prev) / prev * 100) if prev else 0.0, 3), 
                    "emoji": getattr(cfg, "emoji", ""), "color": getattr(cfg, "color", ""), 
                    "is24h": _is_crypto_symbol(cfg.symbol, cfg), "dataSource": source, "chartMetadata": _build_chart_metadata(cfg)
                })
                _prev_prices[cfg.symbol] = float(last)
        except Exception:
            out = []
            
    if not out:
        async def _fetch(cfg):
            try:
                if ENGINE_OK:
                    price_val, source = await asyncio.to_thread(PriceFeed.get_latest_price, cfg)
                    last = float(price_val)
                else:
                    last = float(SIM_PRICE.get(cfg.symbol, cfg.base_price))
                    source = "SIM"
                prev = _prev_prices.get(cfg.symbol, last)
                return {
                    "symbol": cfg.symbol, "name": cfg.name, "type": cfg.asset_type, 
                    "price": round(last, 5 if _is_forex(cfg) else (3 if "JPY" in cfg.symbol else 2)), 
                    "changePct": round(((last - prev) / prev * 100) if prev else 0.0, 3), 
                    "emoji": getattr(cfg, "emoji", ""), "color": getattr(cfg, "color", ""), 
                    "is24h": _is_crypto_symbol(cfg.symbol, cfg), "dataSource": source, "chartMetadata": _build_chart_metadata(cfg)
                }
            except Exception:
                return None
                
        results = await asyncio.gather(*[_fetch(cfg) for cfg in ALL_ASSETS])
        out = [r for r in results if r is not None]
        
    _cset("watchlist", out)
    return out

@app.get("/api/ohlcv")
async def ohlcv(symbol: str = Query(...), interval: str = Query("M15")):
    cfg = get_config(symbol)
    tf = _normalize_tf(interval)
    cache_key = f"ohlcv_resp:{cfg.symbol}:{tf}"
    
    stale_cached = _cget(cache_key, 3600.0) 
    
    async def refresh_task():
        try:
            if ENGINE_OK:
                _, _, ohlcv_dict = await asyncio.to_thread(PriceFeed.get, cfg, tf)
            else:
                _, _, ohlcv_dict = PriceFeed.get(cfg, tf)
            if ohlcv_dict:
                candles = _format_candles(ohlcv_dict, cfg, _INT_MIN.get(tf, 15))
                if candles:
                    _cset(cache_key, {"candles": candles[-500:], "chartMetadata": _build_chart_metadata(cfg), "source": "live"})
        except Exception:
            pass

    if stale_cached:
        asyncio.create_task(refresh_task())
        return stale_cached

    await refresh_task()
    final = _cget(cache_key, 60.0)
    if final:
        return final
    
    candles = _sim_candles(cfg, tf)
    return {"candles": candles, "chartMetadata": _build_chart_metadata(cfg), "source": "simulated"}

@app.post("/api/analyze")
async def analyze(request: AnalyzeRequest):
    cfg = get_config(request.symbol)
    sym = request.symbol.upper()
    tf = _normalize_tf(request.timeframe)
    cache_key = f"analyze:{sym}:{tf}"
    cached = _cget(cache_key, 30.0)
    if cached is not None:
        return cached
        
    try:
        if ENGINE_OK:
            try:
                intelligence, news_items, source = await asyncio.to_thread(
                    lambda: run_analysis(cfg=cfg, atr_mult=request.atr_mult, rr_ratio=request.rr_ratio, 
                                         initial_balance=request.balance, risk_per_trade=request.risk_percentage, 
                                         timeframe=tf, run_mtf=request.run_mtf)
                )
            except TypeError:
                intelligence, news_items, source = await asyncio.to_thread(
                    lambda: run_analysis(cfg=cfg, atr_mult=request.atr_mult, rr_ratio=request.rr_ratio, 
                                         initial_balance=request.balance, risk_per_trade=request.risk_percentage)
                )
            mi_raw = asdict(intelligence)
            news_list = []
            for it in (news_items or []):
                try:
                    news_list.append(_enrich_news_item(to_camel_case(sanitize_float(asdict(it) if hasattr(it, '__dataclass_fields__') else dict(it))), cfg.asset_type))
                except Exception:
                    pass
        else:
            mi_raw = run_analysis(cfg)[0]
            news_list = [_enrich_news_item(x, cfg.asset_type) for x in _sim_news(cfg)]
            source = "NEXUS Simulated Feed"
            
        mi_camel = to_camel_case(sanitize_float(mi_raw))
        _analysis_cache[sym] = (time.time(), mi_camel)
        _push_to_archive(sym, mi_camel, source)
        
        if _ws_manager.active_count:
            prev = _prev_signals.get(sym, {})
            for f in ("safetySignal", "direction"):
                cur, old = mi_camel.get(f), prev.get(f)
                if old is not None and cur != old:
                    await _ws_manager.broadcast({
                        "type": "metric_shift", "ts": datetime.now(timezone.utc).isoformat(), 
                        "symbol": sym, "field": f, "previous": old, "current": cur
                    })
            _prev_signals[sym] = {f: mi_camel.get(f) for f in ("safetySignal", "direction")}
            
        res = {
            "success": True, 
            "data": {"symbol": sym, "source": source, "intelligence": mi_camel, "news": news_list, "chartMetadata": _build_chart_metadata(cfg)}
        }
        _cset(cache_key, res)
        return res
        
    except Exception as e:
        logger.exception(f"Analysis failed [{request.symbol}]: {e}")
        raise HTTPException(500, f"Analysis error: {e}")

@app.get("/api/ai-plan")
async def ai_plan(symbol: str = Query(...), force: bool = Query(False)):
    cfg = get_config(symbol)
    sym = symbol.upper()
    cache_key = f"aiplan:{sym}"
    if not force:
        cached = _cget(cache_key, 300.0)
        if cached is not None:
            return cached
            
    cached_analysis = _analysis_cache.get(sym)
    if cached_analysis and (time.time() - cached_analysis[0]) < 300 and not force:
        mi_camel, used = cached_analysis[1], True
    else:
        if ENGINE_OK:
            try:
                intelligence, _, source = await asyncio.to_thread(lambda: run_analysis(cfg=cfg))
                mi_camel = to_camel_case(sanitize_float(asdict(intelligence)))
            except Exception:
                mi_camel = to_camel_case(sanitize_float(run_analysis(cfg)[0]))
        else:
            mi_camel = to_camel_case(sanitize_float(run_analysis(cfg)[0]))
        _analysis_cache[sym] = (time.time(), mi_camel)
        used = False
        
    if ai_planner is not None:
        try:
            plan = await asyncio.to_thread(lambda: ai_planner.get_ai_plan(sym, mi_camel, force=force))
        except Exception as e:
            logger.error(f"AI plan failed [{sym}]: {e}")
            fallback_fn = getattr(ai_planner, '_fallback_plan', None)
            plan = fallback_fn(sym, mi_camel) if fallback_fn else _fallback_ai_plan(sym, mi_camel)
    else:
        plan = _fallback_ai_plan(sym, mi_camel)
        
    res = {"success": True, "symbol": sym, "used_cached_analysis": used, "data": plan, "disclaimer": "AI-generated educational analysis."}
    _cset(cache_key, res)
    return res

@app.get("/api/news/{symbol}")
async def news(symbol: str, days: int = Query(7, ge=1, le=30)):
    cfg = get_config(symbol)
    cache_key = f"news:{symbol}:{days}"
    cached = _cget(cache_key, 300.0)
    if cached is not None:
        return cached
        
    if ENGINE_OK:
        try:
            items = await asyncio.to_thread(FinnhubNewsEngine.fetch_company_news, symbol, days)
            res = {
                "success": True, "symbol": symbol.upper(), "count": len(items), 
                "news": [_enrich_news_item(to_camel_case(sanitize_float(asdict(i))), cfg.asset_type) for i in items]
            }
            _cset(cache_key, res)
            return res
        except Exception:
            pass
            
    res = {"success": True, "symbol": symbol.upper(), "count": 1, "news": [_enrich_news_item(x, cfg.asset_type) for x in _sim_news(cfg)]}
    _cset(cache_key, res)
    return res

@app.get("/api/calendar")
async def calendar(days: int = Query(7, ge=1, le=30)):
    cache_key = f"cal:{days}"
    cached = _cget(cache_key, 600.0)
    if cached is not None:
        return cached
        
    if ENGINE_OK:
        try:
            ev = await asyncio.to_thread(FinnhubNewsEngine.fetch_economic_calendar, days)
            res = {"success": True, "count": len(ev), "events": ev}
            _cset(cache_key, res)
            return res
        except Exception:
            pass
            
    ev = _sim_calendar()
    res = {"success": True, "count": len(ev), "events": ev}
    _cset(cache_key, res)
    return res

@app.get("/api/macro-events")
async def macro_events(days: int = Query(7, ge=1, le=30)):
    cache_key = f"macro:{days}"
    cached = _cget(cache_key, 600.0)
    if cached is not None:
        return cached
        
    if ENGINE_OK:
        try:
            ev = await asyncio.to_thread(FinnhubNewsEngine.fetch_economic_calendar, days)
            res = {"success": True, "events": ev}
            _cset(cache_key, res)
            return res
        except Exception:
            pass
            
    res = {"success": True, "events": _sim_calendar()}
    _cset(cache_key, res)
    return res

@app.post("/api/position-size")
async def position_size(r: PositionSizeRequest):
    try:
        res = calculate_position_size(balance=r.balance, risk_percentage=r.risk_percentage, entry_price=r.entry_price, stop_loss_price=r.stop_loss_price, symbol=r.symbol.upper())
        if isinstance(res, dict) and "error" in res:
            return {"success": False, "error": res["error"]}
        return {"success": True, "data": res}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/api/correlation")
async def correlation():
    try:
        m = get_correlation_matrix()
        if not m:
            raise HTTPException(404, "Correlation unavailable")
        return sanitize_float(m)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, str(e))

@app.get("/api/v1/instrument/{symbol}")
async def instrument(symbol: str):
    s = symbol.upper()
    if s not in INSTRUMENT_SPECS:
        raise HTTPException(404, f"Instrument {symbol} not found")
    sp = INSTRUMENT_SPECS[s]
    return {
        "symbol": getattr(sp, "symbol", s), "contract_size": sp.contract_size, "tick_size": sp.tick_size, 
        "tick_value": sp.tick_value, "pip_size": sp.pip_size, "min_lot": sp.min_lot, "max_lot": sp.max_lot, 
        "lot_step": sp.lot_step, "leverage": sp.leverage, "spread_pips": sp.spread_pips
    }

@app.get("/api/v1/archive")
async def archive(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100), symbol: Optional[str] = Query(None)):
    recs = list(_signal_archive)
    if symbol:
        recs = [r for r in recs if r.get("symbol") == symbol.upper()]
    total, pages = len(recs), max(1, math.ceil(len(recs) / page_size))
    page_recs = recs[(page - 1) * page_size : page * page_size]
    return {"page": page, "pageSize": page_size, "totalRecords": total, "totalPages": pages, "records": page_recs}

@app.post("/auth/register")
async def register(r: AuthRequest):
    if r.email in _USERS:
        raise HTTPException(400, "User exists")
    user = {"id": f"u{len(_USERS) + 1}", "email": r.email, "name": r.name, "tier": "free", "tradesRemaining": 2}
    _USERS[r.email] = {"password": r.password, "user": user}
    return {"access_token": f"tok_{r.email}", "user": user}

@app.post("/auth/login")
async def login(r: AuthRequest):
    rec = _USERS.get(r.email)
    if not rec or rec["password"] != r.password:
        raise HTTPException(401, "Invalid credentials")
    return {"access_token": f"tok_{r.email}", "user": rec["user"]}

@app.get("/auth/me")
async def me():
    return {"id": "local", "email": "guest@nexus.app", "name": "Guest", "tier": "free", "tradesRemaining": 2}

@app.websocket("/ws/live")
async def ws_live(ws: WebSocket):
    await _ws_manager.connect(ws)
    try:
        init = {}
        for cfg in ALL_ASSETS:
            try:
                # 🚀 Check RAM first for instant initialization
                if cfg.symbol in LIVE_PRICES and LIVE_PRICES[cfg.symbol] > 0:
                    price_val = LIVE_PRICES[cfg.symbol]
                else:
                    price_val, _ = PriceFeed.get_latest_price(cfg)
                    
                init[cfg.symbol] = {
                    "price": round(float(price_val), 5 if _is_forex(cfg) else (3 if "JPY" in cfg.symbol else 2)), 
                    "changePct": 0.0, "direction": "FLAT", "glowIntensity": 0.0
                }
                _prev_prices.setdefault(cfg.symbol, float(price_val))
            except Exception:
                pass
                
        await ws.send_text(json.dumps({"type": "connected", "ts": datetime.now(timezone.utc).isoformat(), "data": init, "version": "13.10.0"}))
        
        while True:
            try:
                msg = await asyncio.wait_for(ws.receive_text(), timeout=60)
                payload = json.loads(msg)
                if "symbols" in payload and isinstance(payload["symbols"], list):
                    await _ws_manager.set_filter(ws, payload["symbols"])
            except asyncio.TimeoutError:
                pass
            except (WebSocketDisconnect, Exception):
                break
    finally:
        await _ws_manager.disconnect(ws)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=os.getenv("HOST", "0.0.0.0"), port=int(os.getenv("PORT", 8000)), log_level="info")