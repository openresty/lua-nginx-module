
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_uri.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_set_uri(lua_State *L);
static ngx_int_t ngx_http_lua_check_uri_safe(ngx_http_request_t *r,
    u_char *str, size_t len);


void
ngx_http_lua_inject_req_uri_api(ngx_log_t *log, lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_uri);
    lua_setfield(L, -2, "set_uri");
}


static int
ngx_http_lua_ngx_req_set_uri(lua_State *L)
{
    ngx_http_request_t          *r;
    size_t                       len;
    u_char                      *p;
    int                          n;
    int                          jump = 0;
    ngx_http_lua_ctx_t          *ctx;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments but seen %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_check_fake_request(L, r);

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return luaL_error(L, "attempt to use zero-length uri");
    }

    if (ngx_http_lua_check_uri_safe(r, p, len) != NGX_OK) {
        return luaL_error(L, "attempt to use unsafe uri");
    }

    if (n == 2) {

        luaL_checktype(L, 2, LUA_TBOOLEAN);
        jump = lua_toboolean(L, 2);

        if (jump) {

            ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
            if (ctx == NULL) {
                return luaL_error(L, "no ctx found");
            }

            dd("rewrite: %d, access: %d, content: %d",
               (int) ctx->entered_rewrite_phase,
               (int) ctx->entered_access_phase,
               (int) ctx->entered_content_phase);

            ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE);

            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua set uri jump to \"%*s\"", len, p);

            ngx_http_lua_check_if_abortable(L, ctx);
        }
    }

    r->uri.data = ngx_palloc(r->pool, len);
    if (r->uri.data == NULL) {
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(r->uri.data, p, len);

    r->uri.len = len;

    r->internal = 1;
    r->valid_unparsed_uri = 0;

    ngx_http_set_exten(r);

    if (jump) {
        r->uri_changed = 1;

        return lua_yield(L, 0);
    }

    r->valid_location = 0;
    r->uri_changed = 0;

    return 0;
}


static ngx_inline ngx_int_t
ngx_http_lua_check_uri_safe(ngx_http_request_t *r, u_char *str, size_t len)
{
    size_t           i, buf_len;
    u_char           c;
    u_char          *buf, *src = str;

                     /* %00-%1F, " ", %7F */

    static uint32_t  unsafe[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000001, /* 0000 0000 0000 0000  0000 0000 0000 0001 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000  /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    };

    for (i = 0; i < len; i++, str++) {
        c = *str;
        if (unsafe[c >> 5] & (1 << (c & 0x1f))) {
            buf_len = ngx_http_lua_escape_log(NULL, src, len);
            buf = ngx_palloc(r->pool, buf_len);
            if (buf == NULL) {
                return NGX_ERROR;
            }

            ngx_http_lua_escape_log(buf, src, len);

            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "unsafe byte \"0x%uxd\" in uri \"%*s\"",
                          (unsigned) c, buf_len, buf);

            ngx_pfree(r->pool, buf);

            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
