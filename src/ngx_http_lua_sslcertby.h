
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_ssl_cert_handler_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_cert_handler_file(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L);

char * ngx_http_lua_ssl_cert_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

int ngx_http_lua_ssl_cert_handler(ngx_ssl_conn_t *ssl_conn, void *data);


#endif /* _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
