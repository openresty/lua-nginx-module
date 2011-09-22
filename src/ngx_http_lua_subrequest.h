#ifndef NGX_HTTP_LUA_SUBREQUEST_H
#define NGX_HTTP_LUA_SUBREQUEST_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_location_capture(lua_State *L);
int ngx_http_lua_ngx_location_capture_multi(lua_State *L);
ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r,
        void *data, ngx_int_t rc);
void ngx_http_lua_handle_subreq_responses(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx);


#endif /* NGX_HTTP_LUA_SUBREQUEST_H */

