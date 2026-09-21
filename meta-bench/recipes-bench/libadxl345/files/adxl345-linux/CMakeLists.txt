# libadxl345: a userspace driver for the ADXL345, packaged as a library.
#
# One build definition, consumed by three things: a developer running
# cmake directly, the Debian packaging through dh --buildsystem=cmake, and
# the Yocto recipe through the cmake bbclass. Keeping it single is what
# stops the two packagings drifting apart.
#
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.16)
project(adxl345 VERSION 1.0.0 LANGUAGES C)

include(GNUInstallDirs)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GPIOD REQUIRED libgpiod>=2.0)

# -----------------------------------------------------------------------
# The library
#
# platform.c is listed here and NOT in the test target below. That is the
# entire test seam: two targets, each with one implementation of
# platform.h, chosen at link time. See the header for why it is not a
# vtable.
add_library(adxl345 SHARED
  src/adxl.c
  src/platform.c
)

target_include_directories(adxl345
  PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
          $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/adxl345>
  PRIVATE src
)

target_include_directories(adxl345 SYSTEM PRIVATE ${GPIOD_INCLUDE_DIRS})
target_link_libraries(adxl345 PRIVATE ${GPIOD_LIBRARIES})
target_link_directories(adxl345 PRIVATE ${GPIOD_LIBRARY_DIRS})

# Hidden by default, so a symbol is exported only where adxl.h says
# ADXL_API. This is the mechanism behind the "exactly six symbols"
# acceptance criterion; without it every internal helper is public and
# the ABI is whatever the compiler felt like.
set_target_properties(adxl345 PROPERTIES
  C_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  VERSION ${PROJECT_VERSION}
  SOVERSION ${PROJECT_VERSION_MAJOR}
)

target_compile_options(adxl345 PRIVATE -Wall -Wextra -Werror)

# The version the library reports comes from the project version, so
# adxl_version and the soname cannot disagree.
target_compile_definitions(adxl345 PRIVATE
  ADXL_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
  ADXL_VERSION_MINOR=${PROJECT_VERSION_MINOR}
  ADXL_VERSION_PATCH=${PROJECT_VERSION_PATCH}
)

option(ADXL_SANITIZE "build with ASan and UBSan" OFF)
if(ADXL_SANITIZE)
  # Applied to every target below as well, because a sanitizer build that
  # covers the library and not the test finds nothing: the test is what
  # drives the library.
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g)
  add_link_options(-fsanitize=address,undefined)
endif()

# -----------------------------------------------------------------------
# The application
#
# A separate binary that links the library through its public header
# only, exactly as a third party would. If adxl-map needs something the
# installed headers do not expose, that is a finding about the API rather
# than a reason to reach into src/.
add_executable(adxl-map apps/adxl-map.c)
target_link_libraries(adxl-map PRIVATE adxl345)
target_compile_options(adxl-map PRIVATE -Wall -Wextra -Werror)

# -----------------------------------------------------------------------
# Tests
#
# fake_platform.c replaces src/platform.c. The test therefore exercises
# every line of adxl.c, including the register writes, with no bus, no
# sensor and no kernel. That is what lets CI run it.
enable_testing()

add_executable(test_api
  tests/test_api.c
  tests/fake_platform.c
  src/adxl.c
)
target_include_directories(test_api PRIVATE include src)
target_compile_options(test_api PRIVATE -Wall -Wextra -Werror)
target_compile_definitions(test_api PRIVATE
  ADXL_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
  ADXL_VERSION_MINOR=${PROJECT_VERSION_MINOR}
  ADXL_VERSION_PATCH=${PROJECT_VERSION_PATCH}
)
add_test(NAME api COMMAND test_api)

# -----------------------------------------------------------------------
# Installation
configure_file(cmake/adxl345.pc.in adxl345.pc @ONLY)

install(TARGETS adxl345
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(TARGETS adxl-map
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
# The bindings and the policy program. Installed by CMake rather than by
# each packaging separately, so the Debian package and the Yocto recipe
# ship the same files without either listing them twice.
#
# dist-packages rather than site-packages: Debian's python3 looks in the
# first and Yocto's in the second, and the path below is overridden by
# the recipe for that reason. Hard-coding one would silently install to a
# directory the interpreter never searches, which presents as "the module
# is not there" with the file plainly present.
set(ADXL_PYDIR "lib/python3/dist-packages" CACHE STRING
    "where the python package goes, relative to the prefix")

install(DIRECTORY python/adxl345
  DESTINATION ${ADXL_PYDIR}
  FILES_MATCHING PATTERN "*.py"
)
install(PROGRAMS python/adxl-motion
  DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(FILES include/adxl.h
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/adxl345
)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/adxl345.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)
