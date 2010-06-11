#ifndef NGX_HTTP_LUA_COMMON_H__
#define NGX_HTTP_LUA_COMMON_H__

#ifndef DDEBUG
#define DDEBUG 0
#endif

#include "ddebug.h"

#include <assert.h>
#include <setjmp.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <ndk.h>

extern ngx_module_t ngx_http_lua_module;

#endif

// vi:ts=4 sw=4 fdm=marker

