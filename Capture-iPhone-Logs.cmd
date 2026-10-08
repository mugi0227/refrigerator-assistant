@echo off
setlocal
set "FRIDGE_PYTHON=%~dp0..\backburner\.venv\Scripts\python.exe"
if not exist "%FRIDGE_PYTHON%" (
  echo The existing Backburner Python environment with pymobiledevice3 was not found.
  echo Use Python with pymobiledevice3 installed to run scripts\capture-ios-log.py.
  pause
  exit /b 2
)
"%FRIDGE_PYTHON%" "%~dp0scripts\capture-ios-log.py" %*
pause
