cmake_minimum_required(VERSION 3.20)
project(CFE_LuaRuntime VERSION 5.4.8 LANGUAGES C)

# Build official Lua as a shared library and its command-line interpreter.
# wxLua and future CFE native hosts must link to this same Lua ABI.
set(LUA_SOURCE_DIR "" CACHE PATH "Official Lua src directory containing lua.h")
if(NOT EXISTS "${LUA_SOURCE_DIR}/lua.h")
    message(FATAL_ERROR "Set LUA_SOURCE_DIR to the official Lua src directory.")
endif()

file(GLOB lua_sources CONFIGURE_DEPENDS "${LUA_SOURCE_DIR}/*.c")
list(REMOVE_ITEM lua_sources "${LUA_SOURCE_DIR}/lua.c" "${LUA_SOURCE_DIR}/luac.c")
add_library(lua54 SHARED ${lua_sources})
target_include_directories(lua54 PUBLIC "${LUA_SOURCE_DIR}")
target_compile_definitions(lua54 PRIVATE LUA_BUILD_AS_DLL LUA_COMPAT_5_3)
set_target_properties(lua54 PROPERTIES PREFIX "" OUTPUT_NAME "lua54")

if(APPLE)
    target_compile_definitions(lua54 PRIVATE LUA_USE_MACOSX)
elseif(UNIX)
    target_compile_definitions(lua54 PRIVATE LUA_USE_LINUX)
    target_link_libraries(lua54 PRIVATE m ${CMAKE_DL_LIBS})
endif()

add_executable(lua "${LUA_SOURCE_DIR}/lua.c")
target_link_libraries(lua PRIVATE lua54)
target_compile_definitions(lua PRIVATE LUA_COMPAT_5_3)
if(UNIX)
    set_target_properties(lua PROPERTIES INSTALL_RPATH "$ORIGIN")
endif()

install(TARGETS lua54 lua
    RUNTIME DESTINATION .
    LIBRARY DESTINATION .
    ARCHIVE DESTINATION lib)
install(FILES "${LUA_SOURCE_DIR}/lua.h" "${LUA_SOURCE_DIR}/luaconf.h"
    "${LUA_SOURCE_DIR}/lauxlib.h" "${LUA_SOURCE_DIR}/lualib.h"
    DESTINATION include)
