@echo off
REM Install this project's own build artifacts to
REM out\install\<platform>-<arch>-<compiler>\ (INSTALL_OUTPUT_DIR in
REM Configuration.cmake; see CMakeLists.txt's install() DESTINATION paths).
REM
REM Always passes --component to `cmake --install`. Without it, any
REM vendored/fetched dependency's own install() rules (see
REM cmake\Dependencies.cmake) would also run, typically dumping files under
REM CMAKE_INSTALL_PREFIX -- COMPONENT is what keeps `cmake --install`
REM scoped to just this project's own targets.
REM
REM Usage (from the project root):
REM   scripts\install.bat [BUILD_TYPE]
REM
REM   BUILD_TYPE  Debug|Release|RelWithDebInfo|MinSizeRel
REM               (default: Configuration.cmake's DEFAULT_BUILD_TYPE) --
REM               only relevant for a Ninja Multi-Config build.
setlocal enabledelayedexpansion

cd /d "%~dp0.."

if "%BUILD_DIR%"=="" set "BUILD_DIR=out\build"

where cmake >nul 2>nul
if errorlevel 1 (
    echo error: cmake not found on PATH.
    exit /b 1
)

REM A plain %~1 is safe here (unlike build.bat's arguments): a build type
REM like "Debug" never contains "=", so cmd.exe's positional-parameter
REM splitting on it never comes into play.
set "BUILD_TYPE=%~1"
if "%BUILD_TYPE%"=="" call :read_config DEFAULT_BUILD_TYPE BUILD_TYPE
call :read_config PROJECT_CODE_NAME COMPONENT

if not exist "%BUILD_DIR%" (
    echo error: "%BUILD_DIR%" not found. Run scripts\build.bat first.
    exit /b 1
)

echo ==^> Installing (component: %COMPONENT%)
cmake --install "%BUILD_DIR%" --config %BUILD_TYPE% --component %COMPONENT%
exit /b %ERRORLEVEL%

REM ---------------------------------------------------------------------
REM :read_config <ConfigurationVarName> <LocalVarName>
REM
REM Reads one value out of Configuration.cmake -- this project's single
REM source of truth -- via cmake\PrintConfig.cmake, instead of hardcoding
REM a second copy of a default that can silently drift out of sync, and
REM stores it into %2 in the CALLER's scope. See cmake\PrintConfig.cmake
REM for exactly what's being stripped off of its output below.
REM ---------------------------------------------------------------------
:read_config
setlocal
set "_pmn_line="
for /f "usebackq delims=" %%V in (`cmake "-DPRINT_VARS=%~1" -P cmake\PrintConfig.cmake`) do set "_pmn_line=%%V"
for /f "tokens=1,* delims==" %%A in ("%_pmn_line%") do set "_pmn_value=%%B"
endlocal & set "%~2=%_pmn_value%"
goto :eof
