#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"

#define NGX_UNESCAPE_URI_COMPONENT  0


static ngx_int_t ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr);
static ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc);
static int ngx_http_lua_ngx_echo(lua_State *L, ngx_flag_t newline);
static void ngx_unescape_uri_patched(u_char **dst, u_char **src,
        size_t size, ngx_uint_t type);
uintptr_t ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src,
        size_t size);


/*  longjmp mark for restoring nginx execution after Lua VM crashing */
jmp_buf ngx_http_lua_exception;

/**
 * Override default Lua panic handler, output VM crash reason to NginX error
 * log, and restore execution to the nearest jmp-mark.
 * 
 * @param L Lua state pointer
 * @retval Long jump to the nearest jmp-mark, never returns.
 * @note NginX request pointer should be stored in Lua thread's globals table
 * in order to make logging working.
 * */
int
ngx_http_lua_atpanic(lua_State *L)
{
    const char *s = luaL_checkstring(L, 1);
    ngx_http_request_t *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /*  log Lua VM crashing reason to error log */
    if(r && r->connection && r->connection->log) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-atpanic) Lua VM crashed, reason: %s", s);
    } else {
        dd("(lua-atpanic) can't output Lua VM crashing reason to error log"
                " due to invalid logging context: %s", s);
    }

    /*  restore nginx execution */
	NGX_LUA_EXCEPTION_THROW(1);
}

/**
 * Override Lua print function, output message to NginX error logs.
 *
 * @param L Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * @note NginX request pointer should be stored in Lua VM registry with key
 * 'ngx._req' in order to make logging working.
 * */
int
ngx_http_lua_print(lua_State *L)
{
    ngx_http_request_t *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if(r && r->connection && r->connection->log) {
        const char *s;

        /*  XXX: easy way to support multiple args, any serious performance penalties? */
        lua_concat(L, lua_gettop(L));
        s = lua_tostring(L, -1);

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-print) %s", (s == NULL) ? "(null)" : s);
    } else {
        dd("(lua-print) can't output print content to error log due to invalid logging context!");
    }

    return 0;
}

/**
 * Send out headers
 * */
int
ngx_http_lua_ngx_send_headers(lua_State *L)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if(r) {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if(ctx != NULL && ctx->headers_sent == 0) {
            ngx_http_lua_send_header_if_needed(r, ctx);
        }
    } else {
        dd("(lua-ngx-send-headers) can't find nginx request object!");
    }

    return 0;
}


int
ngx_http_lua_ngx_print(lua_State *L)
{
    return ngx_http_lua_ngx_echo(L, 0);
}


int
ngx_http_lua_ngx_say(lua_State *L)
{
    return ngx_http_lua_ngx_echo(L, 1);
}


static int
ngx_http_lua_ngx_echo(lua_State *L, ngx_flag_t newline)
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

    if (ctx->eof) {
        return luaL_error(L, "seen eof already");
    }

    nargs = lua_gettop(L);
    size = 0;

    for (i = 1; i <= nargs; i++) {
        luaL_checkstring(L, i);
        lua_tolstring(L, i, &len);
        size += len;
    }

    if (newline) {
        size += sizeof("\n") - 1;
    }

    b = ngx_create_temp_buf(r->pool, size);
    if (b == NULL) {
        return luaL_error(L, "memory error");
    }

    for (i = 1; i <= nargs; i++) {
        p = lua_tolstring(L, i, &len);
        b->last = ngx_copy(b->last, p, len);
    }

    if (newline) {
        *b->last++ = '\n';
    }

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        return luaL_error(L, "memory error");
    }

    cl->next = NULL;
    cl->buf = b;

    rc = ngx_http_lua_send_chain_link(r, ctx, cl);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to send data through the output filters");
    }

    lua_settop(L, 0);

    return 0;
}


int
ngx_http_lua_ngx_throw_error(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

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

    if (ctx->headers_sent) {
        ctx->error_rc = NGX_ERROR;

        lua_pushnil(L);
        return lua_error(L);
    }

    ctx->error_rc = (ngx_int_t) luaL_checkinteger(L, 1);

    lua_pushnil(L);
    return lua_error(L);
}


/**
 * Force flush out response content
 * */
int
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

    if (ctx->eof == 0) {
        return luaL_error(L, "already seen eof");
    }

    buf = ngx_calloc_buf(r->pool);
    if (buf == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    buf->flush = 1;

    cl = ngx_alloc_chain_link(r->pool);
    if (cl == NULL) {
        return luaL_error(L, "memory allocation error");
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
int
ngx_http_lua_ngx_eof(lua_State *L)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;

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
    if (ctx != NULL && ctx->eof == 0) {
        ctx->eof = 1;    /*  set eof flag to prevent further output */
        ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
    }

    return 0;
}


int
ngx_http_lua_ngx_location_capture(lua_State *L)
{
    ngx_http_request_t              *r;
    ngx_http_request_t              *sr; /* subrequest object */
    ngx_http_post_subrequest_t      *psr;
    ngx_http_lua_ctx_t              *sr_ctx;
    ngx_str_t                        uri, args;
    ngx_uint_t                       flags = 0;
    const char                      *p;
    size_t                           len;
    int                              rc;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    p = luaL_checklstring(L, 1, &len);

    uri.data = ngx_palloc(r->pool, len);
    if (uri.data == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    uri.len = len;
    ngx_memcpy(uri.data, p, len);

    args.data = NULL;
    args.len = 0;

    if (ngx_http_parse_unsafe_uri(r, &uri, &args, &flags) != NGX_OK) {
        return luaL_argerror(L, 1, "unsafe URL");
    }

    psr = ngx_palloc(r->pool, sizeof(ngx_http_post_subrequest_t));
    if (psr == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    sr_ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
    if(sr_ctx == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    sr_ctx->capture = 1;

    psr->handler = ngx_http_lua_post_subrequest;
    psr->data = sr_ctx;

    rc = ngx_http_subrequest(r, &uri, &args, &sr, psr, 0);

    if (rc != NGX_OK) {
        return luaL_error(L, "failed to issue subrequest: %d", (int) rc);
    }

    ngx_http_set_ctx(sr, sr_ctx, ngx_http_lua_module);

    rc = ngx_http_lua_adjust_subrequest(sr);

    if (rc != NGX_OK) {
        return luaL_error(L, "failed to adjust the subrequest: %d", (int) rc);
    }

    lua_pushinteger(L, location_capture);

    return lua_yield(L, 1);
}


static ngx_int_t
ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr)
{
    ngx_http_core_main_conf_t   *cmcf;
    ngx_http_request_t          *r;

    /* we do not inherit the parent request's variables */
    cmcf = ngx_http_get_module_main_conf(sr, ngx_http_core_module);

    r = sr->parent;

    sr->header_in = r->header_in;

    /* XXX work-around a bug in ngx_http_subrequest */
    if (r->headers_in.headers.last == &r->headers_in.headers.part) {
        sr->headers_in.headers.last = &sr->headers_in.headers.part;
    }

#if 0
    sr->variables = ngx_pcalloc(sr->pool, cmcf->variables.nelts
                                        * sizeof(ngx_http_variable_value_t));
#endif

    sr->variables = r->variables;
    if (sr->variables == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc)
{
    ngx_http_request_t            *pr;
    ngx_http_lua_ctx_t            *pr_ctx;
    ngx_http_lua_ctx_t            *ctx = data;

    pr = r->parent;

    pr_ctx = ngx_http_get_module_ctx(pr, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    pr_ctx->waiting = 0;
    pr_ctx->done = 1;

    pr->write_event_handler = ngx_http_lua_wev_handler;

    /*  capture subrequest response status */
    if(rc == NGX_ERROR) {
        pr_ctx->sr_status = NGX_HTTP_INTERNAL_SERVER_ERROR;
    } else if(rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        pr_ctx->sr_status = rc;
    } else {
        pr_ctx->sr_status = r->headers_out.status;
    }

    /*  copy subrequest response body */
    pr_ctx->sr_body = ctx->body;

    /* ensure that the parent request is (or will be)
     *  posted out the head of the r->posted_requests chain */

    if (r->main->posted_requests
            && r->main->posted_requests->request != pr)
    {
        rc = ngx_http_lua_post_request_at_head(pr, NULL);
        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return rc;
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

    escape = 2 * ngx_escape_uri(NULL, src, len, NGX_ESCAPE_URI);

    dlen = escape + len;

    dst = ngx_palloc(r->pool, dlen);
    if (dst == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    if (escape == 0) {
        ngx_memcpy(dst, src, len);

    } else {
        ngx_escape_uri(dst, src, len, NGX_ESCAPE_URI);
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

    ngx_unescape_uri_patched(&dst, &src, len, NGX_UNESCAPE_URI_COMPONENT);

    lua_pushlstring(L, (char *) p, dst - p);

    return 1;
}


/* XXX we also decode '+' to ' ' */
static void
ngx_unescape_uri_patched(u_char **dst, u_char **src, size_t size,
        ngx_uint_t type)
{
    u_char  *d, *s, ch, c, decoded;
    enum {
        sw_usual = 0,
        sw_quoted,
        sw_quoted_second
    } state;

    d = *dst;
    s = *src;

    state = 0;
    decoded = 0;

    while (size--) {

        ch = *s++;

        switch (state) {
        case sw_usual:
            if (ch == '?'
                && (type & (NGX_UNESCAPE_URI|NGX_UNESCAPE_REDIRECT)))
            {
                *d++ = ch;
                goto done;
            }

            if (ch == '%') {
                state = sw_quoted;
                break;
            }

            if (ch == '+') {
                *d++ = ' ';
                break;
            }

            *d++ = ch;
            break;

        case sw_quoted:

            if (ch >= '0' && ch <= '9') {
                decoded = (u_char) (ch - '0');
                state = sw_quoted_second;
                break;
            }

            c = (u_char) (ch | 0x20);
            if (c >= 'a' && c <= 'f') {
                decoded = (u_char) (c - 'a' + 10);
                state = sw_quoted_second;
                break;
            }

            /* the invalid quoted character */

            state = sw_usual;

            *d++ = ch;

            break;

        case sw_quoted_second:

            state = sw_usual;

            if (ch >= '0' && ch <= '9') {
                ch = (u_char) ((decoded << 4) + ch - '0');

                if (type & NGX_UNESCAPE_REDIRECT) {
                    if (ch > '%' && ch < 0x7f) {
                        *d++ = ch;
                        break;
                    }

                    *d++ = '%'; *d++ = *(s - 2); *d++ = *(s - 1);

                    break;
                }

                *d++ = ch;

                break;
            }

            c = (u_char) (ch | 0x20);
            if (c >= 'a' && c <= 'f') {
                ch = (u_char) ((decoded << 4) + c - 'a' + 10);

                if (type & NGX_UNESCAPE_URI) {
                    if (ch == '?') {
                        *d++ = ch;
                        goto done;
                    }

                    *d++ = ch;
                    break;
                }

                if (type & NGX_UNESCAPE_REDIRECT) {
                    if (ch == '?') {
                        *d++ = ch;
                        goto done;
                    }

                    if (ch > '%' && ch < 0x7f) {
                        *d++ = ch;
                        break;
                    }

                    *d++ = '%'; *d++ = *(s - 2); *d++ = *(s - 1);
                    break;
                }

                *d++ = ch;

                break;
            }

            /* the invalid quoted character */

            break;
        }
    }

done:

    *dst = d;
    *src = s;
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

    escape = ngx_http_lua_ngx_escape_sql_str(NULL, src, len);

    dlen = len + escape;

    p = ngx_palloc(r->pool, dlen);
    if (p == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    dst = p;

    if (escape == 0) {
        p = ngx_copy(p, src, len);
    } else {
        p = (u_char *) ngx_http_lua_ngx_escape_sql_str(p, src, len);
    }

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
