# =============================================================================
# PrintConfig.cmake
#
# Script-mode bridge: lets scripts/*.sh and scripts/*.bat read values out of
# Configuration.cmake -- this project's single source of truth (see that
# file) -- instead of hardcoding a second copy that can silently drift out
# of sync. This is exactly the bug it replaces: scripts/install.sh and
# install.bat used to each hardcode their own literal "demo", with a
# comment warning it had to be kept in sync with PROJECT_CODE_NAME by hand.
#
# Usage:
#   cmake "-DPRINT_VARS=NAME1;NAME2;..." -P cmake/PrintConfig.cmake
#
# Prints one "NAME=value" line per requested variable, in the order given.
# Every line is emitted via message(STATUS ...) -- deliberately: it's the
# only message() mode CMake sends to stdout (verified directly: the
# no-keyword default, NOTICE, and WARNING all go to stderr; STATUS is the
# one exception), which is what lets a caller capture it with plain output
# redirection/command substitution instead of needing a temp file. The
# tradeoff is that STATUS always prefixes the line with "-- ", so every
# caller strips that off along with the "NAME=" it already knows: see
# scripts/build.sh's _pmn_read_config() or scripts/build.bat's
# :read_config for the one small wrapper each shell dialect uses -- every
# script that needs a value calls that wrapper rather than re-deriving
# this convention itself.
#
# Runs with PMN_CONFIG_QUERY_ONLY set before including Configuration.cmake,
# so that file skips its normal side effects (creating out/dist/,
# rewriting .gitignore -- a value lookup shouldn't touch the filesystem,
# and this runs far more often than a real configure) and skips resolving
# DIST_TARGET/PLATFORM/ARCHITECTURE/COMPILER_ID, which need real compiler
# detection (project(... LANGUAGES CXX)) that a plain `cmake -P` script
# never performs and would get wrong. Only ask for names that don't need
# that -- PROJECT_CODE_NAME, DEFAULT_BUILD_TYPE, and the path variables
# are all safe; see Configuration.cmake's header for the full list of
# what's inside vs. outside that guard.
# =============================================================================

if(NOT DEFINED PRINT_VARS)
    message(FATAL_ERROR "Usage: cmake \"-DPRINT_VARS=NAME1;NAME2;...\" -P cmake/PrintConfig.cmake")
endif()

set(PMN_CONFIG_QUERY_ONLY TRUE)
get_filename_component(CMAKE_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
include("${CMAKE_SOURCE_DIR}/Configuration.cmake")

foreach(_pmn_print_name ${PRINT_VARS})
    if(NOT DEFINED ${_pmn_print_name})
        message(FATAL_ERROR
            "PrintConfig.cmake: '${_pmn_print_name}' is not defined by "
            "Configuration.cmake, or isn't available in query mode -- see "
            "that file's header ('How scripts read this file').")
    endif()
    message(STATUS "${_pmn_print_name}=${${_pmn_print_name}}")
endforeach()
