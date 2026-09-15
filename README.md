# DemoApp — a generator-friendly CMake module system

A small template project (one shared library, two executables, one
vendored dependency, one fetched dependency) that demonstrates a CMake
setup where **adding, removing, or renaming a module never requires
editing the root `CMakeLists.txt`**, output paths and project identity
come from exactly one file, and Linux, Windows/MSVC, clang-cl, and
MinGW are all first-class, auto-detected targets.

Copy the structure, delete the demo code, keep the machinery.

## Quick start

```bash
scripts/setup.sh      # once: fetch pinned Ninja + Doxygen, install the git hook
scripts/build.sh      # configure (if needed) + build, Release by default
scripts/run.sh hello_exe World
```

```bat
scripts\setup.bat
scripts\build.bat
scripts\run.bat hello_exe World
```

```
Hello, World! (from demo_core)
```

## What you get

- **One source of truth.** `Configuration.cmake` owns this project's
  identity, target selection, and every output path. Nothing else —
  not a `.cmake` module, not a shell script, not `.gitignore` —
  hardcodes a second copy of a value it defines. See
  [Configuration.cmake: the source of truth](#configurationcmake-the-source-of-truth).
- **Six toolchains, auto-detected.** GCC and Clang on Linux; MSVC,
  clang-cl, GNU-style Clang, and both MinGW flavors on Windows — see
  [Supported targets](#supported-targets-dist_target).
- **Zero-edit module discovery.** Drop a directory with a one-line
  `CMakeLists.txt` under `source/`, `source/tests/`, or
  `source/examples/`; it's built, linked, installed, tested, and
  documented without touching anything else. See
  [Adding a module](#adding-a-module).
- **Self-managing tooling.** `scripts/setup.sh`/`setup.bat` fetch a
  pinned Ninja and Doxygen (so every machine builds and documents
  identically) and wire up a pre-commit hook — no system-wide installs,
  no version drift.
- **A build script that takes real arguments.** Pick a configuration
  and forward arbitrary `-D...` flags to CMake, safely, on both bash
  and `cmd.exe` — see [scripts/build.sh / build.bat](#scriptsbuildsh--buildbat).

## Project layout

```
Configuration.cmake      Source of truth: identity, DIST_TARGET, output paths
CMakeLists.txt            Root build: options, compiler settings, module
                          discovery, install rules -- rarely needs editing
CMakePresets.json         One preset per supported DIST_TARGET, for IDEs
cpp-style-guide.md        The C++ style guide .clang-format/.clang-tidy enforce

cmake/
  BuildHelpers.cmake       add_lib_module / add_exe_module / add_test_module /
                           add_example_module, and module discovery
  Dependencies.cmake       add_vendor_header_only / add_vendor_subdirectory /
                           add_dependency
  Documentation.cmake      Per-module Doxygen wiring
  PrintConfig.cmake        Lets scripts/*.sh|*.bat read Configuration.cmake
  FetchNinja.cmake, NinjaPin.cmake        Pinned Ninja download
  FetchDoxygen.cmake, DoxygenPin.cmake    Pinned Doxygen download

scripts/                  setup, build, run, install, docs, refactor
                           -- .sh and .bat, one-to-one

source/
  Core/                    core_lib -- a SHARED library module
  HelloApp/, FarewellApp/  Executable modules depending on core_lib
  tests/, examples/        Empty by default -- see Adding a module

vendor/
  tiny_case/               A vendored dependency with its own CMakeLists.txt
  tiny_ansi/               A vendored header-only dependency

c-api/.clang-tidy          Stricter naming rules for a C-API subtree, if you add one
.githooks/pre-commit       clang-format/clang-tidy check, installed by scripts/setup
```

## Configuration.cmake: the source of truth

Every value that used to (or could) drift into a second, hand-kept-in-sync
copy lives in `Configuration.cmake`:

- **Identity** — `PROJECT_CODE_NAME` (the `cmake --install --component`
  name) and `DEFAULT_BUILD_TYPE`.
- **Target selection** — `DIST_TARGET`, and the `PLATFORM` /
  `ARCHITECTURE` / `COMPILER_ID` metadata derived from it.
- **Output paths** — `OUT_DIR`, `INSTALL_OUTPUT_DIR`, `DOCS_OUTPUT_DIR`,
  `TOOLCACHE_DIR`, and the `bin`/`lib` subdirectory names.

Retargeting this template for your own project, or changing where
things land, means editing this one file — or passing `-D<NAME>=...` at
configure time — never hunting through `CMakeLists.txt`, a `cmake/*.cmake`
module, or a script for a hardcoded duplicate.

That includes the shell scripts, which run *before* any CMake configure
exists to ask a question of. `cmake/PrintConfig.cmake` is a tiny
`cmake -P` script that loads `Configuration.cmake` and prints one value;
every script that needs one calls it instead of hardcoding a default.
This is exactly the bug it replaces: `install.sh`/`install.bat` used to
each hardcode their own literal `"demo"`, with a comment warning it
*"must match `PROJECT_CODE_NAME` in `CMakeLists.txt`"* — the kind of
comment that's really begging for the two to eventually disagree. They
don't hardcode it anymore; they ask `Configuration.cmake`.

The one thing this deliberately can't do: a bare `cmake -P` script never
runs `project()`, so it never gets real compiler detection. Anything
in `Configuration.cmake` that depends on the compiler — `DIST_TARGET`
and everything derived from it — is skipped in this "query mode" and
fails loudly if a script asks for it anyway, rather than guessing. No
script currently needs to; `cmake --install` reads what a real configure
already baked into the build directory, not these variables directly.

## Supported targets (`DIST_TARGET`)

`DIST_TARGET` is a single `<platform>-<arch>-<compiler>` string that
picks the toolchain metadata (`PLATFORM`, `ARCHITECTURE`, `COMPILER_ID`)
used throughout the build and as the `cmake --install` destination
subdirectory (`out/install/<DIST_TARGET>/...`). It's auto-detected from
whatever compiler CMake finds:

| `DIST_TARGET`          | Compiler                                             |
|------------------------|-------------------------------------------------------|
| `linux-x64-gcc`        | GCC on Linux                                           |
| `linux-x64-clang`      | Clang on Linux                                         |
| `windows-x64-msvc`     | cl.exe (MSVC)                                          |
| `windows-x64-clang-cl` | clang-cl (Clang targeting the MSVC ABI)                |
| `windows-x64-clang`    | Clang with its own GNU-style driver (e.g. MSYS2 CLANG64) |
| `windows-x86-mingw32`  | 32-bit GCC via MinGW                                   |
| `windows-x64-mingw64`  | 64-bit GCC via MinGW-w64                               |

Auto-detection tells clang-cl apart from GNU-style Clang by
`CMAKE_CXX_COMPILER_FRONTEND_VARIANT` (`MSVC` vs. `GNU` — both report
`Clang` as the compiler ID), and mingw32 apart from mingw64 by pointer
size, not by parsing the compiler's own executable name. An
unrecognized compiler is a configure-time `FATAL_ERROR` naming every
valid value above, not a silent guess — auto-detection guessing "must
be MSVC" for anything it doesn't recognize is exactly what used to
misidentify a MinGW build as MSVC and install it to the wrong directory.

Override auto-detection with `-DDIST_TARGET=<value>`, or use one of the
matching entries in `CMakePresets.json` — open the project in an
IDE with CMake preset support (CLion, VS Code, Visual Studio) and pick
one from the target dropdown, or:

```bash
cmake --workflow --preset windows-x64-mingw64   # or --list-presets to see all
```

**MinGW runtime note:** executables built for `windows-x86-mingw32` /
`windows-x64-mingw64` statically link `libgcc`/`libstdc++`/`libwinpthread`
so they run standalone. `core_lib` (a `SHARED` target) can't do the
same — it would collide with the executable's own statically-linked
copy of the C++ unwinder (`multiple definition of _Unwind_Resume`) — so
it keeps the default dynamic runtime instead, and the build copies the
three runtime DLLs next to it automatically (both in the build tree and
at install time). You won't notice this unless you go looking for those
DLLs next to `libdemo_core.dll`; it's mentioned here in case you do.

## Scripts

Every script has a `.sh` and a `.bat` twin with identical behavior, and
prints its own usage in a header comment. All of them assume the
project root as the working directory but `cd` there themselves, so run
them from anywhere inside the repo.

### `scripts/setup.sh` / `setup.bat`

Run once per clone. Fetches a pinned Ninja and Doxygen into
`.cache/tools/` (via `cmake/FetchNinja.cmake` / `FetchDoxygen.cmake` —
safe to re-run, and skips anything already fetched) and points
`git config core.hooksPath` at `.githooks/`, so the pre-commit check
below is active from your very first commit. Also prints whether
`clang-format`/`clang-tidy` are on `PATH` (optional — the hook warns,
rather than blocks, if they aren't installed).

### `scripts/build.sh` / `build.bat`

```
scripts/build.sh [BUILD_TYPE] [CMAKE_ARGS...]
```

`BUILD_TYPE` (`Debug`/`Release`/`RelWithDebInfo`/`MinSizeRel`) is
optional and defaults to `Configuration.cmake`'s `DEFAULT_BUILD_TYPE`.
Anything else is forwarded to `cmake` verbatim at configure time:

```bash
scripts/build.sh Debug -DDIST_TARGET=windows-x64-mingw64
scripts/build.sh -DBUILD_TESTS=ON              # BUILD_TYPE omitted
```

An argument is treated as `BUILD_TYPE` if it doesn't start with `-`;
otherwise there's no `BUILD_TYPE` override and every argument is a
CMake argument.

Prefers a pinned Ninja (from `setup.sh`) over a system one, and falls
back to CMake's platform default generator with a warning — never an
error — if neither is available; run `setup.sh` for the faster,
version-pinned option.

**The `cmd.exe` `=` trap, and why `build.bat` avoids it:** `cmd.exe`
splits a batch file's own `%1`/`%2`/... parameters (and `shift`) on
space, comma, semicolon, *and* `=` — so a naively-written script reading
`-DBUILD_TESTS=ON` through `%1` sees it as two parameters, `-DBUILD_TESTS`
and `ON`, silently. `%*` (the raw, unsplit command line) doesn't have
this problem, and neither does `FOR /F`, which only splits on space/tab
by default — `build.bat` parses arguments that way specifically so a
`-D...=...` argument survives intact. `build.sh`'s `"$@"`/`shift` never
had this problem to begin with; this paragraph is Windows-only trivia.

### `scripts/run.sh` / `run.bat`

```
scripts/run.sh <target-name> [-- program-args...]
```

Resolves a CMake target name to its built executable via the manifest
`_write_module_manifest()` generates at configure time
(`out/build/module_manifest-<CONFIG>.txt`) — so this script never needs
updating when a module is added, removed, or renamed. Run with no
arguments to list every known target.

### `scripts/install.sh` / `install.bat`

```
scripts/install.sh [BUILD_TYPE]
```

Installs to `out/install/<DIST_TARGET>/{bin,lib}`, always passing
`--component` (read from `Configuration.cmake`'s `PROJECT_CODE_NAME`)
so a vendored or fetched dependency's own, untagged `install()` rules
are never pulled in alongside this project's own artifacts.

### `scripts/docs.sh` / `docs.bat`

```
scripts/docs.sh [module-name]
```

Builds the `docs` target (every module) or `docs_<module-name>` (just
one) and prints the path to the generated landing page,
`out/docs/index.html`. A no-op with a clear message — not an error —
if Doxygen hasn't been fetched yet or `ENABLE_DOXYGEN=OFF`.

### `scripts/refactor.sh` / `refactor.bat`

```
scripts/refactor.sh [path]
```

Runs `clang-format -i` and `clang-tidy --fix` across `source/` and
`c-api/` (or just the given path) — the "fix it" counterpart to the
pre-commit hook, which only checks. Review with `git diff` afterward,
like any auto-formatter.

## Adding a module

Every module — library, executable, test, or example — lives in its
own directory with a single-purpose `CMakeLists.txt`. The root
`CMakeLists.txt` discovers `source/*`, `source/tests/*`, and
`source/examples/*` automatically (`_discover_module_subdirectories()`
in `cmake/BuildHelpers.cmake`); nothing there needs editing.

```cmake
# source/MyLib/CMakeLists.txt
add_lib_module(my_lib
    TYPE SHARED            # or STATIC; defaults to BUILD_SHARED_LIBS
    DEPENDS fmt::fmt
)
```

```cmake
# source/MyApp/CMakeLists.txt
add_exe_module(my_app DEPENDS my_lib)
```

```cmake
# source/tests/my_lib_test/CMakeLists.txt
add_test_module(my_lib_test DEPENDS my_lib)   # ctest-registered, built with -DBUILD_TESTS=ON
```

```cmake
# source/examples/my_example/CMakeLists.txt
add_example_module(my_example DEPENDS my_lib) # built with -DBUILD_EXAMPLES=ON
```

All four glob their own sources (`src/*.cpp` + `include/*.h(pp)` for a
library; `*.cpp` + `include/*.h(pp)` for an executable, recursively
from the module's own directory), apply per-target warning flags
(`/W4 /permissive-` on MSVC-family compilers, `-Wall -Wextra -Wpedantic`
elsewhere), set up `$ORIGIN`-relative `RPATH` on Linux, register the
target for install and for `scripts/run.sh`, and get their own Doxygen
target for free. `OUTPUT_NAME`, `EXTRA_SOURCES`, and `NO_DOCS` are
available on all four when the defaults don't fit — see
`cmake/BuildHelpers.cmake` for the full option list.

## Adding a dependency

Three patterns, in `cmake/Dependencies.cmake`, covering vendored and
fetched code:

```cmake
# Header-only, vendored under vendor/<name>/include
add_vendor_header_only(tiny_ansi)

# Vendored, with its own CMakeLists.txt, under vendor/<subdir>
add_vendor_subdirectory(tiny_case)

# Fetched from a Git repo (or an already-installed copy, if found first)
add_dependency(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        11.0.2
    FIND_PACKAGE_ARGS NAMES fmt
)
```

Then depend on whichever target the dependency defines, exactly like
depending on another module: `add_lib_module(my_lib DEPENDS fmt::fmt)`.
All three keep the dependency's warnings out of your build and its
sources out of `compile_commands.json`, and are safe to call more than
once for the same name if two modules need the same dependency.

## Documentation generation

Every module gets a Doxygen target automatically — nothing to add to
its own `CMakeLists.txt`. `scripts/docs.sh` / `docs.bat` build all of
them and print the landing page path; see
[scripts/docs.sh / docs.bat](#scriptsdocssh--docsbat) above. Doxygen
itself is fetched by `scripts/setup.sh` (pinned, not your system's, so
every machine's output matches) — documentation targets print a
pointer to that script instead of building until it has been run once.

Configure it with `-DENABLE_DOXYGEN=OFF`, `-DDOXYGEN_<TAG>=...` for any
[Doxyfile tag](https://www.doxygen.nl/manual/config.html), or opt a
single module out with `NO_DOCS` on its `add_*_module(...)` call. A
module's own `README.md`, if it has one, becomes that module's Doxygen
mainpage automatically.

## Code style & tooling

This project follows [`cpp-style-guide.md`](cpp-style-guide.md),
enforced by:

- **`.clang-format`** — formatting (indentation, brace style, line
  length). Comments throughout cross-reference the style guide section
  each rule comes from.
- **`.clang-tidy`** (and the stricter `c-api/.clang-tidy`, for a C-API
  subtree if you add one) — naming conventions and a handful of
  bug-prone patterns. Comments note what each check *can't* catch, so
  those gaps stay visible instead of silently unenforced.
- **`.githooks/pre-commit`** — runs both tools against staged files
  before every commit, installed automatically by `scripts/setup.sh` /
  `setup.bat`. Neither tool is required to have this hook active: if a
  binary isn't on `PATH`, the hook warns and skips that check instead
  of blocking the commit. Only an actual formatting or lint issue from
  a tool that *is* installed blocks anything.
- **`scripts/refactor.sh` / `refactor.bat`** — the auto-fix counterpart
  to the hook's check-only behavior.
- **`.editorconfig`** / **`.gitattributes`** — editor-level whitespace
  consistency and normalized line endings (`.bat` files are kept
  `CRLF` deliberately; see the file for the rest).

## Output layout

Everything generated lands under `out/`, kept out of git by an
auto-synced block in `.gitignore` (regenerated from
`Configuration.cmake`'s actual path variables on every configure, so it
can't silently drift out of sync with what's really produced):

```
out/
  build/                          Default CMAKE_BINARY_DIR (scripts/build.sh -B out/build)
    bin/                          Executables, .dll/.so
    lib/                          Static libs, import libs
  install/<DIST_TARGET>/{bin,lib} cmake --install destination
  docs/<module>/html/, index.html Generated Doxygen output
  dist/                           Reserved for packaged output (e.g. a future CPack integration)

.cache/tools/                     Pinned Ninja + Doxygen (outside out/ on purpose --
                                   `rm -rf out/` shouldn't force a re-download)
compile_commands.json             Copied to the project root every build, for clangd/clang-tidy
```
