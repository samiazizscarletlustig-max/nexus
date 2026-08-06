@echo off
TITLE NEXUS v11.1 - QUANTUM TERMINAL
echo --------------------------------------------------------
echo              NEXUS v11.1 - QUANTUM TERMINAL
echo --------------------------------------------------------

:: Start Backend
echo [1/2] Starting FastAPI Backend...
start /B "" "C:\Program Files\Python314\python.exe" main.py

:: Instructions
echo [2/2] Backend is running.
echo To start the Flutter app, run:
echo cd nexus_quantum_terminal
echo "C:\Users\user\flutter_desktop\flutter\bin\flutter.bat" run -d windows
echo --------------------------------------------------------
pause
