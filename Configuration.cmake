# =============================================================================
# Configuration.cmake
#
# The single source of truth for this project's identity, target
# selection, and output layout. Change a value here, or override with
# -D<NAME>=... at configure time, instead of hunting through
# CMakeLists.txt/cmake/*.cmake -- or a script under scripts/ -- for a
# hardcoded copy. If you find yourself typing a value this file already
# defines anywhere else, that's a bug: read it from here instead (see
# "How scripts read this file" below for the non-CMake side of that).
#
# -----------------------------------------------------------------------
# Project identity
# -----------------------------------------------------------------------
#   PROJECT_CODE_NAME   machine-friendly identifier baked into every
#                        target as PROJECT_NAME_CODE (BuildHelpers.cmake's
#                        _finalize_module_target) and used as the
#                        `cmake --install --component` name (CMakeLists.txt's
#                        install() calls, scripts/install.sh / install.bat).
#   DEFAULT_BUILD_TYPE   what CMAKE_BUILD_TYPE (single-config Ninja) and
#                        the scripts' own BUILD_TYPE argument default to
#                        when nothing else is specified.
#
# -----------------------------------------------------------------------
# Target selection (DIST_TARGET)
# -----------------------------------------------------------------------
# DIST_TARGET identifies what you're building for as a single
# "<platform>-<arch>-<compiler>" string, auto-detected from the compiler
# CMake found unless you pass -DDIST_TARGET=<value> explicitly (or select
# a CMakePresets.json preset, which does the same thing). Every value in
# PMN_VALID_DIST_TARGETS below is supported:
#
#   linux-x64-gcc          GCC on Linux
#   linux-x64-clang        Clang on Linux
#   windows-x64-msvc       cl.exe (MSVC)
#   windows-x64-clang-cl   clang-cl (Clang targeting the MSVC ABI --
#                          CMake's MSVC variable is TRUE for this too)
#   windows-x64-clang      Clang with its own GNU-style driver on Windows
#                          (e.g. an MSYS2 CLANG64 environment) -- distinct
#                          from clang-cl above, which mimics cl.exe
#                          instead of gcc
#   windows-x86-mingw32    32-bit GCC via MinGW
#   windows-x64-mingw64    64-bit GCC via MinGW-w64
#
# Auto-detection FATAL_ERRORs rather than guessing when the compiler
# doesn't match any of the above, instead of silently assuming MSVC --
# that silent assumption is exactly what used to misidentify a MinGW GCC
# build as MSVC (COMPILER_ID "msvc" for an actual GNU compiler), which in
# turn misfiled its `cmake --install` output under .../windows-x64-msvc/.
#
# PLATFORM, ARCHITECTURE, and COMPILER_ID below are metadata derived from
# DIST_TARGET; CMakeLists.txt and the cmake/*.cmake modules consume these
# rather than re-deriving them.
#
# -----------------------------------------------------------------------
# Output layout
# -----------------------------------------------------------------------
# Everything this project generates lives under one OUT_DIR:
#
#   out/
#     build/                           CMAKE_BINARY_DIR -- scripts/build.sh
#                                       defaults to configuring here (-B
#                                       out/build); compiled artifacts land
#                                       in out/build/<RUNTIME_OUTPUT_SUBDIR>
#                                       and out/build/<ARCHIVE_OUTPUT_SUBDIR>
#                                       during normal day-to-day builds.
#     install/<DIST_TARGET>/{bin,lib}  what `cmake --install` / scripts/
#                                       scripts/install.sh populates.
#     dist/                            reserved for packaged/archived
#                                       output (e.g. a future CPack
#                                       integration) -- not populated by
#                                       this project yet, but the path is
#                                       configured and ready.
#     docs/<module>/html, docs/index.html   generated Doxygen output
#                                       (cmake/Documentation.cmake).
#
# One thing lives outside OUT_DIR on purpose: .cache/tools/ (TOOLCACHE_DIR)
# caches downloaded, pinned build tools (currently Ninja and Doxygen), kept
# separate so a clean `rm -rf out/` doesn't force a re-download.
#
# .gitignore is kept in sync with the paths below automatically, every
# configure -- see the bottom of this file.
#
# -----------------------------------------------------------------------
# How scripts read this file
# -----------------------------------------------------------------------
# scripts/build.sh|build.bat and scripts/install.sh|install.bat need
# values from here too (the install component name, the default build
# type, where the tool cache lives) but are running before any CMake
# configure exists to ask. They get them from cmake/PrintConfig.cmake, a
# tiny `cmake -P` script that includes this file and prints one value --
# see that file for the exact mechanism, and any of the four scripts
# above for how each shell dialect calls it. That's what makes this file
# a *real* source of truth end to end: nothing outside it -- not a
# .cmake module, not a shell script, not .gitignore -- hardcodes a second
# copy of a value defined here.
#
# One consequence: a plain `cmake -P` script never runs project() and so
# never gets real compiler detection -- WIN32, CMAKE_CXX_COMPILER_ID,
# CMAKE_SIZEOF_VOID_P etc. can't be trusted there. Everything in "Target
# selection" above is therefore skipped when PMN_CONFIG_QUERY_ONLY is set
# (cmake/PrintConfig.cmake sets it before including this file), along
# with this file's own filesystem side effects (creating out/dist/,
# rewriting .gitignore) -- a query has no business doing either, and it
# runs far more often than a real configure, which makes that doubly
# true. Keep that in mind if you add to this file: anything that needs a
# real compiler belongs inside the `if(NOT PMN_CONFIG_QUERY_ONLY)` guard
# below (where it's simply unavailable to a script query, on purpose);
# anything else must stay evaluable without one, and must not
# message(STATUS ...) outside that guard either, or it'll show up as
# extra noise in a script's query output (see PrintConfig.cmake).
#
# Included by CMakeLists.txt right after project(), before any other
# variable defined here is used, so every value is available project-wide
# from that point on.
# =============================================================================

include_guard(GLOBAL)

# -------------------------------------------------------
# Project identity
# -------------------------------------------------------
set(PROJECT_CODE_NAME "demo" CACHE STRING
    "Machine-friendly identifier: baked into targets as PROJECT_NAME_CODE and used as the `cmake --install` component name")

set(DEFAULT_BUILD_TYPE "Release" CACHE STRING
    "CMAKE_BUILD_TYPE / scripts BUILD_TYPE default when none is given")

# -------------------------------------------------------
# Target selection -- see the file header for the full model. Skipped in
# query mode (see "How scripts read this file" above): it needs real
# compiler detection that a bare `cmake -P` script never performs, and no
# script currently needs DIST_TARGET/PLATFORM/ARCHITECTURE/COMPILER_ID
# anyway -- cmake --install reads what a real configure already baked
# into the build directory, not these variables directly.
# -------------------------------------------------------
if(NOT PMN_CONFIG_QUERY_ONLY)
    set(PMN_VALID_DIST_TARGETS
        linux-x64-gcc
        linux-x64-clang
        windows-x64-msvc
        windows-x64-clang-cl
        windows-x64-clang
        windows-x86-mingw32
        windows-x64-mingw64
    )
    list(JOIN PMN_VALID_DIST_TARGETS "  " _pmn_valid_dist_targets_str)

    if(NOT DIST_TARGET)
        if(WIN32)
            if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
                set(DIST_TARGET "windows-x64-msvc")
            elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
                # clang-cl: Clang's cl.exe-compatible driver personality,
                # selected either by invoking a binary literally named
                # clang-cl(.exe) or via `clang++ --driver-mode=cl`. CMake
                # surfaces this as CMAKE_CXX_COMPILER_FRONTEND_VARIANT
                # rather than a distinct COMPILER_ID, since it's the same
                # Clang either way -- just a different argument dialect
                # and default target ABI.
                set(DIST_TARGET "windows-x64-clang-cl")
            elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
                set(DIST_TARGET "windows-x64-clang")
            elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
                # A real GCC on Windows is MinGW (mingw.org's original,
                # 32-bit-only project) or MinGW-w64 (adds 64-bit; also
                # provides a 32-bit target, conventionally called
                # "mingw32" too since it's the direct successor). Tell
                # them apart by pointer size rather than parsing the
                # compiler's own executable name, which is a config
                # choice, not something to depend on.
                if(CMAKE_SIZEOF_VOID_P EQUAL 8)
                    set(DIST_TARGET "windows-x64-mingw64")
                else()
                    set(DIST_TARGET "windows-x86-mingw32")
                endif()
            else()
                message(FATAL_ERROR
                    "Could not auto-detect a DIST_TARGET for CXX compiler "
                    "'${CMAKE_CXX_COMPILER_ID}' on Windows -- set one "
                    "explicitly: -DDIST_TARGET=<value>\n"
                    "Valid values: ${_pmn_valid_dist_targets_str}")
            endif()
        else()
            if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
                set(DIST_TARGET "linux-x64-gcc")
            elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
                set(DIST_TARGET "linux-x64-clang")
            else()
                message(FATAL_ERROR
                    "Could not auto-detect a DIST_TARGET for CXX compiler "
                    "'${CMAKE_CXX_COMPILER_ID}' -- set one explicitly: "
                    "-DDIST_TARGET=<value>\n"
                    "Valid values: ${_pmn_valid_dist_targets_str}")
            endif()
        endif()
        message(STATUS "DIST_TARGET not set -- auto-detected: ${DIST_TARGET}")
        message(STATUS "  (use CMakePresets.json or -DDIST_TARGET=<value> to set it explicitly)")
    else()
        message(STATUS "DIST_TARGET    = ${DIST_TARGET}")
    endif()

    # Platform / compiler metadata from DIST_TARGET.
    if(DIST_TARGET STREQUAL "linux-x64-gcc")
        set(PLATFORM "linux")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "gcc")
    elseif(DIST_TARGET STREQUAL "linux-x64-clang")
        set(PLATFORM "linux")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "clang")
    elseif(DIST_TARGET STREQUAL "windows-x64-msvc")
        set(PLATFORM "windows")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "msvc")
    elseif(DIST_TARGET STREQUAL "windows-x64-clang-cl")
        set(PLATFORM "windows")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "clang-cl")
    elseif(DIST_TARGET STREQUAL "windows-x64-clang")
        set(PLATFORM "windows")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "clang")
    elseif(DIST_TARGET STREQUAL "windows-x86-mingw32")
        set(PLATFORM "windows")
        set(ARCHITECTURE "x86")
        set(COMPILER_ID "mingw32")
    elseif(DIST_TARGET STREQUAL "windows-x64-mingw64")
        set(PLATFORM "windows")
        set(ARCHITECTURE "x64")
        set(COMPILER_ID "mingw64")
    else()
        message(FATAL_ERROR
            "Unsupported DIST_TARGET: '${DIST_TARGET}'.\n"
            "Valid values: ${_pmn_valid_dist_targets_str}\n"
            "Tip: open CMakePresets.json in your IDE to select a preset, "
            "or pass -DDIST_TARGET=<value> on the command line.")
    endif()

    message(STATUS "Platform     = ${PLATFORM}")
    message(STATUS "Architecture = ${ARCHITECTURE}")
    message(STATUS "Compiler     = ${COMPILER_ID} (${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION})")
endif()

# -------------------------------------------------------
# Output paths
# -------------------------------------------------------
set(OUT_DIR "${CMAKE_SOURCE_DIR}/out" CACHE PATH
    "Root directory for everything this project generates: build artifacts, install trees, docs, and reserved dist packaging output")

set(DIST_OUTPUT_DIR "${OUT_DIR}/dist" CACHE PATH
    "Reserved for packaged/archived distribution output (e.g. a future CPack integration). Not populated by this project yet.")

set(INSTALL_OUTPUT_DIR "${OUT_DIR}/install" CACHE PATH
    "Root of the cmake --install destination tree, one subdirectory per DIST_TARGET")

set(DOCS_OUTPUT_DIR "${OUT_DIR}/docs" CACHE PATH
    "Root of generated Doxygen documentation, one subdirectory per module")

set(COMPILE_COMMANDS_DESTINATION "${CMAKE_SOURCE_DIR}/compile_commands.json" CACHE FILEPATH
    "Where compile_commands.json is copied to after every build, for clangd/clang-tidy tooling (see CMakeLists.txt)")

# Deliberately NOT under OUT_DIR: this caches downloaded, pinned build
# tools (Ninja and Doxygen -- see cmake/FetchNinja.cmake and
# cmake/FetchDoxygen.cmake), which are machine-local and expensive to
# re-fetch, not build output. Keeping it separate means a clean `rm -rf
# out/` (a normal "start fresh" gesture) doesn't force a re-download.
set(TOOLCACHE_DIR "${CMAKE_SOURCE_DIR}/.cache/tools" CACHE PATH
    "Where pinned build tools (currently Ninja and Doxygen) are cached, kept separate from OUT_DIR")

if(NOT PMN_CONFIG_QUERY_ONLY)
    # out/dist/ is reserved (see the header comment above) and nothing writes
    # to it yet, so it's created eagerly here -- otherwise it simply wouldn't
    # exist until something populates it, which could easily read as "this
    # was never wired up" rather than "intentionally reserved for later".
    # Skipped in query mode along with the .gitignore sync below -- a value
    # lookup shouldn't have filesystem side effects, and it runs far more
    # often than a real configure.
    file(MAKE_DIRECTORY "${DIST_OUTPUT_DIR}")
endif()

# Subdirectory NAMES only (not full paths) for where compiled artifacts
# land inside whatever the current build directory is (CMAKE_BINARY_DIR) --
# these apply correctly no matter where -B points, including if you build
# outside out/build entirely. LIBRARY defaults to the same subdirectory as
# RUNTIME because shared libraries need to sit next to the executables
# that load them via the project's $ORIGIN-relative RPATH strategy (see
# CMakeLists.txt).
set(RUNTIME_OUTPUT_SUBDIR "bin" CACHE STRING "Build-dir subdirectory for runtime artifacts (executables, .dll, .so)")
set(LIBRARY_OUTPUT_SUBDIR "bin" CACHE STRING "Build-dir subdirectory for shared-library artifacts")
set(ARCHIVE_OUTPUT_SUBDIR "lib" CACHE STRING "Build-dir subdirectory for static/import-library artifacts (.a, .lib)")

# =============================================================================
# .gitignore sync
#
# Keeps a marked block in .gitignore in sync with the actual, current
# values of the path variables above -- every configure, automatically.
# Nothing outside that block (e.g. the Visual Studio template this
# project's .gitignore starts from) is ever touched. This is what makes
# this file the real source of truth for these paths specifically: change
# OUT_DIR (or override it with -DOUT_DIR=...) and .gitignore updates on
# the next configure instead of silently drifting out of sync with what
# actually gets generated.
#
# If .gitignore doesn't exist yet, it's created with just this block. If
# it exists but has no markers yet, the block is appended. If the markers
# are already there, only the content between them is replaced. The file
# is only rewritten when the computed content actually differs, so a
# normal reconfigure doesn't spuriously touch it (or its mtime).
#
# A path is only added if it resolves inside the repo (CMAKE_SOURCE_DIR)
# -- e.g. an overridden TOOLCACHE_DIR pointing somewhere else entirely is
# silently skipped, since .gitignore has nothing meaningful to say about
# a location outside the repository it lives in.
#
# Skipped entirely in query mode -- see "How scripts read this file"
# above.
# =============================================================================

if(NOT PMN_CONFIG_QUERY_ONLY)
    set(_pmn_gitignore_begin "# >>> Configuration.cmake generated paths -- BEGIN (do not edit by hand; edit Configuration.cmake and reconfigure) >>>")
    set(_pmn_gitignore_end   "# <<< Configuration.cmake generated paths -- END <<<")

    function(_pmn_gitignore_relpath ABSOLUTE_VALUE OUT_VAR)
        file(RELATIVE_PATH _pmn_rel "${CMAKE_SOURCE_DIR}" "${ABSOLUTE_VALUE}")
        if(_pmn_rel MATCHES "^\\.\\.")
            set(${OUT_VAR} "" PARENT_SCOPE)
        else()
            set(${OUT_VAR} "${_pmn_rel}" PARENT_SCOPE)
        endif()
    endfunction()

    set(_pmn_gitignore_entries "")
    foreach(_pmn_dir_var OUT_DIR DIST_OUTPUT_DIR INSTALL_OUTPUT_DIR DOCS_OUTPUT_DIR TOOLCACHE_DIR)
        _pmn_gitignore_relpath("${${_pmn_dir_var}}" _pmn_rel)
        if(_pmn_rel)
            list(APPEND _pmn_gitignore_entries "${_pmn_rel}/")
        endif()
    endforeach()

    _pmn_gitignore_relpath("${COMPILE_COMMANDS_DESTINATION}" _pmn_cc_rel)
    if(_pmn_cc_rel)
        list(APPEND _pmn_gitignore_entries "${_pmn_cc_rel}")
    endif()

    list(REMOVE_DUPLICATES _pmn_gitignore_entries)
    list(SORT _pmn_gitignore_entries)

    set(_pmn_gitignore_block_content "")
    foreach(_pmn_entry ${_pmn_gitignore_entries})
        string(APPEND _pmn_gitignore_block_content "${_pmn_entry}\n")
    endforeach()

    set(_pmn_gitignore_path "${CMAKE_SOURCE_DIR}/.gitignore")
    set(_pmn_gitignore_new_block "${_pmn_gitignore_begin}\n${_pmn_gitignore_block_content}${_pmn_gitignore_end}")

    if(EXISTS "${_pmn_gitignore_path}")
        file(READ "${_pmn_gitignore_path}" _pmn_gitignore_content)
    else()
        set(_pmn_gitignore_content "")
    endif()

    string(FIND "${_pmn_gitignore_content}" "${_pmn_gitignore_begin}" _pmn_gitignore_begin_pos)
    string(FIND "${_pmn_gitignore_content}" "${_pmn_gitignore_end}" _pmn_gitignore_end_pos)

    if(_pmn_gitignore_begin_pos GREATER -1 AND _pmn_gitignore_end_pos GREATER -1
       AND _pmn_gitignore_end_pos GREATER _pmn_gitignore_begin_pos)
        # Replace only the content between the existing markers.
        string(SUBSTRING "${_pmn_gitignore_content}" 0 ${_pmn_gitignore_begin_pos} _pmn_gitignore_before)
        string(LENGTH "${_pmn_gitignore_end}" _pmn_gitignore_end_marker_len)
        math(EXPR _pmn_gitignore_after_start "${_pmn_gitignore_end_pos} + ${_pmn_gitignore_end_marker_len}")
        string(SUBSTRING "${_pmn_gitignore_content}" ${_pmn_gitignore_after_start} -1 _pmn_gitignore_after)
        set(_pmn_gitignore_final "${_pmn_gitignore_before}${_pmn_gitignore_new_block}${_pmn_gitignore_after}")
    else()
        # No markers yet -- append (trimming trailing blank lines first so we
        # don't accumulate extra blank lines across repeated appends).
        string(REGEX REPLACE "\n+$" "" _pmn_gitignore_trimmed "${_pmn_gitignore_content}")
        if(_pmn_gitignore_trimmed STREQUAL "")
            set(_pmn_gitignore_final "${_pmn_gitignore_new_block}\n")
        else()
            set(_pmn_gitignore_final "${_pmn_gitignore_trimmed}\n\n${_pmn_gitignore_new_block}\n")
        endif()
    endif()

    if(NOT _pmn_gitignore_final STREQUAL _pmn_gitignore_content)
        file(WRITE "${_pmn_gitignore_path}" "${_pmn_gitignore_final}")
    endif()
endif()
