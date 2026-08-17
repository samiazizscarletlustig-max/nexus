"""
╔═══════════════════════════════════════════════════════════════════════════════╗
║          NEXUS v13.1  ─  PRO FASTAPI BACKEND (main.py)                       ║
║          Quantum Institutional Terminal Backend                              ║
║          Complete Bridge Between engine.py and Flutter/Web Frontend         ║
╚══════════════════════════════════════════════════════════════════════════════╝

FEATURES EXTRACTED FROM ENGINE.PY (v13.1):
─────────────────────────────────────────────────────────────────────────────────
  1. MULTI-LAYER SIGNAL ENGINE (7-Layer Confluence)
  2. RISK MANAGEMENT (P0 + Volatility-Adjusted Sizing + Expectancy)
  3. 30+ TECHNICAL INDICATORS & QUANTUM METRICS
  4. SMART MONEY CONCEPTS (OB, FVG, Liquidity Sweeps)
  5. PROXY ORDER FLOW & BUYING PRESSURE ESTIMATION
  6. MACRO EVENT FILTER (NFP, CPI, FOMC Auto-Lock)
  7. FINNHUB NEWS (Real-time headlines + Economic Calendar)  ← NEW
  8. WEBSOCKET LAYER (Real-time ticks, metric shifts, heartbeats)
  
  RUN COMMAND:
  ─────────────────────────────────────────────────────────────────────────────
  uvicorn main:app --reload --host 0.0.0.0 --port 8000

  PRODUCTION DEPLOYMENT:
  ────────────────────────────────────────────────────────────────────────────
  uvicorn main:app --host 0.0.0.0 --port $PORT --workers 4
"""

import os
import asyncio
import math
import re
import json
import logging
import statistics
import requests
from collections import deque
from typing import Dict, List, Any, Optional, Set, Tuple
from datetime import datetime, timezone, timedelta
from dataclasses import asdict

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# ── Engine import (STRICTLY READ-ONLY) ────────────────────────────────────────
try:
    from engine import (
        run_analysis,
        calculate_position_size,
        ASSET_MAP,
        ALL_ASSETS,
        INSTRUMENT_SPECS,
        PriceFeed,
        MathEngine,
        VolumeProfileAnalyzer,
        MonteCarloRiskEngine,
        MultiTimeframeEngine,
        MultiLayerSignalEngine,
        MarketIntelligence,
        get_correlation_matrix,
        AssetConfig,
        InstrumentSpec,
        MarketRegime,
        SignalDirection,
        NewsEngine,
        FinnhubNewsEngine,
        NewsItem,
    )
except ImportError as e:
    print(f"❌ CRITICAL: Failed to import engine.py: {e}")
    print("💡 Make sure engine.py exists in backend/ directory")
    raise

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("NEXUS-API")

# ══════════════════════════════════════════════════════════════════════════════
#  APP SETUP
# ══════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title=os.getenv("APP_NAME", "NEXUS Quantum Terminal"),
    description="Institutional-grade quantum trading intelligence API v13.1",
    version=os.getenv("APP_VERSION", "13.1.0"),
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS Configuration
allowed_origins = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# ══════════════════════════════════════════════════════════════════════════════
#  CONSTANTS & CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

_MAX_DATA_RETRIES = int(os.getenv("MAX_DATA_RETRIES", "2"))
_RETRY_DELAY_SEC = float(os.getenv("RETRY_DELAY_SEC", "1.5"))
_WS_PRICE_INTERVAL_SEC = int(os.getenv("WS_PRICE_INTERVAL_SEC", "3"))
_WS_HEARTBEAT_INTERVAL_SEC = int(os.getenv("WS_HEARTBEAT_INTERVAL_SEC", "30"))
_ARCHIVE_MAX_RECORDS = int(os.getenv("ARCHIVE_MAX_RECORDS", "500"))

_CRYPTO_TYPES = {"crypto", "cryptocurrency", "digital"}
_CRYPTO_SYMBOL_TOKENS = {
    "BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX",
    "MATIC", "LINK", "UNI", "ATOM", "LTC", "ALGO", "XLM", "VET", "NEAR",
    "FIL", "TRX", "ETC", "XMR", "SHIB", "APE",
}
_GOLD_SYMBOLS = {"XAUUSD", "XAGUSD", "GOLD", "XAUEUR", "XAUGBP"}

# News CDN placeholders
_NEWS_PLACEHOLDER: Dict[str, str] = {
    "commodity": "https://nexus-cdn.app/placeholders/gold_news.jpg",
    "crypto": "https://nexus-cdn.app/placeholders/crypto_news.jpg",
    "index": "https://nexus-cdn.app/placeholders/index_news.jpg",
    "forex": "https://nexus-cdn.app/placeholders/forex_news.jpg",
    "default": "https://nexus-cdn.app/placeholders/general_news.jpg",
}

_SOURCE_LOGO_MAP: Dict[str, str] = {
    "bloomberg": "https://nexus-cdn.app/logos/bloomberg.png",
    "reuters": "https://nexus-cdn.app/logos/reuters.png",
    "coindesk": "https://nexus-cdn.app/logos/coindesk.png",
    "cointelegraph": "https://nexus-cdn.app/logos/cointelegraph.png",
    "marketwatch": "https://nexus-cdn.app/logos/marketwatch.png",
    "yahoo finance": "https://nexus-cdn.app/logos/yahoo_finance.png",
    "finnhub": "https://nexus-cdn.app/logos/finnhub.png",
    "rss": "https://nexus-cdn.app/logos/rss_generic.png",
    "wsj": "https://nexus-cdn.app/logos/wsj.png",
    "ft": "https://nexus-cdn.app/logos/ft.png",
    "cnbc": "https://nexus-cdn.app/logos/cnbc.png",
    "default": "https://nexus-cdn.app/logos/default_source.png",
}

# ══════════════════════════════════════════════════════════════════════════════
#  IN-MEMORY CACHE & ARCHIVE
# ══════════════════════════════════════════════════════════════════════════════

_signal_archive: deque = deque(maxlen=_ARCHIVE_MAX_RECORDS)
_prev_prices: Dict[str, float] = {}
_prev_signals: Dict[str, dict] = {}

def _push_to_archive(sym: str, mi_data: dict, source: str) -> None:
    """Push signal record to archive ring-buffer with all v13.0 metrics."""
    try:
        trade_plan = mi_data.get("tradePlan", {})
        _signal_archive.appendleft({
            "id": f"{sym}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}",
            "symbol": sym,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "signal": mi_data.get("safetySignal", "WAIT"),
            "direction": mi_data.get("direction", "NEUTRAL"),
            "confidence": mi_data.get("signalConfidence", 50.0),
            "confidenceLabel": mi_data.get("confidenceLabel", "NEUTRAL"),
            "quality": mi_data.get("entryQuality", "POOR"),
            "price": mi_data.get("currentPrice", 0.0),
            "regime": mi_data.get("regimeAdvanced", "CHOPPY"),
            "source": source,
            "tradePlan": trade_plan,
            "indicators": {
                "rsi": mi_data.get("rsi"),
                "macdHist": mi_data.get("macdHist"),
                "adx": mi_data.get("adxValue"),
                "atr": mi_data.get("atr14"),
            },
            "riskMetrics": {
                "monteCarlo": mi_data.get("monteCarlo"),
                "volumeProfile": mi_data.get("volumeProfile"),
                "expectancyPerDollar": trade_plan.get("expectancyPerDollar"),
                "volatilityAdjustedRisk": trade_plan.get("volatilityAdjustedRiskPct"),
            },
            "orderFlow": trade_plan.get("proxyOrderFlow"),
        })
    except Exception as exc:
        logger.warning(f"Archive push failed [{sym}]: {exc}")

# ══════════════════════════════════════════════════════════════════════════════
#  WEBSOCKET CONNECTION MANAGER
# ══════════════════════════════════════════════════════════════════════════════

class ConnectionManager:
    def __init__(self) -> None:
        self._clients: Dict[WebSocket, Set[str]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._clients[ws] = set()
        logger.info(f"🔌 WS client connected — total: {len(self._clients)}")

    async def disconnect(self, ws: WebSocket) -> None:
        async with self._lock:
            self._clients.pop(ws, None)
        logger.info(f"🔌 WS client disconnected — total: {len(self._clients)}")

    async def set_filter(self, ws: WebSocket, symbols: List[str]) -> None:
        async with self._lock:
            if ws in self._clients:
                self._clients[ws] = {s.upper().strip() for s in symbols}
                logger.info(f"🎯 WS filter set for client: {self._clients[ws]}")

    async def broadcast(self, frame: dict) -> None:
        """Broadcast frame to all connected clients."""
        dead: List[WebSocket] = []
        async with self._lock:
            snapshot = list(self._clients.items())

        for ws, sub_filter in snapshot:
            try:
                await ws.send_text(json.dumps(frame))
            except Exception as e:
                logger.warning(f"WS send failed: {e}")
                dead.append(ws)

        for ws in dead:
            await self.disconnect(ws)

    @property
    def active_count(self) -> int:
        return len(self._clients)

_ws_manager = ConnectionManager()

# ══════════════════════════════════════════════════════════════════════════════
#  WEBSOCKET BROADCAST LOOP
# ══════════════════════════════════════════════════════════════════════════════

async def _ws_broadcast_loop() -> None:
    """Background task: broadcasts price ticks every N seconds."""
    heartbeat_counter = 0

    while True:
        await asyncio.sleep(_WS_PRICE_INTERVAL_SEC)

        if _ws_manager.active_count == 0:
            heartbeat_counter += _WS_PRICE_INTERVAL_SEC
            continue

        # Price tick frame
        tick_data: dict = {}
        ts = datetime.now(timezone.utc).isoformat()

        for cfg in ALL_ASSETS:
            sym = cfg.symbol
            try:
                price, _ = PriceFeed.get_latest_price(cfg)
                price = float(price)
                prev = _prev_prices.get(sym, price)

                pct_change = ((price - prev) / prev * 100.0) if prev else 0.0
                direction = "UP" if price > prev else "DOWN" if price < prev else "FLAT"
                glow_intensity = min(abs(pct_change) / 0.5, 1.0)

                tick_data[sym] = {
                    "price": round(price, 6 if cfg.asset_type == "forex" else 2),
                    "changePct": round(pct_change, 3),
                    "direction": direction,
                    "glowIntensity": round(glow_intensity, 4),
                }
                _prev_prices[sym] = price
            except Exception as exc:
                logger.debug(f"WS price fetch [{sym}]: {exc}")

        if tick_data:
            await _ws_manager.broadcast({
                "type": "price_tick",
                "ts": ts,
                "data": tick_data,
            })

        # Heartbeat
        heartbeat_counter += _WS_PRICE_INTERVAL_SEC
        if heartbeat_counter >= _WS_HEARTBEAT_INTERVAL_SEC:
            heartbeat_counter = 0
            await _ws_manager.broadcast({
                "type": "heartbeat",
                "ts": ts,
                "activeClients": _ws_manager.active_count,
            })

# ══════════════════════════════════════════════════════════════════════════════
#  STARTUP / SHUTDOWN
# ══════════════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def _startup() -> None:
    """Initialize background tasks on startup."""
    asyncio.create_task(_ws_broadcast_loop())
    logger.info("🚀 NEXUS v13.1 — WebSocket broadcast loop started.")
    logger.info(f"📊 Monitoring {len(ALL_ASSETS)} assets")
    logger.info(f"📦 Archive capacity: {_ARCHIVE_MAX_RECORDS} records")

@app.on_event("shutdown")
async def _shutdown() -> None:
    """Cleanup on shutdown."""
    logger.info("👋 NEXUS API shutting down...")

# ══════════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

def sanitize_float(obj: Any) -> Any:
    """Recursively replace NaN/Inf with None for JSON serialization."""
    if isinstance(obj, float):
        return None if (math.isnan(obj) or math.isinf(obj)) else obj
    if isinstance(obj, dict):
        return {k: sanitize_float(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_float(v) for v in obj]
    return obj

_CAMEL_PATTERN = re.compile(r"_([a-z])")

def _snake_to_camel(name: str) -> str:
    """Convert snake_case to camelCase."""
    return _CAMEL_PATTERN.sub(lambda m: m.group(1).upper(), name)

def to_camel_case(obj: Any) -> Any:
    """Recursively convert dict keys from snake_case to camelCase."""
    if isinstance(obj, dict):
        return {_snake_to_camel(k): to_camel_case(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [to_camel_case(v) for v in obj]
    return obj

def get_config(symbol: str) -> AssetConfig:
    """Get asset configuration by symbol."""
    sym = symbol.upper().strip()
    if sym in ASSET_MAP:
        return ASSET_MAP[sym]
    raise HTTPException(status_code=404, detail=f"Asset '{symbol}' not supported.")

def _is_crypto(cfg: AssetConfig) -> bool:
    return getattr(cfg, "asset_type", "").lower() in _CRYPTO_TYPES

def _is_forex(cfg: AssetConfig) -> bool:
    return getattr(cfg, "asset_type", "").lower() == "forex"

def _is_gold(cfg: AssetConfig) -> bool:
    return cfg.symbol.upper() in _GOLD_SYMBOLS

def _is_crypto_symbol(symbol: str, cfg: AssetConfig) -> bool:
    sym_upper = symbol.upper()
    if sym_upper in _GOLD_SYMBOLS:
        return False
    if getattr(cfg, "asset_type", "").lower() in _CRYPTO_TYPES:
        return True
    return any(tok in sym_upper for tok in _CRYPTO_SYMBOL_TOKENS)

def _decimal_places_for_asset(cfg: AssetConfig) -> int:
    if _is_forex(cfg):
        return 5
    if _is_crypto_symbol(cfg.symbol, cfg):
        return 2 if getattr(cfg, "price_hi", 10000) < 10000 else 0
    return 2

def _sentiment_label(score: float) -> str:
    """Map VADER compound [-1, +1] → human label."""
    if score >= 0.35:
        return "VERY_BULLISH"
    if score >= 0.10:
        return "BULLISH"
    if score <= -0.35:
        return "VERY_BEARISH"
    if score <= -0.10:
        return "BEARISH"
    return "NEUTRAL"

def _source_logo(source: str) -> str:
    """Get logo URL for news source."""
    lower = source.lower()
    for key, url in _SOURCE_LOGO_MAP.items():
        if key in lower:
            return url
    return _SOURCE_LOGO_MAP["default"]

def _enrich_news_item(raw: dict, asset_type: str) -> dict:
    """Enrich news item with additional metadata."""
    image_url = (
        raw.get("imageUrl") or
        raw.get("image_url") or
        raw.get("thumbnail") or
        _NEWS_PLACEHOLDER.get(asset_type, _NEWS_PLACEHOLDER["default"])
    )
    source_logo_url = _source_logo(raw.get("source", ""))
    sentiment_score = float(raw.get("sentimentScore", 0.0) or 0.0)
    
    return {
        **raw,
        "imageUrl": image_url,
        "sourceLogoUrl": source_logo_url,
        "sentimentLabel": _sentiment_label(sentiment_score),
    }

# ══════════════════════════════════════════════════════════════════════════════
#  CHART METADATA BUILDER
# ══════════════════════════════════════════════════════════════════════════════

def _market_status(cfg: AssetConfig) -> dict:
    """Determine market status based on UTC time and asset type."""
    now = datetime.now(timezone.utc)
    wday = now.weekday()
    hour = now.hour + now.minute / 60.0

    if _is_crypto_symbol(cfg.symbol, cfg):
        return {"status": "24_7", "sessionLabel": "24/7 CRYPTO MARKET"}
    
    if wday >= 5:
        return {"status": "CLOSED", "sessionLabel": "WEEKEND — MARKET CLOSED"}
    
    if cfg.asset_type == "index":
        if 13.5 <= hour < 20.0:
            return {"status": "OPEN", "sessionLabel": "US MARKET OPEN"}
        if 12.0 <= hour < 13.5:
            return {"status": "PRE_MARKET", "sessionLabel": "PRE-MARKET"}
        return {"status": "CLOSED", "sessionLabel": "US MARKET CLOSED"}
    
    # Gold / Forex
    if wday == 4 and hour >= 22.0:
        return {"status": "CLOSING", "sessionLabel": "WEEKEND APPROACHING"}
    
    return {"status": "OPEN", "sessionLabel": _active_session_label(hour)}

def _active_session_label(hour: float) -> str:
    london_open = 7.0 <= hour < 16.0
    ny_open = 12.0 <= hour < 21.0
    tokyo_open = hour >= 23.0 or hour < 8.0

    if london_open and ny_open:
        return "LONDON–NY OVERLAP"
    if tokyo_open and london_open:
        return "TOKYO–LONDON OVERLAP"
    if london_open:
        return "LONDON SESSION"
    if ny_open:
        return "NEW YORK SESSION"
    if tokyo_open:
        return "TOKYO SESSION"
    return "OFF-HOURS"

def _build_chart_metadata(cfg: AssetConfig) -> dict:
    """Build Syncfusion-ready chart configuration."""
    decimal_places = _decimal_places_for_asset(cfg)
    
    if _is_forex(cfg):
        tick_size = 0.0001
    elif cfg.symbol.upper() in _GOLD_SYMBOLS:
        tick_size = 0.10
    elif _is_crypto_symbol(cfg.symbol, cfg):
        price_hi = getattr(cfg, "price_hi", 100000.0)
        tick_size = 1.0 if price_hi > 10000 else 0.01
    elif cfg.asset_type == "index":
        tick_size = 0.25
    else:
        tick_size = 0.01

    ms = _market_status(cfg)

    return {
        "decimalPlaces": decimal_places,
        "tickSize": tick_size,
        "rightViewportPaddingPct": 5.0,
        "marketStatus": ms["status"],
        "sessionLabel": ms["sessionLabel"],
        "is24h": _is_crypto_symbol(cfg.symbol, cfg),
        "assetColor": getattr(cfg, "color", "#FFFFFF"),
        "priceFormat": f"#,##0.{'0' * decimal_places}",
    }

# ═════════════════════════════════════════════════════════════════════════════
#  REQUEST/RESPONSE MODELS
# ═════════════════════════════════════════════════════════════════════════════

class AnalyzeRequest(BaseModel):
    symbol: str
    balance: float = Field(default=10000.0, ge=100.0)
    risk_percentage: float = Field(default=1.0, ge=0.1, le=10.0)
    timeframe: str = Field(default="M5", pattern="^(M1|M5|M15|H1|H4|D1)$")
    run_mtf: bool = True
    atr_mult: float = Field(default=1.5, ge=1.0, le=3.0)
    rr_ratio: float = Field(default=2.5, ge=1.0, le=5.0)

class PositionSizeRequest(BaseModel):
    symbol: str
    balance: float = Field(..., ge=0.0)
    risk_percentage: float = Field(..., ge=0.1, le=10.0)
    entry_price: float = Field(..., gt=0.0)
    stop_loss_price: float = Field(..., gt=0.0)

# ══════════════════════════════════════════════════════════════════════════════
#  ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/")
async def root():
    """API root — status and available endpoints."""
    return {
        "status": "ONLINE",
        "system": os.getenv("APP_NAME", "NEXUS QUANTUM v13.1"),
        "version": os.getenv("APP_VERSION", "13.1.0"),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "endpoints": {
            "health": "/api/health",
            "assets": "/api/assets",
            "watchlist": "/api/watchlist",
            "ohlcv": "/api/ohlcv?symbol=XAUUSD&interval=5m",
            "analyze": "POST /api/analyze",
            "position_size": "POST /api/position-size",
            "news": "/api/news/BTCUSD",
            "calendar": "/api/calendar",
            "macro_events": "/api/macro-events",
            "correlation": "/api/correlation",
            "archive": "/api/v1/archive",
            "instrument": "/api/v1/instrument/{symbol}",
            "websocket": "/ws/live",
            "docs": "/docs",
        },
    }

@app.get("/api/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "ok",
        "engine_loaded": True,
        "ws_clients": _ws_manager.active_count,
        "archive_records": len(_signal_archive),
        "version": os.getenv("APP_VERSION", "13.1.0"),
    }

@app.get("/api/assets")
async def get_available_assets():
    """Returns list of all supported assets with full specifications."""
    return {
        "assets": [
            {
                "symbol": cfg.symbol,
                "name": cfg.name,
                "type": cfg.asset_type,
                "contract_size": cfg.contract_size,
                "pip_size": cfg.pip_size,
                "tick_size": cfg.tick_size,
                "tick_value": cfg.tick_value,
                "min_lot": cfg.min_lot,
                "max_lot": cfg.max_lot,
                "lot_step": cfg.lot_step,
                "leverage": cfg.leverage,
                "spread_pips": cfg.spread_pips,
                "is_24_7": cfg.is_24_7,
                "emoji": cfg.emoji,
                "color": cfg.color,
            }
            for cfg in ALL_ASSETS
        ]
    }

@app.get("/api/watchlist")
async def get_watchlist():
    """Live snapshot of all tracked assets."""
    results = []
    for cfg in ALL_ASSETS:
        try:
            prices, source, _ = PriceFeed.get(cfg)
            if not prices:
                results.append({
                    "symbol": cfg.symbol,
                    "name": cfg.name,
                    "type": cfg.asset_type,
                    "price": None,
                    "changePct": None,
                    "emoji": cfg.emoji,
                    "color": cfg.color,
                    "is24h": _is_crypto_symbol(cfg.symbol, cfg),
                    "chartMetadata": _build_chart_metadata(cfg),
                })
                continue

            last = float(prices[-1])
            prev = float(prices[-2]) if len(prices) > 1 else last
            chg_pct = ((last - prev) / prev * 100.0) if prev != 0 else 0.0

            results.append({
                "symbol": cfg.symbol,
                "name": cfg.name,
                "type": cfg.asset_type,
                "price": round(last, 6 if _is_forex(cfg) else 2),
                "changePct": round(chg_pct, 3),
                "emoji": cfg.emoji,
                "color": cfg.color,
                "is24h": _is_crypto_symbol(cfg.symbol, cfg),
                "chartMetadata": _build_chart_metadata(cfg),
            })
        except Exception as exc:
            logger.error(f"Watchlist error [{cfg.symbol}]: {exc}")
            results.append({
                "symbol": cfg.symbol,
                "name": cfg.name,
                "type": cfg.asset_type,
                "price": None,
                "changePct": None,
                "emoji": cfg.emoji,
                "color": cfg.color,
                "is24h": _is_crypto_symbol(cfg.symbol, cfg),
                "chartMetadata": _build_chart_metadata(cfg),
            })
    return results

@app.get("/api/ohlcv")
async def get_ohlcv(
    symbol: str = Query(..., description="Asset symbol (e.g., XAUUSD, BTCUSD)"),
    interval: str = Query("5m", description="Timeframe: 1m, 5m, 15m, 1h, 4h, 1d"),
):
    """Historical OHLCV data for charting."""
    cfg = get_config(symbol)
    interval = interval.lower().strip()

    # Map interval to yfinance parameters
    yf_map = {
        "1m": ("2d", "1m") if _is_crypto_symbol(symbol, cfg) else ("1d", "1m"),
        "5m": ("7d", "5m") if _is_crypto_symbol(symbol, cfg) else ("5d", "5m"),
        "15m": ("10d", "15m") if _is_crypto_symbol(symbol, cfg) else ("5d", "15m"),
        "1h": ("2mo", "1h") if _is_crypto_symbol(symbol, cfg) else ("1mo", "1h"),
        "4h": ("3mo", "1h") if _is_crypto_symbol(symbol, cfg) else ("3mo", "1h"),
        "1d": ("1y", "1d"),
    }

    period, yf_interval = yf_map.get(interval, ("5d", "5m"))
    decimal_places = _decimal_places_for_asset(cfg)

    try:
        raw = PriceFeed._from_yfinance_ohlcv(cfg.yf_ticker, period=period, interval=yf_interval)

        if not raw:
            return {
                "candles": [],
                "chartMetadata": _build_chart_metadata(cfg),
                "message": "No data available",
            }

        closes = raw.get("close", [])
        opens = raw.get("open", closes)
        highs = raw.get("high", closes)
        lows = raw.get("low", closes)
        volumes = raw.get("volume", [0.0] * len(closes))

        n = min(len(closes), len(opens), len(highs), len(lows))
        if n == 0:
            return {"candles": [], "chartMetadata": _build_chart_metadata(cfg)}

        # Generate timestamps
        now = datetime.now(timezone.utc)
        delta_map = {
            "1m": timedelta(minutes=1),
            "5m": timedelta(minutes=5),
            "15m": timedelta(minutes=15),
            "1h": timedelta(hours=1),
            "4h": timedelta(hours=4),
            "1d": timedelta(days=1),
        }
        delta = delta_map.get(interval, timedelta(minutes=5))
        timestamps = [(now - delta * (n - 1 - i)).isoformat() for i in range(n)]

        candles = []
        for i in range(n):
            o = float(opens[i])
            h = float(highs[i])
            lo = float(lows[i])
            c = float(closes[i])
            v = float(volumes[i]) if i < len(volumes) else 0.0

            if any(math.isnan(x) or math.isinf(x) or x <= 0 for x in (o, h, lo, c)):
                continue

            candles.append({
                "timestamp": timestamps[i],
                "open": round(o, 8),
                "high": round(h, 8),
                "low": round(lo, 8),
                "close": round(c, 8),
                "volume": round(v, 2),
                "decimalPlaces": decimal_places,
                "assetType": cfg.asset_type,
            })

        max_bars = 1000 if _is_crypto_symbol(symbol, cfg) else 500
        return {
            "candles": candles[-max_bars:],
            "chartMetadata": _build_chart_metadata(cfg),
        }

    except Exception as exc:
        logger.exception(f"OHLCV error [{symbol}]: {exc}")
        return {"candles": [], "chartMetadata": _build_chart_metadata(cfg), "error": str(exc)}

@app.post("/api/analyze")
async def analyze_assets(request: AnalyzeRequest):
    """
    Core NEXUS analysis endpoint — runs full quantum analysis pipeline (v13.1).
    Returns complete market intelligence, multi-layer signal, Monte Carlo risk, 
    volume profile, trade plan, proxy order flow, AND real Finnhub news.
    """
    cfg = get_config(request.symbol)
    sym_upper = request.symbol.upper()

    try:
        intelligence, news_items, source = run_analysis(
            cfg=cfg,
            atr_mult=request.atr_mult,
            rr_ratio=request.rr_ratio,
            initial_balance=request.balance,
            risk_per_trade=request.risk_percentage,
        )

        if not intelligence:
            raise HTTPException(status_code=500, detail="Analysis failed — no data")

        # Convert dataclass to dict
        mi_raw = asdict(intelligence)
        mi_clean = sanitize_float(mi_raw)
        mi_camel = to_camel_case(mi_clean)

        # Enrich news items
        news_list = []
        for item in (news_items or []):
            try:
                raw_dict = to_camel_case(sanitize_float(asdict(item)))
                news_list.append(_enrich_news_item(raw_dict, cfg.asset_type))
            except Exception:
                pass

        # Build response
        response_data = {
            "symbol": sym_upper,
            "source": source,
            "intelligence": mi_camel,
            "news": news_list,
            "chartMetadata": _build_chart_metadata(cfg),
        }

        # Push to archive
        _push_to_archive(sym_upper, mi_camel, source)

        # Broadcast metric shift if WebSocket clients connected
        if _ws_manager.active_count > 0:
            prev = _prev_signals.get(sym_upper, {})
            watch_fields = ["safetySignal", "direction", "signalConfidence"]
            for field_name in watch_fields:
                current_val = mi_camel.get(field_name)
                previous_val = prev.get(field_name)
                if previous_val is not None and current_val != previous_val:
                    await _ws_manager.broadcast({
                        "type": "metric_shift",
                        "ts": datetime.now(timezone.utc).isoformat(),
                        "symbol": sym_upper,
                        "field": field_name,
                        "previous": previous_val,
                        "current": current_val,
                    })
            _prev_signals[sym_upper] = {f: mi_camel.get(f) for f in watch_fields}

        return {"success": True, "data": response_data}

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception(f"Analysis failed [{request.symbol}]: {exc}")
        raise HTTPException(status_code=500, detail=f"Analysis error: {str(exc)}")

@app.post("/api/position-size")
async def calculate_position(request: PositionSizeRequest):
    """Calculate optimal position size with broker constraints (P0) + Volatility Adjustment."""
    result = calculate_position_size(
        balance=request.balance,
        risk_percentage=request.risk_percentage,
        entry_price=request.entry_price,
        stop_loss_price=request.stop_loss_price,
        symbol=request.symbol.upper(),
    )

    if "error" in result:
        return {
            "success": False,
            "error": result["error"],
            "suggestion": result.get("suggestion"),
        }

    return {"success": True, "data": result}

@app.get("/api/news/{symbol}")
async def get_news(symbol: str, days: int = Query(7, ge=1, le=30)):
    """Fetch latest real news for a specific asset from Finnhub."""
    if symbol.upper() not in ASSET_MAP:
        raise HTTPException(status_code=404, detail=f"Symbol {symbol} not supported")
    news = FinnhubNewsEngine.fetch_company_news(symbol, days_back=days)
    return {
        "success": True,
        "symbol": symbol.upper(),
        "count": len(news),
        "news": [asdict(item) for item in news]
    }

@app.get("/api/calendar")
async def get_economic_calendar(days: int = Query(7, ge=1, le=30)):
    """Fetch upcoming high-impact economic events (NFP, CPI, FOMC) from Finnhub."""
    events = FinnhubNewsEngine.fetch_economic_calendar(days_ahead=days)
    return {
        "success": True,
        "count": len(events),
        "events": events
    }

@app.get("/api/macro-events")
async def get_macro_events(days: int = Query(7, ge=1, le=30, description="Days ahead to fetch")):
    """Fetch upcoming high-impact macroeconomic events (NFP, CPI, FOMC, etc.) from Twelve Data."""
    api_key = os.getenv("TWELVE_DATA_API_KEY", "")
    if not api_key:
        raise HTTPException(status_code=500, detail="TWELVE_DATA_API_KEY not configured in .env")
    
    start_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    end_date = (datetime.now(timezone.utc) + timedelta(days=days)).strftime("%Y-%m-%d")
    
    try:
        url = "https://api.twelvedata.com/economic_calendar"
        params = {
            "apikey": api_key,
            "country": "united_states",
            "impact": "high",
            "start_date": start_date,
            "end_date": end_date,
            "format": "JSON"
        }
        response = requests.get(url, params=params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            return {"success": True, "events": data.get("values", [])}
        else:
            return {"success": False, "error": f"API Error: {response.status_code}"}
    except Exception as e:
        logger.error(f"Macro events fetch error: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch macro events")

@app.get("/api/correlation")
async def get_correlation():
    """30-day rolling correlation matrix across all assets."""
    try:
        matrix = get_correlation_matrix()
        if not matrix:
            raise HTTPException(status_code=404, detail="Correlation data unavailable")
        return sanitize_float(matrix)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception(f"Correlation error: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))

@app.get("/api/v1/instrument/{symbol}")
async def get_instrument_specs(symbol: str):
    """Get detailed instrument specifications."""
    sym_upper = symbol.upper()
    if sym_upper not in INSTRUMENT_SPECS:
        raise HTTPException(status_code=404, detail=f"Instrument {symbol} not found")

    spec = INSTRUMENT_SPECS[sym_upper]
    return {
        "symbol": spec.symbol,
        "contract_size": spec.contract_size,
        "tick_size": spec.tick_size,
        "tick_value": spec.tick_value,
        "pip_size": spec.pip_size,
        "min_lot": spec.min_lot,
        "max_lot": spec.max_lot,
        "lot_step": spec.lot_step,
        "leverage": spec.leverage,
        "spread_pips": spec.spread_pips,
    }

@app.get("/api/v1/archive")
async def get_archive(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    symbol: Optional[str] = Query(None),
    signal: Optional[str] = Query(None),
):
    """Paginated historical signal archive."""
    records: List[dict] = list(_signal_archive)

    if symbol:
        sym_upper = symbol.upper()
        records = [r for r in records if r.get("symbol") == sym_upper]

    if signal:
        sig_upper = signal.upper()
        records = [r for r in records if r.get("signal") == sig_upper]

    total_records = len(records)
    total_pages = max(1, math.ceil(total_records / page_size))
    start = (page - 1) * page_size
    end = start + page_size
    page_records = records[start:end]

    # Calculate summary statistics
    bull_count = sum(1 for r in records if r.get("direction") in ("BULLISH", "STRONG_BUY"))
    bear_count = sum(1 for r in records if r.get("direction") in ("BEARISH", "STRONG_SELL"))
    neutral_count = total_records - bull_count - bear_count

    actionable = [
        r for r in records
        if r.get("signal") in ("BUY", "SELL") and isinstance(r.get("confidence"), (int, float))
    ]
    high_conf = [r for r in actionable if r.get("confidence", 0) >= 70]
    win_rate = round(len(high_conf) / len(actionable) * 100.0, 1) if actionable else 0.0

    strengths = [r["confidence"] for r in records if isinstance(r.get("confidence"), (int, float))]
    avg_strength = round(statistics.mean(strengths), 1) if strengths else 0.0

    return {
        "page": page,
        "pageSize": page_size,
        "totalRecords": total_records,
        "totalPages": total_pages,
        "summary": {
            "winRate": win_rate,
            "avgStrength": avg_strength,
            "bullCount": bull_count,
            "bearCount": bear_count,
            "neutralCount": neutral_count,
        },
        "records": page_records,
    }

@app.websocket("/ws/live")
async def ws_live(ws: WebSocket):
    """
    Real-time WebSocket stream for live price updates and metric shifts.

    Client flow:
    1. Connect → receives "connected" frame with initial prices
    2. Optionally send: {"symbols": ["XAUUSD", "BTCUSD"]} to filter
    3. Receive:
       - price_tick every 3 seconds
       - metric_shift on signal changes
       - heartbeat every 30 seconds
    4. Disconnect → server cleans up automatically
    """
    await _ws_manager.connect(ws)

    # Send initial snapshot
    try:
        init_data: dict = {}
        for cfg in ALL_ASSETS:
            try:
                price, _ = PriceFeed.get_latest_price(cfg)
                price = float(price)
                init_data[cfg.symbol] = {
                    "price": round(price, 6 if _is_forex(cfg) else 2),
                    "changePct": 0.0,
                    "direction": "FLAT",
                    "glowIntensity": 0.0,
                }
                _prev_prices.setdefault(cfg.symbol, price)
            except Exception:
                pass

        await ws.send_text(json.dumps({
            "type": "connected",
            "ts": datetime.now(timezone.utc).isoformat(),
            "data": init_data,
            "version": os.getenv("APP_VERSION", "13.1.0"),
        }))
    except Exception as exc:
        logger.error(f"WS initial snapshot failed: {exc}")

    # Keep connection alive and handle filters
    try:
        while True:
            try:
                msg = await asyncio.wait_for(ws.receive_text(), timeout=60.0)
                payload = json.loads(msg)
                if "symbols" in payload and isinstance(payload["symbols"], list):
                    await _ws_manager.set_filter(ws, payload["symbols"])
                    await ws.send_text(json.dumps({
                        "type": "filter_ack",
                        "symbols": payload["symbols"],
                        "ts": datetime.now(timezone.utc).isoformat(),
                    }))
            except asyncio.TimeoutError:
                # No message in 60s — keep alive
                pass
            except (WebSocketDisconnect, Exception) as exc:
                logger.info(f"WS client error: {exc}")
                break
    finally:
        await _ws_manager.disconnect(ws)

# ══════════════════════════════════════════════════════════════════════════════
#  ENTRYPOINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", 8000)),
        log_level="info",
    )