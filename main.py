"""
NEXUS v12.0 — PRO FASTAPI BACKEND (main.py)
-------------------------------------------------------------------------------
Decoupled bridge between engine.py (read-only) and the Flutter frontend.

v12.0 additions over v11.3
────────────────────────────
  WEBSOCKET LAYER  /ws/live
  • ConnectionManager handles N concurrent Flutter clients.
  • Startup background task broadcasts price_tick frames every 3 s.
  • metric_shift frames are pushed when safety_signal or direction changes.
  • heartbeat frame every 30 s keeps the Flutter socket alive through proxies.
  • Per-client symbol filter: client sends {"symbols":["BTCUSD","XAUUSD"]} after
    connecting; the broadcast loop respects the filter.  Default = all assets.
  • glowIntensity (0.0–1.0) derived from normalised tick velocity for Flutter
    AnimationController binding.

  RICH NEWS PAYLOAD  (enriched in /api/analyze)
  • _enrich_news_item() is called AFTER asdict() — never touches engine output.
  • Guaranteed non-null fields: image_url, source_logo_url, impact_percentage.
  • Three-tier fallback for each field (engine value → derived → CDN placeholder).
  • sentiment_label maps sentiment_score [-1,+1] to VERY_BULLISH … VERY_BEARISH.

  HISTORICAL ARCHIVE  /api/v1/archive
  • In-memory ring-buffer (deque, max 500 records) populated by /api/analyze
    calls; no DB dependency.
  • Supports page / page_size / symbol / signal query params.
  • Returns aggregated win-rate and avg strength per page.

  CHART METADATA  (injected into /api/analyze response per symbol)
  • chart_metadata object: decimal_places, tick_size, right_viewport_padding_pct,
    market_status, session_label.
  • market_status is computed live from UTC clock + asset calendar.
  • Syncfusion-ready: decimal_places drives NumberFormat; tick_size drives
    interval on price axis.

  DEEP QUANTUM DECISION  /api/v1/deep-decision
  • Thin wrapper around engine.deep_quantum_decision() — 120 s cadence.
  • Response includes next_refresh_ms so Flutter can schedule its own timer.

  engine.py IS NEVER MODIFIED.
-------------------------------------------------------------------------------
Run: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import asyncio
import math
import re
import json
import logging
import statistics
from collections import deque
from typing import Dict, List, Any, Optional, Set
from datetime import datetime, timezone, timedelta
from dataclasses import asdict

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ── Engine import (STRICTLY READ-ONLY – never edited) ─────────────────────────
try:
    import engine
except ImportError:
    import sys
    from pathlib import Path
    sys.path.append(str(Path(__file__).parent))
    import engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("NEXUS-API")

# ══════════════════════════════════════════════════════════════════════════════
#  APP SETUP
# ══════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title="NEXUS QUANTUM API",
    description="Institutional-grade trading intelligence — Flutter bridge.",
    version="12.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ══════════════════════════════════════════════════════════════════════════════
#  CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

_MAX_DATA_RETRIES   = 2
_RETRY_DELAY_SEC    = 1.5
_WEEKEND_RETRY_WAIT = 5.0

_CRYPTO_TYPES = {"crypto", "cryptocurrency", "digital"}

_CRYPTO_SYMBOL_TOKENS = {
    "BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX",
    "MATIC", "LINK", "UNI", "ATOM", "LTC", "ALGO", "XLM", "VET", "NEAR",
    "FIL", "TRX", "ETC", "XMR", "SHIB", "APE",
}

_GOLD_SYMBOLS = {"XAUUSD", "XAGUSD", "GOLD", "XAUEUR", "XAUGBP"}

# WebSocket broadcast intervals (seconds)
_WS_PRICE_INTERVAL_SEC     = 3
_WS_HEARTBEAT_INTERVAL_SEC = 30

# Signal archive ring-buffer max size
_ARCHIVE_MAX_RECORDS = 500

# ── News CDN placeholders — Flutter UI never crashes on missing media ──────────
_NEWS_PLACEHOLDER: Dict[str, str] = {
    "commodity": "https://nexus-cdn.app/placeholders/gold_news.jpg",
    "crypto":    "https://nexus-cdn.app/placeholders/crypto_news.jpg",
    "index":     "https://nexus-cdn.app/placeholders/index_news.jpg",
    "forex":     "https://nexus-cdn.app/placeholders/forex_news.jpg",
    "default":   "https://nexus-cdn.app/placeholders/general_news.jpg",
}

_SOURCE_LOGO_MAP: Dict[str, str] = {
    "bloomberg":      "https://nexus-cdn.app/logos/bloomberg.png",
    "reuters":        "https://nexus-cdn.app/logos/reuters.png",
    "coindesk":       "https://nexus-cdn.app/logos/coindesk.png",
    "cointelegraph":  "https://nexus-cdn.app/logos/cointelegraph.png",
    "marketwatch":    "https://nexus-cdn.app/logos/marketwatch.png",
    "yahoo finance":  "https://nexus-cdn.app/logos/yahoo_finance.png",
    "finnhub calendar":"https://nexus-cdn.app/logos/finnhub.png",
    "rss":            "https://nexus-cdn.app/logos/rss_generic.png",
    "wsj":            "https://nexus-cdn.app/logos/wsj.png",
    "ft":             "https://nexus-cdn.app/logos/ft.png",
    "cnbc":           "https://nexus-cdn.app/logos/cnbc.png",
    "default":        "https://nexus-cdn.app/logos/default_source.png",
}

# ══════════════════════════════════════════════════════════════════════════════
#  IN-MEMORY SIGNAL ARCHIVE  (ring-buffer, no DB required)
# ══════════════════════════════════════════════════════════════════════════════

_signal_archive: deque = deque(maxlen=_ARCHIVE_MAX_RECORDS)

def _push_to_archive(sym: str, mi_camel: dict, source: str) -> None:
    """Called after each successful analysis. Pushes a slim record to the ring."""
    try:
        _signal_archive.appendleft({
            "id":          f"{sym}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}",
            "symbol":      sym,
            "timestamp":   datetime.now(timezone.utc).isoformat(),
            "signal":      mi_camel.get("safetySignal", "WAIT"),
            "direction":   mi_camel.get("direction", "NEUTRAL"),
            "strength":    mi_camel.get("signalStrength", 0),
            "quality":     mi_camel.get("entryQuality", "POOR"),
            "price":       mi_camel.get("currentPrice", 0.0),
            "probabilityBull": mi_camel.get("probabilityBull", 50.0),
            "regime":      mi_camel.get("regimeAdvanced", "CHOPPY"),
            "source":      source,
            "tradePlan":   mi_camel.get("tradePlan", {}),
        })
    except Exception as exc:
        logger.warning(f"Archive push failed [{sym}]: {exc}")

# ══════════════════════════════════════════════════════════════════════════════
#  WEBSOCKET CONNECTION MANAGER
# ══════════════════════════════════════════════════════════════════════════════

class ConnectionManager:
    def __init__(self) -> None:
        # Maps websocket → set of subscribed symbols (empty = all)
        self._clients: Dict[WebSocket, Set[str]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._clients[ws] = set()
        logger.info(f"WS client connected — total: {len(self._clients)}")

    async def disconnect(self, ws: WebSocket) -> None:
        async with self._lock:
            self._clients.pop(ws, None)
        logger.info(f"WS client disconnected — total: {len(self._clients)}")

    async def set_filter(self, ws: WebSocket, symbols: List[str]) -> None:
        async with self._lock:
            if ws in self._clients:
                self._clients[ws] = {s.upper() for s in symbols}

    async def broadcast(self, frame: dict) -> None:
        """Send frame to every client whose filter matches (or has no filter)."""
        frame_sym: Optional[str] = frame.get("data") and None  # price_tick has nested data
        # For metric_shift frames the symbol is top-level
        metric_sym: Optional[str] = frame.get("symbol")

        dead: List[WebSocket] = []
        async with self._lock:
            snapshot = list(self._clients.items())

        for ws, sub_filter in snapshot:
            # Determine if this client wants this frame
            if sub_filter:
                if metric_sym and metric_sym not in sub_filter:
                    continue
                if frame.get("type") == "price_tick":
                    # Filter the data dict to only subscribed symbols
                    filtered_data = {
                        k: v for k, v in frame.get("data", {}).items()
                        if k in sub_filter
                    }
                    if not filtered_data:
                        continue
                    send_frame = {**frame, "data": filtered_data}
                else:
                    send_frame = frame
            else:
                send_frame = frame

            try:
                await ws.send_text(json.dumps(send_frame))
            except Exception:
                dead.append(ws)

        for ws in dead:
            await self.disconnect(ws)

    @property
    def active_count(self) -> int:
        return len(self._clients)


_ws_manager = ConnectionManager()

# Previous price snapshot for velocity / glow calculation
_prev_prices: Dict[str, float] = {}
# Previous signal state for metric_shift detection
_prev_signals: Dict[str, dict] = {}


def _calc_glow_intensity(sym: str, current_price: float) -> float:
    """
    Normalises tick velocity to [0.0, 1.0] for Flutter AnimationController.
    Uses a rolling single-bar percent change clamped at 0.5% = full glow.
    """
    prev = _prev_prices.get(sym, current_price)
    if prev == 0:
        return 0.0
    pct = abs((current_price - prev) / prev) * 100.0
    # 0.5% move = intensity 1.0; linear below that
    intensity = min(pct / 0.5, 1.0)
    return round(intensity, 4)


def _direction_label(current: float, prev: float) -> str:
    if current > prev:
        return "UP"
    if current < prev:
        return "DOWN"
    return "FLAT"


async def _ws_broadcast_loop() -> None:
    """
    Background task started at app startup.
    Pushes price_tick every 3 s, heartbeat every 30 s.
    metric_shift pushed whenever safety_signal or direction changes.
    """
    heartbeat_counter = 0

    while True:
        await asyncio.sleep(_WS_PRICE_INTERVAL_SEC)

        if _ws_manager.active_count == 0:
            heartbeat_counter += _WS_PRICE_INTERVAL_SEC
            continue

        # ── Price tick frame ────────────────────────────────────────────────
        tick_data: dict = {}
        ts = datetime.now(timezone.utc).isoformat()

        for cfg in engine.ALL_ASSETS:
            sym = cfg.symbol
            try:
                price, _ = engine.PriceFeed.get_latest_price(cfg)
                price = float(price)
                prev  = _prev_prices.get(sym, price)

                tick_data[sym] = {
                    "price":         round(price, 6 if _is_forex(cfg) else 2),
                    "changePct":     round(((price - prev) / prev * 100.0) if prev else 0.0, 3),
                    "direction":     _direction_label(price, prev),
                    "glowIntensity": _calc_glow_intensity(sym, price),
                }
                _prev_prices[sym] = price
            except Exception as exc:
                logger.debug(f"WS price fetch [{sym}]: {exc}")

        if tick_data:
            await _ws_manager.broadcast({
                "type": "price_tick",
                "ts":   ts,
                "data": tick_data,
            })

        # ── Heartbeat ───────────────────────────────────────────────────────
        heartbeat_counter += _WS_PRICE_INTERVAL_SEC
        if heartbeat_counter >= _WS_HEARTBEAT_INTERVAL_SEC:
            heartbeat_counter = 0
            await _ws_manager.broadcast({
                "type": "heartbeat",
                "ts":   ts,
                "activeClients": _ws_manager.active_count,
            })


async def _push_metric_shift(sym: str, mi_camel: dict) -> None:
    """
    Compare current signal state against previous snapshot.
    Broadcast metric_shift frame for safetySignal or direction changes.
    """
    prev = _prev_signals.get(sym, {})
    ts   = datetime.now(timezone.utc).isoformat()

    watch_fields = ["safetySignal", "direction", "probabilityLabel", "regimeAdvanced"]
    for field_name in watch_fields:
        current_val  = mi_camel.get(field_name)
        previous_val = prev.get(field_name)
        if previous_val is not None and current_val != previous_val:
            await _ws_manager.broadcast({
                "type":     "metric_shift",
                "ts":       ts,
                "symbol":   sym,
                "field":    field_name,
                "previous": previous_val,
                "current":  current_val,
                "delta":    None,
            })

    _prev_signals[sym] = {f: mi_camel.get(f) for f in watch_fields}


# ══════════════════════════════════════════════════════════════════════════════
#  STARTUP / SHUTDOWN
# ══════════════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def _startup() -> None:
    asyncio.create_task(_ws_broadcast_loop())
    logger.info("NEXUS v12.0 — WebSocket broadcast loop started.")


# ══════════════════════════════════════════════════════════════════════════════
#  UTILITIES  (unchanged from v11.3)
# ══════════════════════════════════════════════════════════════════════════════

def sanitize_float(obj: Any) -> Any:
    """Recursively replace NaN / Inf with None so JSON serialization never fails."""
    if isinstance(obj, float):
        return None if (math.isnan(obj) or math.isinf(obj)) else obj
    if isinstance(obj, dict):
        return {k: sanitize_float(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_float(v) for v in obj]
    return obj


_CAMEL_PATTERN = re.compile(r"_([a-z])")


def _snake_to_camel(name: str) -> str:
    return _CAMEL_PATTERN.sub(lambda m: m.group(1).upper(), name)


def to_camel_case(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {_snake_to_camel(k): to_camel_case(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [to_camel_case(v) for v in obj]
    return obj


def get_config(symbol: str) -> "engine.AssetConfig":
    sym = symbol.upper().strip()
    if sym in engine.ASSET_MAP:
        return engine.ASSET_MAP[sym]
    raise HTTPException(
        status_code=404,
        detail=f"Asset '{symbol}' not supported by NEXUS engine.",
    )


def _is_crypto(cfg: "engine.AssetConfig") -> bool:
    return getattr(cfg, "asset_type", "").lower() in _CRYPTO_TYPES


def _is_forex(cfg: "engine.AssetConfig") -> bool:
    return getattr(cfg, "asset_type", "").lower() == "forex"


def _is_gold(cfg: "engine.AssetConfig") -> bool:
    return cfg.symbol.upper() in _GOLD_SYMBOLS


def _is_crypto_symbol(symbol: str, cfg: "engine.AssetConfig") -> bool:
    sym_upper = symbol.upper()
    if sym_upper in _GOLD_SYMBOLS:
        return False
    if getattr(cfg, "asset_type", "").lower() in _CRYPTO_TYPES:
        return True
    return any(tok in sym_upper for tok in _CRYPTO_SYMBOL_TOKENS)


def _is_weekend() -> bool:
    return datetime.now(timezone.utc).weekday() >= 5


def _synthesise_timestamps(n: int, interval: str) -> List[str]:
    delta_map: dict = {
        "1m":  timedelta(minutes=1),
        "5m":  timedelta(minutes=5),
        "15m": timedelta(minutes=15),
        "1h":  timedelta(hours=1),
        "4h":  timedelta(hours=4),
        "1d":  timedelta(days=1),
    }
    delta = delta_map.get(interval, timedelta(minutes=5))
    now   = datetime.now(timezone.utc)
    return [(now - delta * (n - 1 - i)).isoformat() for i in range(n)]


def _decimal_places_for_asset(cfg: "engine.AssetConfig") -> int:
    if _is_forex(cfg):
        return 5
    if _is_crypto_symbol(cfg.symbol, cfg):
        return 2
    return 2


# ══════════════════════════════════════════════════════════════════════════════
#  CHART METADATA BUILDER  (v12.0 — new)
# ══════════════════════════════════════════════════════════════════════════════

def _market_status(cfg: "engine.AssetConfig") -> dict:
    """
    Returns {"status": "OPEN"|"CLOSED"|"PRE_MARKET"|"24_7", "session_label": str}
    based on UTC clock and asset calendar.

    Crypto is always OPEN.
    Gold / Forex: Mon 00:00 – Fri 22:00 UTC (approximate; exchange-agnostic).
    Index (SPX): weekdays 13:30 – 20:00 UTC.
    """
    now   = datetime.now(timezone.utc)
    wday  = now.weekday()   # 0=Mon … 6=Sun
    hour  = now.hour + now.minute / 60.0

    if _is_crypto_symbol(cfg.symbol, cfg):
        return {"status": "24_7", "sessionLabel": "24/7 CRYPTO MARKET"}

    if wday >= 5:   # Saturday or Sunday
        return {"status": "CLOSED", "sessionLabel": "WEEKEND — MARKET CLOSED"}

    if cfg.asset_type == "index":
        if 13.5 <= hour < 20.0:
            return {"status": "OPEN",      "sessionLabel": "US MARKET OPEN"}
        if 12.0 <= hour < 13.5:
            return {"status": "PRE_MARKET","sessionLabel": "PRE-MARKET"}
        return     {"status": "CLOSED",    "sessionLabel": "US MARKET CLOSED"}

    # Gold / Forex — Sun 22:00 to Fri 22:00 UTC
    if wday == 4 and hour >= 22.0:
        return {"status": "CLOSED", "sessionLabel": "WEEKEND CLOSE APPROACHING"}
    return {"status": "OPEN", "sessionLabel": _active_session_label(hour)}


def _active_session_label(hour: float) -> str:
    london_open = 7.0  <= hour < 16.0
    ny_open     = 12.0 <= hour < 21.0
    tokyo_open  = hour >= 23.0 or hour < 8.0

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


def _build_chart_metadata(cfg: "engine.AssetConfig") -> dict:
    """
    Syncfusion-ready chart configuration object injected into every
    /api/analyze symbol response.

    decimal_places        → SfCartesianChart numberFormat
    tick_size             → interval on price axis
    rightViewportPaddingPct → chart right margin % so latest candle isn't clipped
    marketStatus          → Flutter UI badge (green OPEN / red CLOSED)
    sessionLabel          → trading session string
    """
    decimal_places = _decimal_places_for_asset(cfg)

    if _is_forex(cfg):
        tick_size = 0.0001
    elif cfg.symbol.upper() in _GOLD_SYMBOLS:
        tick_size = 0.10
    elif _is_crypto_symbol(cfg.symbol, cfg):
        price_hi = getattr(cfg, "price_hi", 100000.0)
        if price_hi > 10000:
            tick_size = 1.0    # BTC-scale
        else:
            tick_size = 0.01   # ETH-scale
    elif cfg.asset_type == "index":
        tick_size = 0.25
    else:
        tick_size = 0.01

    ms = _market_status(cfg)

    return {
        "decimalPlaces":             decimal_places,
        "tickSize":                  tick_size,
        "rightViewportPaddingPct":   5.0,
        "marketStatus":              ms["status"],
        "sessionLabel":              ms["sessionLabel"],
        "is24h":                     _is_crypto_symbol(cfg.symbol, cfg),
        "assetColor":                getattr(cfg, "color", "#FFFFFF"),
        "priceFormat":               f"#,##0.{'0' * decimal_places}",
    }


# ══════════════════════════════════════════════════════════════════════════════
#  NEWS ENRICHMENT  (v12.0 — new)
# ══════════════════════════════════════════════════════════════════════════════

def _sentiment_label(score: float) -> str:
    """Map VADER compound [-1, +1] → human label."""
    if score >= 0.35:   return "VERY_BULLISH"
    if score >= 0.10:   return "BULLISH"
    if score <= -0.35:  return "VERY_BEARISH"
    if score <= -0.10:  return "BEARISH"
    return "NEUTRAL"


def _impact_pct_from_category(category: str) -> float:
    """Derive impact_percentage from engine category when not provided directly."""
    mapping = {
        "CRITICAL": 95.0,
        "HIGH":     75.0,
        "MEDIUM":   50.0,
        "LOW":      20.0,
    }
    return mapping.get(category.upper(), 50.0)


def _source_logo(source: str) -> str:
    """Best-effort logo URL from known source names. Never returns None."""
    lower = source.lower()
    for key, url in _SOURCE_LOGO_MAP.items():
        if key in lower:
            return url
    return _SOURCE_LOGO_MAP["default"]


def _enrich_news_item(raw: dict, asset_type: str) -> dict:
    """
    Guarantees image_url, source_logo_url, impact_percentage, sentiment_label
    are always present and non-null in the Flutter news payload.

    Priority chain:
      image_url        → engine field → thumbnail field → CDN placeholder
      source_logo_url  → lookup table → CDN default
      impact_percentage→ engine field → category-derived → 50.0
      sentiment_label  → derived from sentiment_score
    """
    # ── image_url ──────────────────────────────────────────────────────────
    image_url = (
        raw.get("imageUrl") or
        raw.get("image_url") or
        raw.get("thumbnail") or
        _NEWS_PLACEHOLDER.get(asset_type, _NEWS_PLACEHOLDER["default"])
    )

    # ── source_logo_url ────────────────────────────────────────────────────
    source_logo_url = _source_logo(raw.get("source", ""))

    # ── impact_percentage ──────────────────────────────────────────────────
    raw_impact = raw.get("impactPercentage") or raw.get("impact_percentage")
    if raw_impact is not None:
        try:
            impact_percentage = float(raw_impact)
        except (TypeError, ValueError):
            impact_percentage = _impact_pct_from_category(raw.get("category", "LOW"))
    else:
        # Derive from category (already set by engine) or fallback 50
        impact_percentage = _impact_pct_from_category(raw.get("category", "LOW"))

    # ── sentiment_label (derived — always present) ─────────────────────────
    sentiment_score = float(raw.get("sentimentScore", 0.0) or 0.0)
    sentiment_label = _sentiment_label(sentiment_score)

    return {
        **raw,
        "imageUrl":         image_url,
        "sourceLogoUrl":    source_logo_url,
        "impactPercentage": round(impact_percentage, 1),
        "sentimentLabel":   sentiment_label,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  CRYPTO-SPECIFIC ANALYTICS  (unchanged from v11.3)
# ══════════════════════════════════════════════════════════════════════════════

def _compute_volume_delta(
    volumes: List[float],
    closes:  List[float],
    opens:   List[float],
) -> dict:
    n = min(len(volumes), len(closes), len(opens))
    if n == 0:
        return {
            "buy_volume": 0.0, "sell_volume": 0.0,
            "volume_delta": 0.0, "volume_delta_pct": 0.0,
            "volume_delta_signal": "NEUTRAL",
        }

    buy_vol  = sum(volumes[i] for i in range(n) if closes[i] >= opens[i])
    sell_vol = sum(volumes[i] for i in range(n) if closes[i] <  opens[i])
    total    = buy_vol + sell_vol
    delta    = buy_vol - sell_vol
    delta_pct = (delta / total * 100.0) if total > 0 else 0.0

    signal = (
        "BULLISH_PRESSURE" if delta_pct > 10  else
        "BEARISH_PRESSURE" if delta_pct < -10 else
        "NEUTRAL"
    )

    return {
        "buy_volume":          round(buy_vol,   2),
        "sell_volume":         round(sell_vol,  2),
        "volume_delta":        round(delta,     2),
        "volume_delta_pct":    round(delta_pct, 2),
        "volume_delta_signal": signal,
    }


def _compute_crypto_volatility_band(
    closes:   List[float],
    atr14:    float,
    lookback: int = 20,
) -> dict:
    if len(closes) < lookback or atr14 <= 0:
        price = closes[-1] if closes else 0.0
        return {
            "cavb_upper": price, "cavb_mid": price, "cavb_lower": price,
            "cavb_width": 0.0,  "normalized_bandwidth": 0.0,
            "cavb_signal": "NORMAL", "cavb_position": "MIDDLE",
        }

    window = closes[-lookback:]
    mid    = statistics.mean(window)
    std    = statistics.pstdev(window)
    mult   = 2.5

    upper  = mid + mult * std
    lower  = mid - mult * std
    width  = upper - lower
    norm_bw = width / atr14 if atr14 > 0 else 0.0
    price  = closes[-1]

    signal = (
        "SQUEEZE"   if norm_bw < 1.0 else
        "EXPANSION" if norm_bw > 4.0 else
        "NORMAL"
    )

    if   price > upper:            position = "ABOVE_UPPER"
    elif price < lower:            position = "BELOW_LOWER"
    elif price > mid + 0.5 * std: position = "NEAR_UPPER"
    elif price < mid - 0.5 * std: position = "NEAR_LOWER"
    else:                          position = "MIDDLE"

    return {
        "cavb_upper":           round(upper,   8),
        "cavb_mid":             round(mid,     8),
        "cavb_lower":           round(lower,   8),
        "cavb_width":           round(width,   8),
        "normalized_bandwidth": round(norm_bw, 4),
        "cavb_signal":          signal,
        "cavb_position":        position,
    }


def _build_crypto_metrics(
    cfg:     "engine.AssetConfig",
    closes:  List[float],
    opens:   List[float],
    volumes: List[float],
    atr14:   float,
) -> dict:
    vol_delta  = _compute_volume_delta(volumes, closes, opens)
    cavb       = _compute_crypto_volatility_band(closes, atr14)

    now_utc      = datetime.now(timezone.utc)
    is_weekend   = now_utc.weekday() >= 5
    session_note = (
        "WEEKEND — elevated volatility, thinner order books"
        if is_weekend
        else "WEEKDAY — normal 24/7 liquidity"
    )

    bars_24h       = min(288, len(closes))
    change_24h_pct = 0.0
    if bars_24h > 1 and closes[-bars_24h] != 0:
        change_24h_pct = (
            (closes[-1] - closes[-bars_24h]) / closes[-bars_24h] * 100.0
        )

    return {
        "is_24h_market":   True,
        "session_note":    session_note,
        "is_weekend":      is_weekend,
        "change_24h_pct":  round(change_24h_pct, 4),
        **vol_delta,
        **cavb,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  REQUEST MODELS
# ══════════════════════════════════════════════════════════════════════════════

class AnalyzeRequest(BaseModel):
    symbols:  List[str] = Field(default_factory=list)
    run_mtf:  bool      = True
    atr_mult: float     = 1.5
    rr_ratio: float     = 2.5


# ══════════════════════════════════════════════════════════════════════════════
#  SAFE DATA-FETCH HELPERS  (unchanged from v11.3)
# ══════════════════════════════════════════════════════════════════════════════

async def _safe_fetch_ohlcv(
    cfg:         "engine.AssetConfig",
    period:      str,
    yf_interval: str,
) -> Optional[dict]:
    is_crypto_asset = _is_crypto_symbol(cfg.symbol, cfg)
    last_exc: Optional[Exception] = None

    for attempt in range(1, _MAX_DATA_RETRIES + 1):
        try:
            raw = engine.PriceFeed._from_yfinance_ohlcv(
                cfg.yf_ticker, period=period, interval=yf_interval
            )
            if raw:
                return raw
        except Exception as exc:
            last_exc = exc
            err_str  = str(exc).lower()
            is_rate_limit = any(
                tok in err_str
                for tok in ("rate limit", "too many requests", "429", "throttle")
            )
            if is_crypto_asset:
                wait = _RETRY_DELAY_SEC if not is_rate_limit else _RETRY_DELAY_SEC * 2
            else:
                base = _WEEKEND_RETRY_WAIT if _is_weekend() else _RETRY_DELAY_SEC
                wait = base * 3 if is_rate_limit else base

            logger.warning(
                f"OHLCV fetch attempt {attempt}/{_MAX_DATA_RETRIES} "
                f"[{cfg.symbol}]: {exc} — retrying in {wait:.1f}s"
            )
            if attempt < _MAX_DATA_RETRIES:
                await asyncio.sleep(wait)

    logger.error(
        f"OHLCV fetch failed [{cfg.symbol}] after {_MAX_DATA_RETRIES} "
        f"attempts: {last_exc}"
    )
    return None


async def _safe_get_prices(
    cfg: "engine.AssetConfig",
) -> tuple:
    last_exc: Optional[Exception] = None
    is_crypto_asset = _is_crypto_symbol(cfg.symbol, cfg)

    for attempt in range(1, _MAX_DATA_RETRIES + 1):
        try:
            prices, source, extra = engine.PriceFeed.get(cfg)
            if prices:
                return prices, source, extra
        except Exception as exc:
            last_exc = exc
            err_str  = str(exc).lower()
            is_rate_limit = any(
                tok in err_str
                for tok in ("rate limit", "too many requests", "429", "throttle")
            )
            if is_crypto_asset:
                wait = _RETRY_DELAY_SEC if not is_rate_limit else _RETRY_DELAY_SEC * 2
            else:
                base = _WEEKEND_RETRY_WAIT if _is_weekend() else _RETRY_DELAY_SEC
                wait = base * 3 if is_rate_limit else base

            logger.warning(
                f"PriceFeed.get attempt {attempt}/{_MAX_DATA_RETRIES} "
                f"[{cfg.symbol}]: {exc} — retrying in {wait:.1f}s"
            )
            if attempt < _MAX_DATA_RETRIES:
                await asyncio.sleep(wait)

    logger.error(f"PriceFeed.get failed [{cfg.symbol}]: {last_exc}")
    return [], "unavailable", None


# ══════════════════════════════════════════════════════════════════════════════
#  ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/")
async def root():
    return {
        "status":    "ONLINE",
        "system":    "NEXUS QUANTUM v12.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "endpoints": [
            "/api/analyze",
            "/api/watchlist",
            "/api/ohlcv",
            "/api/correlation",
            "/api/v1/archive",
            "/api/v1/deep-decision",
            "/ws/live",
        ],
    }


@app.get("/api/health")
async def health():
    return {
        "status":          "ok",
        "engine_loaded":   engine is not None,
        "ws_clients":      _ws_manager.active_count,
        "archive_records": len(_signal_archive),
        "version":         "12.0.0",
    }


# ── WebSocket endpoint ────────────────────────────────────────────────────────

@app.websocket("/ws/live")
async def ws_live(ws: WebSocket):
    """
    Real-time price tick + metric shift stream for Flutter UI.

    Connection lifecycle
    ────────────────────
    1. Client connects.
    2. Server sends an initial "connected" frame with current prices.
    3. Client optionally sends: {"symbols": ["BTCUSD", "XAUUSD"]}
       to filter the stream.  Omit for all assets.
    4. Server pushes:
         • price_tick  every ~3 s
         • metric_shift on signal/direction change (triggered by /api/analyze)
         • heartbeat   every 30 s
    5. Client disconnects → server cleans up silently.

    Frame schemas
    ─────────────
    price_tick:
      {
        "type":  "price_tick",
        "ts":    "ISO-8601",
        "data": {
          "XAUUSD": {
            "price":         2341.85,
            "changePct":     0.12,
            "direction":     "UP",
            "glowIntensity": 0.73
          }
        }
      }

    metric_shift:
      {
        "type":     "metric_shift",
        "ts":       "ISO-8601",
        "symbol":   "BTCUSD",
        "field":    "safetySignal",
        "previous": "WAIT",
        "current":  "BUY",
        "delta":    null
      }

    heartbeat:
      {"type": "heartbeat", "ts": "ISO-8601", "activeClients": 3}
    """
    await _ws_manager.connect(ws)

    # Send immediate snapshot so Flutter does not wait 3 s for first paint
    try:
        init_data: dict = {}
        for cfg in engine.ALL_ASSETS:
            try:
                price, _ = engine.PriceFeed.get_latest_price(cfg)
                price = float(price)
                init_data[cfg.symbol] = {
                    "price":         round(price, 6 if _is_forex(cfg) else 2),
                    "changePct":     0.0,
                    "direction":     "FLAT",
                    "glowIntensity": 0.0,
                }
                _prev_prices.setdefault(cfg.symbol, price)
            except Exception:
                pass

        await ws.send_text(json.dumps({
            "type": "connected",
            "ts":   datetime.now(timezone.utc).isoformat(),
            "data": init_data,
            "version": "12.0.0",
        }))
    except Exception:
        pass

    try:
        while True:
            try:
                msg = await asyncio.wait_for(ws.receive_text(), timeout=60.0)
                payload = json.loads(msg)
                if "symbols" in payload and isinstance(payload["symbols"], list):
                    await _ws_manager.set_filter(ws, payload["symbols"])
                    await ws.send_text(json.dumps({
                        "type":    "filter_ack",
                        "symbols": payload["symbols"],
                        "ts":      datetime.now(timezone.utc).isoformat(),
                    }))
            except asyncio.TimeoutError:
                # No message from client in 60 s — that's fine, keep alive
                pass
            except (WebSocketDisconnect, Exception):
                break
    finally:
        await _ws_manager.disconnect(ws)


# ── Watchlist ─────────────────────────────────────────────────────────────────

@app.get("/api/watchlist")
async def get_watchlist():
    """Snapshot of all tracked assets: symbol, name, price, % change."""
    results = []
    for cfg in engine.ALL_ASSETS:
        try:
            prices, source, _ = await _safe_get_prices(cfg)
            if not prices:
                results.append({
                    "symbol":    cfg.symbol,
                    "name":      cfg.name,
                    "type":      cfg.asset_type,
                    "price":     None,
                    "changePct": None,
                    "emoji":     cfg.emoji,
                    "color":     cfg.color,
                    "is24h":     _is_crypto_symbol(cfg.symbol, cfg),
                    "chartMetadata": _build_chart_metadata(cfg),
                })
                continue
            last    = float(prices[-1])
            prev    = float(prices[-2]) if len(prices) > 1 else last
            chg_pct = ((last - prev) / prev * 100.0) if prev != 0 else 0.0
            results.append({
                "symbol":    cfg.symbol,
                "name":      cfg.name,
                "type":      cfg.asset_type,
                "price":     round(last, 6 if _is_forex(cfg) else 2),
                "changePct": round(chg_pct, 3),
                "emoji":     cfg.emoji,
                "color":     cfg.color,
                "is24h":     _is_crypto_symbol(cfg.symbol, cfg),
                "chartMetadata": _build_chart_metadata(cfg),
            })
        except Exception as exc:
            logger.error(f"Watchlist error [{cfg.symbol}]: {exc}")
            results.append({
                "symbol":    cfg.symbol,
                "name":      cfg.name,
                "type":      cfg.asset_type,
                "price":     None,
                "changePct": None,
                "emoji":     cfg.emoji,
                "color":     cfg.color,
                "is24h":     _is_crypto_symbol(cfg.symbol, cfg),
                "chartMetadata": _build_chart_metadata(cfg),
            })
    return results


# ── OHLCV ─────────────────────────────────────────────────────────────────────

@app.get("/api/ohlcv")
async def get_ohlcv(
    symbol:   str = Query(..., description="e.g. BTCUSD, XAUUSD, EURUSD"),
    interval: str = Query("5m", description="1m | 5m | 15m | 1h | 4h | 1d"),
):
    """
    Historical OHLCV bars.

    JSON shape per candle:
    {
      "timestamp":     "2025-06-01T12:05:00+00:00",
      "open":          2345.12,
      "high":          2347.80,
      "low":           2340.50,
      "close":         2346.00,
      "volume":        14523.0,
      "decimalPlaces": 2,
      "assetType":     "crypto"
    }

    v12.0 note: chartMetadata appended to response wrapper for Syncfusion init.
    """
    cfg              = get_config(symbol)
    interval         = interval.lower().strip()
    is_crypto_asset  = _is_crypto_symbol(symbol, cfg)
    is_forex_asset   = _is_forex(cfg)
    decimal_places   = _decimal_places_for_asset(cfg)

    if is_crypto_asset:
        yf_map = {
            "1m":  ("2d",  "1m"),
            "5m":  ("7d",  "5m"),
            "15m": ("10d", "15m"),
            "1h":  ("2mo", "1h"),
            "4h":  ("3mo", "1h"),
            "1d":  ("1y",  "1d"),
        }
    elif is_forex_asset:
        yf_map = {
            "1m":  ("1d",  "1m"),
            "5m":  ("5d",  "5m"),
            "15m": ("5d",  "15m"),
            "1h":  ("1mo", "1h"),
            "4h":  ("3mo", "1h"),
            "1d":  ("1y",  "1d"),
        }
    else:
        yf_map = {
            "1m":  ("1d",  "1m"),
            "5m":  ("5d",  "5m"),
            "15m": ("5d",  "15m"),
            "1h":  ("1mo", "1h"),
            "4h":  ("3mo", "1h"),
            "1d":  ("1y",  "1d"),
        }

    period, yf_interval = yf_map.get(interval, ("5d", "5m"))

    try:
        raw = await _safe_fetch_ohlcv(cfg, period=period, yf_interval=yf_interval)

        if not raw:
            logger.warning(f"OHLCV returned empty for [{symbol}/{interval}]")
            return {"candles": [], "chartMetadata": _build_chart_metadata(cfg)}

        closes  = raw.get("close",  [])
        opens   = raw.get("open",   closes)
        highs   = raw.get("high",   closes)
        lows    = raw.get("low",    closes)
        volumes = raw.get("volume", [0.0] * len(closes))

        n = min(len(closes), len(opens), len(highs), len(lows))
        if n == 0:
            return {"candles": [], "chartMetadata": _build_chart_metadata(cfg)}

        timestamps = _synthesise_timestamps(n, interval)
        candles    = []

        for i in range(n):
            o  = float(opens[i])
            h  = float(highs[i])
            lo = float(lows[i])
            c  = float(closes[i])
            v  = float(volumes[i]) if i < len(volumes) else 0.0

            if any(math.isnan(x) or math.isinf(x) or x <= 0 for x in (o, h, lo, c)):
                continue

            candles.append({
                "timestamp":     timestamps[i],
                "open":          round(o,  8),
                "high":          round(h,  8),
                "low":           round(lo, 8),
                "close":         round(c,  8),
                "volume":        round(v,  2),
                "decimalPlaces": decimal_places,
                "assetType":     cfg.asset_type,
            })

        max_bars = 1000 if is_crypto_asset else 500
        return {
            "candles":       candles[-max_bars:],
            "chartMetadata": _build_chart_metadata(cfg),
        }

    except Exception as exc:
        logger.exception(f"OHLCV error [{symbol}]: {exc}")
        return {"candles": [], "chartMetadata": _build_chart_metadata(cfg)}


# ── Core Analysis ─────────────────────────────────────────────────────────────

@app.post("/api/analyze")
async def analyze_assets(req: AnalyzeRequest):
    """
    Core NEXUS analysis endpoint — v12.0.

    Enhancements over v11.3:
    • chart_metadata injected per-symbol (Syncfusion binding).
    • News items enriched with image_url, source_logo_url, impact_percentage.
    • Successful analysis records pushed to in-memory archive ring-buffer.
    • metric_shift WebSocket frames broadcast on signal state changes.

    Response shape:
    {
      "XAUUSD": {
        "intelligence":  {..., "chartMetadata": {...}},
        "news":          [{..., "imageUrl": "...", "sourceLogoUrl": "...", "impactPercentage": 75.0}],
        "source":        "..."
      }
    }
    """
    symbols = req.symbols if req.symbols else [a.symbol for a in engine.ALL_ASSETS]
    results: dict = {}

    for sym in symbols:
        try:
            cfg = get_config(sym)

            gold_asset   = _is_gold(cfg)
            crypto_asset = _is_crypto_symbol(sym, cfg) and not gold_asset

            # ── Core engine analysis (IMMUTABLE) ─────────────────────────────
            mi, news_items, source = engine.run_analysis(
                cfg,
                atr_mult=req.atr_mult,
                rr_ratio=req.rr_ratio,
                run_mtf=req.run_mtf,
            )

            if not mi:
                logger.warning(f"engine.run_analysis returned None MI for [{sym}]")
                continue

            # ── Serialise MI ──────────────────────────────────────────────────
            mi_raw   = asdict(mi)
            mi_clean = sanitize_float(mi_raw)
            mi_camel = to_camel_case(mi_clean)

            # ── Crypto enrichment ─────────────────────────────────────────────
            if crypto_asset:
                crypto_block: dict = {}
                try:
                    raw_ohlcv = await _safe_fetch_ohlcv(
                        cfg, period="5d", yf_interval="5m"
                    )

                    if raw_ohlcv:
                        closes  = [float(x) for x in raw_ohlcv.get("close",  [])]
                        opens   = [float(x) for x in raw_ohlcv.get("open",   closes)]
                        volumes = [float(x) for x in raw_ohlcv.get("volume", [])]
                    else:
                        prices, _, _ = await _safe_get_prices(cfg)
                        closes  = [float(p) for p in prices] if prices else []
                        opens   = closes
                        volumes = []

                    atr14_val = float(mi_clean.get("atr14", 0.0) or 0.0)
                    raw_metrics  = _build_crypto_metrics(cfg, closes, opens, volumes, atr14_val)
                    crypto_block = to_camel_case(sanitize_float(raw_metrics))

                except Exception as cm_exc:
                    logger.warning(f"cryptoMetrics build failed [{sym}]: {cm_exc}")
                    crypto_block = {}

                mi_camel["cryptoMetrics"] = crypto_block

            # ── Forex enrichment ──────────────────────────────────────────────
            elif _is_forex(cfg):
                try:
                    fm_raw = _build_forex_metrics(cfg, mi_clean)
                    mi_camel["forexMetrics"] = to_camel_case(sanitize_float(fm_raw))
                except Exception as fm_exc:
                    logger.warning(f"forexMetrics build failed [{sym}]: {fm_exc}")
                    mi_camel["forexMetrics"] = {}

            # ── v12.0: inject chart metadata ──────────────────────────────────
            mi_camel["chartMetadata"] = _build_chart_metadata(cfg)

            # ── v12.0: enrich news items ──────────────────────────────────────
            news_list: list = []
            for item in (news_items or []):
                try:
                    raw_dict     = to_camel_case(sanitize_float(asdict(item)))
                    enriched     = _enrich_news_item(raw_dict, cfg.asset_type)
                    news_list.append(enriched)
                except Exception:
                    pass

            results[sym] = {
                "intelligence": mi_camel,
                "news":         news_list,
                "source":       source,
            }

            # ── v12.0: push archive record + WebSocket metric_shift ───────────
            _push_to_archive(sym, mi_camel, source)
            if _ws_manager.active_count > 0:
                await _push_metric_shift(sym, mi_camel)

        except HTTPException:
            raise
        except Exception as exc:
            logger.exception(f"Analysis failed [{sym}]: {exc}")
            continue

    if not results:
        raise HTTPException(
            status_code=500,
            detail="Analysis failed for all requested symbols.",
        )

    return results


# ── Forex helpers (unchanged from v11.3) ──────────────────────────────────────

def _build_forex_metrics(cfg: "engine.AssetConfig", mi_clean: dict) -> dict:
    sym         = cfg.symbol.upper()
    is_jpy_pair = sym.endswith("JPY") or "JPY" in sym
    pip_size    = 0.01 if is_jpy_pair else 0.0001

    now_utc     = datetime.now(timezone.utc)
    hour        = now_utc.hour
    london_open = 7  <= hour < 16
    ny_open     = 12 <= hour < 21
    tokyo_open  = 23 <= hour or hour < 8

    if london_open and ny_open:
        overlap = "LONDON-NY"
    elif tokyo_open and london_open:
        overlap = "TOKYO-LONDON"
    elif london_open:
        overlap = "LONDON"
    elif ny_open:
        overlap = "NEW YORK"
    elif tokyo_open:
        overlap = "TOKYO"
    else:
        overlap = "OFF-HOURS"

    is_overlap = overlap in ("LONDON-NY", "TOKYO-LONDON")
    change_24h = float(mi_clean.get("price_change_pct", 0.0) or 0.0)

    return {
        "pip_size":           pip_size,
        "is_jpy_pair":        is_jpy_pair,
        "session_overlap":    overlap,
        "is_overlap_session": is_overlap,
        "change_24h_pct":     round(change_24h, 4),
    }


# ── Correlation ───────────────────────────────────────────────────────────────

@app.get("/api/correlation")
async def get_correlation():
    """30-day rolling asset correlation matrix."""
    try:
        matrix = engine.get_correlation_matrix()
        if not matrix:
            raise HTTPException(status_code=404, detail="Correlation data unavailable.")
        return sanitize_float(matrix)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception(f"Correlation error: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))


# ── Historical Archive  (v12.0 — new) ────────────────────────────────────────

@app.get("/api/v1/archive")
async def get_archive(
    page:      int = Query(1,    ge=1,  description="Page number (1-indexed)"),
    page_size: int = Query(20,   ge=1,  le=100, description="Records per page"),
    symbol:    str = Query(None, description="Filter by symbol e.g. XAUUSD"),
    signal:    str = Query(None, description="Filter by signal e.g. BUY, SELL, WAIT"),
):
    """
    Paginated historical signal archive sourced from the in-memory ring-buffer.
    The buffer is populated on every /api/analyze call (max 500 records, LIFO).

    Response:
    {
      "page":        1,
      "pageSize":    20,
      "totalRecords":87,
      "totalPages":  5,
      "filters":     {"symbol": "XAUUSD", "signal": null},
      "summary": {
        "winRate":      63.2,
        "avgStrength":  72,
        "bullCount":    34,
        "bearCount":    21,
        "neutralCount": 32
      },
      "records": [
        {
          "id":             "XAUUSD-20250615T143200",
          "symbol":         "XAUUSD",
          "timestamp":      "2025-06-15T14:32:00+00:00",
          "signal":         "BUY",
          "direction":      "BULLISH",
          "strength":       85,
          "quality":        "EXCELLENT",
          "price":          2341.85,
          "probabilityBull":71.4,
          "regime":         "TRENDING_BULL",
          "source":         "Yahoo Finance",
          "tradePlan":      {...}
        }
      ]
    }

    Note: win_rate is estimated as the percentage of BUY/SELL signals with
    strength >= 70.  This is a heuristic — no live P&L tracking is implemented
    in this bridge.  It reflects signal quality confidence, not realised profit.
    """
    # ── Filter ────────────────────────────────────────────────────────────────
    records: List[dict] = list(_signal_archive)

    if symbol:
        sym_upper = symbol.upper()
        records = [r for r in records if r.get("symbol") == sym_upper]

    if signal:
        sig_upper = signal.upper()
        records = [r for r in records if r.get("signal") == sig_upper]

    total_records = len(records)
    total_pages   = max(1, math.ceil(total_records / page_size))
    start         = (page - 1) * page_size
    end           = start + page_size
    page_records  = records[start:end]

    # ── Page-level summary statistics ────────────────────────────────────────
    bull_count    = sum(1 for r in records if r.get("direction") in ("BULLISH", "STRONG_BULL"))
    bear_count    = sum(1 for r in records if r.get("direction") in ("BEARISH", "STRONG_BEAR"))
    neutral_count = total_records - bull_count - bear_count

    actionable = [
        r for r in records
        if r.get("signal") in ("BUY", "SELL") and isinstance(r.get("strength"), (int, float))
    ]
    high_conf   = [r for r in actionable if r.get("strength", 0) >= 70]
    win_rate    = round(len(high_conf) / len(actionable) * 100.0, 1) if actionable else 0.0

    strengths   = [r["strength"] for r in records if isinstance(r.get("strength"), (int, float))]
    avg_strength = round(statistics.mean(strengths), 1) if strengths else 0.0

    return {
        "page":         page,
        "pageSize":     page_size,
        "totalRecords": total_records,
        "totalPages":   total_pages,
        "filters": {
            "symbol": symbol,
            "signal": signal,
        },
        "summary": {
            "winRate":      win_rate,
            "avgStrength":  avg_strength,
            "bullCount":    bull_count,
            "bearCount":    bear_count,
            "neutralCount": neutral_count,
            "totalAnalyzed":total_records,
        },
        "records": page_records,
    }


# ── Deep Quantum Decision  (v12.0 — new endpoint, engine.py untouched) ────────

@app.get("/api/v1/deep-decision")
async def deep_decision(
    symbol: str = Query(..., description="e.g. BTCUSD, XAUUSD"),
):
    """
    Wraps engine.deep_quantum_decision() — heavy 120-second cadence analysis.
    Returns the decision plus next_refresh_ms so Flutter can self-schedule.

    Response:
    {
      "symbol":          "BTCUSD",
      "decision":        "BUY",
      "price":           67412.00,
      "rsi14":           58.4,
      "volPct":          0.312,
      "trendSlopePct":   0.041,
      "trendStrength":   1.47,
      "source":          "Binance/ccxt (1m)",
      "tsEpoch":         1718459520.0,
      "nextEpoch":       1718459640.0,
      "nextRefreshMs":   120000,
      "chartMetadata":   {...}
    }
    """
    cfg = get_config(symbol)
    try:
        loop   = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None, engine.deep_quantum_decision, cfg
        )
        import time as _time
        remaining_ms = max(0, int((result.next_epoch - _time.time()) * 1000))

        return {
            "symbol":        result.symbol,
            "decision":      result.decision,
            "price":         round(result.price, 6 if _is_forex(cfg) else 2),
            "rsi14":         result.rsi_14,
            "volPct":        result.vol_pct,
            "trendSlopePct": result.trend_slope_pct,
            "trendStrength": result.trend_strength,
            "source":        result.source,
            "tsEpoch":       result.ts_epoch,
            "nextEpoch":     result.next_epoch,
            "nextRefreshMs": remaining_ms,
            "chartMetadata": _build_chart_metadata(cfg),
        }
    except Exception as exc:
        logger.exception(f"Deep decision error [{symbol}]: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))


# ══════════════════════════════════════════════════════════════════════════════
#  ENTRYPOINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)