/*
 * Copyright (C) Yichun Zhang (agentzh)
 */

#ifndef _NGX_HTTP_LUA_SSL_CLIENT_HELLOBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_CLIENT_HELLOBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_HTTP_SSL)

ngx_int_t ngx_http_lua_ssl_client_hello_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_client_hello_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_ssl_client_hello_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);

char *ngx_http_lua_ssl_client_hello_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

#ifdef OPENSSL_IS_BORINGSSL
int ngx_http_lua_ssl_client_hello_handler(const SSL_CLIENT_HELLO *);
#else
int ngx_http_lua_ssl_client_hello_handler(ngx_ssl_conn_t *ssl_conn,
    int *al, void *arg);
#endif



#endif  /* NGX_HTTP_SSL */


#endif /* _NGX_HTTP_LUA_SSL_CLIENT_HELLOBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
