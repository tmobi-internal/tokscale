@echo off
REM tokscale CLI - SCCM deployment script (Windows equivalent of Jamf policy script)
REM Executes tokscale submit as the logged-in console user.

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "TOKSCALE_EXE=%SCRIPT_DIR%tokscale.exe"

REM Version and script metadata
for /f "tokens=2" %%v in ('"%TOKSCALE_EXE%" --version 2^>nul') do set "VERSION=%%v"
if not defined VERSION set "VERSION=unknown"
echo [tokscale-submit v%VERSION%]

REM Detect currently logged-in console user
REM Method 1: WMI ComputerSystem (most reliable, returns DOMAIN\user)
for /f "usebackq tokens=2 delims==" %%u in (`wmic computersystem get username /value 2^>nul ^| findstr /i "UserName"`) do set "RAW_USER=%%u"

REM Strip domain prefix (DOMAIN\user -> user)
if defined RAW_USER (
    for /f "tokens=2 delims=\" %%n in ("%RAW_USER%") do set "USERNAME_FOUND=%%n"
    REM If no backslash (local user), use as-is
    if not defined USERNAME_FOUND set "USERNAME_FOUND=%RAW_USER%"
)

REM Method 2: Fallback to explorer.exe owner
if not defined USERNAME_FOUND (
    for /f "tokens=2 delims=\" %%u in ('wmic process where "name='explorer.exe'" get owner /value 2^>nul ^| findstr /i "Owner"') do set "USERNAME_FOUND=%%u"
)

REM Method 3: Fallback to query user
if not defined USERNAME_FOUND (
    for /f "skip=1 tokens=1" %%u in ('query user 2^>nul') do (
        if not defined USERNAME_FOUND set "USERNAME_FOUND=%%u"
    )
)

REM Debug output
echo [DEBUG] RAW_USER=%RAW_USER% USERNAME_FOUND=%USERNAME_FOUND%

if not defined USERNAME_FOUND (
    echo No console user detected >&2
    exit /b 1
)

REM Trim whitespace and carriage returns (wmic outputs Unicode with trailing \r)
for /f "tokens=* delims= " %%a in ("%USERNAME_FOUND%") do set "USERNAME_FOUND=%%a"
REM Remove any trailing CR/spaces via re-parse
for /f "delims=" %%a in ("%USERNAME_FOUND%") do set "USERNAME_FOUND=%%a"

if "%USERNAME_FOUND%"=="SYSTEM" (
    echo No interactive user detected >&2
    exit /b 1
)

echo [DEBUG] Trimmed USERNAME_FOUND=[%USERNAME_FOUND%]

REM Resolve profile path via registry (most accurate)
set "USER_PROFILE="
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" /s /v ProfileImagePath 2^>nul ^| findstr /i "\%USERNAME_FOUND%"') do set "USER_PROFILE=%%b"

REM Fallback to standard path
if not defined USER_PROFILE set "USER_PROFILE=C:\Users\%USERNAME_FOUND%"

echo [DEBUG] USER_PROFILE=[%USER_PROFILE%]

if not exist "%USER_PROFILE%" (
    echo User profile not found: %USER_PROFILE% >&2
    exit /b 1
)

echo Submitting for user: %USERNAME_FOUND%

REM Create a temporary VBS to launch process as logged-in user context via scheduled task
set "TASK_NAME=tokscale-submit-%USERNAME_FOUND%"

REM Clean up any leftover task
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1

REM Build the command with environment variables
set "SUBMIT_CMD=cmd /c "set TOKSCALE_API_URL=https://tokscale.tmobiweb.com && set TOKSCALE_API_TOKEN=tt_%USERNAME_FOUND% && set HOME=%USER_PROFILE% && set USERPROFILE=%USER_PROFILE% && \"%TOKSCALE_EXE%\" submit --no-spinner""

REM Create and run scheduled task as the console user
schtasks /Create /TN "%TASK_NAME%" /TR "%SUBMIT_CMD%" /SC ONCE /ST 00:00 /RU "%USERNAME_FOUND%" /RL LIMITED /F >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Failed to create scheduled task >&2
    exit /b 1
)

schtasks /Run /TN "%TASK_NAME%" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Failed to start scheduled task >&2
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    exit /b 1
)

REM Wait for completion (max 5 minutes)
set /a ELAPSED=0
set /a TIMEOUT=300

:WAIT_LOOP
timeout /t 2 /nobreak >nul
set /a ELAPSED+=2

schtasks /Query /TN "%TASK_NAME%" /FO CSV /NH 2>nul | findstr /i "Running" >nul
if %ERRORLEVEL%==0 (
    if %ELAPSED% lss %TIMEOUT% goto WAIT_LOOP
)

REM Get result
for /f "tokens=7 delims=," %%r in ('schtasks /Query /TN "%TASK_NAME%" /FO CSV /NH 2^>nul') do set "LAST_RESULT=%%~r"

REM Cleanup
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1

if "%LAST_RESULT%"=="0" (
    echo tokscale submit completed successfully for user: %USERNAME_FOUND%
    exit /b 0
)

echo tokscale submit failed (result: %LAST_RESULT%) >&2
exit /b 1
