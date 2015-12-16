/*
 * Copyright (C) 2014 Daurnimator
 */

#ifndef _NGX_HTTP_LUA_CONNECTION_H_INCLUDED_
#define _NGX_HTTP_LUA_CONNECTION_H_INCLUDED_

#include <lua.h>
#include "ngx_http_lua_common.h"

#define NGX_HTTP_LUA_CONNECTION_KEY "ngx_connection_t*"

int ngx_http_lua_connection_init(ngx_connection_t **p, ngx_socket_t fd, const char **err);
void ngx_http_lua_connection_release(ngx_connection_t *conn);
int ngx_http_lua_connection_prep(ngx_http_request_t *r, ngx_connection_t *conn,
    int poll_mask, ngx_msec_t wait_ms, const char **err);
void ngx_http_lua_inject_connection(lua_State *L);


#endif /* _NGX_HTTP_LUA_CONNECTION_H_INCLUDED_ */
