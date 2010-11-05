#ifndef NGX_HTTP_LUA_HEADERS_H
#define NGX_HTTP_LUA_HEADERS_H


#include <ngx_core.h>
#include <ngx_http.h>

typedef struct ngx_http_lua_header_val_s ngx_http_lua_header_val_t;

typedef ngx_int_t (*ngx_http_lua_set_header_pt)(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);

struct ngx_http_lua_header_val_s {
    ngx_http_complex_value_t                value;
    ngx_uint_t                              hash;
    ngx_str_t                               key;
    ngx_http_lua_set_header_pt              handler;
    ngx_uint_t                              offset;
    ngx_flag_t                              no_override;
};

typedef struct {
    ngx_str_t                               name;
    ngx_uint_t                              offset;
    ngx_http_lua_set_header_pt     handler;

} ngx_http_lua_set_header_t;


ngx_int_t ngx_http_lua_set_header(ngx_http_request_t *r, ngx_str_t key,
        ngx_str_t value, ngx_flag_t override);


#endif

