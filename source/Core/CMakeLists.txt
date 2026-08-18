add_dependency(fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        11.0.2
    FIND_PACKAGE_ARGS NAMES fmt
)
add_lib_module(core_lib TYPE SHARED OUTPUT_NAME "demo_core" DEPENDS fmt::fmt)
