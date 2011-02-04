/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#define DDEBUG 0

#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"


static void init_ngx_lua_registry(lua_State *L);
static void init_ngx_lua_globals(lua_State *L);
static void inject_http_consts(lua_State *L);
static void inject_core_consts(lua_State *L);
static void setpath(lua_State *L, int tab_idx, const char *fieldname,
        const char *path, const char *def);


#define LUA_PATH_SEP ";"
#define AUX_MARK "\1"


static void
setpath(lua_State *L, int tab_idx, const char *fieldname, const char *path,
        const char *def)
{
    const char *tmp_path;

    tmp_path = luaL_gsub(L, path, LUA_PATH_SEP LUA_PATH_SEP,
            LUA_PATH_SEP AUX_MARK LUA_PATH_SEP);
    luaL_gsub(L, tmp_path, AUX_MARK, def);
    lua_remove(L, -2);

    /* fix negative index as there's new data on stack */
    tab_idx = (tab_idx < 0) ? (tab_idx - 1) : tab_idx;
    lua_setfield(L, tab_idx, fieldname);
}

lua_State *
ngx_http_lua_new_state(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
    lua_State *L = luaL_newstate();
    if (L == NULL) {
        return NULL;
    }

    luaL_openlibs(L);

    lua_getglobal(L, "package");

    if (! lua_istable(L, -1)) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                "the \"package\" table does not exist");
        return NULL;
    }

    if (lmcf->lua_path.len != 0) {
        const char *old_path;
        const char *new_path;

        lua_getfield(L, -1, "path"); /* get original package.path */
        old_path = lua_tostring(L, -1);

        lua_pushlstring(L, (char *) lmcf->lua_path.data, lmcf->lua_path.len);
        new_path = lua_tostring(L, -1);

        setpath(L, -3, "path", new_path, old_path);

        lua_pop(L, 2);
    }

    if (lmcf->lua_cpath.len != 0) {
        const char *old_cpath;
        const char *new_cpath;

        lua_getfield(L, -1, "cpath"); /* get original package.cpath */
        old_cpath = lua_tostring(L, -1);

        lua_pushlstring(L, (char *) lmcf->lua_cpath.data, lmcf->lua_cpath.len);
        new_cpath = lua_tostring(L, -1);

        setpath(L, -3, "cpath", new_cpath, old_cpath);

        lua_pop(L, 2);
    }

    lua_remove(L, -1); /* remove the "package" table */

    init_ngx_lua_registry(L);
    init_ngx_lua_globals(L);

    return L;
}


lua_State *
ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *L, int *ref)
{
    int top = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);

    lua_State *cr = lua_newthread(L);

    if (cr) {
        /*  new globals table for coroutine */
        lua_newtable(cr);

        /*  {{{ inherit coroutine's globals to main thread's globals table
         *  for print() function will try to find tostring() in current
         *  globals *  table. */
        lua_createtable(cr, 0, 1);
        lua_pushvalue(cr, LUA_GLOBALSINDEX);
        lua_setfield(cr, -2, "__index");
        lua_setmetatable(cr, -2);
        /*  }}} */

        lua_replace(cr, LUA_GLOBALSINDEX);

        *ref = luaL_ref(L, -2);

        if (*ref == LUA_NOREF) {
            lua_settop(L, top);    /*  restore main trhead stack */
            return NULL;
        }
    }

    /*  pop coroutine refernece on main thread's stack after anchoring it
     *  in registery */
    lua_pop(L, 1);

    return cr;
}


void
ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *L, int ref,
        int force_quit)
{
    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);

    lua_rawgeti(L, -1, ref);
    lua_State *cr = lua_tothread(L, -1);
    lua_pop(L, 1);

    if (cr && force_quit) {
        /* {{{ save orig code closure's env */
        lua_getglobal(cr, GLOBALS_SYMBOL_RUNCODE);
        lua_getfenv(cr, -1);
        lua_xmove(cr, L, 1);
        /* }}} */

        /* {{{ clean code closure's env */
        lua_newtable(cr);
        lua_setfenv(cr, -2);
        /* }}} */

        /* {{{ blocking run code till ending */
        do {
            lua_settop(cr, 0);
        } while (lua_resume(cr, 0) == LUA_YIELD);
        /* }}} */

        /* {{{ restore orig code closure's env */
        lua_settop(cr, 0);
        lua_getglobal(cr, GLOBALS_SYMBOL_RUNCODE);
        lua_xmove(L, cr, 1);
        lua_setfenv(cr, -2);
        lua_pop(cr, 1);
        /* }}} */
    }

    /* release reference to coroutine */
    luaL_unref(L, -1, ref);
    lua_pop(L, 1);
}


ngx_int_t
ngx_http_lua_has_inline_var(ngx_str_t *s)
{
    return (ngx_http_script_variables_count(s) != 0);
}


u_char *
ngx_http_lua_rebase_path(ngx_pool_t *pool, u_char *src, size_t len)
{
    u_char            *p, *dst;

    if (len == 0) {
        return NULL;
    }

    if (src[0] == '/') {
        /* being an absolute path already */
        dst = ngx_palloc(pool, len + 1);
        if (dst == NULL) {
            return NULL;
        }

        p = ngx_copy(dst, src, len);

        *p = '\0';

        return dst;
    }

    dst = ngx_palloc(pool, ngx_cycle->prefix.len + len + 1);
    if (dst == NULL) {
        return NULL;
    }

    p = ngx_copy(dst, ngx_cycle->prefix.data, ngx_cycle->prefix.len);
    p = ngx_copy(p, src, len);

    *p = '\0';

    return dst;
}


ngx_int_t
ngx_http_lua_send_header_if_needed(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx)
{
    if ( ! ctx->headers_sent ) {
        if (r->headers_out.status == 0) {
            r->headers_out.status = NGX_HTTP_OK;
        }

        if (! ctx->headers_set && ngx_http_set_content_type(r) != NGX_OK) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        if (! ctx->headers_set) {
            ngx_http_clear_content_length(r);
            ngx_http_clear_accept_ranges(r);
        }

        if (r->http_version >= NGX_HTTP_VERSION_11) {
            /* Send response headers for HTTP version <= 1.0 elsewhere */
            ctx->headers_sent = 1;
            return ngx_http_send_header(r);
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_send_chain_link(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
        ngx_chain_t *in)
{
    ngx_int_t        rc;
    size_t           size;
    ngx_chain_t     *cl;

#if 1
    if (ctx->eof) {
        dd("ctx->eof already set");
        return NGX_OK;
    }
#endif

    rc = ngx_http_lua_send_header_if_needed(r, ctx);

    if (r->header_only || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        ctx->eof = 1;
        return rc;
    }

    if (r->http_version < NGX_HTTP_VERSION_11 && !ctx->headers_sent) {
        ctx->headers_sent = 1;

        size = 0;

        for (cl = in; cl; cl = cl->next) {
            size += ngx_buf_size(cl->buf);
            if (cl->next == NULL) {
                cl->buf->last_buf = 1;
            }
        }

        r->headers_out.content_length_n = (off_t) size;

        if (r->headers_out.content_length) {
            r->headers_out.content_length->hash = 0;
        }

        r->headers_out.content_length = NULL;

        dd("setting ctx->eof = 1");
        ctx->eof = 1;

        rc = ngx_http_send_header(r);

        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }
    }

    if (in == NULL) {

#if defined(nginx_version) && nginx_version <= 8004

        /* earlier versions of nginx does not allow subrequests
           to send last_buf themselves */
        if (r != r->main) {
            return NGX_OK;
        }

#endif

        ctx->eof = 1;

        dd("send special buf");

        rc = ngx_http_send_special(r, NGX_HTTP_LAST);
        if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }

        return NGX_OK;
    }

    return ngx_http_output_filter(r, in);
}


static void
init_ngx_lua_registry(lua_State *L)
{
    /* {{{ register table to anchor lua coroutines reliablly:
     * {([int]ref) = [cort]} */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
    /* }}} */

    /* {{{ register table to cache user code:
     * {([string]cache_key) = [code closure]} */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);
    /* }}} */
}


static void
inject_core_consts(lua_State *L)
{
    /* {{{ core constants */
    lua_pushinteger(L, NGX_OK);
    lua_setfield(L, -2, "OK");

    lua_pushinteger(L, NGX_AGAIN);
    lua_setfield(L, -2, "AGAIN");

    lua_pushinteger(L, NGX_DONE);
    lua_setfield(L, -2, "DONE");

    lua_pushinteger(L, NGX_ERROR);
    lua_setfield(L, -2, "ERROR");
    /* }}} */
}


static void
inject_http_consts(lua_State *L)
{
    /* {{{ HTTP status constants */
    lua_pushinteger(L, NGX_HTTP_GET);
    lua_setfield(L, -2, "HTTP_GET");

    lua_pushinteger(L, NGX_HTTP_POST);
    lua_setfield(L, -2, "HTTP_POST");

    lua_pushinteger(L, NGX_HTTP_PUT);
    lua_setfield(L, -2, "HTTP_PUT");

    lua_pushinteger(L, NGX_HTTP_DELETE);
    lua_setfield(L, -2, "HTTP_DELETE");

    lua_pushinteger(L, NGX_HTTP_HEAD);
    lua_setfield(L, -2, "HTTP_HEAD");

    lua_pushinteger(L, 200);
    lua_setfield(L, -2, "HTTP_OK");

    lua_pushinteger(L, 201);
    lua_setfield(L, -2, "HTTP_CREATED");

    lua_pushinteger(L, 301);
    lua_setfield(L, -2, "HTTP_MOVED_PERMANENTLY");

    lua_pushinteger(L, 302);
    lua_setfield(L, -2, "HTTP_MOVED_TEMPORARILY");

    lua_pushinteger(L, 304);
    lua_setfield(L, -2, "HTTP_NOT_MODIFIED");

    lua_pushinteger(L, 400);
    lua_setfield(L, -2, "HTTP_BAD_REQUEST");

    lua_pushinteger(L, 410);
    lua_setfield(L, -2, "HTTP_GONE");

    lua_pushinteger(L, 404);
    lua_setfield(L, -2, "HTTP_NOT_FOUND");

    lua_pushinteger(L, 405);
    lua_setfield(L, -2, "HTTP_NOT_ALLOWED");

    lua_pushinteger(L, 403);
    lua_setfield(L, -2, "HTTP_FORBIDDEN");

    lua_pushinteger(L, 500);
    lua_setfield(L, -2, "HTTP_INTERNAL_SERVER_ERROR");

    lua_pushinteger(L, 503);
    lua_setfield(L, -2, "HTTP_SERVICE_UNAVAILABLE");
    /* }}} */
}

void
ngx_http_lua_inject_log_consts(lua_State *L)
{
    /* {{{ NginX log level constants */
    lua_pushinteger(L, NGX_LOG_STDERR);
    lua_setfield(L, -2, "STDERR");

    lua_pushinteger(L, NGX_LOG_EMERG);
    lua_setfield(L, -2, "EMERG");

    lua_pushinteger(L, NGX_LOG_ALERT);
    lua_setfield(L, -2, "ALERT");

    lua_pushinteger(L, NGX_LOG_CRIT);
    lua_setfield(L, -2, "CRIT");

    lua_pushinteger(L, NGX_LOG_ERR);
    lua_setfield(L, -2, "ERR");

    lua_pushinteger(L, NGX_LOG_WARN);
    lua_setfield(L, -2, "WARN");

    lua_pushinteger(L, NGX_LOG_NOTICE);
    lua_setfield(L, -2, "NOTICE");

    lua_pushinteger(L, NGX_LOG_INFO);
    lua_setfield(L, -2, "INFO");

    lua_pushinteger(L, NGX_LOG_DEBUG);
    lua_setfield(L, -2, "DEBUG");
    /* }}} */
}

static void
init_ngx_lua_globals(lua_State *L)
{
    /* {{{ remove unsupported globals */
    lua_pushnil(L);
    lua_setfield(L, LUA_GLOBALSINDEX, "coroutine");
    /* }}} */

    /* {{{ register global hook functions */
    lua_pushcfunction(L, ngx_http_lua_print);
    lua_setglobal(L, "print");
    /* }}} */

    lua_createtable(L, 0, 1);    /* ndk.* */

    lua_newtable(L);    /* .set_var */

    lua_createtable(L, 0, 2); /* metatable for .set_var */
    lua_pushcfunction(L, ngx_http_lua_ndk_set_var_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ndk_set_var_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "set_var");

    lua_setglobal(L, "ndk");

    lua_createtable(L, 0, 20);    /* ngx.* */

    /* {{{ register nginx hook functions */
    lua_pushcfunction(L, ngx_http_lua_ngx_exec);
    lua_setfield(L, -2, "exec");

    lua_pushcfunction(L, ngx_http_lua_ngx_send_headers);
    lua_setfield(L, -2, "send_headers");

    lua_pushcfunction(L, ngx_http_lua_ngx_print);
    lua_setfield(L, -2, "print");

    lua_pushcfunction(L, ngx_http_lua_ngx_say);
    lua_setfield(L, -2, "say");

    lua_pushcfunction(L, ngx_http_lua_ngx_log);
    lua_setfield(L, -2, "log");

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "throw_error"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "exit");

    lua_pushcfunction(L, ngx_http_lua_ngx_flush);
    lua_setfield(L, -2, "flush");

    lua_pushcfunction(L, ngx_http_lua_ngx_eof);
    lua_setfield(L, -2, "eof");

    lua_pushcfunction(L, ngx_http_lua_ngx_escape_uri);
    lua_setfield(L, -2, "escape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_unescape_uri);
    lua_setfield(L, -2, "unescape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_quote_sql_str);
    lua_setfield(L, -2, "quote_sql_str");

    lua_pushcfunction(L, ngx_http_lua_ngx_decode_base64);
    lua_setfield(L, -2, "decode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_encode_base64);
    lua_setfield(L, -2, "encode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5_bin);
    lua_setfield(L, -2, "md5_bin");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5);
    lua_setfield(L, -2, "md5");

    lua_pushcfunction(L, ngx_http_lua_ngx_utctime);
    lua_setfield(L, -2, "utctime");

    lua_pushcfunction(L, ngx_http_lua_ngx_time);
    lua_setfield(L, -2, "get_now_ts"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_localtime);
    lua_setfield(L, -2, "get_now"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_localtime);
    lua_setfield(L, -2, "localtime");

    lua_pushcfunction(L, ngx_http_lua_ngx_time);
    lua_setfield(L, -2, "time");

    lua_pushcfunction(L, ngx_http_lua_ngx_today);
    lua_setfield(L, -2, "get_today"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_today);
    lua_setfield(L, -2, "today");

    lua_pushcfunction(L, ngx_http_lua_ngx_cookie_time);
    lua_setfield(L, -2, "cookie_time");

    lua_pushcfunction(L, ngx_http_lua_ngx_redirect);
    lua_setfield(L, -2, "redirect");

    lua_createtable(L, 0, 2); /* .location */

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture);
    lua_setfield(L, -2, "capture");

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture_multi);
    lua_setfield(L, -2, "capture_multi");

    lua_setfield(L, -2, "location");

    /* }}} */

    inject_http_consts(L);
    ngx_http_lua_inject_log_consts(L);
    inject_core_consts(L);

    /* {{{ register reference maps */
    lua_newtable(L);    /* .var */

    lua_createtable(L, 0, 2); /* metatable for .var */
    lua_pushcfunction(L, ngx_http_lua_var_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_var_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "var");

#if 1
    lua_newtable(L);    /* .header */

    lua_createtable(L, 0, 2); /* metatable for .header */
    lua_pushcfunction(L, ngx_http_lua_header_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_header_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "header");
#endif

    /* ngx. getter and setter */
    lua_createtable(L, 0, 2); /* metatable for .ngx */
    lua_pushcfunction(L, ngx_http_lua_ngx_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    /*  }}} */

    lua_setglobal(L, "ngx");
}


/**
 * Get nginx internal variables content
 *
 * @retval Always return a string or nil on Lua stack. Return nil when failed
 * to get content, and actual content string when found the specified variable.
 * @seealso ngx_http_lua_var_set
 * */
int
ngx_http_lua_var_get(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p, *lowcase;
    size_t                       len;
    ngx_uint_t                   hash;
    ngx_str_t                    name;
    ngx_http_variable_value_t   *vv;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = (u_char *) luaL_checklstring(L, -1, &len);

    lowcase = ngx_palloc(r->pool, len);
    if (lowcase == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    hash = ngx_hash_strlow(lowcase, p, len);

    name.len = len;
    name.data = lowcase;

#if defined(nginx_version) && \
    (nginx_version >= 8036 || \
     (nginx_version < 8000 && nginx_version >= 7066))
    vv = ngx_http_get_variable(r, &name, hash);
#else
    vv = ngx_http_get_variable(r, &name, hash, 1);
#endif

    if (vv == NULL || vv->not_found) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlstring(L, (const char*) vv->data, (size_t) vv->len);

    return 1;
}


/**
 * Set nginx internal variable content
 *
 * @retval Always return a boolean on Lua stack. Return true when variable
 * content was modified successfully, false otherwise.
 * @seealso ngx_http_lua_var_get
 * */
int
ngx_http_lua_var_set(lua_State *L)
{
    ngx_http_variable_value_t   *vv;
    u_char                      *p, *lowcase, *val;
    size_t                       len;
    ngx_str_t                    name;
    ngx_uint_t                   hash;
    ngx_http_request_t          *r;

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    lowcase = ngx_palloc(r->pool, len + 1);
    if (lowcase == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    lowcase[len] = '\0';

    hash = ngx_hash_strlow(lowcase, p, len);

    name.len = len;
    name.data = lowcase;

#if defined(nginx_version) && \
    (nginx_version >= 8036 || \
     (nginx_version < 8000 && nginx_version >= 7066))
    vv = ngx_http_get_variable(r, &name, hash);
#else
    vv = ngx_http_get_variable(r, &name, hash, 1);
#endif

    if (vv == NULL || vv->not_found) {
        return luaL_error(L, "variable \"%s\" not defined yet; "
                "you sould have used \"set $%s '';\" earlier "
                "in the config file", lowcase, lowcase);
    }

    p = (u_char*) luaL_checklstring(L, 3, &len);

    val = ngx_palloc(r->pool, len);
    if (val == NULL) {
        return luaL_error(L, "memory allocation erorr");
    }

    ngx_memcpy(val, p, len);

    vv->valid = 1;
    vv->not_found = 0;

    vv->data = val;
    vv->len = len;

    return 0;
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
        cl->buf->file_pos = cl->buf->file_last;
    }
}


ngx_int_t
ngx_http_lua_add_copy_chain(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
        ngx_chain_t **chain, ngx_chain_t *in)
{
    ngx_chain_t     *cl, **ll;
    size_t           len;
    ngx_buf_t       *b;

    ll = chain;

    for (cl = *chain; cl; cl = cl->next) {
        ll = &cl->next;
    }

    len = 0;

    for (cl = in; cl; cl = cl->next) {
        if (ngx_buf_in_memory(cl->buf)) {
            len += cl->buf->last - cl->buf->pos;
        }
    }

    if (len == 0) {
        return NGX_OK;
    }

    cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    b = cl->buf;

    b->start = ngx_palloc(r->pool, len);
    if (b->start == NULL) {
        return NGX_ERROR;
    }

    b->end = b->start + len;

    b->pos  = b->start;
    b->last = b->pos;
    b->memory = 1;

#if 0
    b->tag = (ngx_buf_tag_t) &ngx_http_lua_module;
#endif

    while (in) {
        if (ngx_buf_in_memory(in->buf)) {
            b->last = ngx_copy(b->last, in->buf->pos,
                    in->buf->last - in->buf->pos);
        }

        in = in->next;
    }

    *ll = cl;
    cl->next = NULL;

    return NGX_OK;
}


void
ngx_http_lua_reset_ctx(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_ctx_t *ctx)
{
    if (ctx->cc_ref != LUA_NOREF) {
        ngx_http_lua_del_thread(r, L, ctx->cc_ref, 0);
        ctx->cc_ref = LUA_NOREF;
    }

    ctx->waiting = 0;
    ctx->done = 0;

    ctx->entered_rewrite_phase = 0;
    ctx->entered_access_phase = 0;

    ctx->exit_code = 0;
    ctx->exited = 0;
    ctx->exec_uri.data = NULL;
    ctx->exec_uri.len = 0;

    ctx->sr_statuses = NULL;
    ctx->sr_headers = NULL;
    ctx->sr_bodies = NULL;
}


/* post read callback for rewrite and access phases */
void
ngx_http_lua_generic_phase_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    r->read_event_handler = ngx_http_request_empty_handler;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;
        ngx_http_core_run_phases(r);
    }
}


void
ngx_http_lua_request_cleanup(void *data)
{
    ngx_http_request_t          *r = data;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_ctx_t          *ctx;
    lua_State                   *L;

    dd("(lua-request-cleanup) force request coroutine quit");

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    /*  force coroutine handling the request quit */
    if (ctx == NULL) {
        return;
    }

    if (ctx->cleanup) {
        *ctx->cleanup = NULL;
        ctx->cleanup = NULL;
    }

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
    lua_rawgeti(L, -1, ctx->cc_ref);

    if (lua_isthread(L, -1)) {
        /*  coroutine not finished yet, force quit */
        ngx_http_lua_del_thread(r, L, ctx->cc_ref, 1);
        ctx->cc_ref = LUA_NOREF;
    }

    lua_pop(L, 2);
}


ngx_int_t
ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int nret)
{
    int                      rv;
    int                      cc_ref;
    lua_State               *cc;
    const char              *err, *msg;
    ngx_int_t                rc;

    /* set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    dd("ctx = %p", ctx);

    NGX_LUA_EXCEPTION_TRY {
        cc = ctx->cc;
        cc_ref = ctx->cc_ref;

        /*  run code */
        rv = lua_resume(cc, nret);

        dd("lua resume returns %d", (int) rv);

        switch (rv) {
            case LUA_YIELD:
                /*  yielded, let event handler do the rest job */
                /*  FIXME: add io cmd dispatcher here */

                dd("lua coroutine yielded");

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                lua_settop(cc, 0);
                return NGX_AGAIN;

            case 0:
                dd("normal end %.*s", (int) r->uri.len, r->uri.data);

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                ngx_http_lua_del_thread(r, L, cc_ref, 0);
                ctx->cc_ref = LUA_NOREF;

                if (ctx->cleanup) {
                    dd("cleaning up cleanup");
                    *ctx->cleanup = NULL;
                    ctx->cleanup = NULL;
                }

                if (ctx->entered_content_phase) {
                    rc = ngx_http_lua_send_chain_link(r, ctx,
                            NULL /* indicate last_buf */);

                    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                        return rc;
                    }
                }

                return NGX_OK;

            case LUA_ERRRUN:
                err = "runtime error";
                break;

            case LUA_ERRSYNTAX:
                err = "syntax error";
                break;

            case LUA_ERRMEM:
                err = "memory allocation error";
                break;

            case LUA_ERRERR:
                err = "error handler error";
                break;

            default:
                err = "unknown error";
                break;
        }

        if (lua_isstring(cc, -1)) {
            dd("user custom error msg");
            msg = lua_tostring(cc, -1);

        } else {
            if (lua_isnil(cc, -1)) {
                if (ctx->exited) {
                    dd("run here...exiting... %d", (int) ctx->exit_code);

                    ngx_http_lua_del_thread(r, L, cc_ref, 0);
                    ctx->cc_ref = LUA_NOREF;

                    if (ctx->cleanup) {
                        *ctx->cleanup = NULL;
                        ctx->cleanup = NULL;
                    }

                    if (ctx->exit_code == NGX_OK) {
                        if (ctx->entered_content_phase) {
                            rc = ngx_http_lua_send_chain_link(r, ctx,
                                    NULL /* indicate last_buf */);

                            if (rc == NGX_ERROR ||
                                    rc >= NGX_HTTP_SPECIAL_RESPONSE)
                            {
                                return rc;
                            }
                        }
                    }

                    return ctx->exit_code;
                }

                if (ctx->exec_uri.len) {
                    ngx_http_lua_del_thread(r, L, cc_ref, 0);
                    ctx->cc_ref = LUA_NOREF;

                    if (ctx->cleanup) {
                        *ctx->cleanup = NULL;
                        ctx->cleanup = NULL;
                    }

                    if (ctx->exec_uri.data[0] == '@') {
                        if (ctx->exec_args.len > 0) {
                            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                                    "query strings %V ignored when exec'ing "
                                    "named location %V",
                                    &ctx->exec_args, &ctx->exec_uri);
                        }

#if defined(nginx_version) && nginx_version >= 8011
                        /* ngx_http_named_location always increments
                         * r->main->count, which is not we want for
                         * non-content phases */

                        if (! ctx->entered_content_phase) {
                            r->main->count--;
                        }
#endif

                        return ngx_http_named_location(r, &ctx->exec_uri);
                    }

                    dd("internal redirect to %.*s", (int) ctx->exec_uri.len,
                            ctx->exec_uri.data);

#if defined(nginx_version) && nginx_version >= 8011
                    /* ngx_http_internal_redirect always increments
                     * r->main->count, which is not we want for
                     * non-content phases */

                    if (! ctx->entered_content_phase) {
                        r->main->count--;
                    }
#endif

                    return ngx_http_internal_redirect(r, &ctx->exec_uri,
                            &ctx->exec_args);
                }
            }

            msg = "unknown reason";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "content_by_lua aborted: %s: %s",
                err, msg);

        ngx_http_lua_del_thread(r, L, cc_ref, 0);
        ctx->cc_ref = LUA_NOREF;

        if (ctx->cleanup) {
            *ctx->cleanup = NULL;
            ctx->cleanup = NULL;
        }

        dd("headers sent? %d", ctx->headers_sent ? 1 : 0);

        return ctx->headers_sent ? NGX_ERROR : NGX_HTTP_INTERNAL_SERVER_ERROR;

    } NGX_LUA_EXCEPTION_CATCH {
        dd("NginX execution restored");
    }

    return NGX_ERROR;
}


ngx_int_t
ngx_http_lua_wev_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_main_conf_t    *lmcf;
    lua_State                   *cc;
    ngx_str_t                   *body_str;
    ngx_http_headers_out_t      *sr_headers;
    ngx_list_part_t             *part;
    ngx_table_elt_t             *header;
    ngx_uint_t                   i, index;

    dd("wev handler %.*s %.*s a:%d, postponed:%p",
            (int) r->uri.len, r->uri.data,
            (int) ngx_cached_err_log_time.len,
            ngx_cached_err_log_time.data,
            r == r->connection->data,
            r->postponed);
#if 0
    ngx_http_lua_dump_postponed(r);
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        goto error;
    }

    dd("ctx = %p", ctx);
    dd("request done: %d", (int) r->done);
    dd("cleanup done: %p", ctx->cleanup);

    if (ctx->cleanup == NULL) {
        /* already done */
        dd("cleanup is null: %.*s", (int) r->uri.len, r->uri.data);

        if (ctx->entered_content_phase) {
            ngx_http_finalize_request(r,
                    ngx_http_lua_flush_postponed_outputs(r));
        }

        return NGX_DONE;
    }

    dd("waiting: %d, done: %d", (int) ctx->waiting,
            ctx->done);

    if (ctx->waiting && ! ctx->done) {
        dd("%.*s waiting and not done", (int) r->uri.len, r->uri.data);

#if 0
        ngx_http_lua_dump_postponed(r);
#endif

        if (r == r->connection->data && r->postponed) {
            if (r->postponed->request) {
                r->connection->data = r->postponed->request;

#if defined(nginx_version) && nginx_version >= 8012
                ngx_http_post_request(r->postponed->request, NULL);
#else
                ngx_http_post_request(r->postponed->request);
#endif

            } else {
                ngx_http_lua_flush_postponed_outputs(r);
            }
        }

        return NGX_DONE;
    }

    ctx->done = 0;

    dd("nsubreqs: %d", (int) ctx->nsubreqs);

    for (index = 0; index < ctx->nsubreqs; index++) {
        dd("summary: reqs %d, subquery %d, waiting %d, req %.*s",
                (int) ctx->nsubreqs,
                (int) index,
                (int) ctx->waiting,
                (int) r->uri.len, r->uri.data);

        cc = ctx->cc;

        /*  {{{ construct ret value */
        lua_newtable(cc);

        /*  copy captured status */
        lua_pushinteger(cc, ctx->sr_statuses[index]);
        lua_setfield(cc, -2, "status");

        /*  copy captured body */

        body_str = &ctx->sr_bodies[index];

        lua_pushlstring(cc, (char *) body_str->data, body_str->len);
        lua_setfield(cc, -2, "body");

        if (body_str->data) {
            dd("free body buffer ASAP");
            ngx_pfree(r->pool, body_str->data);
        }

        /* copy captured headers */

        lua_newtable(cc); /* res.header */

        sr_headers = ctx->sr_headers[index];

        if (sr_headers->content_length == NULL
            && sr_headers->content_length_n >= 0)
        {
            lua_pushliteral(cc, "Content-Length"); /* header key */

            lua_pushnumber(cc, sr_headers->content_length_n);
                /* head key value */

            lua_rawset(cc, -3); /* head */
        }

        if (sr_headers->content_type.len) {
            lua_pushliteral(cc, "Content-Type"); /* header key */
            lua_pushlstring(cc, (char *) sr_headers->content_type.data,
                    sr_headers->content_type.len); /* head key value */
            lua_rawset(cc, -3); /* head */
        }

        dd("saving subrequest response headers");

        part = &sr_headers->headers.part;
        header = part->elts;

        for (i = 0; /* void */; i++) {

            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                header = part->elts;
                i = 0;
            }

            dd("checking sr header %.*s", (int) header[i].key.len,
                    header[i].key.data);

#if 1
            if (header[i].hash == 0) {
                continue;
            }
#endif

            dd("pushing sr header %.*s", (int) header[i].key.len,
                    header[i].key.data);

            lua_pushlstring(cc, (char *) header[i].key.data,
                    header[i].key.len); /* header key */
            lua_pushvalue(cc, -1); /* stack: table key key */

            /* check if header already exists */
            lua_rawget(cc, -3); /* stack: table key value */

            if (lua_isnil(cc, -1)) {
                lua_pop(cc, 1); /* stack: table key */

                lua_pushlstring(cc, (char *) header[i].value.data,
                        header[i].value.len); /* stack: table key value */

                lua_rawset(cc, -3); /* stack: table */

            } else {
                if (! lua_istable(cc, -1)) { /* already inserted one value */
                    lua_createtable(cc, 4, 0);
                        /* stack: table key value table */

                    lua_insert(cc, -2); /* stack: table key table value */
                    lua_rawseti(cc, -2, 1); /* stack: table key table */

                    lua_pushlstring(cc, (char *) header[i].value.data,
                            header[i].value.len);
                        /* stack: table key table value */

                    lua_rawseti(cc, -2, lua_objlen(cc, -2) + 1);
                        /* stack: table key table */

                    lua_rawset(cc, -3); /* stack: table */

                } else {
                    lua_pushlstring(cc, (char *) header[i].value.data,
                            header[i].value.len);
                        /* stack: table key table value */

                    lua_rawseti(cc, -2, lua_objlen(cc, -2) + 1);
                        /* stack: table key table */

                    lua_pop(cc, 2); /* stack: table */
                }
            }
        }

        lua_setfield(cc, -2, "header");

        /*  }}} */
    }

    dd("free sr_statues/headers/bodies memory ASAP");

#if 1
    ngx_pfree(r->pool, ctx->sr_statuses);

    ctx->sr_statuses = NULL;
    ctx->sr_headers = NULL;
    ctx->sr_bodies = NULL;
#endif

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    dd("about to run thread for %.*s...", (int) r->uri.len, r->uri.data);

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, ctx->nsubreqs);

    dd("already run thread for %.*s...", (int) r->uri.len, r->uri.data);

    if (rc == NGX_AGAIN || rc == NGX_DONE) {
        return NGX_DONE;
    }

    dd("entered content phase: %d", (int) ctx->entered_content_phase);

    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r, rc);
    }

    if (rc == NGX_OK) {
        return NGX_DECLINED;
    }

    return rc;

error:
    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r,
                ctx->headers_sent ? NGX_ERROR: NGX_HTTP_INTERNAL_SERVER_ERROR);
    }

    return NGX_ERROR;
}


u_char *
ngx_http_lua_digest_hex(u_char *dest, const u_char *buf, int buf_len)
{
    u_char digest[MD5_DIGEST_LENGTH];
    MD5(buf, buf_len, digest);
    return ngx_hex_dump(dest, digest, sizeof(digest));
}


void
ngx_http_lua_dump_postponed(ngx_http_request_t *r)
{
    ngx_http_postponed_request_t    *pr;
    ngx_uint_t                       i;
    ngx_str_t                        out;
    size_t                           len;
    ngx_chain_t                     *cl;
    u_char                          *p;
    ngx_str_t                        nil_str;

    ngx_str_set(&nil_str, "(nil)");

    for (i = 0, pr = r->postponed; pr; pr = pr->next, i++) {
        out.data = NULL;
        out.len = 0;

        len = 0;
        for (cl = pr->out; cl; cl = cl->next) {
            len += ngx_buf_size(cl->buf);
        }

        if (len) {
            p = ngx_palloc(r->pool, len);
            if (p == NULL) {
                return;
            }

            out.data = p;

            for (cl = pr->out; cl; cl = cl->next) {
                p = ngx_copy(p, cl->buf->pos, ngx_buf_size(cl->buf));
            }

            out.len = len;
        }

        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                "postponed request for %V: "

#if defined(nginx_version) && nginx_version >= 8011
                "c:%d, "
#endif

                "a:%d, i:%d, r:%V, out:%V",
                &r->uri,

#if defined(nginx_version) && nginx_version >= 8011
                r->main->count,
#endif

                r == r->connection->data, i,
                pr->request ? &pr->request->uri : &nil_str, &out);
    }
}


ngx_int_t
ngx_http_lua_flush_postponed_outputs(ngx_http_request_t *r)
{
    if (r == r->connection->data && r->postponed) {
        /* notify the downstream postpone filter to flush the postponed
         * outputs of the current request */
        return ngx_http_lua_next_body_filter(r, NULL);
    }

    /* do nothing */
    return NGX_OK;
}

