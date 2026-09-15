### Project
cmake_minimum_required(VERSION 3.25)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
project(
    DemoApp
    VERSION 0.1.0
    DESCRIPTION "Demo app exercising the generator-friendly CMake module system"
    LANGUAGES CXX
)

# This project's identity (PROJECT_CODE_NAME, DEFAULT_BUILD_TYPE), target
# selection (DIST_TARGET/PLATFORM/ARCHITECTURE/COMPILER_ID), and output-path
# configuration (out/, install/, dist/, docs/, and the bin/lib subdirectory
# names) all live in Configuration.cmake -- included immediately after
# project() since it needs real compiler detection (for DIST_TARGET
# auto-detection) and since everything below depends on it. See that file
# for the full model; edit it, or pass -D<NAME>=... at configure time,
# rather than hardcoding a value it already owns anywhere else in this
# project, scripts included.
include("${CMAKE_CURRENT_SOURCE_DIR}/Configuration.cmake")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Every static library in the project gets built with -fPIC by default --
# including vendored/fetched ones, whose own CMakeLists.txt we don't
# control and can't rely on to opt in themselves. Without this, a static
# dependency (ours or third-party) fails to link the moment it ends up
# pulled into a SHARED module: "recompile with -fPIC". Cheap on every
# platform that matters here; add_lib_module's STATIC branch also sets
# this per-target as a belt-and-braces fallback.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# -------------------------------------------------------
# Generator guard -- require Ninja (single or multi-config)
# -------------------------------------------------------
if(NOT CMAKE_GENERATOR MATCHES "Ninja")
    message(WARNING
        "This project targets Ninja. "
        "Current generator: '${CMAKE_GENERATOR}'. "
        "Reconfigure with:  cmake -G Ninja  or  cmake -G \"Ninja Multi-Config\"")
endif()

# Single-config Ninja needs CMAKE_BUILD_TYPE at configure time.
# Ninja Multi-Config uses CMAKE_CONFIGURATION_TYPES instead (no BUILD_TYPE needed).
if(CMAKE_GENERATOR STREQUAL "Ninja")
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "${DEFAULT_BUILD_TYPE}" CACHE STRING
            "Build type (Debug|Release|RelWithDebInfo|MinSizeRel)" FORCE)
        message(STATUS "CMAKE_BUILD_TYPE not set -- defaulting to ${DEFAULT_BUILD_TYPE}")
    endif()
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        Debug Release RelWithDebInfo MinSizeRel)
endif()

# -------------------------------------------------------
# Flat output layout
# Multi-config generators (Ninja Multi-Config) append /<Config> by default.
# Override all four configs so both Ninja variants produce the same layout.
# Subdirectory names come from Configuration.cmake (RUNTIME_OUTPUT_SUBDIR
# etc.); the base directory is always CMAKE_BINARY_DIR, wherever -B points
# (scripts/build.sh defaults to out/build -- see Configuration.cmake).
# -------------------------------------------------------
foreach(_cfg Debug Release RelWithDebInfo MinSizeRel)
    string(TOUPPER "${_cfg}" _CFG)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${RUNTIME_OUTPUT_SUBDIR}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${LIBRARY_OUTPUT_SUBDIR}")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${CMAKE_BINARY_DIR}/${ARCHIVE_OUTPUT_SUBDIR}")
endforeach()

# -------------------------------------------------------
# RPATH strategy
# By default CMake builds with a temporary RPATH and relinks at install time
# to embed the final one. Ninja on Linux with Clang does not support that
# relink step and will error out. Setting this ON tells CMake to embed the
# install RPATH at build time so no relink is ever needed.
# This is safe here because all our RPATHs are $ORIGIN-relative, so the
# same value is correct for both the build tree and the installed layout.
# Guarded to non-Windows since RPATH is an ELF concept only.
# -------------------------------------------------------
if(NOT WIN32)
    set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
endif()

# -------------------------------------------------------
# options
# -------------------------------------------------------
option(BUILD_TESTS      "Build test binaries"      OFF)
option(BUILD_EXAMPLES   "Build example binaries"   OFF)
option(INSTALL_TESTS    "Install test binaries"    OFF)
option(INSTALL_EXAMPLES "Install example binaries" OFF)

# Project-wide default for add_lib_module() when a module doesn't pass
# TYPE explicitly. This is CMake's own BUILD_SHARED_LIBS variable, so it
# also affects any third-party add_library() calls (FetchContent, etc.)
# that respect it. Override per-module with add_lib_module(... TYPE
# STATIC|SHARED ...), or globally with -DBUILD_SHARED_LIBS=ON.
option(BUILD_SHARED_LIBS "Build libraries as SHARED by default" OFF)

# INSTALL_* implies BUILD_* so targets exist when cmake --install runs
if(INSTALL_TESTS)
    set(BUILD_TESTS ON CACHE BOOL "" FORCE)
endif()
if(INSTALL_EXAMPLES)
    set(BUILD_EXAMPLES ON CACHE BOOL "" FORCE)
endif()

message(STATUS "BUILD_TESTS      = ${BUILD_TESTS}")
message(STATUS "BUILD_EXAMPLES   = ${BUILD_EXAMPLES}")
message(STATUS "BUILD_SHARED_LIBS (default lib TYPE) = ${BUILD_SHARED_LIBS}")

# -------------------------------------------------------
# Global compiler settings
#
# MSVC is TRUE for both cl.exe and clang-cl (windows-x64-msvc and
# windows-x64-clang-cl -- Clang targeting the MSVC ABI), so this block
# covers both Windows compiler variants with MSVC-style flags.
#
# /MP              -- parallel file compilation (Windows only; guarded
#                     because Ninja drives parallelism on Linux and
#                     clang-cl warns if passed /MP there)
# /EHsc            -- standard C++ exception handling
# /Zc:preprocessor -- conformant preprocessor (fixes __VA_ARGS__ etc.)
# /utf-8           -- UTF-8 source + execution charset
# -------------------------------------------------------
if(MSVC)
    if(WIN32)
        add_compile_options(/MP)
    endif()
    add_compile_options(/EHsc /Zc:preprocessor /utf-8)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

# -------------------------------------------------------
# MinGW runtime linking (windows-x86-mingw32 / windows-x64-mingw64)
#
# A MinGW build dynamically links libgcc/libstdc++/(on some distributions)
# libwinpthread by default, which then have to ship alongside the binary
# or sit on PATH -- easy to forget, and the exact DLL names differ between
# mingw32 and mingw64. Statically linking them instead trades a slightly
# larger binary for one that runs standalone, which is what you want for
# anything actually distributed. Verified directly (objdump -p on the
# result): this combination drops every non-Windows-system DLL from the
# import table, whether the toolchain's thread model is win32
# (libwinpthread isn't linked in the first place; -static is then a no-op
# for it) or posix (it is, and -static covers it). MINGW is CMake's
# built-in equivalent of this project's own COMPILER_ID being "mingw32"
# or "mingw64".
#
# EXECUTABLE targets only, deliberately, via a generator expression
# rather than a plain add_link_options() -- add_lib_module's SHARED
# targets (e.g. core_lib -- see source/Core/CMakeLists.txt) build with
# WINDOWS_EXPORT_ALL_SYMBOLS ON (BuildHelpers.cmake), which re-exports
# every symbol a statically-linked libgcc/libstdc++ would pull in,
# unwinder included. A dependent executable that *also* statically links
# the unwinder then collides with the copy the DLL already re-exports:
# "multiple definition of `_Unwind_Resume'". Confirmed directly (this
# project's demo_core + hello/farewell fail to link with that error if
# this is widened to every target) -- shared library modules keep the
# default dynamic runtime; only the final executables that link against
# them go fully static.
#
# That leaves every SHARED target still dynamically depending on exactly
# the DLLs the executables no longer need -- confirmed directly too: an
# executable built this way starts fine standalone, but loading a sibling
# SHARED module next to it fails (module not found) without them.
# PMN_MINGW_RUNTIME_DLLS resolves the actual files so BuildHelpers.cmake's
# add_lib_module can copy them next to every SHARED target (both in the
# build tree and at install time -- see the "install" section below),
# rather than making SHARED targets static too, which would hit the exact
# same symbol collision as above, just from the other direction. The
# filename varies by exception model (SEH on x86_64; DWARF-2 or SJLJ on
# i686) and by whether this toolchain uses posix threads, so each
# candidate is resolved by asking the compiler rather than hardcoding
# one -- -print-file-name=NAME echoes NAME back unchanged if it can't
# find it, which is how "not applicable to this toolchain" is detected
# below. Computed once, here, rather than per SHARED module, since it's
# the same toolchain-wide answer every time.
# -------------------------------------------------------
if(MINGW)
    add_link_options(
        "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:-static-libgcc;-static-libstdc++;-static;-lwinpthread>"
    )

    set(PMN_MINGW_RUNTIME_DLLS "")
    foreach(_pmn_dll_candidate
        libgcc_s_seh-1.dll
        libgcc_s_dw2-1.dll
        libgcc_s_sjlj-1.dll
        libstdc++-6.dll
        libwinpthread-1.dll
    )
        execute_process(
            COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=${_pmn_dll_candidate}
            OUTPUT_VARIABLE _pmn_resolved_dll
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(EXISTS "${_pmn_resolved_dll}")
            list(APPEND PMN_MINGW_RUNTIME_DLLS "${_pmn_resolved_dll}")
        endif()
    endforeach()
    if(PMN_MINGW_RUNTIME_DLLS)
        message(STATUS "MinGW runtime DLLs (bundled next to SHARED targets): ${PMN_MINGW_RUNTIME_DLLS}")
    endif()
endif()

# -------------------------------------------------------
# Build machinery (macros/functions) -- see cmake/BuildHelpers.cmake.
# This file should change rarely; it holds nothing project-specific.
# -------------------------------------------------------
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildHelpers.cmake")

# -------------------------------------------------------
# Third-party dependencies -- see cmake/Dependencies.cmake for
# add_vendor_header_only / add_vendor_subdirectory / add_dependency.
# A module declares its own dependencies in its own CMakeLists.txt (see
# source/Core/CMakeLists.txt for an example); nothing to add here.
# -------------------------------------------------------
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Dependencies.cmake")

# -------------------------------------------------------
# Documentation -- see cmake/Documentation.cmake. Every module
# automatically gets its own Doxygen target the moment Doxygen is
# installed; nothing to add here or in a module's own CMakeLists.txt
# unless you want to opt a module out (NO_DOCS) or override a Doxyfile
# setting (-DDOXYGEN_<TAG>=...).
# -------------------------------------------------------
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Documentation.cmake")

# -------------------------------------------------------
# Module discovery
#
# Every module lives in its own directory with its own CMakeLists.txt --
# usually a single add_lib_module/add_exe_module/add_test_module/
# add_example_module(...) call (see cmake/BuildHelpers.cmake for what each
# accepts). This file never needs editing to add, remove, or reconfigure
# a module: just add or remove the module's directory + CMakeLists.txt.
#
#   source/<Name>/CMakeLists.txt          -- library or app/executable module
#   source/tests/<Name>/CMakeLists.txt    -- test module
#   source/examples/<Name>/CMakeLists.txt -- example module
#
# (source/tests and source/examples aren't picked up by the first call
# below -- they have no CMakeLists.txt directly inside them, only their
# own children do, so they're only ever visited by their dedicated calls.)
#
# _discover_module_subdirectories() add_subdirectory()s every matching
# directory automatically; CONFIGURE_DEPENDS means the next build
# reconfigures on its own once a module directory is added or removed.
# -------------------------------------------------------
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source")
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source/tests")
_discover_module_subdirectories("${CMAKE_SOURCE_DIR}/source/examples")

# Emits <build-dir>/module_manifest-<CONFIG>.txt ("target_name=path_to_binary"
# per line) for every executable module discovered above. scripts/run.sh / run.bat
# read this to resolve a CMake target name to its binary -- must run after
# discovery.
_write_module_manifest("${CMAKE_BINARY_DIR}")

# Writes out/docs/index.html (DOCS_OUTPUT_DIR, see Configuration.cmake)
# linking to every module's generated documentation (a no-op if
# ENABLE_DOXYGEN is off) -- must run after discovery, same reasoning as
# the manifest above.
_write_docs_index("${DOCS_OUTPUT_DIR}")

# -------------------------------------------------------
# Copy compile_commands.json to the project root once it's fully
# populated, so clangd/clang-tidy/IWYU find it without extra config (most
# editors look for it at the repo root or search upward from the source
# file; CMake only ever writes it into the build directory). Runs at
# build time, by which point CMake's own generate step has already
# written build/compile_commands.json, so this works even on the very
# first build with no prior build directory. Vendored and fetched
# dependencies are excluded from it (see cmake/Dependencies.cmake) so it
# only reflects code this project owns.
# -------------------------------------------------------
if(CMAKE_EXPORT_COMPILE_COMMANDS)
    add_custom_target(copy_compile_commands ALL
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_BINARY_DIR}/compile_commands.json"
            "${COMPILE_COMMANDS_DESTINATION}"
        COMMENT "Copying compile_commands.json to project root"
        VERBATIM
    )
endif()

# -------------------------------------------------------
# install
# -------------------------------------------------------
set(_pmn_install_target_dir ${INSTALL_OUTPUT_DIR}/${DIST_TARGET})

# primary
set(RUNTIME_OUT_DIR  ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR})
set(LIBRARY_OUT_DIR  ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR})
set(ARCHIVE_OUT_DIR  ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR})

# tests -- runtime/library -> bin/tests/   archives -> lib/tests/
set(TEST_RUNTIME_OUT_DIR ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR}/tests)
set(TEST_LIBRARY_OUT_DIR ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR}/tests)
set(TEST_ARCHIVE_OUT_DIR ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR}/tests)

# examples -- runtime/library -> bin/examples/   archives -> lib/examples/
set(EXAMPLE_RUNTIME_OUT_DIR ${_pmn_install_target_dir}/${RUNTIME_OUTPUT_SUBDIR}/examples)
set(EXAMPLE_LIBRARY_OUT_DIR ${_pmn_install_target_dir}/${LIBRARY_OUTPUT_SUBDIR}/examples)
set(EXAMPLE_ARCHIVE_OUT_DIR ${_pmn_install_target_dir}/${ARCHIVE_OUTPUT_SUBDIR}/examples)

# Every install(TARGETS ...) below is tagged COMPONENT ${PROJECT_CODE_NAME}.
# A vendored/fetched dependency's own CMakeLists.txt (see
# cmake/Dependencies.cmake) usually has install() rules of its own, with
# no COMPONENT tag -- installing with `cmake --install build` (no
# --component filter) would pull those in too, typically under
# CMAKE_INSTALL_PREFIX (e.g. /usr/local). scripts/install.sh / install.bat always
# pass --component ${PROJECT_CODE_NAME} so only this project's own
# artifacts are installed; use the same flag if you invoke cmake --install
# directly.
message(STATUS "Will install primary modules.")
get_property(_pmn_primary_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_PRIMARY)
if(_pmn_primary_targets)
    install(TARGETS ${_pmn_primary_targets}
        COMPONENT ${PROJECT_CODE_NAME}
        ARCHIVE DESTINATION ${ARCHIVE_OUT_DIR}
        LIBRARY DESTINATION ${LIBRARY_OUT_DIR}
        RUNTIME DESTINATION ${RUNTIME_OUT_DIR}
    )
endif()

# MinGW SHARED targets (see the "MinGW runtime linking" comment above) --
# installed as plain files, alongside the DLLs above, rather than as
# TARGETS, since they're not CMake targets this project defines. RUNTIME,
# not LIBRARY: a .dll is a runtime artifact on Windows no matter which
# install()-TARGETS category built it.
if(PMN_MINGW_RUNTIME_DLLS)
    install(FILES ${PMN_MINGW_RUNTIME_DLLS}
        COMPONENT ${PROJECT_CODE_NAME}
        DESTINATION ${RUNTIME_OUT_DIR}
    )
endif()

# Both blocks below read whatever test/example modules discovery actually
# found -- no target names to keep in sync here when a module is added,
# removed, or renamed.
if(INSTALL_TESTS)
    get_property(_pmn_test_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_TEST)
    if(_pmn_test_targets)
        message(STATUS "Will install test modules: ${_pmn_test_targets}")
        install(TARGETS ${_pmn_test_targets}
            COMPONENT ${PROJECT_CODE_NAME}
            ARCHIVE DESTINATION ${TEST_ARCHIVE_OUT_DIR}
            LIBRARY DESTINATION ${TEST_LIBRARY_OUT_DIR}
            RUNTIME DESTINATION ${TEST_RUNTIME_OUT_DIR}
        )
    else()
        message(WARNING "INSTALL_TESTS is ON but no test modules were found under source/tests/.")
    endif()
endif()

if(INSTALL_EXAMPLES)
    get_property(_pmn_example_targets GLOBAL PROPERTY PMN_MODULE_TARGETS_EXAMPLE)
    if(_pmn_example_targets)
        message(STATUS "Will install example modules: ${_pmn_example_targets}")
        install(TARGETS ${_pmn_example_targets}
            COMPONENT ${PROJECT_CODE_NAME}
            ARCHIVE DESTINATION ${EXAMPLE_ARCHIVE_OUT_DIR}
            LIBRARY DESTINATION ${EXAMPLE_LIBRARY_OUT_DIR}
            RUNTIME DESTINATION ${EXAMPLE_RUNTIME_OUT_DIR}
        )
    else()
        message(WARNING "INSTALL_EXAMPLES is ON but no example modules were found under source/examples/.")
    endif()
endif()
