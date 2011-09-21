/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif

#include <nginx.h>
#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ctx.h"


jmp_buf ngx_http_lua_exception;

static uintptr_t ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src,
        size_t size);

/*  longjmp mark for restoring nginx execution after Lua VM crashing */
jmp_buf ngx_http_lua_exception;

/**
 * Override default Lua panic handler, output VM crash reason to nginx error
 * log, and restore execution to the nearest jmp-mark.
 * 
 * @param L Lua state pointer
 * @retval Long jump to the nearest jmp-mark, never returns.
 * @note nginx request pointer should be stored in Lua thread's globals table
 * in order to make logging working.
 * */
int
ngx_http_lua_atpanic(lua_State *L)
{
    const char              *s;
    ngx_http_request_t      *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /*  log Lua VM crashing reason to error log */
    if (r && r->connection && r->connection->log) {
        s = luaL_checkstring(L, 1);
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "(lua-atpanic) Lua VM crashed, reason: %s", s);

    } else {
        dd("(lua-atpanic) can't output Lua VM crashing reason to error log"
                " due to invalid logging context");
    }

    /*  restore nginx execution */
    NGX_LUA_EXCEPTION_THROW(1);

    /* cannot reach here, just to suppress a potential gcc warning */
    return 0;
}


int
ngx_http_lua_ngx_escape_uri(lua_State *L)
{
    ngx_http_request_t      *r;
    size_t                   len, dlen;
    uintptr_t                escape;
    u_char                  *src, *dst;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        lua_pushlstring(L, NULL, 0);
        return 1;
    }

    escape = 2 * ngx_http_lua_escape_uri(NULL, src, len, NGX_ESCAPE_URI);

    dlen = escape + len;

    dst = ngx_palloc(r->pool, dlen);
    if (dst == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    if (escape == 0) {
        ngx_memcpy(dst, src, len);

    } else {
        ngx_http_lua_escape_uri(dst, src, len, NGX_ESCAPE_URI);
    }

    lua_pushlstring(L, (char *) dst, dlen);

    return 1;
}


int
ngx_http_lua_ngx_unescape_uri(lua_State *L)
{
    ngx_http_request_t      *r;
    size_t                   len, dlen;
    u_char                  *p;
    u_char                  *src, *dst;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    /* the unescaped string can only be smaller */
    dlen = len;

    p = ngx_palloc(r->pool, dlen);
    if (p == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    dst = p;

    ngx_http_lua_unescape_uri(&dst, &src, len, NGX_UNESCAPE_URI_COMPONENT);

    lua_pushlstring(L, (char *) p, dst - p);

    return 1;
}


int
ngx_http_lua_ngx_quote_sql_str(lua_State *L)
{
    ngx_http_request_t      *r;
    size_t                   len, dlen, escape;
    u_char                  *p;
    u_char                  *src, *dst;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        dst = (u_char *) "''";
        dlen = sizeof("''") - 1;
        lua_pushlstring(L, (char *) dst, dlen);
        return 1;
    }

    escape = ngx_http_lua_ngx_escape_sql_str(NULL, src, len);

    dlen = sizeof("''") - 1 + len + escape;

    p = ngx_palloc(r->pool, dlen);
    if (p == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    dst = p;

    *p++ = '\'';

    if (escape == 0) {
        p = ngx_copy(p, src, len);
    } else {
        p = (u_char *) ngx_http_lua_ngx_escape_sql_str(p, src, len);
    }

    *p++ = '\'';

    if (p != dst + dlen) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "ngx.quote_sql_str: buffer error");
        return NGX_ERROR;
    }

    lua_pushlstring(L, (char *) dst, p - dst);

    return 1;
}


uintptr_t
ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src,
        size_t size)
{
    ngx_uint_t               n;

    if (dst == NULL) {
        /* find the number of chars to be escaped */
        n = 0;
        while (size) {
            /* the highest bit of all the UTF-8 chars
             * is always 1 */
            if ((*src & 0x80) == 0) {
                switch (*src) {
                    case '\r':
                    case '\n':
                    case '\\':
                    case '\'':
                    case '"':
                    case '\032':
                        n++;
                        break;
                    default:
                        break;
                }
            }
            src++;
            size--;
        }

        return (uintptr_t) n;
    }

    while (size) {
        if ((*src & 0x80) == 0) {
            switch (*src) {
                case '\r':
                    *dst++ = '\\';
                    *dst++ = 'r';
                    break;

                case '\n':
                    *dst++ = '\\';
                    *dst++ = 'n';
                    break;

                case '\\':
                    *dst++ = '\\';
                    *dst++ = '\\';
                    break;

                case '\'':
                    *dst++ = '\\';
                    *dst++ = '\'';
                    break;

                case '"':
                    *dst++ = '\\';
                    *dst++ = '"';
                    break;

                case '\032':
                    *dst++ = '\\';
                    *dst++ = *src;
                    break;

                default:
                    *dst++ = *src;
                    break;
            }
        } else {
            *dst++ = *src;
        }
        src++;
        size--;
    } /* while (size) */

    return (uintptr_t) dst;
}


int
ngx_http_lua_ngx_md5(lua_State *L)
{
    ngx_http_request_t      *r;
    u_char                  *src;
    size_t                   slen;

    ngx_md5_t                md5;
    u_char                   md5_buf[MD5_DIGEST_LENGTH];
    u_char                   hex_buf[2 * sizeof(md5_buf)];

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (strcmp(luaL_typename(L, 1), (char *) "nil") == 0) {
        src     = (u_char *) "";
        slen    = 0;

    } else {
        src = (u_char *) luaL_checklstring(L, 1, &slen);
    }

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, slen);
    ngx_md5_final(md5_buf, &md5);

    ngx_hex_dump(hex_buf, md5_buf, sizeof(md5_buf));

    lua_pushlstring(L, (char *) hex_buf, sizeof(hex_buf));

    return 1;
}


int
ngx_http_lua_ngx_md5_bin(lua_State *L)
{
    ngx_http_request_t      *r;
    u_char                  *src;
    size_t                   slen;

    ngx_md5_t                md5;
    u_char                   md5_buf[MD5_DIGEST_LENGTH];

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (strcmp(luaL_typename(L, 1), (char *) "nil") == 0) {
        src     = (u_char *) "";
        slen    = 0;

    } else {
        src = (u_char *) luaL_checklstring(L, 1, &slen);
    }

    dd("slen: %d", (int) slen);

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, slen);
    ngx_md5_final(md5_buf, &md5);

    lua_pushlstring(L, (char *) md5_buf, sizeof(md5_buf));

    return 1;
}


int
ngx_http_lua_ngx_decode_base64(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_str_t                p, src;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (strcmp(luaL_typename(L, 1), (char *) "nil") == 0) {
        src.data     = (u_char *) "";
        src.len      = 0;
    } else {
        src.data = (u_char *) luaL_checklstring(L, 1, &src.len);
    }

    p.len = ngx_base64_decoded_length(src.len);

    p.data = ngx_palloc(r->pool, p.len);
    if (p.data == NULL) {
        return NGX_ERROR;
    }

    if (ngx_decode_base64(&p, &src) == NGX_OK) {
        lua_pushlstring(L, (char *) p.data, p.len);
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
            "lua decode ok");
    } else {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
            "lua sent invalid base64 encoding");
        lua_pushnil(L);
    }

    ngx_pfree(r->pool, p.data);

    return 1;
}


int
ngx_http_lua_ngx_encode_base64(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_str_t                p, src;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (strcmp(luaL_typename(L, 1), (char *) "nil") == 0) {
        src.data     = (u_char *) "";
        src.len      = 0;
    } else {
        src.data = (u_char *) luaL_checklstring(L, 1, &src.len);
    }

    p.len = ngx_base64_encoded_length(src.len);

    p.data = ngx_palloc(r->pool, p.len);
    if (p.data == NULL) {
        return NGX_ERROR;
    }

    ngx_encode_base64(&p, &src);

    lua_pushlstring(L, (char *) p.data, p.len);

    ngx_pfree(r->pool, p.data);

    return 1;
}


int
ngx_http_lua_ngx_get(lua_State *L) {
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;

    p = (u_char *) luaL_checklstring(L, -1, &len);

    if (len == sizeof("status") - 1 &&
            ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
        r = lua_touserdata(L, -1);
        lua_pop(L, 1);

        if (r == NULL) {
            return luaL_error(L, "no request object found");
        }

        lua_pushnumber(L, (lua_Number) r->headers_out.status);
        return 1;
    }

    if (len == sizeof("ctx") - 1 &&
            ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        return ngx_http_lua_ngx_get_ctx(L);
    }

    if (len == sizeof("is_subrequest") - 1 &&
            ngx_strncmp(p, "is_subrequest", sizeof("is_subrequest") - 1) == 0)
    {
        lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
        r = lua_touserdata(L, -1);
        lua_pop(L, 1);

        if (r == NULL) {
            return luaL_error(L, "no request object found");
        }

        lua_pushboolean(L, r != r->main);
        return 1;
    }

    dd("key %s not matched", p);

    lua_pushnil(L);
    return 1;
}


int
ngx_http_lua_ngx_set(lua_State *L) {
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    if (len == sizeof("status") - 1 &&
            ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
        r = lua_touserdata(L, -1);
        lua_pop(L, 1);

        if (r == NULL) {
            return luaL_error(L, "no request object found");
        }

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx->headers_sent) {
            return luaL_error(L, "attempt to set ngx.status after "
                    "sending out response headers");
        }

        /* get the value */
        r->headers_out.status = (ngx_uint_t) luaL_checknumber(L, 3);
        return 0;
    }

    if (len == sizeof("ctx") - 1 &&
            ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        return ngx_http_lua_ngx_set_ctx(L);
    }

    return luaL_error(L, "Attempt to write to ngx. with the key \"%s\"", p);
}

