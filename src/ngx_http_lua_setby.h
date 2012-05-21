/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_SET_BY_H
#define NGX_HTTP_LUA_SET_BY_H

#include "ngx_http_lua_common.h"


#if !(defined(NDK) && NDK)
typedef struct {
    void           *func;
    size_t          size;
    void           *data;
} ngx_http_lua_var_filter_t;


char *ngx_http_lua_set_multi_var(ngx_conf_t *cf, ngx_str_t *name,
        ngx_str_t *value, ngx_http_lua_var_filter_t *filter);


extern ngx_module_t   ngx_http_rewrite_module;
#endif


typedef struct {
    size_t       size;
    u_char      *key;
    ngx_str_t    value;
} ngx_http_lua_set_var_data_t;


ngx_int_t ngx_http_lua_set_by_chunk(lua_State *L, ngx_http_request_t *r,
        ngx_str_t *val, ngx_http_variable_value_t *args, size_t nargs);

#endif /* NGX_HTTP_LUA_SET_BY_H */

