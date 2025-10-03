#############################################################################
#Copyright (c) 2024,
#
#Distributed under the terms of the BSD 3-Clause License.
#
#The full license is in the file LICENSE, distributed with this software.
#############################################################################

cmake_minimum_required(VERSION 4.0.0)
project(xeus-ocaml)
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake;${CMAKE_MODULE_PATH}")

set(XEUS_OCAML_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Versionning
# ===========

file(STRINGS "${XEUS_OCAML_INCLUDE_DIR}/xeus-ocaml/xeus_ocaml_config.hpp" version_defines
     REGEX "#define XEUS_OCAML_VERSION_(MAJOR|MINOR|PATCH)")
foreach (ver ${version_defines})
    if (ver MATCHES "#define XEUS_OCAML_VERSION_(MAJOR|MINOR|PATCH) +([^ ]+)$")
        set(XEUS_OCAML_VERSION_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}" CACHE INTERNAL "")
    endif ()
endforeach ()
set(${PROJECT_NAME}_VERSION
    ${XEUS_OCAML_VERSION_MAJOR}.${XEUS_OCAML_VERSION_MINOR}.${XEUS_OCAML_VERSION_PATCH})
message(STATUS "Building xeus-ocaml v${${PROJECT_NAME}_VERSION}")

# Configuration
# =============

include(GNUInstallDirs)

if (NOT DEFINED XEUS_OCAML_KERNELSPEC_PATH)
    set(XEUS_OCAML_KERNELSPEC_PATH "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}/")
endif ()

configure_file (
    "${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels/xocaml/kernel.json.in"
    "${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels/xocaml/kernel.json"
)

# Build options
# =============

option(XEUS_OCAML_BUILD_STATIC "Build xeus-ocaml static library" ON)
OPTION(XEUS_OCAML_BUILD_SHARED "Split xocaml build into executable and library" ON)
OPTION(XEUS_OCAML_BUILD_EXECUTABLE "Build the xocaml executable" ON)

OPTION(XEUS_OCAML_USE_SHARED_XEUS "Link xocaml  with the xeus shared library (instead of the static library)" ON)
OPTION(XEUS_OCAML_USE_SHARED_XEUS_OCAML "Link xocaml  with the xeus shared library (instead of the static library)" ON)


if(EMSCRIPTEN)
    add_compile_definitions(XEUS_OCAML_EMSCRIPTEN_WASM_BUILD)
    message("Build with emscripten")
    SET(XEUS_OCAML_BUILD_STATIC ON)
    SET(XEUS_OCAML_BUILD_SHARED OFF)
    SET(XEUS_OCAML_BUILD_EXECUTABLE OFF)
    SET(XEUS_OCAML_USE_SHARED_XEUS ON)
    SET(XEUS_OCAML_USE_SHARED_XEUS_OCAML OFF)
    SET(XEUS_OCAML_BUILD_TESTS OFF)
endif()


# Dependencies
# ============

set(xeus_REQUIRED_VERSION 5.0.0)
set(xeus_lite_REQUIRED_VERSION 4.0.0)

find_package(xeus-lite ${xeus_lite_REQUIRED_VERSION} REQUIRED)
find_package(xeus ${xeus_REQUIRED_VERSION} REQUIRED)


# Flags
# =====
include(CheckCXXCompilerFlag)

if (MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /wd4251 /wd4141")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /wd4018 /wd4267 /wd4715 /wd4146 /wd4129")
endif ()

if (CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID MATCHES "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Intel")
    message(STATUS "COMPILER ID: ${CMAKE_CXX_COMPILER_ID}")
    if(NOT EMSCRIPTEN)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wunused-parameter -Wextra -Wreorder")
    endif()


    CHECK_CXX_COMPILER_FLAG("-std=c++17" HAS_CPP_17_FLAG)
    if (HAS_CPP_17_FLAG)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")

    else ()
        message(FATAL_ERROR "Unsupported compiler -- xeus requires C++17 support!")
    endif ()
endif ()

if(EMSCRIPTEN)
    # ENV (https://github.com/emscripten-core/emscripten/commit/6d9681ad04f60b41ef6345ab06c29bbc9eeb84e0)
    set(EMSCRIPTEN_FEATURES "${EMSCRIPTEN_FEATURES} -s \"EXTRA_EXPORTED_RUNTIME_METHODS=[ENV']\"")
endif()


# Source files
# ============

set(XEUS_OCAML_HEADERS
    include/xeus-ocaml/xeus_ocaml_config.hpp
    include/xeus-ocaml/xinterpreter.hpp
)

set(XEUS_OCAML_SRC
    src/xinterpreter.cpp

)

set(XEUS_OCAML_MAIN_SRC
    src/main.cpp
)


# Targets and link - Macros
# =========================

include(CheckCXXCompilerFlag)

string(TOUPPER "${CMAKE_BUILD_TYPE}" U_CMAKE_BUILD_TYPE)

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib; ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")

macro(xeus_ocaml_set_common_options target_name)
    if (MSVC)
        target_compile_options(${target_name} PUBLIC /wd4251 /wd4141)
        target_compile_options(${target_name} PUBLIC /wd4018 /wd4267 /wd4715 /wd4146 /wd4129)
    endif ()

    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR
        CMAKE_CXX_COMPILER_ID MATCHES "GNU" OR
        CMAKE_CXX_COMPILER_ID MATCHES "Intel")

        target_compile_options(${target_name} PUBLIC -Wunused-parameter -Wextra -Wreorder)

        # C++17 flag
        CHECK_CXX_COMPILER_FLAG("-std=c++17" HAS_CPP_17_FLAG)
        if (HAS_CPP_17_FLAG)
            target_compile_features(${target_name} PRIVATE cxx_std_17)
        else ()
            message(FATAL_ERROR "Unsupported compiler -- xeus-ocaml requires C++17 support!")
        endif ()
    endif ()

    if (APPLE)
        set_target_properties(${target_name} PROPERTIES
            MACOSX_RPATH ON
        )
    else ()
        set_target_properties(${target_name} PROPERTIES
            BUILD_WITH_INSTALL_RPATH 1
            SKIP_BUILD_RPATH FALSE
        )
    endif ()

    set_target_properties(${target_name} PROPERTIES
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )
endmacro()

# Common macro kernels (xocaml)
macro(xeus_ocaml_set_kernel_options target_name)
    if (XEUS_OCAML_USE_SHARED_XEUS_OCAML)
        target_link_libraries(${target_name} PRIVATE xeus-ocaml)
        if(CMAKE_DL_LIBS)
            target_link_libraries(${target_name} PRIVATE ${CMAKE_DL_LIBS} util)
        endif()
    else ()
        target_link_libraries(${target_name} PRIVATE xeus-ocaml-static)
    endif()

    if(NOT EMSCRIPTEN)
        find_package(Threads)
        target_link_libraries(${target_name} PRIVATE ${CMAKE_THREAD_LIBS_INIT})
    endif()

endmacro()

# Common macro for shared and static library
macro(xeus_ocaml_create_target target_name linkage output_name)
    string(TOUPPER "${linkage}" linkage_upper)

    if (NOT ${linkage_upper} MATCHES "^(SHARED|STATIC)$")
        message(FATAL_ERROR "Invalid library linkage: ${linkage}")
    endif ()

    add_library(${target_name} ${linkage_upper} ${XEUS_OCAML_SRC} ${XEUS_OCAML_HEADERS})
    xeus_ocaml_set_common_options(${target_name})

    set_target_properties(${target_name} PROPERTIES
                          PUBLIC_HEADER "${XEUS_OCAML_HEADERS}"
                          PREFIX ""
                          VERSION ${${PROJECT_NAME}_VERSION}
                          SOVERSION ${XEUS_OCAML_VERSION_MAJOR}
                          OUTPUT_NAME "lib${output_name}")

    target_compile_features(${target_name} PUBLIC cxx_std_17)



    target_compile_definitions(${target_name} PUBLIC "XEUS_OCAML_EXPORTS")


    target_include_directories(${target_name}
                               PUBLIC
                               $<BUILD_INTERFACE:${XEUS_OCAML_INCLUDE_DIR}>
                               $<INSTALL_INTERFACE:include>)

    if (XEUS_OCAML_USE_SHARED_XEUS)
        set(XEUS_OCAML_XEUS_TARGET xeus)
    else ()
        set(XEUS_OCAML_XEUS_TARGET xeus-static)
    endif ()

    target_link_libraries(${target_name} PUBLIC ${XEUS_OCAML_XEUS_TARGET})
    if (WIN32 OR CYGWIN)
        #
    elseif (APPLE)
        target_link_libraries(${target_name} PRIVATE "-undefined dynamic_lookup")
    endif ()
    if(NOT EMSCRIPTEN)
        find_package(Threads) # TODO: add Threads as a dependence of xeus-static?
        target_link_libraries(${target_name} PRIVATE ${CMAKE_THREAD_LIBS_INIT})
    endif()

    target_link_libraries(${target_name} PUBLIC xeus-lite)

endmacro()

# xeus-ocaml
# ===========

set(XEUS_OCAML_TARGETS "")

if (XEUS_OCAML_BUILD_SHARED)
    # Build libraries
    xeus_ocaml_create_target(xeus-ocaml SHARED xeus-ocaml)
    list(APPEND XEUS_OCAML_TARGETS xeus-ocaml)
endif ()

if (XEUS_OCAML_BUILD_STATIC)
    # On Windows, a static library should use a different output name
    # to avoid the conflict with the import library of a shared one.
    if (CMAKE_HOST_WIN32)
        xeus_ocaml_create_target(xeus-ocaml-static STATIC xeus-ocaml-static)
    else ()
        xeus_ocaml_create_target(xeus-ocaml-static STATIC xeus-ocaml)
    endif ()
    if(EMSCRIPTEN)
        target_compile_options(xeus-ocaml-static PRIVATE -fPIC)
    endif()
    list(APPEND XEUS_OCAML_TARGETS xeus-ocaml-static)
endif ()

target_link_options(xeus-ocaml-static
    PUBLIC "SHELL: -s WASM_BIGINT=1"
    PUBLIC "SHELL: -s ALLOW_MEMORY_GROWTH=1"
)

include(WasmBuildOptions)

add_executable(xocaml src/main_emscripten_kernel.cpp )
target_compile_options(xocaml
PRIVATE "-fPIC"
PUBLIC "SHELL: -s WASM_BIGINT=1"
PUBLIC "SHELL: -s ALLOW_MEMORY_GROWTH=1"
)
XEUS_OCAML_set_kernel_options(xocaml)
xeus_wasm_compile_options(xocaml)
xeus_wasm_link_options(xocaml "web,worker")

#
target_link_options(xocaml
    PUBLIC "SHELL: -s WASM_BIGINT=1"
    PUBLIC "SHELL: -s ALLOW_MEMORY_GROWTH=1"
    PUBLIC "SHELL: -s MAIN_MODULE=1"
    PUBLIC "SHELL: -s NO_EXIT_RUNTIME=1"
    PUBLIC "SHELL: -s FORCE_FILESYSTEM=1"
    # "SHELL:--pre-js ${CMAKE_CURRENT_SOURCE_DIR}/src/ocaml/xocaml.js"
    PUBLIC "SHELL:--pre-js ${CMAKE_CURRENT_SOURCE_DIR}/src/pre.js"

    PUBLIC "SHELL:--post-js ${CMAKE_CURRENT_SOURCE_DIR}/src/post.js"
)


# Installation
# ============
include(CMakePackageConfigHelpers)

set(XEUS_OCAML_CMAKECONFIG_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}" CACHE STRING "install path for xeus-ocamlConfig.cmake")

# Install xeus-ocaml and xeus-ocaml-static
if (XEUS_OCAML_BUILD_SHARED)
    install(TARGETS ${XEUS_OCAML_TARGETS}
            EXPORT ${PROJECT_NAME}-targets
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/xeus-ocaml)

    # Makes the project importable from the build directory
    export(EXPORT ${PROJECT_NAME}-targets
           FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Targets.cmake")
endif ()

# Install xocaml
if (XEUS_OCAML_BUILD_EXECUTABLE)
    install(TARGETS xocaml
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()

if (XEUS_OCAML_BUILD_EXECUTABLE OR EMSCRIPTEN)
    # Configuration and data directories for jupyter and xeus-ocaml
    set(XJUPYTER_DATA_DIR "share"    CACHE STRING "Jupyter data directory")

    # Install xocaml Jupyter kernelspec
    set(KERNELSPEC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter)
    install(DIRECTORY ${KERNELSPEC_DIR}
            DESTINATION ${XJUPYTER_DATA_DIR}
            PATTERN "*.in" EXCLUDE)


    # Extra path for installing Jupyter kernelspec
    if (XEXTRA_JUPYTER_DATA_DIR)
        install(DIRECTORY ${KERNELSPEC_DIR}
                DESTINATION ${XEXTRA_JUPYTER_DATA_DIR}
                PATTERN "*.in" EXCLUDE)
    endif ()
endif ()

# Configure 'xeus-ocamlConfig.cmake' for a build tree
set(XEUS_OCAML_CONFIG_CODE "####### Expanded from \@XEUS_OCAML_CONFIG_CODE\@ #######\n")
set(XEUS_OCAML_CONFIG_CODE "${XEUS_OCAML_CONFIG_CODE}set(CMAKE_MODULE_PATH \"${CMAKE_CURRENT_SOURCE_DIR}/cmake;\${CMAKE_MODULE_PATH}\")\n")
set(XEUS_OCAML_CONFIG_CODE "${XEUS_OCAML_CONFIG_CODE}##################################################")
configure_package_config_file(${PROJECT_NAME}Config.cmake.in
                              "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake"
                              INSTALL_DESTINATION ${PROJECT_BINARY_DIR})

# Configure 'xeus-ocamlConfig.cmake.in for an install tree
set(XEUS_OCAML_CONFIG_CODE "")
configure_package_config_file(${PROJECT_NAME}Config.cmake.in
                              "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${PROJECT_NAME}Config.cmake"
                              INSTALL_DESTINATION ${XEUS_OCAML_CMAKECONFIG_INSTALL_DIR})

write_basic_package_version_file(${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake
                                 VERSION ${${PROJECT_NAME}_VERSION}
                                 COMPATIBILITY AnyNewerVersion)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${PROJECT_NAME}Config.cmake
              ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake
              DESTINATION ${XEUS_OCAML_CMAKECONFIG_INSTALL_DIR})

if (XEUS_OCAML_BUILD_SHARED)
    install(EXPORT ${PROJECT_NAME}-targets
            FILE ${PROJECT_NAME}Targets.cmake
            DESTINATION ${XEUS_OCAML_CMAKECONFIG_INSTALL_DIR})
endif ()

if(EMSCRIPTEN)
    install(TARGETS xocaml
            ARCHIVE DESTINATION ${XEUS_OCAML_CMAKECONFIG_INSTALL_DIR})

    install(FILES
            "${CMAKE_CURRENT_SOURCE_DIR}/src/x-ocaml.worker+effects.js"
            DESTINATION ${CMAKE_INSTALL_LIBDIR})

    install(FILES
            "$<TARGET_FILE_DIR:xocaml>/xocaml.js"
            "$<TARGET_FILE_DIR:xocaml>/xocaml.wasm"
            DESTINATION ${CMAKE_INSTALL_BINDIR})
endif ()