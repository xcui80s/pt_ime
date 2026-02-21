@echo off
setlocal

set SCRIPT_DIR=%~dp0
set SERVER_EXE=%SCRIPT_DIR%whisper\whisper-server.exe
set MODEL=%SCRIPT_DIR%models\ggml-large-v3-turbo.bin
set PORT=8989
set LANGUAGE=auto
set BEAM_SIZE=1

if not exist "%SERVER_EXE%" (
    echo ERROR: server.exe not found at:
    echo   %SERVER_EXE%
    echo.
    echo Build whisper.cpp from source ^(examples/server^) or download a pre-built binary
    echo and place it in the whisper\ folder.
    pause
    exit /b 1
)

if not exist "%MODEL%" (
    echo ERROR: Model file not found at:
    echo   %MODEL%
    echo.
    echo Download a .bin model and place it in the models\ folder.
    pause
    exit /b 1
)

echo ============================================================
echo  whisper.cpp server
echo ============================================================
echo  Listening : 0.0.0.0:%PORT%  (all network interfaces)
echo  Model     : %MODEL%
echo.
echo  LAN clients: set WHISPER_HOST to this machine's IP in ptt.ahk
echo  Press Ctrl+C to stop.
echo ============================================================
echo.

echo Command:
echo   "%SERVER_EXE%" -m "%MODEL%" --host 0.0.0.0 --port %PORT% -l %LANGUAGE% --beam-size %BEAM_SIZE% --no-timestamps
echo.
"%SERVER_EXE%" -m "%MODEL%" --host 0.0.0.0 --port %PORT% -l %LANGUAGE% --beam-size %BEAM_SIZE% --no-timestamps
