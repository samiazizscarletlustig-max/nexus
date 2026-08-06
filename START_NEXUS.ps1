# NEXUS QUANTUM TERMINAL - Unified Startup Script
# This script starts the FastAPI backend and provides instructions for the Flutter app.

$PythonPath = "C:\Program Files\Python314\python.exe"
$FlutterPath = "C:\Users\user\flutter_desktop\flutter\bin\flutter.bat"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Gold
Write-Host "║              NEXUS v11.1 - QUANTUM TERMINAL                  ║" -ForegroundColor Gold
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Gold

# 1. Start FastAPI Backend
Write-Host "`n[1/2] Launching FastAPI Backend..." -ForegroundColor Cyan
if (Test-Path $PythonPath) {
    Start-Process -FilePath $PythonPath -ArgumentList "main.py" -NoNewWindow
    Write-Host "      ✅ Backend started on http://127.0.0.1:8000" -ForegroundColor Green
} else {
    Write-Host "      ❌ ERROR: Python not found at $PythonPath" -ForegroundColor Red
}

# 2. Check Flutter
Write-Host "`n[2/2] Preparing Flutter Frontend..." -ForegroundColor Cyan
if (Test-Path $FlutterPath) {
    Write-Host "      ✅ Flutter SDK found." -ForegroundColor Green
    Write-Host "`n      To run the app, execute:" -ForegroundColor White
    Write-Host "      cd nexus_quantum_terminal" -ForegroundColor Yellow
    Write-Host "      & '$FlutterPath' run -d windows" -ForegroundColor Yellow
} else {
    Write-Host "      ❌ ERROR: Flutter SDK not found at $FlutterPath" -ForegroundColor Red
}

Write-Host "`n════════════════════════════════════════════════════════════════" -ForegroundColor Gold
Write-Host "System initialized. Ready for institutional analysis." -ForegroundColor White
