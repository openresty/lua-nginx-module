#ifndef NGX_HTTP_LUA_PROBE_H
#define NGX_HTTP_LUA_PROBE_H


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if defined(NGX_DTRACE) && NGX_DTRACE

#include <ngx_dtrace_provider.h>

#define ngx_http_lua_probe_register_preload_package(L, pkg)                  \
    NGINX_LUA_HTTP_LUA_REGISTER_PRELOAD_PACKAGE(L, pkg)

#else /* !(NGX_DTRACE) */

#define ngx_http_lua_probe_register_preload_package(L, pkg)

#endif


#endif /* NGX_HTTP_LUA_PROBE_H */
