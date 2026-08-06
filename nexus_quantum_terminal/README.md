# NEXUS Quantum Terminal (Flutter)

High-quality **Android** + **Windows** client for the NEXUS Quantum Terminal. It talks to the **FastAPI** app in the repo root: `backend/main.py` (which wraps `engine.py`).

Full run commands: see **`../RUN.md`** at the repository root.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable), with **Android** + **Windows** toolchains enabled.

## Project layout (this package)

| Path | Purpose |
|------|---------|
| `lib/screens/` | UI screens (`home_shell.dart` — desktop + mobile layouts) |
| `lib/models/` | DTOs (`market_models.dart`) |
| `lib/services/` | HTTP client (`nexus_api_client.dart`) |
| `lib/providers/` | `MarketState` |
| `lib/widgets/` | Charts, signal cards |
| `lib/theme/` | OLED / Bloomberg theme |

## First-time Flutter bootstrap

If `android/` or `windows/` is missing:

```powershell
cd nexus_quantum_terminal
flutter create --org com.nexus.quantum --platforms=android,windows .
flutter pub get
```

## API base URL (local testing)

Default in code: **`http://127.0.0.1:8000`** (`kApiBaseUrl` in `lib/services/nexus_api_client.dart`).

Override at run/build time:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

**Android emulator:** use `http://10.0.2.2:8000` instead of `127.0.0.1`.

## REST contract (implemented by `backend/main.py`)

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/health` | Liveness |
| `GET` | `/api/v1/watchlist` | Symbols + last price (from `PriceFeed`) |
| `GET` | `/api/v1/ohlcv?symbol=XAUUSD&interval=5m` | OHLCV candles |
| `POST` | `/api/v1/quantum-scan` | Body `{"symbols":["XAUUSD"]}` — full `run_analysis` + `deep_quantum_decision` per symbol |

## Builds

```powershell
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Syncfusion

Charts use **Syncfusion Flutter Charts**. Review [Syncfusion licensing](https://www.syncfusion.com/sales/products) before store release.

## AdMob (placeholders)

`lib/ads/ad_placeholders.dart` — replace with `google_mobile_ads` on Android when you have ad unit IDs.

## Legacy note

The old stub server was removed from `backend_stub/`; use **`../backend/main.py`** instead.
