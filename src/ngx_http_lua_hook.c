/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#define DDEBUG 0

#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_headers.h"

#define NGX_UNESCAPE_URI_COMPONENT  0

#ifndef ngx_str_set
#define ngx_str_set(str, text)                                               \
    (str)->len = sizeof(text) - 1; (str)->data = (u_char *) text
#endif


#define ngx_http_lua_method_name(m) { sizeof(m) - 1, (u_char *) m " " }

static ngx_str_t  ngx_http_lua_get_method = ngx_http_lua_method_name("GET");
static ngx_str_t  ngx_http_lua_put_method = ngx_http_lua_method_name("PUT");
static ngx_str_t  ngx_http_lua_post_method = ngx_http_lua_method_name("POST");
static ngx_str_t  ngx_http_lua_head_method = ngx_http_lua_method_name("HEAD");
static ngx_str_t  ngx_http_lua_delete_method =
        ngx_http_lua_method_name("DELETE");


static ngx_str_t  ngx_http_lua_content_length_header_key =
        ngx_string("Content-Length");


static void ngx_http_lua_process_args_option(ngx_http_request_t *r,
        lua_State *L, int table, ngx_str_t *args);
static ngx_int_t ngx_http_lua_set_content_length_header(ngx_http_request_t *r,
        size_t len);
static ngx_int_t ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr,
        ngx_uint_t method, ngx_http_request_body_t *body,
        ngx_flag_t share_all_vars);
static ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r,
        void *data, ngx_int_t rc);
static int ngx_http_lua_ngx_echo(lua_State *L, ngx_flag_t newline);
static void ngx_http_lua_unescape_uri(u_char **dst, u_char **src, size_t size,
        ngx_uint_t type);
static uintptr_t ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src,
        size_t size);
static void log_wrapper(ngx_http_request_t *r, const char *ident, int level,
        lua_State *L);
static uintptr_t ngx_http_lua_escape_uri(u_char *dst, u_char *src,
        size_t size, ngx_uint_t type);
static ndk_set_var_value_pt ngx_http_lookup_ndk_set_var_directive(u_char *name,
        size_t name_len);


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
    if (r && r->connection && r->connection->log) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "(lua-atpanic) Lua VM crashed, reason: %s", s);

    } else {
        dd("(lua-atpanic) can't output Lua VM crashing reason to error log"
                " due to invalid logging context: %s", s);
    }

    /*  restore nginx execution */
    NGX_LUA_EXCEPTION_THROW(1);
}


static void
log_wrapper(ngx_http_request_t *r, const char *ident, int level, lua_State *L)
{
    u_char              *buf;
    u_char              *p;
    u_char              *q;
    int                  nargs, i;
    size_t               size, len;

    nargs = lua_gettop(L);
    if (nargs == 0) {
        buf = NULL;
        goto done;
    }

    size = 0;

    for (i = 1; i <= nargs; i++) {
        if (lua_type(L, i) == LUA_TNIL) {
            size += sizeof("nil") - 1;
        } else {
            luaL_checkstring(L, i);
            lua_tolstring(L, i, &len);
            size += len;
        }
    }

    buf = ngx_palloc(r->pool, size + 1);
    if (buf == NULL) {
        luaL_error(L, "out of memory");
        return;
    }

    p = buf;
    for (i = 1; i <= nargs; i++) {
        if (lua_type(L, i) == LUA_TNIL) {
            *p++ = 'n';
            *p++ = 'i';
            *p++ = 'l';
        } else {
            q = (u_char *) lua_tolstring(L, i, &len);
            p = ngx_copy(p, q, len);
        }
    }

    *p++ = '\0';

done:
    ngx_log_error((ngx_uint_t) level, r->connection->log, 0,
            "%s%s", ident, (buf == NULL) ? (u_char *) "(null)" : buf);
}


/**
 * Wrapper of NginX log functionality. Take a log level param and varargs of
 * log message params.
 *
 * @param L Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * */
int
ngx_http_lua_ngx_log(lua_State *L)
{
    ngx_http_request_t *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r && r->connection && r->connection->log) {
        int level = luaL_checkint(L, 1);

        /* remove log-level param from stack */
        lua_remove(L, 1);

        log_wrapper(r, "", level, L);
    } else {
        dd("(lua-log) can't output log due to invalid logging context!");
    }

    return 0;
}


/**
 * Override Lua print function, output message to NginX error logs. Equal to
 * ngx.log(ngx.ERR, ...).
 *
 * @param L Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * */
int
ngx_http_lua_print(lua_State *L)
{
    ngx_http_request_t *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r && r->connection && r->connection->log) {
        log_wrapper(r, "lua print: ", NGX_LOG_NOTICE, L);

    } else {
        dd("(lua-print) can't output print content to error log due "
                "to invalid logging context!");
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


int
ngx_http_lua_ngx_print(lua_State *L)
{
    dd("calling lua print");
    return ngx_http_lua_ngx_echo(L, 0);
}


int
ngx_http_lua_ngx_say(lua_State *L)
{
    dd("calling");
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
        return luaL_error(L, "out of memory");
    }

    for (i = 1; i <= nargs; i++) {
        p = lua_tolstring(L, i, &len);
        b->last = ngx_copy(b->last, (u_char*)p, len);
    }

    if (newline) {
        *b->last++ = '\n';
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

    lua_settop(L, 0);

    return 0;
}


int
ngx_http_lua_ngx_exit(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;

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

    rc = (ngx_int_t) luaL_checkinteger(L, 1);

    if (rc >= 200 && ctx->headers_sent) {
        return luaL_error(L, "attempt to call ngx.exit after sending "
                "out the headers");
    }

    ctx->exit_code = rc;
    ctx->exited = 1;

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
int
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


/* ngx.location.capture is just a thin wrapper around
 * ngx.location.capture_multi */
int
ngx_http_lua_ngx_location_capture(lua_State *L)
{
    int                 n;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments");
    }

    lua_createtable(L, n, 0); /* uri opts? table  */
    lua_insert(L, 1); /* table uri opts? */
    if (n == 1) { /* table uri */
        lua_rawseti(L, 1, 1); /* table */

    } else { /* table uri opts */
        lua_rawseti(L, 1, 2); /* table uri */
        lua_rawseti(L, 1, 1); /* table */
    }

    lua_createtable(L, 1, 0); /* table table' */
    lua_insert(L, 1);   /* table' table */
    lua_rawseti(L, 1, 1); /* table' */

    return ngx_http_lua_ngx_location_capture_multi(L);
}


int
ngx_http_lua_ngx_location_capture_multi(lua_State *L)
{
    ngx_http_request_t              *r;
    ngx_http_request_t              *sr; /* subrequest object */
    ngx_http_post_subrequest_t      *psr;
    ngx_http_lua_ctx_t              *sr_ctx;
    ngx_http_lua_ctx_t              *ctx;
    ngx_str_t                        uri;
    ngx_str_t                        args;
    ngx_str_t                        extra_args;
    ngx_uint_t                       flags;
    u_char                          *p;
    u_char                          *q;
    size_t                           len;
    size_t                           nargs;
    int                              rc;
    int                              n;
    ngx_uint_t                       method;
    ngx_http_request_body_t         *body;
    int                              type;
    ngx_buf_t                       *b;
    ngx_flag_t                       share_all_vars;
    ngx_uint_t                       nsubreqs;
    ngx_uint_t                       index;
    size_t                           waitings_len;
    size_t                           sr_statuses_len;
    size_t                           sr_headers_len;
    size_t                           sr_bodies_len;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "only one argument is expected, but got %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    nsubreqs = lua_objlen(L, 1);
    if (nsubreqs == 0) {
        return luaL_error(L, "at least one subrequest should be specified");
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    waitings_len    = nsubreqs * sizeof(unsigned);
    sr_statuses_len = nsubreqs * sizeof(ngx_int_t);
    sr_headers_len  = nsubreqs * sizeof(ngx_http_headers_out_t*);
    sr_bodies_len   = nsubreqs * sizeof(ngx_chain_t *);

    p = ngx_palloc(r->pool, waitings_len + sr_statuses_len + sr_headers_len +
            sr_bodies_len);

    if (p == NULL) {
        return luaL_error(L, "out of memory");
    }

    ctx->waitings = (void *) p;
    p += waitings_len;

    ctx->sr_statuses = (void *) p;
    p += sr_statuses_len;

    ctx->sr_headers = (void *) p;
    p += sr_headers_len;

    ctx->sr_bodies = (void *) p;

    ctx->nsubreqs = nsubreqs;

    n = lua_gettop(L);
    dd("top before loop: %d", n);

    for (index = 0; index < nsubreqs; index++) {
        ctx->waitings[index] = 1;

        lua_rawgeti(L, 1, index + 1);
        if (lua_isnil(L, -1)) {
            return luaL_error(L, "only array-like tables are allowed");
        }

        if (lua_type(L, -1) != LUA_TTABLE) {
            return luaL_error(L, "the query argument %d is not a table, "
                    "but a %s",
                    index, lua_typename(L, lua_type(L, -1)));
        }

        dd("lua top so far: %d", lua_gettop(L));

        nargs = lua_objlen(L, -1);

        if (nargs != 1 && nargs != 2) {
            return luaL_error(L, "query argument %d expecting one or "
                    "two arguments", index);
        }

        lua_rawgeti(L, 2, 1); /* queries query uri */

        dd("first arg in first query: %s", lua_typename(L, lua_type(L, -1)));

        body = NULL;

        extra_args.data = NULL;
        extra_args.len = 0;

        share_all_vars = 0;

        if (nargs == 2) {
            /* check out the options table */

            lua_rawgeti(L, 2, 2);

            if (lua_type(L, 4) != LUA_TTABLE) {
                return luaL_error(L, "expecting table as the 2nd argument for "
                        "subrequest %d", index);
            }

            /* check the args option */

            lua_getfield(L, 4, "args");

            type = lua_type(L, -1);

            switch (type) {
            case LUA_TTABLE:
                ngx_http_lua_process_args_option(r, L, -1, &extra_args);
                break;

            case LUA_TNIL:
                /* do nothing */
                break;

            case LUA_TNUMBER:
            case LUA_TSTRING:
                extra_args.data = (u_char *) lua_tolstring(L, -1, &len);
                extra_args.len = len;

                break;

            default:
                return luaL_error(L, "Bad args option value");
            }

            lua_pop(L, 1);

            /* check the share_all_vars option */

            lua_getfield(L, 4, "share_all_vars");

            type = lua_type(L, -1);
            if (type == LUA_TNIL) {
                /* do nothing */
            } else {
                if (type != LUA_TBOOLEAN) {
                    return luaL_error(L, "Bad share_all_vars option value");
                }

                share_all_vars = lua_toboolean(L, -1);
            }

            lua_pop(L, 1);

            /* check the method option */

            lua_getfield(L, 4, "method");

            type = lua_type(L, -1);
            if (type == LUA_TNIL) {
                method = NGX_HTTP_GET;
            } else {
                if (type != LUA_TNUMBER) {
                    return luaL_error(L, "Bad http request method");
                }

                method = (ngx_uint_t) lua_tonumber(L, -1);
            }

            lua_pop(L, 1);

            /* check the body option */

            lua_getfield(L, 4, "body");

            if (type != LUA_TNIL) {
                if (type != LUA_TSTRING && type != LUA_TNUMBER) {
                    return luaL_error(L, "Bad http request body");
                }

                q = (u_char *) lua_tolstring(L, -1, &len);
                if (len != 0) {
                    body = ngx_pcalloc(r->pool,
                            sizeof(ngx_http_request_body_t));
                    if (body == NULL) {
                        return luaL_error(L, "out of memory");
                    }

                    b = ngx_create_temp_buf(r->pool, len);
                    if (b == NULL) {
                        return luaL_error(L, "out of memory");
                    }

                    b->last = ngx_copy(b->last, q, len);

                    body->bufs = ngx_alloc_chain_link(r->pool);
                    if (body->bufs == NULL) {
                        return luaL_error(L, "out of memory");
                    }

                    body->bufs->buf = b;
                    body->bufs->next = NULL;

                    body->buf = b;
                }
            }

            lua_pop(L, 2); /* pop body and opts table */
        } else {
            method = NGX_HTTP_GET;
        }

        n = lua_gettop(L);
        dd("top size so far: %d", n);

        p = (u_char *) luaL_checklstring(L, 3, &len);

        uri.data = ngx_palloc(r->pool, len);
        if (uri.data == NULL) {
            return luaL_error(L, "memory allocation error");
        }

        ngx_memcpy(uri.data, p, len);

        uri.len = len;

        args.data = NULL;
        args.len = 0;

        flags = 0;

        rc = ngx_http_parse_unsafe_uri(r, &uri, &args, &flags);
        if (rc != NGX_OK) {
            dd("rc = %d", (int) rc);

            return luaL_error(L, "unsafe uri in argument #1: %s", p);
        }

        if (args.len == 0) {
            args = extra_args;

        } else if (extra_args.len) {
            /* concatenate the two parts of args together */
            len = args.len + (sizeof("&") - 1) + extra_args.len;

            p = ngx_palloc(r->pool, len);
            if (p == NULL) {
                return luaL_error(L, "out of memory");
            }

            q = ngx_copy(p, args.data, args.len);
            *q++ = '&';
            q = ngx_copy(q, extra_args.data, extra_args.len);

            args.data = p;
            args.len = len;
        }

        psr = ngx_palloc(r->pool, sizeof(ngx_http_post_subrequest_t));
        if (psr == NULL) {
            return luaL_error(L, "memory allocation error");
        }

        sr_ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
        if (sr_ctx == NULL) {
            return luaL_error(L, "out of memory");
        }

        sr_ctx->cc_ref = LUA_NOREF;

        sr_ctx->capture = 1;

        sr_ctx->index = index;

        psr->handler = ngx_http_lua_post_subrequest;
        psr->data = sr_ctx;

        rc = ngx_http_subrequest(r, &uri, &args, &sr, psr, 0);

        if (rc != NGX_OK) {
            return luaL_error(L, "failed to issue subrequest: %d", (int) rc);
        }

        ngx_http_set_ctx(sr, sr_ctx, ngx_http_lua_module);

        rc = ngx_http_lua_adjust_subrequest(sr, method, body, share_all_vars);

        if (rc != NGX_OK) {
            return luaL_error(L, "failed to adjust the subrequest: %d",
                    (int) rc);
        }

        lua_pop(L, 2); /* pop the subrequest argument and uri */
    }

    lua_pushinteger(L, location_capture);

    return lua_yield(L, 1);
}


static ngx_int_t
ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr, ngx_uint_t method,
        ngx_http_request_body_t *body, ngx_flag_t share_all_vars)
{
    ngx_http_request_t          *r;
    ngx_int_t                    rc;
    ngx_http_core_main_conf_t   *cmcf;

    r = sr->parent;

    sr->header_in = r->header_in;

#if 1
    /* XXX work-around a bug in ngx_http_subrequest */
    if (r->headers_in.headers.last == &r->headers_in.headers.part) {
        sr->headers_in.headers.last = &sr->headers_in.headers.part;
    }
#endif

    if (body) {
        sr->request_body = body;

        rc = ngx_http_lua_set_content_length_header(sr,
                ngx_buf_size(body->buf));

        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }

    sr->method = method;

    switch (method) {
        case NGX_HTTP_GET:
            sr->method_name = ngx_http_lua_get_method;
            break;

        case NGX_HTTP_POST:
            sr->method_name = ngx_http_lua_post_method;
            break;

        case NGX_HTTP_PUT:
            sr->method_name = ngx_http_lua_put_method;
            break;

        case NGX_HTTP_HEAD:
            sr->method_name = ngx_http_lua_head_method;
            break;

        case NGX_HTTP_DELETE:
            sr->method_name = ngx_http_lua_delete_method;
            break;

        default:
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "unsupported HTTP method: %u", (unsigned) method);

            return NGX_ERROR;
    }

    /* XXX work-around a bug in ngx_http_subrequest */
    if (r->headers_in.headers.last == &r->headers_in.headers.part) {
        sr->headers_in.headers.last = &sr->headers_in.headers.part;
    }

    if (! share_all_vars) {
        /* we do not inherit the parent request's variables */
        cmcf = ngx_http_get_module_main_conf(sr, ngx_http_core_module);

        sr->variables = ngx_pcalloc(sr->pool, cmcf->variables.nelts
                                * sizeof(ngx_http_variable_value_t));

        if (sr->variables == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc)
{
    ngx_http_request_t            *pr;
    ngx_http_lua_ctx_t            *pr_ctx;
    ngx_http_lua_ctx_t            *ctx = data;
    ngx_uint_t                     i;

    dd("uri %.*s, rc:%d, waiting: %d, done:%d", (int) r->uri.len, r->uri.data,
            (int) rc, (int) ctx->waiting, (int) ctx->done);

    if (ctx->run_post_subrequest) {
        return rc;
    }

    ctx->run_post_subrequest = 1;

#if 0
    ngx_http_lua_dump_postponed(r);
#endif

    pr = r->parent;

    pr_ctx = ngx_http_get_module_ctx(pr, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    pr_ctx->waitings[ctx->index] = 0;

    for (i = 0; i < pr_ctx->nsubreqs; i++) {
        if (pr_ctx->waitings[i]) {
            goto done;
        }
    }

    pr_ctx->done = 1;
    pr_ctx->waiting = 0;

done:
    if (pr_ctx->entered_content_phase) {
        dd("setting wev handler");
        pr->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    dd("status rc = %d", (int) rc);
    dd("status headers_out.status = %d", (int) r->headers_out.status);
    dd("uri: %.*s", (int) r->uri.len, r->uri.data);

    /*  capture subrequest response status */
    if (rc == NGX_ERROR) {
        pr_ctx->sr_statuses[ctx->index] = NGX_HTTP_INTERNAL_SERVER_ERROR;

    } else if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        dd("HERE");
        pr_ctx->sr_statuses[ctx->index] = rc;

    } else {
        dd("THERE");
        pr_ctx->sr_statuses[ctx->index] = r->headers_out.status;
    }

    if (pr_ctx->sr_statuses[ctx->index] == 0) {
        pr_ctx->sr_statuses[ctx->index] = NGX_HTTP_OK;
    }

    dd("pr_ctx status: %d", (int) pr_ctx->sr_statuses[ctx->index]);

    /*  copy subrequest response body */
    dd("saving sr body, r:%.*s, body:%p, done:%d, nsubreqs:%d",
            (int) r->uri.len, r->uri.data, ctx->body, ctx->done,
            (int) ctx->nsubreqs);

    pr_ctx->sr_bodies[ctx->index] = ctx->body;

    /* copy subrequest response headers */
    pr_ctx->sr_headers[ctx->index] = &r->headers_out;

    if (r != r->connection->data && r->postponed &&
            (r->main->posted_requests == NULL ||
            r->main->posted_requests->request != pr))
    {
        ngx_http_post_request(pr, NULL);
    }

#if 0
    /* ensure that the parent request is (or will be)
     *  posted out the head of the r->posted_requests chain */

    dd("posted requests: %p", r->main->posted_requests);

    if (r->main->posted_requests
            && r->main->posted_requests->request != pr)
    {
        dd("posting parent request");

        rc = ngx_http_lua_post_request_at_head(pr, NULL);
        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }
#endif

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


/* XXX we also decode '+' to ' ' */
static void
ngx_http_lua_unescape_uri(u_char **dst, u_char **src, size_t size,
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
    u_char                  *p = NULL;
    u_char                  *src;
    size_t                   len, slen;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    len = MD5_DIGEST_LENGTH * 2;

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

    p = ngx_palloc(r->pool, len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    ndk_md5_hash(p, (char *) src, slen);

    lua_pushlstring(L, (char *) p, len);

    return 1;
}


int
ngx_http_lua_ngx_md5_bin(lua_State *L)
{
    ngx_http_request_t      *r;
    u_char                  *p = NULL;
    u_char                  *src;
    size_t                   len, slen;
    ngx_md5_t                md5;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    len = MD5_DIGEST_LENGTH;

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

    p = ngx_palloc(r->pool, len);
    if (p == NULL) {
        return NGX_ERROR;
    }

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, (char *) src, slen);
    ngx_md5_final(p, &md5);

    dd("len: %d", (int) len);

    lua_pushlstring(L, (char *) p, len);

    ngx_pfree(r->pool, p);

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
ngx_http_lua_ngx_today(lua_State *L)
{
    ngx_http_request_t      *r;
    time_t                   now;
    ngx_tm_t                 tm;
    u_char                   buf[sizeof("2010-11-19") - 1];

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) > 0) {
        return luaL_error(L, "shouldn't have argument");
    }

    now = ngx_time();
    ngx_gmtime(now + ngx_cached_time->gmtoff * 60, &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d", tm.ngx_tm_year, tm.ngx_tm_mon,
            tm.ngx_tm_mday);

    lua_pushlstring(L, (char *) buf, sizeof(buf));

    return 1;
}


int
ngx_http_lua_ngx_localtime(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_tm_t                 tm;

    u_char buf[sizeof("2010-11-19 20:56:31") - 1];

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) > 0) {
        return luaL_error(L, "shouldn't have argument");
    }

    ngx_gmtime(ngx_time() + ngx_cached_time->gmtoff * 60, &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d", tm.ngx_tm_year,
            tm.ngx_tm_mon, tm.ngx_tm_mday, tm.ngx_tm_hour, tm.ngx_tm_min,
            tm.ngx_tm_sec);

    lua_pushlstring(L, (char *) buf, sizeof(buf));

    return 1;
}


int
ngx_http_lua_ngx_time(lua_State *L)
{
    ngx_http_request_t      *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) > 0) {
        return luaL_error(L, "shouldn't have argument");
    }

    lua_pushnumber(L, (lua_Number) ngx_time());

    return 1;
}


int
ngx_http_lua_ngx_utctime(lua_State *L)
{
    ngx_http_request_t      *r;
    ngx_tm_t                 tm;

    u_char buf[sizeof("2010-11-19 20:56:31") - 1];

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (lua_gettop(L) > 0) {
        return luaL_error(L, "shouldn't have argument");
    }

    ngx_gmtime(ngx_time(), &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d", tm.ngx_tm_year,
            tm.ngx_tm_mon, tm.ngx_tm_mday, tm.ngx_tm_hour, tm.ngx_tm_min,
            tm.ngx_tm_sec);

    lua_pushlstring(L, (char *) buf, sizeof(buf));

    return 1;
}


static uintptr_t
ngx_http_lua_escape_uri(u_char *dst, u_char *src, size_t size, ngx_uint_t type)
{
    ngx_uint_t      n;
    uint32_t       *escape;
    static u_char   hex[] = "0123456789abcdef";

                    /* " ", "#", "%", "?", %00-%1F, %7F-%FF */

    static uint32_t   uri[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0xfc00886d, /* 1111 1100 0000 0000  1000 1000 0110 1101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x78000000, /* 0111 1000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0xa8000000, /* 1010 1000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "#", "%", "+", "?", %00-%1F, %7F-%FF */

    static uint32_t   args[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x80000829, /* 1000 0000 0000 0000  0000 1000 0010 1001 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "#", """, "%", "'", %00-%1F, %7F-%FF */

    static uint32_t   html[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x000000ad, /* 0000 0000 0000 0000  0000 0000 1010 1101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", """, "%", "'", %00-%1F, %7F-%FF */

    static uint32_t   refresh[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000085, /* 0000 0000 0000 0000  0000 0000 1000 0101 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x80000000, /* 1000 0000 0000 0000  0000 0000 0000 0000 */

        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */
        0xffffffff  /* 1111 1111 1111 1111  1111 1111 1111 1111 */
    };

                    /* " ", "%", %00-%1F */

    static uint32_t   memcached[] = {
        0xffffffff, /* 1111 1111 1111 1111  1111 1111 1111 1111 */

                    /* ?>=< ;:98 7654 3210  /.-, +*)( '&%$ #"!  */
        0x00000021, /* 0000 0000 0000 0000  0000 0000 0010 0001 */

                    /* _^]\ [ZYX WVUT SRQP  ONML KJIH GFED CBA@ */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

                    /*  ~}| {zyx wvut srqp  onml kjih gfed cba` */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */

        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
        0x00000000, /* 0000 0000 0000 0000  0000 0000 0000 0000 */
    };

                    /* mail_auth is the same as memcached */

    static uint32_t  *map[] =
        { uri, args, html, refresh, memcached, memcached };


    escape = map[type];

    if (dst == NULL) {

        /* find the number of the characters to be escaped */

        n = 0;

        while (size) {
            if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
                n++;
            }
            src++;
            size--;
        }

        return (uintptr_t) n;
    }

    while (size) {
        if (escape[*src >> 5] & (1 << (*src & 0x1f))) {
            *dst++ = '%';
            *dst++ = hex[*src >> 4];
            *dst++ = hex[*src & 0xf];
            src++;

        } else {
            *dst++ = *src++;
        }
        size--;
    }

    return (uintptr_t) dst;
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

    return luaL_error(L, "Attempt to write to ngx. with the key \"%s\"", p);
}


int
ngx_http_lua_header_get(lua_State *L)
{
    return luaL_error(L, "header get not implemented yet");
}


int
ngx_http_lua_header_set(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    ngx_str_t                    key;
    ngx_str_t                    value;
    ngx_uint_t                   i;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    ngx_uint_t                   n;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    dd("key: %.*s, len %d", (int) len, p, (int) len);

    /* replace "_" with "-" */
    for (i = 0; i < len; i++) {
        if (p[i] == '_') {
            p[i] = '-';
        }
    }

    key.data = ngx_palloc(r->pool, len + 1);
    if (key.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(key.data, p, len);

    key.data[len] = '\0';

    key.len = len;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (! ctx->headers_set) {
        rc = ngx_http_set_content_type(r);
        if (rc != NGX_OK) {
            return luaL_error(L,
                    "failed to set default content type: %d",
                    (int) rc);
        }

        ctx->headers_set = 1;
    }

    if (lua_type(L, 3) == LUA_TNIL) {
        value.data = NULL;
        value.len = 0;

    } else if (lua_type(L, 3) == LUA_TTABLE) {
        n = luaL_getn(L, 3);
        if (n == 0) {
            value.data = NULL;
            value.len = 0;

        } else {
            for (i = 1; i <= n; i++) {
                dd("header value table index %d", (int) i);

                lua_rawgeti(L, 3, i);
                p = (u_char*) luaL_checklstring(L, -1, &len);

                value.data = ngx_palloc(r->pool, len);
                if (value.data == NULL) {
                    return luaL_error(L, "out of memory");
                }

                ngx_memcpy(value.data, p, len);
                value.len = len;

                rc = ngx_http_lua_set_header(r, key, value,
                        i == 1 /* override */);

                if (rc != NGX_OK) {
                    return luaL_error(L,
                            "failed to set header %s (error: %d)",
                            key.data, (int) rc);
                }
            }

            return 0;
        }

    } else {
        p = (u_char*) luaL_checklstring(L, 3, &len);
        value.data = ngx_palloc(r->pool, len);
        if (value.data == NULL) {
            return luaL_error(L, "out of memory");
        }

        ngx_memcpy(value.data, p, len);
        value.len = len;
    }

    dd("key: %.*s, value: %.*s",
            (int) key.len, key.data, (int) value.len, value.data);

    rc = ngx_http_lua_set_header(r, key, value, 1 /* override */);

    if (rc != NGX_OK) {
        return luaL_error(L, "failed to set header %s (error: %d)",
                key.data, (int) rc);
    }

    return 0;
}


int
ngx_http_lua_ngx_exec(lua_State *L)
{
    int                          n;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_str_t                    uri;
    ngx_str_t                    args, user_args;
    ngx_uint_t                   flags;
    u_char                      *p;
    u_char                      *q;
    size_t                       len;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments, but got %d",
                n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    args.data = NULL;
    args.len = 0;

    /* read the 1st argument (uri) */

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return luaL_error(L, "The uri argument is empty");
    }

    uri.data = ngx_palloc(r->pool, len);
    ngx_memcpy(uri.data, p, len);

    uri.len = len;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ngx_http_parse_unsafe_uri(r, &uri, &args, &flags)
            != NGX_OK) {
        ctx->headers_sent = 1;
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (n == 2) {
        /* read the 2nd argument (args) */
        p = (u_char *) luaL_checklstring(L, 2, &len);

        user_args.data = ngx_palloc(r->pool, len);
        ngx_memcpy(user_args.data, p, len);

        user_args.len = len;

    } else {
        user_args.data = NULL;
        user_args.len = 0;
    }

    if (user_args.len) {
        if (args.len == 0) {
            args = user_args;
        } else {
            p = ngx_palloc(r->pool, args.len + user_args.len + 1);
            if (p == NULL) {
                return luaL_error(L, "out of memory");
            }

            q = ngx_copy(p, args.data, args.len);
            *q++ = '&';
            q = ngx_copy(q, user_args.data, user_args.len);

            args.data = p;
            args.len += user_args.len + 1;
        }
    }

    if (ctx->headers_sent) {
        return luaL_error(L, "attempt to call ngx.exec after "
                "sending out response headers");
    }

    ctx->exec_uri = uri;
    ctx->exec_args = args;

    lua_pushnil(L);
    return lua_error(L);
}


int
ngx_http_lua_ndk_set_var_get(lua_State *L)
{
    ndk_set_var_value_pt                 func;
    size_t                               len;
    u_char                              *p;

    p = (u_char *) luaL_checklstring(L, 2, &len);

    dd("ndk.set_var metatable __index: %s", p);

    func = ngx_http_lookup_ndk_set_var_directive(p, len);

    if (func == NULL) {
        return luaL_error(L, "ndk.set_var: directive \"%s\" not found "
                "or does not use ndk_set_var_value",
                p);

    }

    lua_pushvalue(L, -1); /* table key key */
    lua_pushvalue(L, -1); /* table key key key */

    lua_pushlightuserdata(L, func); /* table key key key func */

    lua_pushcclosure(L, ngx_http_lua_run_set_var_directive, 2);
        /* table key key closure */

    lua_rawset(L, 1); /* table key */

    lua_rawget(L, 1); /* table closure */

    return 1;
}


int
ngx_http_lua_ndk_set_var_set(lua_State *L)
{
    return luaL_error(L, "Not allowed");
}


static ndk_set_var_value_pt
ngx_http_lookup_ndk_set_var_directive(u_char *name,
        size_t name_len)
{
    ndk_set_var_t           *filter;
    ngx_uint_t               i;
    ngx_module_t            *module;
    ngx_command_t           *cmd;

    for (i = 0; ngx_modules[i]; i++) {
        module = ngx_modules[i];
        if (module->type != NGX_HTTP_MODULE) {
            continue;
        }

        cmd = ngx_modules[i]->commands;
        if (cmd == NULL) {
            continue;
        }

        for ( /* void */ ; cmd->name.len; cmd++) {
            if (cmd->set != ndk_set_var_value) {
                continue;
            }

            filter = cmd->post;
            if (filter == NULL) {
                continue;
            }

            if (cmd->name.len != name_len
                    || ngx_strncmp(cmd->name.data, name, name_len) != 0)
            {
                continue;
            }

            return (ndk_set_var_value_pt)(filter->func);
        }
    }

    return NULL;
}


int
ngx_http_lua_run_set_var_directive(lua_State *L)
{
    ngx_int_t                            rc;
    ndk_set_var_value_pt                 func;
    ngx_str_t                            res;
    ngx_http_variable_value_t            arg;
    u_char                              *p;
    size_t                               len;
    ngx_http_request_t                  *r;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    arg.data = (u_char *) luaL_checklstring(L, 1, &len);
    arg.len = len;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = (u_char *) luaL_checklstring(L, lua_upvalueindex(1), &len);

    dd("calling set_var func for %s", p);

    func = (ndk_set_var_value_pt)lua_touserdata(L, lua_upvalueindex(2));

    rc = func(r, &res, &arg);

    if (rc != NGX_OK) {
        return luaL_error(L, "calling directive %s failed with code %d",
                p, (int) rc);
    }

    lua_pushlstring(L, (char *) res.data, res.len);

    return 1;
}


static ngx_int_t
ngx_http_lua_set_content_length_header(ngx_http_request_t *r, size_t len)
{
    ngx_table_elt_t            *h;

    r->headers_in.content_length_n = len;
    r->headers_in.content_length = ngx_pcalloc(r->pool,
            sizeof(ngx_table_elt_t));

    r->headers_in.content_length->value.data =
        ngx_palloc(r->pool, NGX_OFF_T_LEN);

    if (r->headers_in.content_length->value.data == NULL) {
        return NGX_ERROR;
    }

    r->headers_in.content_length->value.len = ngx_sprintf(
            r->headers_in.content_length->value.data, "%O",
            r->headers_in.content_length_n) -
            r->headers_in.content_length->value.data;

    if (ngx_list_init(&r->headers_in.headers, r->pool, 20,
                sizeof(ngx_table_elt_t)) != NGX_OK) {
        return NGX_ERROR;
    }

    h = ngx_list_push(&r->headers_in.headers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    h->hash = r->header_hash;

    h->key = ngx_http_lua_content_length_header_key;
    h->value = r->headers_in.content_length->value;

    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_ERROR;
    }

    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);

    dd("r content length: %.*s",
            (int)r->headers_in.content_length->value.len,
            r->headers_in.content_length->value.data);

    return NGX_OK;
}


int
ngx_http_lua_ngx_cookie_time(lua_State *L)
{
    ngx_http_request_t                  *r;
    time_t                               t;
    u_char                              *p;

    u_char   buf[sizeof("Mon, 28 Sep 1970 06:00:00 GMT") - 1];

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    t = (time_t) luaL_checknumber(L, 1);

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = buf;
    p = ngx_http_cookie_time(p, t);

    lua_pushlstring(L, (char *) buf, p - buf);

    return 1;
}


int
ngx_http_lua_ngx_redirect(lua_State *L)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    int                          n;
    u_char                      *p;
    u_char                      *uri;
    size_t                       len;
    ngx_http_request_t          *r;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments");
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (n == 2) {
        rc = (ngx_int_t) luaL_checknumber(L, 2);

        if (rc != NGX_HTTP_MOVED_TEMPORARILY &&
                rc != NGX_HTTP_MOVED_PERMANENTLY)
        {
            return luaL_error(L, "only ngx.HTTP_MOVED_TEMPORARILY and "
                    "ngx.HTTP_MOVED_PERMANENTLY are allowed");
        }
    } else {
        rc = NGX_HTTP_MOVED_TEMPORARILY;
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
        return luaL_error(L, "attempt to call ngx.redirect after sending out "
                "the headers");
    }

    uri = ngx_palloc(r->pool, len);
    if (uri == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(uri, p, len);

    r->headers_out.location = ngx_list_push(&r->headers_out.headers);
    if (r->headers_out.location == NULL) {
        return luaL_error(L, "out of memory");
    }

    r->headers_out.location->hash = 1;
    r->headers_out.location->value.len = len;
    r->headers_out.location->value.data = uri;
    ngx_str_set(&r->headers_out.location->key, "Location");

    r->headers_out.status = rc;

    ctx->exit_code = rc;
    ctx->exited = 1;

    lua_pushnil(L);
    return lua_error(L);
}


static void
ngx_http_lua_process_args_option(ngx_http_request_t *r, lua_State *L,
        int table, ngx_str_t *args)
{
    u_char              *key;
    size_t               key_len;
    u_char              *value;
    size_t               value_len;
    size_t               len = 0;
    uintptr_t            total_escape = 0;
    int                  n;
    int                  i;
    u_char              *p;

    n = 0;
    lua_pushnil(L);
    while (lua_next(L, table - 1) != 0) {
        if (lua_type(L, -2) != LUA_TSTRING) {
            luaL_error(L, "attemp to use a non-string key in the "
                    "\"args\" option table");
            return;
        }

        key = (u_char *) lua_tolstring(L, -2, &key_len);

        total_escape += 2 * ngx_http_lua_escape_uri(NULL, key, key_len,
                NGX_ESCAPE_URI);

        value = (u_char *) lua_tolstring(L, -1, &value_len);

        total_escape += 2 * ngx_http_lua_escape_uri(NULL, value, value_len,
                NGX_ESCAPE_URI);

        len += key_len + value_len + (sizeof("=") - 1);

        n++;

        lua_pop(L, 1);
    }

    len += (size_t) total_escape;

    if (n > 1) {
        len += (n - 1) * (sizeof("&") - 1);
    }

    dd("len 1: %d", (int) len);

    p = ngx_palloc(r->pool, len);
    if (p == 0) {
        luaL_error(L, "out of memory");
        return;
    }

    args->data = p;
    args->len = len;

    i = 0;
    lua_pushnil(L);
    while (lua_next(L, table - 1) != 0) {
        key = (u_char *) lua_tolstring(L, -2, &key_len);

        if (total_escape) {
            p = (u_char *) ngx_http_lua_escape_uri(p, key, key_len,
                    NGX_ESCAPE_URI);

        } else {
            dd("shortcut: no escape required");

            p = ngx_copy(p, key, key_len);
        }

        *p++ = '=';

        value = (u_char *) lua_tolstring(L, -1, &value_len);

        if (total_escape) {
            p = (u_char *) ngx_http_lua_escape_uri(p, value, value_len,
                    NGX_ESCAPE_URI);

        } else {
            p = ngx_copy(p, value, value_len);
        }

        if (i != n - 1) {
            /* not the last pair */
            *p++ = '&';
        }

        i++;
        lua_pop(L, 1);
    }

    if (p - args->data != (ssize_t) len) {
        luaL_error(L, "buffer error: %d != %d",
                (int) (p - args->data), (int) len);
        return;
    }
}

