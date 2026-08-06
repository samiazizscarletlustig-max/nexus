The HTTP API now lives at the **repository root**: `backend/main.py` (imports `engine.py`).

Start the server from the repo root:

```bash
uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```
