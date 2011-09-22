#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_output.h"
#include "ngx_http_lua_util.h"
#include <math.h>


static int ngx_http_lua_ngx_say(lua_State *L);
static int ngx_http_lua_ngx_print(lua_State *L);
static int ngx_http_lua_ngx_flush(lua_State *L);
static int ngx_http_lua_ngx_eof(lua_State *L);
static int ngx_http_lua_ngx_send_headers(lua_State *L);
static int ngx_http_lua_ngx_echo(lua_State *L, unsigned newline);
static size_t ngx_http_lua_calc_strlen_in_table(lua_State *L, int arg_i);
static u_char * ngx_http_lua_copy_str_in_table(lua_State *L, u_char *dst);


static int
ngx_http_lua_ngx_print(lua_State *L)
{
    dd("calling lua print");
    return ngx_http_lua_ngx_echo(L, 0);
}


static int
ngx_http_lua_ngx_say(lua_State *L)
{
    dd("calling");
    return ngx_http_lua_ngx_echo(L, 1);
}


static int
ngx_http_lua_ngx_echo(lua_State *L, unsigned newline)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    const char                  *p;
    size_t                       len;
    size_t                       size;
    ngx_buf_t                   *b;
    ngx_chain_t                 *cl;
    ngx_int_t                    rc;
    int                          i;
    int                          nargs;
    int                          type;
    const char                  *msg;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if ((r->method & NGX_HTTP_HEAD) || r->header_only) {
        return 0;
    }

    if (ctx->eof) {
        return luaL_error(L, "seen eof already");
    }

    nargs = lua_gettop(L);
    size = 0;

    for (i = 1; i <= nargs; i++) {
        type = lua_type(L, i);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                lua_tolstring(L, i, &len);
                size += len;
                break;

            case LUA_TNIL:
                size += sizeof("nil") - 1;
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, i)) {
                    size += sizeof("true") - 1;

                } else {
                    size += sizeof("false") - 1;
                }

                break;

            case LUA_TTABLE:
                size += ngx_http_lua_calc_strlen_in_table(L, i);
                break;

            default:
                msg = lua_pushfstring(L, "string, number, boolean, nil, "
                        "or array table expected, got %s",
                        lua_typename(L, type));

                return luaL_argerror(L, i, msg);
        }
    }

    if (newline) {
        size += sizeof("\n") - 1;
    }

    if (size == 0) {
        /* do nothing for empty strings */
        return 0;
    }

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return luaL_error(L, "out of memory");
    }

    for (i = 1; i <= nargs; i++) {
        type = lua_type(L, i);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                p = lua_tolstring(L, i, &len);
                b->last = ngx_copy(b->last, (u_char *) p, len);
                break;

            case LUA_TNIL:
                *b->last++ = 'n';
                *b->last++ = 'i';
                *b->last++ = 'l';
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, i)) {
                    *b->last++ = 't';
                    *b->last++ = 'r';
                    *b->last++ = 'u';
                    *b->last++ = 'e';

                } else {
                    *b->last++ = 'f';
                    *b->last++ = 'a';
                    *b->last++ = 'l';
                    *b->last++ = 's';
                    *b->last++ = 'e';
                }

                break;

            case LUA_TTABLE:
                b->last = ngx_http_lua_copy_str_in_table(L, b->last);
                break;

            default:
                return luaL_error(L, "impossible to reach here");
        }
    }

    if (newline) {
        *b->last++ = '\n';
    }

    if (b->last != b->end) {
        return luaL_error(L, "buffer error: %p != %p", b->last, b->end);
    }

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        return luaL_error(L, "out of memory");
    }

    cl->next = NULL;
    cl->buf = b;

    rc = ngx_http_lua_send_chain_link(r, ctx, cl);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to send data through the output filters");
    }

    return 0;
}


static size_t
ngx_http_lua_calc_strlen_in_table(lua_State *L, int arg_i)
{
    double              key;
    int                 max;
    int                 i;
    int                 type;
    size_t              size;
    size_t              len;
    const char         *msg;

    max = 0;

    lua_pushnil(L); /* stack: table key */
    while (lua_next(L, -2) != 0) { /* stack: table key value */
        if (lua_type(L, -2) == LUA_TNUMBER && (key = lua_tonumber(L, -2))) {
            if (floor(key) == key && key >= 1) {
                if (key > max) {
                    max = key;
                }

                lua_pop(L, 1); /* stack: table key */
                continue;
            }
        }

        /* not an array (non positive integer key) */
        lua_pop(L, 2); /* stack: table */

        msg = lua_pushfstring(L, "on-array table found");
        luaL_argerror(L, arg_i, msg);
        return 0;
    }

    size = 0;

    for (i = 1; i <= max; i++) {
        lua_rawgeti(L, -1, i); /* stack: table value */
        type = lua_type(L, -1);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                lua_tolstring(L, -1, &len);
                size += len;
                break;

            case LUA_TNIL:
                size += sizeof("nil") - 1;
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, -1)) {
                    size += sizeof("true") - 1;

                } else {
                    size += sizeof("false") - 1;
                }

                break;

            case LUA_TTABLE:
                size += ngx_http_lua_calc_strlen_in_table(L, arg_i);
                break;

            default:
                msg = lua_pushfstring(L, "bad data type %s found",
                        lua_typename(L, type));
                luaL_argerror(L, arg_i, msg);
                return 0;
        }

        lua_pop(L, 1); /* stack: table */
    }

    return size;
}


static u_char *
ngx_http_lua_copy_str_in_table(lua_State *L, u_char *dst)
{
    double               key;
    int                  max;
    int                  i;
    int                  type;
    size_t               len;
    u_char              *p;

    max = 0;

    lua_pushnil(L); /* stack: table key */
    while (lua_next(L, -2) != 0) { /* stack: table key value */
        key = lua_tonumber(L, -2);
        if (key > max) {
            max = key;
        }

        lua_pop(L, 1); /* stack: table key */
    }

    for (i = 1; i <= max; i++) {
        lua_rawgeti(L, -1, i); /* stack: table value */
        type = lua_type(L, -1);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                p = (u_char *) lua_tolstring(L, -1, &len);
                dst = ngx_copy(dst, p, len);
                break;

            case LUA_TNIL:
                *dst++ = 'n';
                *dst++ = 'i';
                *dst++ = 'l';
                break;

            case LUA_TBOOLEAN:
                if (lua_toboolean(L, -1)) {
                    *dst++ = 't';
                    *dst++ = 'r';
                    *dst++ = 'u';
                    *dst++ = 'e';

                } else {
                    *dst++ = 'f';
                    *dst++ = 'a';
                    *dst++ = 'l';
                    *dst++ = 's';
                    *dst++ = 'e';
                }

                break;

            case LUA_TTABLE:
                dst = ngx_http_lua_copy_str_in_table(L, dst);
                break;

            default:
                luaL_error(L, "impossible to reach here");
                return NULL;
        }

        lua_pop(L, 1); /* stack: table */
    }

    return dst;
}


/**
 * Force flush out response content
 * */
static int
ngx_http_lua_ngx_flush(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_buf_t                   *buf;
    ngx_chain_t                 *cl;
    ngx_int_t                    rc;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if ((r->method & NGX_HTTP_HEAD) || r->header_only) {
        return 0;
    }

    if (ctx->eof) {
        return luaL_error(L, "already seen eof");
    }

    buf = ngx_calloc_buf(r->pool);
    if (buf == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    buf->flush = 1;

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        return luaL_error(L, "out of memory");
    }

    cl->next = NULL;
    cl->buf = buf;

    rc = ngx_http_lua_send_chain_link(r, ctx, cl);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to send chain link: %d", (int) rc);
    }

    return 0;
}


/**
 * Send last_buf, terminate output stream
 * */
static int
ngx_http_lua_ngx_eof(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_int_t                rc;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 0) {
        return luaL_error(L, "no argument is expected");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    rc = ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to send eof buf");
    }

    return 0;
}


void
ngx_http_lua_inject_output_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_send_headers);
    lua_setfield(L, -2, "send_headers");

    lua_pushcfunction(L, ngx_http_lua_ngx_print);
    lua_setfield(L, -2, "print");

    lua_pushcfunction(L, ngx_http_lua_ngx_say);
    lua_setfield(L, -2, "say");

    lua_pushcfunction(L, ngx_http_lua_ngx_flush);
    lua_setfield(L, -2, "flush");

    lua_pushcfunction(L, ngx_http_lua_ngx_eof);
    lua_setfield(L, -2, "eof");
}


/**
 * Send out headers
 * */
static int
ngx_http_lua_ngx_send_headers(lua_State *L)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r) {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx != NULL && ctx->headers_sent == 0) {
            ngx_http_lua_send_header_if_needed(r, ctx);
        }
    } else {
        dd("(lua-ngx-send-headers) can't find nginx request object!");
    }

    return 0;
}

