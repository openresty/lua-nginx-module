
/*
 * Based on ngx_http_lua_ssl_certby.h and ngx_http_lua_ssl_session_storeby.h
 * by Yichun Zhang (agentzh)
 * 
 * Author: Tuure Vartiainen (vartiait)
 */


#ifndef _NGX_HTTP_LUA_SSL_PSKBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_PSKBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_HTTP_SSL)


ngx_int_t ngx_http_lua_ssl_psk_server_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_psk_server_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_ssl_psk_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_ssl_psk_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

unsigned int ngx_http_lua_ssl_psk_server_handler(ngx_ssl_conn_t *ssl_conn,
    const char *identity, unsigned char *psk, unsigned int max_psk_len);

unsigned int ngx_http_lua_ssl_psk_client_handler(ngx_ssl_conn_t *ssl_conn,
    const char *hint, char *identity, unsigned int max_identity_len,
    unsigned char *psk, unsigned int max_psk_len);

#endif  /* NGX_HTTP_SSL */


#endif /* _NGX_HTTP_LUA_SSL_PSKBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
