"""
NEXUS v11.1 — PRO FASTAPI BACKEND (main.py)
-------------------------------------------------------------------------------
Decoupled bridge between engine.py (read-only) and the Flutter frontend.

Key changes vs prior version
─────────────────────────────
  • /api/ohlcv  → full-word JSON keys (timestamp/open/high/low/close/volume)
                  with synthesised ISO-8601 timestamps aligned to the interval
  • /api/analyze → ALL MarketIntelligence fields extracted via dataclasses.asdict()
                   then recursively converted snake_case → camelCase so Flutter
                   can consume them with zero custom mapping

Run: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import math
import re
import logging
from typing import List, Any, Optional
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dataclasses import asdict

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
    version="11.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ══════════════════════════════════════════════════════════════════════════════
#  UTILITIES
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
    """Convert a single snake_case key to camelCase."""
    return _CAMEL_PATTERN.sub(lambda m: m.group(1).upper(), name)


def to_camel_case(obj: Any) -> Any:
    """
    Recursively walk a dict/list structure and convert every dict key
    from snake_case to camelCase.  Leaf values are untouched.
    """
    if isinstance(obj, dict):
        return {_snake_to_camel(k): to_camel_case(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [to_camel_case(v) for v in obj]
    return obj


def get_config(symbol: str) -> engine.AssetConfig:
    sym = symbol.upper().strip()
    if sym in engine.ASSET_MAP:
        return engine.ASSET_MAP[sym]
    raise HTTPException(
        status_code=404,
        detail=f"Asset '{symbol}' not supported by NEXUS engine.",
    )


def _synthesise_timestamps(n: int, interval: str) -> List[str]:
    """
    Generate n ISO-8601 UTC timestamps going backwards from now,
    spaced by the requested chart interval.
    Used when the engine returns only price arrays (no datetime index).
    """
    delta_map: dict = {
        "1m":  timedelta(minutes=1),
        "5m":  timedelta(minutes=5),
        "15m": timedelta(minutes=15),
        "1h":  timedelta(hours=1),
        "4h":  timedelta(hours=4),
        "1d":  timedelta(days=1),
    }
    delta = delta_map.get(interval, timedelta(minutes=5))
    now = datetime.now(timezone.utc)
    return [(now - delta * (n - 1 - i)).isoformat() for i in range(n)]

# ══════════════════════════════════════════════════════════════════════════════
#  REQUEST MODELS
# ══════════════════════════════════════════════════════════════════════════════

class AnalyzeRequest(BaseModel):
    symbols: List[str] = Field(default_factory=list)
    run_mtf: bool = True
    atr_mult: float = 1.5
    rr_ratio: float = 2.5

# ══════════════════════════════════════════════════════════════════════════════
#  ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/")
async def root():
    return {
        "status": "ONLINE",
        "system": "NEXUS QUANTUM v11.1",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "endpoints": ["/api/analyze", "/api/watchlist", "/api/ohlcv", "/api/correlation"],
    }


@app.get("/api/health")
async def health():
    return {"status": "ok", "engine_loaded": engine is not None}


@app.get("/api/watchlist")
async def get_watchlist():
    """Snapshot of all tracked assets: symbol, name, price, % change."""
    results = []
    for cfg in engine.ALL_ASSETS:
        try:
            prices, source, _ = engine.PriceFeed.get(cfg)
            if not prices:
                continue
            last = float(prices[-1])
            prev = float(prices[-2]) if len(prices) > 1 else last
            chg_pct = ((last - prev) / prev * 100.0) if prev != 0 else 0.0
            results.append({
                "symbol":     cfg.symbol,
                "name":       cfg.name,
                "type":       cfg.asset_type,
                "price":      round(last, 6 if cfg.asset_type == "forex" else 2),
                "changePct":  round(chg_pct, 3),
                "emoji":      cfg.emoji,
                "color":      cfg.color,
            })
        except Exception as exc:
            logger.error(f"Watchlist error [{cfg.symbol}]: {exc}")
    return results


@app.get("/api/ohlcv")
async def get_ohlcv(
    symbol: str = Query(..., description="e.g. BTCUSD, XAUUSD"),
    interval: str = Query("5m", description="1m | 5m | 15m | 1h | 4h | 1d"),
):
    """
    Historical OHLCV bars.

    JSON shape per candle (Flutter / Syncfusion ready):
    {
      "timestamp": "2025-06-01T12:05:00+00:00",   ← ISO-8601 UTC string
      "open":  2345.12,
      "high":  2347.80,
      "low":   2340.50,
      "close": 2346.00,
      "volume": 14523.0
    }
    """
    cfg = get_config(symbol)
    interval = interval.lower().strip()

    # yfinance period / interval pairs
    yf_map = {
        "1m":  ("1d",  "1m"),
        "5m":  ("5d",  "5m"),
        "15m": ("5d",  "15m"),
        "1h":  ("1mo", "1h"),
        "4h":  ("3mo", "1h"),   # yfinance has no 4h; we serve 1h bars
        "1d":  ("1y",  "1d"),
    }
    period, yf_interval = yf_map.get(interval, ("5d", "5m"))

    try:
        raw: Optional[dict] = engine.PriceFeed._from_yfinance_ohlcv(
            cfg.yf_ticker, period=period, interval=yf_interval
        )
        if not raw:
            return []

        closes  = raw.get("close",  [])
        opens   = raw.get("open",   closes)
        highs   = raw.get("high",   closes)
        lows    = raw.get("low",    closes)
        volumes = raw.get("volume", [0.0] * len(closes))

        n = min(len(closes), len(opens), len(highs), len(lows))
        if n == 0:
            return []

        # ── Timestamps ────────────────────────────────────────────────────────
        # engine._from_yfinance_ohlcv returns only numeric arrays (no index).
        # We synthesise ISO timestamps anchored to the current UTC time.
        timestamps = _synthesise_timestamps(n, interval)

        # ── Build payload ─────────────────────────────────────────────────────
        candles = []
        for i in range(n):
            o = float(opens[i])
            h = float(highs[i])
            lo = float(lows[i])
            c = float(closes[i])
            v = float(volumes[i]) if i < len(volumes) else 0.0

            # Skip degenerate / NaN candles
            if any(math.isnan(x) or math.isinf(x) or x <= 0 for x in (o, h, lo, c)):
                continue

            candles.append({
                "timestamp": timestamps[i],
                "open":      round(o,  8),
                "high":      round(h,  8),
                "low":       round(lo, 8),
                "close":     round(c,  8),
                "volume":    round(v,  2),
            })

        # Return last 500 bars (Syncfusion performs best in this range)
        return candles[-500:]

    except Exception as exc:
        logger.exception(f"OHLCV error [{symbol}]: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/analyze")
async def analyze_assets(req: AnalyzeRequest):
    """
    Core NEXUS analysis endpoint.

    For each symbol this returns the COMPLETE MarketIntelligence snapshot with
    all fields converted from snake_case to camelCase so Flutter can access them
    directly (e.g. `mi.signalStrength`, `mi.tradePlan.sl`, `mi.smcExplanation`).

    Response shape:
    {
      "XAUUSD": {
        "intelligence": { ...all MI camelCase fields... },
        "news": [ {...newsItem camelCase...}, ... ],
        "source": "Yahoo Finance"
      }
    }
    """
    symbols = req.symbols if req.symbols else [a.symbol for a in engine.ALL_ASSETS]
    results = {}

    for sym in symbols:
        try:
            cfg = get_config(sym)
            mi, news_items, source = engine.run_analysis(
                cfg,
                atr_mult=req.atr_mult,
                rr_ratio=req.rr_ratio,
                run_mtf=req.run_mtf,
            )

            if not mi:
                continue

            # ── Full extraction: dataclass → raw dict → sanitised → camelCase ─
            mi_raw    = asdict(mi)
            mi_clean  = sanitize_float(mi_raw)
            mi_camel  = to_camel_case(mi_clean)

            # ── News items ────────────────────────────────────────────────────
            news_list = []
            for item in (news_items or []):
                try:
                    news_list.append(to_camel_case(sanitize_float(asdict(item))))
                except Exception:
                    pass

            results[sym] = {
                "intelligence": mi_camel,
                "news":         news_list,
                "source":       source,
            }

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


@app.get("/api/correlation")
async def get_correlation():
    """30-day rolling asset correlation matrix."""
    matrix = engine.get_correlation_matrix()
    if not matrix:
        raise HTTPException(status_code=404, detail="Correlation data unavailable.")
    return sanitize_float(matrix)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)