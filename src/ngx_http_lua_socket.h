#ifndef NGX_HTTP_LUA_SOCKET_H
#define NGX_HTTP_LUA_SOCKET_H


#include "ngx_http_lua_common.h"

typedef struct ngx_http_lua_socket_upstream_s  ngx_http_lua_socket_upstream_t;


typedef void (*ngx_http_lua_socket_upstream_handler_pt)(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);


struct ngx_http_lua_socket_upstream_s {
    ngx_http_lua_socket_upstream_handler_pt     read_event_handler;
    ngx_http_lua_socket_upstream_handler_pt     write_event_handler;

    ngx_http_request_t              *request;
    ngx_peer_connection_t           *peer;

    ngx_buf_t                        buffer;
    size_t                           length;
};


void ngx_http_lua_inject_socket_api(lua_State *L);


#endif /* NGX_HTTP_LUA_SOCKET_H */

