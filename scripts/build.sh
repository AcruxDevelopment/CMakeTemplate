#!/usr/bin/env bash
# Configure (if needed) and build the project, preferably with Ninja.
#
# Usage (from the project root):
#   scripts/build.sh [BUILD_TYPE] [CMAKE_ARGS...]
#
#   BUILD_TYPE   Debug|Release|RelWithDebInfo|MinSizeRel
#                (default: Configuration.cmake's DEFAULT_BUILD_TYPE)
#   CMAKE_ARGS   Anything else is forwarded to `cmake` verbatim at configure
#                time, e.g. to pick a target or turn an option on:
#                  scripts/build.sh Debug -DDIST_TARGET=windows-x64-mingw64
#                  scripts/build.sh -DBUILD_TESTS=ON
#                            (BUILD_TYPE omitted -- the default is used;
#                            recognized by not starting with "-")
#
# Set BUILD_DIR to build somewhere other than out/build (see Configuration.cmake).
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

command -v cmake >/dev/null 2>&1 || { echo "error: cmake not found on PATH." >&2; exit 1; }

# Reads one value out of Configuration.cmake -- this project's single
# source of truth -- via cmake/PrintConfig.cmake, instead of hardcoding a
# second copy of a default that can silently drift out of sync. See that
# file for exactly what this strips off of its output.
_pmn_read_config() {
    cmake "-DPRINT_VARS=$1" -P cmake/PrintConfig.cmake | sed -E 's/^-- [^=]*=//'
}

BUILD_DIR="${BUILD_DIR:-out/build}"

# If the first argument doesn't start with "-", it's BUILD_TYPE and
# everything after it is CMAKE_ARGS; otherwise there's no BUILD_TYPE
# override and every argument is CMAKE_ARGS. Plain bash "$@"/shift, no
# special-casing needed: unlike Windows cmd.exe (see build.bat), bash
# never splits a "-DFOO=BAR"-style argument on its own "=".
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
    BUILD_TYPE="$1"
    shift
else
    BUILD_TYPE="$(_pmn_read_config DEFAULT_BUILD_TYPE)"
fi
CMAKE_ARGS=("$@")

# Prefer a pinned ninja (fetched by scripts/setup.sh -- see
# cmake/FetchNinja.cmake) over a system one, same "always the pinned copy"
# preference as Doxygen.
TOOLCACHE_DIR="${TOOLCACHE_DIR:-$(_pmn_read_config TOOLCACHE_DIR)}"
NINJA_BIN=""
for _candidate in "${TOOLCACHE_DIR}"/ninja-*/ninja; do
    if [ -x "$_candidate" ]; then
        # Must be absolute: CMake invokes CMAKE_MAKE_PROGRAM from several
        # different working directories during its own internal
        # try-compile steps, where a relative path doesn't resolve.
        NINJA_BIN="$(cd "$(dirname "$_candidate")" && pwd)/$(basename "$_candidate")"
        break
    fi
done

GENERATOR_ARGS=()
if [ -n "$NINJA_BIN" ]; then
    echo "==> Using pinned ninja: ${NINJA_BIN}"
    GENERATOR_ARGS=(-G Ninja "-DCMAKE_MAKE_PROGRAM=${NINJA_BIN}")
elif command -v ninja >/dev/null 2>&1; then
    echo "==> Using system ninja: $(command -v ninja)"
    GENERATOR_ARGS=(-G Ninja)
else
    echo "warning: ninja not found (no pinned copy, none on PATH) -- falling back to" >&2
    echo "         CMake's default generator for this platform. Run scripts/setup.sh" >&2
    echo "         to fetch a pinned ninja, or install ninja yourself, for a faster" >&2
    echo "         and more consistent build. Continuing without it." >&2
    GENERATOR_ARGS=()
fi

echo "==> Configuring (${BUILD_TYPE}) into ${BUILD_DIR}/"
if [ "${#CMAKE_ARGS[@]}" -gt 0 ]; then
    echo "    Extra CMake arguments: ${CMAKE_ARGS[*]}"
fi
cmake "${GENERATOR_ARGS[@]}" -S . -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" "${CMAKE_ARGS[@]}"

echo "==> Building"
cmake --build "${BUILD_DIR}"

echo "==> Done. Run a module with:  scripts/run.sh <target-name>"
