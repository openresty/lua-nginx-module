#ifndef NGX_HTTP_LUA_DIRECTIVE_H__
#define NGX_HTTP_LUA_DIRECTIVE_H__

#include "ngx_http_lua_common.h"


extern char* ngx_http_lua_set_by_lua(
        ngx_conf_t *cf,
        ngx_command_t *cmd,
        void *conf
        );

extern ngx_int_t ngx_http_lua_filter_set_by_lua_inline(
        ngx_http_request_t *r,
        ngx_str_t *val,
        ngx_http_variable_value_t *v,
        void *data
        );
extern ngx_int_t ngx_http_lua_filter_set_by_lua_file(
        ngx_http_request_t *r,
        ngx_str_t *val,
        ngx_http_variable_value_t *v,
        void *data
        );

extern ngx_int_t ngx_http_lua_init_vm(ngx_conf_t *cf);

#endif

