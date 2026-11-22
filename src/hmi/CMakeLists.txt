# bench-hmi: an LVGL dashboard as a Wayland client.
#
# The interesting part of this file is the protocol generation, and it is
# interesting because LVGL does not do it for you.
#
# src/drivers/wayland/lv_wl_xdg_shell.c in LVGL 9.3 contains
#
#     #include "wayland_xdg_shell.h"
#
# and that header is NOT in the LVGL source tree: there is no CMakeLists
# inside src/drivers/wayland, and neither LVGL's own CMakeLists nor
# lv_port_linux's generates it. The integrator generates it, with
# wayland-scanner, from the xdg-shell protocol description that the
# wayland-protocols package ships. The file name is not free: it has to
# be exactly wayland_xdg_shell.h, because that is what the driver
# includes.
#
# Leaving this out produces link errors about xdg_wm_base symbols that
# name neither wayland-protocols nor wayland-scanner, which the project
# specification lists as a pitfall for exactly this reason.

cmake_minimum_required(VERSION 3.13)
project(bench-hmi C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra)

find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(XKBCOMMON REQUIRED xkbcommon)

# --- the xdg-shell protocol code ----------------------------------------
#
# wayland-scanner runs on the BUILD machine, so under BitBake it comes
# from wayland-native. pkg-config gives both the tool and the directory
# holding the protocol xml, rather than either being hardcoded.
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)

find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

set(XDG_SHELL_XML "${WAYLAND_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml")
if(NOT EXISTS "${XDG_SHELL_XML}")
    message(FATAL_ERROR
        "xdg-shell.xml not found at ${XDG_SHELL_XML}. "
        "wayland-protocols reported pkgdatadir=${WAYLAND_PROTOCOLS_DIR}. "
        "Without it the LVGL wayland driver cannot be built.")
endif()

set(XDG_GEN_DIR "${CMAKE_BINARY_DIR}/wayland-generated")
file(MAKE_DIRECTORY "${XDG_GEN_DIR}")

# The names matter. lv_wl_xdg_shell.c includes "wayland_xdg_shell.h".
add_custom_command(
    OUTPUT "${XDG_GEN_DIR}/wayland_xdg_shell.h"
    COMMAND "${WAYLAND_SCANNER}" client-header
            "${XDG_SHELL_XML}" "${XDG_GEN_DIR}/wayland_xdg_shell.h"
    DEPENDS "${XDG_SHELL_XML}"
    VERBATIM)

add_custom_command(
    OUTPUT "${XDG_GEN_DIR}/wayland_xdg_shell.c"
    COMMAND "${WAYLAND_SCANNER}" private-code
            "${XDG_SHELL_XML}" "${XDG_GEN_DIR}/wayland_xdg_shell.c"
    DEPENDS "${XDG_SHELL_XML}"
    VERBATIM)

# --- LVGL ----------------------------------------------------------------
#
# Built from the vendored copy. LV_CONF_PATH points at the lv_conf.h that
# the recipe generates from upstream's template and then verifies, so a
# silently unapplied option cannot reach this point.
set(LV_CONF_PATH "${CMAKE_CURRENT_SOURCE_DIR}/lv_conf.h"
    CACHE STRING "" FORCE)
set(LV_CONF_BUILD_DISABLE_EXAMPLES ON CACHE BOOL "" FORCE)
set(LV_CONF_BUILD_DISABLE_DEMOS ON CACHE BOOL "" FORCE)
add_subdirectory(lvgl)

# LVGL's wayland driver compiles as part of the lvgl target, so the
# generated header has to be on ITS include path, not only on ours.
target_include_directories(lvgl PRIVATE "${XDG_GEN_DIR}")

# --- the application ------------------------------------------------------
add_executable(bench-hmi
    main.c
    dashboard.c
    metrics.c
    "${XDG_GEN_DIR}/wayland_xdg_shell.c"
    "${XDG_GEN_DIR}/wayland_xdg_shell.h")

target_include_directories(bench-hmi PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${XDG_GEN_DIR}"
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${XKBCOMMON_INCLUDE_DIRS})

target_link_libraries(bench-hmi PRIVATE
    lvgl
    ${WAYLAND_CLIENT_LIBRARIES}
    ${XKBCOMMON_LIBRARIES}
    m)

install(TARGETS bench-hmi RUNTIME DESTINATION bin)
