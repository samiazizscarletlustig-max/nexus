# NEXUS — Runbook (Backend + Flutter)

Repository layout:

| Path | Role |
|------|------|
| `engine.py` | Core quant engine (indicators, feeds, `run_analysis`) |
| `backend/main.py` | FastAPI REST on top of `engine.py` |
| `nexus_quantum_terminal/` | Flutter client (Android + Windows) |

---

## 1) Python dependencies

From the **repository root** (this folder):

```powershell
Set-Location c:\Users\user\OneDrive\nexus
python -m pip install -r requirements.txt
```

---

## 2) Start the Python backend (FastAPI)

Still from the **repository root**:

```powershell
Set-Location c:\Users\user\OneDrive\nexus
python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```

- API docs: http://127.0.0.1:8000/docs  
- Health: http://127.0.0.1:8000/api/v1/health  

Keep this terminal open while testing the app.

---

## 3) Flutter dependencies

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter pub get
```

If `android/` or `windows/` folders are missing (first clone), generate them once:

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter create --org com.nexus.quantum --platforms=android,windows .
```

---

## 4) Launch Windows desktop app

With the backend running on port 8000:

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Release build:

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 5) Launch Android mobile app

- Connect a device with USB debugging **or** start an emulator, then:

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter devices
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

**Note:** An Android emulator cannot reach `127.0.0.1` on your PC as “the host”. Use:

- Android Emulator: `http://10.0.2.2:8000`  
  ```powershell
  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  ```
- Physical phone on same Wi‑Fi: use your PC’s LAN IP, e.g. `http://192.168.1.10:8000`, and run uvicorn with `--host 0.0.0.0`.

Release APK:

```powershell
Set-Location c:\Users\user\OneDrive\nexus\nexus_quantum_terminal
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 6) Streamlit (optional, original UI)

```powershell
Set-Location c:\Users\user\OneDrive\nexus
python -m streamlit run app.py
```
