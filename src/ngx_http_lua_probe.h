/*
 * automatically generated from the file dtrace/ngx_lua_provider.d by the
 *  gen-dtrace-probe-header tool in the nginx-devel-utils project:
 *  https://github.com/agentzh/nginx-devel-utils
 */

#ifndef NGX_HTTP_LUA_PROBE_H
#define NGX_HTTP_LUA_PROBE_H


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>


#if defined(NGX_DTRACE) && NGX_DTRACE

#include <ngx_dtrace_provider.h>

#define ngx_http_lua_probe_register_preload_package(L, pkg)                  \
    NGINX_LUA_HTTP_LUA_REGISTER_PRELOAD_PACKAGE(L, pkg)

#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)          \
    NGINX_LUA_HTTP_LUA_REQ_SOCKET_CONSUME_PREREAD(r, data, len)

#define ngx_http_lua_probe_user_coroutine_create(r, parent, child)           \
    NGINX_LUA_HTTP_LUA_USER_COROUTINE_CREATE(r, parent, child)

#define ngx_http_lua_probe_user_coroutine_resume(r, parent, child)           \
    NGINX_LUA_HTTP_LUA_USER_COROUTINE_RESUME(r, parent, child)

#else /* !(NGX_DTRACE) */

#define ngx_http_lua_probe_register_preload_package(L, pkg)
#define ngx_http_lua_probe_req_socket_consume_preread(r, data, len)
#define ngx_http_lua_probe_user_coroutine_create(r, parent, child)
#define ngx_http_lua_probe_user_coroutine_resume(r, parent, child)

#endif

#endif /* NGX_HTTP_LUA_PROBE_H */
