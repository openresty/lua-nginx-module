
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SERVER_NAME_RESOLVERBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SERVER_NAME_RESOLVERBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


char *ngx_http_lua_server_name_resolver_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);

ngx_int_t ngx_http_lua_server_name_resolver(ngx_connection_t *c,
    ngx_pool_t *pool, ngx_str_t *host, ngx_str_t *name);


#endif /* _NGX_HTTP_LUA_SERVER_NAME_RESOLVERBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
