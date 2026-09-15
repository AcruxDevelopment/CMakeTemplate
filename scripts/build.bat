@echo off
REM Configure (if needed) and build the project, preferably with Ninja.
REM
REM Usage (from the project root):
REM   scripts\build.bat [BUILD_TYPE] [CMAKE_ARGS...]
REM
REM   BUILD_TYPE   Debug^|Release^|RelWithDebInfo^|MinSizeRel
REM                (default: Configuration.cmake's DEFAULT_BUILD_TYPE)
REM   CMAKE_ARGS   Anything else is forwarded to `cmake` verbatim at
REM                configure time, e.g. to pick a target or turn an
REM                option on:
REM                  scripts\build.bat Debug -DDIST_TARGET=windows-x64-mingw64
REM                  scripts\build.bat -DBUILD_TESTS=ON
REM                            (BUILD_TYPE omitted -- the default is used;
REM                            recognized by not starting with "-")
REM
REM cmd.exe splits %1, %2, ... (and SHIFT) on space, comma, semicolon, AND
REM "=" -- type "-DFOO=BAR" as an argument and it arrives as TWO separate
REM parameters, %1=-DFOO %2=BAR, silently, with no way to tell after the
REM fact. This script never reads a "="-laden argument through %1 or
REM SHIFT; everything is peeled off of the raw, unsplit %* instead using
REM FOR /F (which only ever splits on space/tab), so "=" survives intact
REM -- see :parse_args below. (bash's "$@"/shift has no such bug -- see
REM build.sh for that half of this same feature.)
REM
REM Set BUILD_DIR to build somewhere other than out\build (see Configuration.cmake).
setlocal enabledelayedexpansion

cd /d "%~dp0.."

if "%BUILD_DIR%"=="" set "BUILD_DIR=out\build"

where cmake >nul 2>nul
if errorlevel 1 (
    echo error: cmake not found on PATH.
    exit /b 1
)

REM See the header comment above for why this doesn't use %1/SHIFT.
set "ALL_ARGS=%*"
set "BUILD_TYPE="
set "EXTRA_ARGS="
if not defined ALL_ARGS goto args_done

for /f "tokens=1,* delims= " %%A in ("%ALL_ARGS%") do (
    set "_FIRST=%%A"
    set "_REST=%%B"
)
if "%_FIRST:~0,1%"=="-" (
    set "EXTRA_ARGS=%ALL_ARGS%"
) else (
    set "BUILD_TYPE=%_FIRST%"
    set "EXTRA_ARGS=%_REST%"
)

:args_done
if "%BUILD_TYPE%"=="" call :read_config DEFAULT_BUILD_TYPE BUILD_TYPE
if "%TOOLCACHE_DIR%"=="" call :read_config TOOLCACHE_DIR TOOLCACHE_DIR

REM Prefer a pinned ninja (fetched by scripts\setup.bat -- see
REM cmake\FetchNinja.cmake) over a system one, same "always the pinned
REM copy" preference as Doxygen. Deliberately goto-based, and deliberately
REM `pushd` + a bare wildcard rather than `for /d %%D in ("path\*")` --
REM both tested directly; a path-prefixed wildcard didn't match here,
REM this form does, and it also sidesteps nesting a FOR loop inside an
REM if/else block, which separately corrupts cmd.exe's paren-matching for
REM the enclosing block (see scripts\refactor.bat for that one).
set "NINJA_BIN="
if not exist "%TOOLCACHE_DIR%" goto check_system_ninja

pushd "%TOOLCACHE_DIR%"
for /d %%D in (ninja-*) do if exist "%%D\ninja.exe" if not defined NINJA_BIN set "NINJA_BIN=%%~fD\ninja.exe"
popd

if defined NINJA_BIN goto have_pinned_ninja

:check_system_ninja
where ninja >nul 2>nul
if errorlevel 1 goto no_ninja
echo ==^> Using system ninja
set "GENERATOR_ARGS=-G Ninja"
goto configure

:have_pinned_ninja
echo ==^> Using pinned ninja: %NINJA_BIN%
set "GENERATOR_ARGS=-G Ninja -DCMAKE_MAKE_PROGRAM=%NINJA_BIN%"
goto configure

:no_ninja
echo warning: ninja not found ^(no pinned copy, none on PATH^) -- falling back to
echo          CMake's default generator for this platform. Run scripts\setup.bat
echo          to fetch a pinned ninja, or install ninja yourself, for a faster
echo          and more consistent build. Continuing without it.
set "GENERATOR_ARGS="

:configure
echo ==^> Configuring (%BUILD_TYPE%) into %BUILD_DIR%\
if defined EXTRA_ARGS echo     Extra CMake arguments: %EXTRA_ARGS%
cmake %GENERATOR_ARGS% -S . -B "%BUILD_DIR%" -DCMAKE_BUILD_TYPE=%BUILD_TYPE% %EXTRA_ARGS%
if errorlevel 1 exit /b 1

echo ==^> Building
cmake --build "%BUILD_DIR%"
if errorlevel 1 exit /b 1

echo ==^> Done. Run a module with:  scripts\run.bat ^<target-name^>
exit /b 0

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
