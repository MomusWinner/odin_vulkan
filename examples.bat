@echo off
setlocal enabledelayedexpansion

set APP_NAME=ve_examples.exe
set SRC_DIR=examples
set BIN_DIR=bin
set DEBUG_BIN=%BIN_DIR%\debug\%APP_NAME%
set RELEASE_BIN=%BIN_DIR%\release\%APP_NAME%

set ODIN_FLAGS=-custom-attribute:buffer
set ODIN_DEBUG_FLAGS=-debug %ODIN_FLAGS%
set ODIN_RELEASE_FLAGS=-o:speed -no-bounds-check -disable-assert %ODIN_FLAGS%
set ODIN=odin

if "%1"=="" goto help
if "%1"=="debug" goto debug
if "%1"=="release" goto release
if "%1"=="all" goto all
if "%1"=="run" goto run
if "%1"=="run-release" goto run-release
if "%1"=="gen" goto gen
if "%1"=="clean" goto clean
if "%1"=="help" goto help
if "%1"=="-h" goto help
if "%1"=="--help" goto help

echo Error: Unknown command '%1'
echo.
goto help

:debug
echo Building debug examples ...
if not exist "%BIN_DIR%\debug" mkdir "%BIN_DIR%\debug"
%ODIN% build %SRC_DIR% -out:"%DEBUG_BIN%" %ODIN_DEBUG_FLAGS%
echo Built: %DEBUG_BIN%
goto end

:release
echo Building release examples ...
if not exist "%BIN_DIR%\release" mkdir "%BIN_DIR%\release"
%ODIN% build %SRC_DIR% -out:"%RELEASE_BIN%" -o:speed %ODIN_FLAGS%
echo Built: %RELEASE_BIN%
goto end

:all
echo Building all examples ...
if not exist "%BIN_DIR%\debug" mkdir "%BIN_DIR%\debug"
if not exist "%BIN_DIR%\release" mkdir "%BIN_DIR%\release"
%ODIN% build %SRC_DIR% -out:"%DEBUG_BIN%" %ODIN_DEBUG_FLAGS%
echo Built: %DEBUG_BIN%
%ODIN% build %SRC_DIR% -out:"%RELEASE_BIN%" -o:speed %ODIN_FLAGS%
echo Built: %RELEASE_BIN%
goto end

:run
echo Building debug examples ...
if not exist "%BIN_DIR%\debug" mkdir "%BIN_DIR%\debug"
%ODIN% build %SRC_DIR% -out:"%DEBUG_BIN%" %ODIN_DEBUG_FLAGS%
echo Built: %DEBUG_BIN%
echo 🐢 Running examples %DEBUG_BIN%...
"%DEBUG_BIN%"
goto end

:run-release
echo Building release examples ...
if not exist "%BIN_DIR%\release" mkdir "%BIN_DIR%\release"
%ODIN% build %SRC_DIR% -out:"%RELEASE_BIN%" -o:speed %ODIN_FLAGS%
echo Built: %RELEASE_BIN%
echo 🐇 Running example %RELEASE_BIN%...
"%RELEASE_BIN%"
goto end

:gen
echo Generating...
%ODIN% run ./tools/shadertypegen/ -- ^
    -outpute-glsl-dir:examples/assets/shaders/ ^
    -src-dir:./examples ^
    -ve-import:"ve .."
goto end

:clean
echo Cleaning...
if exist "%BIN_DIR%" rmdir /s /q "%BIN_DIR%"
goto end

:help
echo Usage: %~nx0 {debug^|release^|all^|run^|run-release^|gen^|clean}
echo.
echo Commands:
echo   debug        - Build debug version
echo   release      - Build release version
echo   all          - Build both debug and release versions
echo   run          - Build and run debug version
echo   run-release  - Build and run release version
echo   gen          - Generate shaders
echo   clean        - Remove build directory
goto end

:end
endlocal
