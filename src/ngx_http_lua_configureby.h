
/*
 * Copyright (C) Yichun Zhang (agentzh)
 *
 * Author: Thibault Charbonnier (thibaultcha)
 * I hereby assign copyright in this code to the lua-nginx-module project,
 * to be licensed under the same terms as the rest of the code.
 */


#ifndef _NGX_HTTP_LUA_CONFIGUREBY_H_INCLUDED_
#define _NGX_HTTP_LUA_CONFIGUREBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


char *ngx_http_lua_configure_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_configure_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

ngx_int_t ngx_http_lua_configure_handler_inline(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);

ngx_int_t ngx_http_lua_configure_handler_file(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);

ngx_uint_t ngx_http_lua_is_configure_phase();


#endif /* _NGX_HTTP_LUA_CONFIGUREBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
