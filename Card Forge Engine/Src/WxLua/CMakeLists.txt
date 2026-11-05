cmake_minimum_required(VERSION 3.20)
project(CFE_wxLua LANGUAGES C CXX)

# Keep compatibility settings and Lua module naming outside upstream wxLua.
# The upstream tree is downloaded to temporary staging for each build.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "Compatibility floor for upstream CMake")
set(WXLUA_SOURCE_DIR "" CACHE PATH "Pinned upstream wxLua source directory")
if(NOT EXISTS "${WXLUA_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Set WXLUA_SOURCE_DIR to the upstream wxLua directory.")
endif()

add_subdirectory("${WXLUA_SOURCE_DIR}" upstream)
set_target_properties(wxLuaModule PROPERTIES PREFIX "" OUTPUT_NAME "wx")

# Match the assertion ABI of the release wxWidgets libraries.
target_compile_definitions(wxLuaModule PRIVATE wxDEBUG_LEVEL=0)
