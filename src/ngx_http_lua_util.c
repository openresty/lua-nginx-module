#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"

static void init_ngx_lua_registry(lua_State *l);
static void init_ngx_lua_globals(lua_State *l);
static int ngx_http_lua_var_get(lua_State *l);
static int ngx_http_lua_var_set(lua_State *l);

lua_State*
ngx_http_lua_new_state()
{
    lua_State *l = luaL_newstate();
    if(l == NULL) {
        return NULL;
    }

    luaL_openlibs(l);

    init_ngx_lua_registry(l);
    init_ngx_lua_globals(l);

    return l;
}

lua_State*
ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *l, int *ref)
{
    int top = lua_gettop(l);

    lua_getfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);

    lua_State *cr = lua_newthread(l);
    if(cr) {
        // new globals table for coroutine
        lua_newtable(cr);

        // {{{ inherit coroutine's globals to main thread's globals table
        // for print() function will try to find tostring() in current globals
        // table.
        lua_newtable(cr);
        lua_pushvalue(cr, LUA_GLOBALSINDEX);
        lua_setfield(cr, -2, "__index");
        lua_setmetatable(cr, -2);
        // }}}

        lua_replace(cr, LUA_GLOBALSINDEX);

        *ref = luaL_ref(l, -2);
        if(*ref == LUA_NOREF) {
            lua_settop(l, top);    // restore main trhead stack
            return NULL;
        }
    }

    // pop coroutine refernece on main thread's stack after anchoring it in registery
    lua_pop(l, 1);
    return cr;
}

void
ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *l, int ref, int force_quit)
{
    lua_getfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);

    lua_rawgeti(l, -1, ref);
    lua_State *cr = lua_tothread(l, -1);
    lua_pop(l, 1);

    if(cr && force_quit) {
        // {{{ save orig code closure's env
        lua_getglobal(cr, GLOBALS_SYMBOL_RUNCODE);
        lua_getfenv(cr, -1);
        lua_xmove(cr, l, 1);
        // }}}

        // {{{ clean code closure's env
        lua_newtable(cr);
        lua_setfenv(cr, -2);
        // }}}

        // {{{ blocking run code till ending
        do {
            lua_settop(cr, 0);
        } while(lua_resume(cr, 0) == LUA_YIELD);
        // }}}

        // {{{ restore orig code closure's env
        lua_settop(cr, 0);
        lua_getglobal(cr, GLOBALS_SYMBOL_RUNCODE);
        lua_xmove(l, cr, 1);
        lua_setfenv(cr, -2);
        lua_pop(cr, 1);
        // }}}
    }

    // release reference to coroutine
    luaL_unref(l, -1, ref);
    lua_pop(l, 1);
}

ngx_int_t
ngx_http_lua_has_inline_var(ngx_str_t *s)
{
    return (ngx_http_script_variables_count(s) != 0);
}

char *
ngx_http_lua_rebase_path(ngx_pool_t *pool, ngx_str_t *str)
{
    char *path;
    u_char *tmp;

    if(str->data[0] != '/') {
        // {{{ make relative path based on NginX default prefix
        path = ngx_pcalloc(pool, ngx_cycle->prefix.len + str->len + 1);
        if (path == NULL) {
            return NULL;
        }

        tmp = ngx_copy(
                ngx_copy(path, ngx_cycle->prefix.data, ngx_cycle->prefix.len),
                str->data, str->len
                );
        // }}}
    } else {
        // {{{ copy absolute path directly
        path = ngx_pcalloc(pool, str->len + 1);
        if (path == NULL) {
            return NULL;
        }

        tmp = ngx_copy(path, str->data, str->len);
        // }}}
    }
    *tmp = '\0';

    return path;
}

ngx_int_t
ngx_http_lua_send_header_if_needed(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx)
{
    if ( ! ctx->headers_sent ) {
        r->headers_out.status = NGX_HTTP_OK;

        if (ngx_http_set_content_type(r) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ngx_http_clear_content_length(r);
        ngx_http_clear_accept_ranges(r);

        if (r->http_version >= NGX_HTTP_VERSION_11) {
            // Send response headers for HTTP version <= 1.0 elsewhere
            ctx->headers_sent = 1;
            return ngx_http_send_header(r);
        }
    }

    return NGX_OK;
}

ngx_int_t
ngx_http_lua_send_chain_link(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, ngx_chain_t *cl)
{
    ngx_int_t       rc;
    size_t          size;
    ngx_chain_t     *p;

    rc = ngx_http_lua_send_header_if_needed(r, ctx);

    if (r->header_only || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    if (r->http_version < NGX_HTTP_VERSION_11 && !ctx->headers_sent) {
        ctx->headers_sent = 1;

        size = 0;

        for (p = cl; p; p = p->next) {
            if (p->buf->memory) {
                size += p->buf->last - p->buf->pos;
            }
        }

        r->headers_out.content_length_n = (off_t) size;

        if (r->headers_out.content_length) {
            r->headers_out.content_length->hash = 0;
        }

        r->headers_out.content_length = NULL;

        rc = ngx_http_send_header(r);

        if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }
    }

    if (cl == NULL) {

#if defined(nginx_version) && nginx_version <= 8004

        /* earlier versions of nginx does not allow subrequests
           to send last_buf themselves */
        if (r != r->main) {
            return NGX_OK;
        }

#endif

        rc = ngx_http_send_special(r, NGX_HTTP_LAST);
        if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }

        return NGX_OK;
    }

    return ngx_http_output_filter(r, cl);
}

static void
init_ngx_lua_registry(lua_State *l)
{
    // {{{ register table to anchor lua coroutines reliablly: {([int]ref) = [cort]}
    lua_newtable(l);
    lua_setfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
    // }}}
    // {{{ register table to cache user code: {([string]cache_key) = [code closure]}
    lua_newtable(l);
    lua_setfield(l, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);
    // }}}
}

static void
init_ngx_lua_globals(lua_State *l)
{
    // {{{ remove unsupported globals
    lua_pushnil(l);
    lua_setfield(l, LUA_GLOBALSINDEX, "coroutine");
    // }}}

    // {{{ register global hook functions
    lua_pushcfunction(l, ngx_http_lua_print);
    lua_setglobal(l, "print");
    // }}}

    lua_newtable(l);    // ngx.*

    // {{{ register nginx hook functions
    lua_pushcfunction(l, ngx_http_lua_ngx_send_headers);
    lua_setfield(l, -2, "send_headers");
    lua_pushcfunction(l, ngx_http_lua_ngx_echo);
    lua_setfield(l, -2, "echo");
    lua_pushcfunction(l, ngx_http_lua_ngx_flush);
    lua_setfield(l, -2, "flush");
    lua_pushcfunction(l, ngx_http_lua_ngx_eof);
    lua_setfield(l, -2, "eof");

    lua_newtable(l);
    lua_pushcfunction(l, ngx_http_lua_ngx_location_capture);
    lua_setfield(l, -2, "capture");
    lua_setfield(l, -2, "location");
    // }}}

    // {{{ register nginx constants
    lua_newtable(l);    // .status

    lua_pushinteger(l, 200);
    lua_setfield(l, -2, "HTTP_OK");
    lua_pushinteger(l, 302);
    lua_setfield(l, -2, "HTTP_LOCATION");

    lua_setfield(l, -2, "status");
    // }}}

    // {{{ register reference maps
    lua_newtable(l);    // .var

    lua_newtable(l);
    lua_pushcfunction(l, ngx_http_lua_var_get);
    lua_setfield(l, -2, "__index");
    lua_pushcfunction(l, ngx_http_lua_var_set);
    lua_setfield(l, -2, "__newindex");
    lua_setmetatable(l, -2);

    lua_setfield(l, -2, "var");
    // }}}

    lua_setglobal(l, "ngx");
}

/**
 * Get NginX internal variables content
 *
 * @retval Always return a string or nil on Lua stack. Return nil when failed to get
 * content, and actual content string when found the specified variable.
 * @seealso ngx_http_lua_var_set
 * */
static int
ngx_http_lua_var_get(lua_State *l)
{
    ngx_http_request_t *r;
    u_char *p, *lowcase;
    size_t len;
    ngx_uint_t hash;
    ngx_str_t var;
    ngx_http_variable_value_t *vv;
    int got = 0;

    lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

    p = (u_char*)luaL_checklstring(l, -1, &len);

    if(r != NULL && p != NULL) {
        lowcase = ngx_pnalloc(r->pool, len);
        if(lowcase == NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "(lua-var-get) can't allocate memory to hold lower-cased variable name: varname='%.*s', len=%d",
                    len, p, len);
        }

        hash = ngx_hash_strlow(lowcase, p, len);

        var.len = len;
        var.data = lowcase;

#if defined(nginx_version) && nginx_version > 8036
        vv = ngx_http_get_variable(r, &var, hash);
#else
        vv = ngx_http_get_variable(r, &var, hash, 1);
#endif

        if(vv == NULL || vv->not_found) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                    "(lua-var-get) no such a nginx variable: varname='%.*s', len=%d",
                    len, lowcase, len);
        } else {
            // found the specified var
            lua_pushlstring(l, (const char*)vv->data, (size_t)vv->len);
            got = 1;
        }
    } else {
        dd("(lua-var-get) no valid nginx request pointer or variable name: r=%p, p=%p", r, p);
    }

    // return nil if no data were found
    if(!got) {
        lua_pushnil(l);
    }

    return 1;
}

/**
 * Set NginX internal variable content
 *
 * @retval Always return a boolean on Lua stack. Return true when variable
 * content was modified successfully, false otherwise.
 * @seealso ngx_http_lua_var_get
 * */
static int
ngx_http_lua_var_set(lua_State *l)
{
    ngx_http_request_t *r;

    lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

    // TODO: 
    lua_pushboolean(l, 0);    // return false

    return 1;
}

ngx_int_t
ngx_http_lua_post_request_at_head(ngx_http_request_t *r,
        ngx_http_posted_request_t *pr)
{
    if (pr == NULL) {
        pr = ngx_palloc(r->pool, sizeof(ngx_http_posted_request_t));
        if (pr == NULL) {
            return NGX_ERROR;
        }
    }

    pr->request = r;
    pr->next = r->main->posted_requests;
    r->main->posted_requests = pr;

    return NGX_OK;
}

void
ngx_http_lua_discard_bufs(ngx_pool_t *pool, ngx_chain_t *in)
{
    ngx_chain_t         *cl;

    for (cl = in; cl; cl = cl->next) {
        cl->buf->pos = cl->buf->last;
    }
}

ngx_int_t
ngx_http_lua_add_copy_chain(ngx_pool_t *pool, ngx_chain_t **chain, ngx_chain_t *in)
{
    ngx_chain_t     *cl, **ll;
    size_t           len;

    ll = chain;

    for (cl = *chain; cl; cl = cl->next) {
        ll = &cl->next;
    }

    while (in) {
        cl = ngx_alloc_chain_link(pool);
        if (cl == NULL) {
            return NGX_ERROR;
        }

        if (ngx_buf_special(in->buf)) {
            cl->buf = in->buf;
        } else {
            if (ngx_buf_in_memory(in->buf)) {
                len = ngx_buf_size(in->buf);
                cl->buf = ngx_create_temp_buf(pool, len);
                dd("buf: %.*s", (int) len, in->buf->pos);

                cl->buf->last = ngx_copy(cl->buf->pos, in->buf->pos, len);

            } else {
                return NGX_ERROR;
            }
        }

        *ll = cl;
        ll = &cl->next;
        in = in->next;
    }

    *ll = NULL;

    return NGX_OK;
}

// vi:ts=4 sw=4 fdm=marker

