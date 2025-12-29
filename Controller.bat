@echo off
setlocal enabledelayedexpansion
title Rclone Portable Controller (Temp-File Method)

:: ==========================================================
:: [DEBUG] SYSTEM CHECK
:: ==========================================================
cls
color 0E
echo =======================================================
echo                 DEBUG REPORT
echo =======================================================
echo [DEBUG] Timestamp: %DATE% %TIME%

:: 1. Force CD to script location
cd /d "%~dp0"
set "ROOT=%~dp0"
:: Remove trailing backslash if present
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
echo [DEBUG] Working Directory: "%ROOT%"

:: 2. Check Rclone
set "RCLONE_EXE=%ROOT%\rclone.exe"
if exist "%RCLONE_EXE%" (
    echo [DEBUG] Rclone found at: "%RCLONE_EXE%"
) else (
    echo [ERROR] rclone.exe missing!
    echo Please put rclone.exe in this folder.
    pause
    exit
)

echo =======================================================
echo [INFO] Ready.
timeout /t 1 >nul
goto MAIN_MENU

:: ==========================================================
:: [MENU] MAIN INTERFACE
:: ==========================================================
:MAIN_MENU
cls
color 0B
echo =======================================================
echo              RCLONE PORTABLE CONTROLLER
echo =======================================================
echo.
echo    [1] NEW: Encrypted Google Drive (Browser Auth)
echo    [2] NEW: Encrypted Local Folder (Portable)
echo    [3] RUN: Mount Drives (Bulletproof Engine)
echo    [4] EDIT: Modify or Delete a Config File
echo    [5] EXIT: Clean System (Keep Configs Safe)
echo.
echo =======================================================
set /p opt="Select Option (1-5): "

if "%opt%"=="1" goto NEW_GDRIVE
if "%opt%"=="2" goto NEW_LOCAL
if "%opt%"=="3" goto MOUNT_MENU
if "%opt%"=="4" goto EDIT_MENU
if "%opt%"=="5" goto SAFE_EXIT
goto MAIN_MENU

:: ==========================================================
:: [1] NEW GOOGLE DRIVE
:: ==========================================================
:NEW_GDRIVE
cls
set "RAND=%RANDOM%"
set "NEW_CONF=gdrive_%RAND%.conf"
echo =======================================================
echo       STEP 1: AUTHORIZE GOOGLE DRIVE
echo =======================================================
echo.
echo 1. A browser will open.
echo 2. Log in and click "Allow".
echo.
pause

"%RCLONE_EXE%" --config "%ROOT%\%NEW_CONF%" config create gdrive drive scope drive

if not exist "%ROOT%\%NEW_CONF%" (
    echo [ERROR] Config creation failed.
    pause
    goto MAIN_MENU
)

echo.
echo =======================================================
echo       STEP 2: ADD ENCRYPTION
echo =======================================================
echo.
echo Creating encrypted folder inside Google Drive...
set /p "USER_PASS=Enter Password (leave blank for none): "

if "%USER_PASS%"=="" (
    "%RCLONE_EXE%" --config "%ROOT%\%NEW_CONF%" config create my_crypt crypt remote="gdrive:/Encrypted" filename_encryption=standard
) else (
    "%RCLONE_EXE%" --config "%ROOT%\%NEW_CONF%" config create my_crypt crypt remote="gdrive:/Encrypted" filename_encryption=standard password="%USER_PASS%"
)

echo.
echo [SUCCESS] Config Saved: %NEW_CONF%
pause
goto MAIN_MENU

:: ==========================================================
:: [2] NEW LOCAL ENCRYPTED
:: ==========================================================
:NEW_LOCAL
cls
set "RAND=%RANDOM%"
set "NEW_CONF=local_crypt_%RAND%.conf"
echo.
echo Enter a name for the data folder (Created in USB folder):
set /p "FOLDER_NAME=Folder Name (e.g. MyData): "

if not exist "%ROOT%\%FOLDER_NAME%" mkdir "%ROOT%\%FOLDER_NAME%"

echo.
set /p "USER_PASS=Enter Password (leave blank for none): "

echo.
echo [DEBUG] Saving portable config...
if "%USER_PASS%"=="" (
    "%RCLONE_EXE%" --config "%ROOT%\%NEW_CONF%" config create my_crypt crypt remote=".\%FOLDER_NAME%" filename_encryption=standard
) else (
    "%RCLONE_EXE%" --config "%ROOT%\%NEW_CONF%" config create my_crypt crypt remote=".\%FOLDER_NAME%" filename_encryption=standard password="%USER_PASS%"
)

echo.
echo [SUCCESS] Config Saved: %NEW_CONF%
pause
goto MAIN_MENU

:: ==========================================================
:: [3] MOUNT MENU
:: ==========================================================
:MOUNT_MENU
cls
echo [DEBUG] Scanning for config files...
echo.
set count=0
for %%f in (*.conf) do (
    set /a count+=1
    set "file!count!=%%f"
    echo    [!count!] %%f
)

if %count%==0 (
    echo [!] No config files found.
    pause
    goto MAIN_MENU
)

echo.
echo    [A] MOUNT ALL (Auto-Stack all Drives)
echo    [B] Back to Main Menu
echo.
set /p sel="Select: "

if /i "%sel%"=="B" goto MAIN_MENU
if /i "%sel%"=="A" goto MOUNT_ALL

if defined file%sel% (
    set "SELECTED_CONF=!file%sel%!"
    goto MOUNT_SINGLE
) else (
    goto MOUNT_MENU
)

:: ==========================================================
:: [MOUNT SINGLE CONFIG]
:: ==========================================================
:MOUNT_SINGLE
cls
echo [DEBUG] Analyzing config: "!SELECTED_CONF!"
echo.

call :PROCESS_CONFIG_FILE "!SELECTED_CONF!"

echo.
echo [COMPLETE] Finished processing file.
pause
goto MAIN_MENU

:: ==========================================================
:: [MOUNT ALL CONFIGS]
:: ==========================================================
:MOUNT_ALL
cls
echo [DEBUG] Starting Bulk Mount Sequence...
echo [DEBUG] Scanning ALL files...
echo.

for %%f in (*.conf) do (
    call :PROCESS_CONFIG_FILE "%%f"
)

echo.
echo [COMPLETE] All files processed.
pause
goto MAIN_MENU

:: ==========================================================
:: [FUNCTION] PROCESS A CONFIG FILE (TEMP FILE FIX)
:: ==========================================================
:PROCESS_CONFIG_FILE
:: %~1 = Config Filename
set "CFG_FILE=%~1"
set "TEMP_LIST=%ROOT%\remotes_list.tmp"

echo [INFO] Reading file: "%CFG_FILE%"

:: STEP 1: Run Rclone independently and write output to a temp file
:: This avoids quotation issues inside loops completely.
"%RCLONE_EXE%" --config "%ROOT%\%CFG_FILE%" listremotes > "%TEMP_LIST%"

:: STEP 2: Read the temp file
if exist "%TEMP_LIST%" (
    for /f "usebackq tokens=*" %%R in ("%TEMP_LIST%") do (
        set "RAW_NAME=%%R"
        
        :: Remove colon from "RemoteName:"
        set "REMOTE_NAME=!RAW_NAME:~0,-1!"
        
        echo [DEBUG] Found Remote: "!REMOTE_NAME!"
        call :MOUNT_REMOTE "!REMOTE_NAME!" "%CFG_FILE%"
    )
    :: Cleanup
    del "%TEMP_LIST%" >nul 2>&1
) else (
    echo [ERROR] Could not read remotes from %CFG_FILE%
)
exit /b

:: ==========================================================
:: [FUNCTION] MOUNT A SPECIFIC REMOTE
:: ==========================================================
:MOUNT_REMOTE
:: %~1 = Remote Name
:: %~2 = Config File

set "R_NAME=%~1"
set "C_FILE=%~2"

:: Find a free letter
call :FIND_NEXT_FREE_LETTER

if "!ASSIGNED_LETTER!"=="NONE" (
    echo [WARN] Out of drive letters! Cannot mount "%R_NAME%"
    exit /b
)

echo [ACTION] Mounting "%R_NAME%" to !ASSIGNED_LETTER!
start "Rclone !ASSIGNED_LETTER! - %R_NAME%" "%RCLONE_EXE%" --config "%ROOT%\%C_FILE%" mount "%R_NAME%": !ASSIGNED_LETTER! --vfs-cache-mode full

:: Mark letter as used internally
set "SESSION_USED=!SESSION_USED!!ASSIGNED_LETTER!"

:: Small delay to let Rclone start
timeout /t 2 >nul
exit /b

:: ==========================================================
:: [HELPER] FIND NEXT FREE LETTER
:: ==========================================================
:FIND_NEXT_FREE_LETTER
set "ASSIGNED_LETTER=NONE"

:: Loop through P to Z
for %%L in (P Q R S T U V W X Y Z) do (
    
    set "IS_TAKEN=NO"
    
    :: CHECK 1: Standard 'if exist'
    if exist %%L:\ set "IS_TAKEN=YES"
    
    :: CHECK 2: WMIC (Catches ghosts/network drives)
    wmic logicaldisk get caption 2>nul | find /i "%%L:" >nul
    if !errorlevel! equ 0 set "IS_TAKEN=YES"
    
    :: CHECK 3: Session Memory
    echo !SESSION_USED! | findstr "%%L" >nul
    if !errorlevel! equ 0 set "IS_TAKEN=YES"
    
    :: If passed all checks, assign it and break loop
    if "!IS_TAKEN!"=="NO" (
        set "ASSIGNED_LETTER=%%L:"
        exit /b
    )
)
exit /b

:: ==========================================================
:: [4] EDIT CONFIG
:: ==========================================================
:EDIT_MENU
cls
echo [DEBUG] Edit List:
set count=0
for %%f in (*.conf) do (
    set /a count+=1
    set "file!count!=%%f"
    echo    [!count!] %%f
)

if %count%==0 (
    echo [!] No config files.
    pause
    goto MAIN_MENU
)

echo.
set /p sel="Select # to edit (0 to Cancel): "
if "%sel%"=="0" goto MAIN_MENU
if defined file%sel% (
    set "EDIT_CONF=!file%sel%!"
    cls
    echo [DEBUG] Editing !EDIT_CONF!
    "%RCLONE_EXE%" --config "%ROOT%\!EDIT_CONF!" config
    goto MAIN_MENU
)
goto EDIT_MENU

:: ==========================================================
:: [5] SAFE EXIT
:: ==========================================================
:SAFE_EXIT
cls
color 4F
echo =======================================================
echo              SYSTEM CLEANUP (SAFE MODE)
echo =======================================================
echo.
echo [1/4] Stopping Rclone processes...
taskkill /f /im rclone.exe >nul 2>&1

echo [2/4] Wiping Host Cache...
if exist "%LocalAppData%\rclone" (
    rmdir /s /q "%LocalAppData%\rclone" >nul 2>&1
)

echo [3/4] Cleaning Clipboard + DNS...
echo off | clip
ipconfig /flushdns >nul

echo [4/4] Removing Backup (.old) Files...
del /q "%ROOT%\*.conf.old" >nul 2>&1

echo.
echo [COMPLETE] System cleaned. Config files preserved.
timeout /t 3 >nul
exit