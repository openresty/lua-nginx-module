/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "nginx.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_patch.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_args.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_echo.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_redirect.h"
#include "ngx_http_lua_ndk.h"
#include "ngx_http_lua_subrequest.h"
#include "ngx_http_lua_log.h"


static ngx_int_t ngx_http_lua_send_http10_headers(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx);
static void init_ngx_lua_registry(ngx_conf_t *cf, lua_State *L);
static void init_ngx_lua_globals(ngx_conf_t *cf, lua_State *L);
static void ngx_http_lua_set_path(ngx_conf_t *cf, lua_State *L, int tab_idx,
        const char *fieldname, const char *path, const char *default_path);
static void ngx_http_lua_inject_log_consts(lua_State *L);


#ifndef LUA_PATH_SEP
#define LUA_PATH_SEP ";"
#endif

#define AUX_MARK "\1"


static void
ngx_http_lua_set_path(ngx_conf_t *cf, lua_State *L, int tab_idx,
        const char *fieldname, const char *path, const char *default_path)
{
    const char *tmp_path;

    /* XXX here we use some hack to simplify string manipulation */
    tmp_path = luaL_gsub(L, path, LUA_PATH_SEP LUA_PATH_SEP,
            LUA_PATH_SEP AUX_MARK LUA_PATH_SEP);

    dd("tmp_path path: %s", tmp_path);

    tmp_path = luaL_gsub(L, tmp_path, AUX_MARK, default_path);

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua setting lua package.%s to \"%s\"", fieldname, tmp_path);

    lua_remove(L, -2);

    /* fix negative index as there's new data on stack */
    tab_idx = (tab_idx < 0) ? (tab_idx - 1) : tab_idx;
    lua_setfield(L, tab_idx, fieldname);
}


lua_State *
ngx_http_lua_new_state(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
    lua_State       *L;
    const char      *old_path;
    const char      *new_path;
    size_t           old_path_len;
    const char      *old_cpath;
    const char      *new_cpath;
    size_t           old_cpath_len;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0, "lua creating new vm state");

    L = luaL_newstate();
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

#ifdef LUA_DEFAULT_PATH
#   define LUA_DEFAULT_PATH_LEN (sizeof(LUA_DEFAULT_PATH) - 1)
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua prepending default package.path with %s", LUA_DEFAULT_PATH);

    lua_pushliteral(L, LUA_DEFAULT_PATH ";"); /* package default */
    lua_getfield(L, -2, "path"); /* package default old */
    old_path = lua_tolstring(L, -1, &old_path_len);
    lua_concat(L, 2); /* package new */
    lua_setfield(L, -2, "path"); /* package */
#endif

#ifdef LUA_DEFAULT_CPATH
#   define LUA_DEFAULT_CPATH_LEN (sizeof(LUA_DEFAULT_CPATH) - 1)
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua prepending default package.cpath with %s", LUA_DEFAULT_CPATH);

    lua_pushliteral(L, LUA_DEFAULT_CPATH ";"); /* package default */
    lua_getfield(L, -2, "cpath"); /* package default old */
    old_cpath = lua_tolstring(L, -1, &old_cpath_len);
    lua_concat(L, 2); /* package new */
    lua_setfield(L, -2, "cpath"); /* package */
#endif

    if (lmcf->lua_path.len != 0) {
        lua_getfield(L, -1, "path"); /* get original package.path */
        old_path = lua_tolstring(L, -1, &old_path_len);

        dd("old path: %s", old_path);

        lua_pushlstring(L, (char *) lmcf->lua_path.data, lmcf->lua_path.len);
        new_path = lua_tostring(L, -1);

        ngx_http_lua_set_path(cf, L, -3, "path", new_path, old_path);

        lua_pop(L, 2);
    }

    if (lmcf->lua_cpath.len != 0) {
        lua_getfield(L, -1, "cpath"); /* get original package.cpath */
        old_cpath = lua_tolstring(L, -1, &old_cpath_len);

        dd("old cpath: %s", old_cpath);

        lua_pushlstring(L, (char *) lmcf->lua_cpath.data, lmcf->lua_cpath.len);
        new_cpath = lua_tostring(L, -1);

        ngx_http_lua_set_path(cf, L, -3, "cpath", new_cpath, old_cpath);


        lua_pop(L, 2);
    }

    lua_remove(L, -1); /* remove the "package" table */

    init_ngx_lua_registry(cf, L);
    init_ngx_lua_globals(cf, L);

    return L;
}


lua_State *
ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *L, int *ref)
{
    int              top;
    lua_State       *cr;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua creating new thread");

    top = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);

    cr = lua_newthread(L);

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
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua deleting thread");

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
    ngx_int_t            rc;

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
            dd("sending headers");
            rc = ngx_http_send_header(r);
            ctx->headers_sent = 1;
            return rc;
        }
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_send_chain_link(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx,
        ngx_chain_t *in)
{
    ngx_int_t            rc;
    ngx_chain_t         *cl;
    ngx_chain_t        **ll;

#if 1
    if (ctx->eof) {
        dd("ctx->eof already set");
        return NGX_OK;
    }
#endif

    if (!r->header_only && (r->method & NGX_HTTP_HEAD)) {
        r->header_only = 1;
    }

    rc = ngx_http_lua_send_header_if_needed(r, ctx);

    if (rc == NGX_ERROR || rc > NGX_OK) {
        return rc;
    }

    if (r->header_only) {
        ctx->eof = 1;

        if (r->http_version < NGX_HTTP_VERSION_11) {
            return ngx_http_lua_send_http10_headers(r, ctx);
        }

        return rc;
    }

    if (in == NULL) {
        if (r->http_version < NGX_HTTP_VERSION_11) {
            rc = ngx_http_lua_send_http10_headers(r, ctx);
            if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                return rc;
            }

            if (ctx->out) {
                rc = ngx_http_output_filter(r, ctx->out);

                if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                    return rc;
                }

                ctx->out = NULL;
            }
        }

#if defined(nginx_version) && nginx_version <= 8004

        /* earlier versions of nginx does not allow subrequests
           to send last_buf themselves */
        if (r != r->main) {
            return NGX_OK;
        }

#endif

        ctx->eof = 1;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua sending last buf of the response body");

        rc = ngx_http_send_special(r, NGX_HTTP_LAST);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return rc;
        }

        return NGX_OK;
    }

    /* in != NULL */

    if (r->http_version < NGX_HTTP_VERSION_11 && !ctx->headers_sent) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua buffering output bufs for the HTTP 1.0 request");

        for (cl = ctx->out, ll = &ctx->out; cl; cl = cl->next) {
            ll = &cl->next;
        }

        *ll = in;

        return NGX_OK;
    }

    return ngx_http_output_filter(r, in);
}


static ngx_int_t
ngx_http_lua_send_http10_headers(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx)
{
    size_t               size;
    ngx_chain_t         *cl;
    ngx_int_t            rc;

    if (ctx->headers_sent) {
        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua sending HTTP 1.0 response headers");

    if (r->header_only) {
        goto send;
    }

    if (r->headers_out.content_length == NULL) {
        for (size = 0, cl = ctx->out; cl; cl = cl->next) {
            size += ngx_buf_size(cl->buf);
        }

        r->headers_out.content_length_n = (off_t) size;

        if (r->headers_out.content_length) {
            r->headers_out.content_length->hash = 0;
        }
    }

send:
    rc = ngx_http_send_header(r);
    ctx->headers_sent = 1;
    return rc;
}


static void
init_ngx_lua_registry(ngx_conf_t *cf, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua initializing lua registry");

    /* {{{ register table to anchor lua coroutines reliablly:
     * {([int]ref) = [cort]} */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
    /* }}} */

    /* create registry entry for the Lua request ctx data table */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);

    /* create registry entry for the Lua request ctx data table */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, NGX_LUA_REGEX_CACHE);

    /* {{{ register table to cache user code:
     * {([string]cache_key) = [code closure]} */
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);
    /* }}} */
}


void
ngx_http_lua_inject_core_consts(lua_State *L)
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


void
ngx_http_lua_inject_http_consts(lua_State *L)
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

    lua_pushinteger(L, NGX_HTTP_OK);
    lua_setfield(L, -2, "HTTP_OK");

    lua_pushinteger(L, NGX_HTTP_CREATED);
    lua_setfield(L, -2, "HTTP_CREATED");

    lua_pushinteger(L, NGX_HTTP_SPECIAL_RESPONSE);
    lua_setfield(L, -2, "HTTP_SPECIAL_RESPONSE");

    lua_pushinteger(L, NGX_HTTP_MOVED_PERMANENTLY);
    lua_setfield(L, -2, "HTTP_MOVED_PERMANENTLY");

    lua_pushinteger(L, NGX_HTTP_MOVED_TEMPORARILY);
    lua_setfield(L, -2, "HTTP_MOVED_TEMPORARILY");

#if defined(nginx_version) && nginx_version >= 8042
    lua_pushinteger(L, NGX_HTTP_SEE_OTHER);
    lua_setfield(L, -2, "HTTP_SEE_OTHER");
#endif

    lua_pushinteger(L, NGX_HTTP_NOT_MODIFIED);
    lua_setfield(L, -2, "HTTP_NOT_MODIFIED");

    lua_pushinteger(L, NGX_HTTP_BAD_REQUEST);
    lua_setfield(L, -2, "HTTP_BAD_REQUEST");

    lua_pushinteger(L, NGX_HTTP_UNAUTHORIZED);
    lua_setfield(L, -2, "HTTP_UNAUTHORIZED");


    lua_pushinteger(L, NGX_HTTP_FORBIDDEN);
    lua_setfield(L, -2, "HTTP_FORBIDDEN");

    lua_pushinteger(L, NGX_HTTP_NOT_FOUND);
    lua_setfield(L, -2, "HTTP_NOT_FOUND");

    lua_pushinteger(L, NGX_HTTP_NOT_ALLOWED);
    lua_setfield(L, -2, "HTTP_NOT_ALLOWED");

    lua_pushinteger(L, 410);
    lua_setfield(L, -2, "HTTP_GONE");

    lua_pushinteger(L, NGX_HTTP_INTERNAL_SERVER_ERROR);
    lua_setfield(L, -2, "HTTP_INTERNAL_SERVER_ERROR");

    lua_pushinteger(L, NGX_HTTP_SERVICE_UNAVAILABLE);
    lua_setfield(L, -2, "HTTP_SERVICE_UNAVAILABLE");
    /* }}} */
}


static void
ngx_http_lua_inject_log_consts(lua_State *L)
{
    /* {{{ nginx log level constants */
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
init_ngx_lua_globals(ngx_conf_t *cf, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cf->log, 0,
            "lua initializing lua globals");

    /* {{{ remove unsupported globals */
    lua_pushnil(L);
    lua_setfield(L, LUA_GLOBALSINDEX, "coroutine");
    /* }}} */

#if defined(NDK) && NDK
    ngx_http_lua_inject_ndk_api(L);
#endif /* defined(NDK) && NDK */

    lua_createtable(L, 0, 22);    /* ngx.* */

    ngx_http_lua_inject_http_consts(L);
    ngx_http_lua_inject_core_consts(L);

    ngx_http_lua_inject_log_api(L);
    ngx_http_lua_inject_output_api(L);
    ngx_http_lua_inject_time_api(L);
    ngx_http_lua_inject_string_api(L);
    ngx_http_lua_inject_control_api(L);
    ngx_http_lua_inject_subrequest_api(L);
#if (NGX_PCRE)
    ngx_http_lua_inject_regex_api(L);
#endif
    ngx_http_lua_inject_req_api(L);
    ngx_http_lua_inject_resp_header_api(L);
    ngx_http_lua_inject_variable_api(L);
    ngx_http_lua_inject_misc_api(L);

    lua_getglobal(L, "package"); /* ngx package */
    lua_getfield(L, -1, "loaded"); /* ngx package loaded */
    lua_pushvalue(L, -3); /* ngx package loaded ngx */
    lua_setfield(L, -2, "ngx"); /* ngx package loaded */
    lua_pop(L, 2);

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

#if (NGX_PCRE)
    u_char                      *val;
    ngx_uint_t                   n;
    LUA_NUMBER                   index;
    int                         *cap;
#endif

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

#if (NGX_PCRE)
    if (lua_type(L, -1) == LUA_TNUMBER) {
        /* it is a regex capturing variable */

        index = lua_tonumber(L, -1);

        if (index <= 0) {
            lua_pushnil(L);
            return 1;
        }

        n = (ngx_uint_t) index * 2;

        dd("n = %d, ncaptures = %d", (int) n, (int) r->ncaptures);

        if (r->captures == NULL || r->captures_data == NULL ||
                n >= r->ncaptures)
        {
            lua_pushnil(L);
            return 1;
        }

        /* n >= 0 && n < r->ncaptures */

        cap = r->captures;

        p = r->captures_data;

        val = &p[cap[n]];

        lua_pushlstring(L, (const char *) val, (size_t) (cap[n + 1] - cap[n]));

        return 1;
    }
#endif

    p = (u_char *) luaL_checklstring(L, -1, &len);

    lowcase = ngx_palloc(r->pool, len);
    if (lowcase == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    hash = ngx_hash_strlow(lowcase, p, len);

    name.len = len;
    name.data = lowcase;

    vv = ngx_http_get_variable(r, &name, hash);

    if (vv == NULL || vv->not_found) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlstring(L, (const char *) vv->data, (size_t) vv->len);

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
    ngx_http_variable_t         *v;
    ngx_http_variable_value_t   *vv;
    ngx_http_core_main_conf_t   *cmcf;
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

    /* we read the variable name */

    p = (u_char *) luaL_checklstring(L, 2, &len);

    lowcase = ngx_palloc(r->pool, len + 1);
    if (lowcase == NULL) {
        return luaL_error(L, "memory allocation error");
    }

    lowcase[len] = '\0';

    hash = ngx_hash_strlow(lowcase, p, len);

    name.len = len;
    name.data = lowcase;

    /* we read the variable new value */

    p = (u_char *) luaL_checklstring(L, 3, &len);

    val = ngx_palloc(r->pool, len);
    if (val == NULL) {
        return luaL_error(L, "memory allocation erorr");
    }

    ngx_memcpy(val, p, len);

    /* we fetch the variable itself */

    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    v = ngx_hash_find(&cmcf->variables_hash, hash, name.data, name.len);

    if (v) {
        if (! (v->flags & NGX_HTTP_VAR_CHANGEABLE)) {
            return luaL_error(L, "variable \"%s\" not changeable", lowcase);
        }

        if (v->set_handler) {
            vv = ngx_palloc(r->pool, sizeof(ngx_http_variable_value_t));
            if (vv == NULL) {
                return luaL_error(L, "out of memory");
            }

            vv->valid = 1;
            vv->not_found = 0;
            vv->no_cacheable = 0;

            vv->data = val;
            vv->len = len;

            v->set_handler(r, vv, v->data);

            return 0;
        }

        if (v->flags & NGX_HTTP_VAR_INDEXED) {
            vv = &r->variables[v->index];

            vv->valid = 1;
            vv->not_found = 0;
            vv->no_cacheable = 0;

            vv->data = val;
            vv->len = len;

            return 0;
        }

        return luaL_error(L, "variable \"%s\" cannot be assigned a value",
                lowcase);
    }

    /* variable not found */

    return luaL_error(L, "varaible \"%s\" not found for writing; "
                "maybe it is a built-in variable that is not changeable "
                "or you sould have used \"set $%s '';\" earlier "
                "in the config file", lowcase, lowcase);
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
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua reset ctx");

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

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua post read for rewrite/access phases");

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

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua request cleanup");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    /*  force coroutine handling the request quit */
    if (ctx == NULL) {
        return;
    }

    if (ctx->cleanup) {
        *ctx->cleanup = NULL;
        ctx->cleanup = NULL;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    if (ctx->ctx_ref != LUA_NOREF) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua release ngx.ctx");

        lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REQ_CTX_REF);
        luaL_unref(L, -1, ctx->ctx_ref);
        ctx->ctx_ref = LUA_NOREF;
        lua_pop(L, 1);
    }

    if (ctx->cc_ref == LUA_NOREF) {
        return;
    }

    lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
    lua_rawgeti(L, -1, ctx->cc_ref);

    if (lua_isthread(L, -1)) {
        /*  coroutine not finished yet, force quit */
        ngx_http_lua_del_thread(r, L, ctx->cc_ref, 1);
        ctx->cc_ref = LUA_NOREF;

    } else {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua internal error: not a thread object for the current "
                "coroutine");

        luaL_unref(L, -2, ctx->cc_ref);
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

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua run thread");

    /* set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    dd("ctx = %p", ctx);

    NGX_LUA_EXCEPTION_TRY {
        cc = ctx->cc;
        cc_ref = ctx->cc_ref;

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        ngx_http_lua_pcre_malloc_init(r->pool);
#endif

        /*  run code */
        rv = lua_resume(cc, nret);

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        ngx_http_lua_pcre_malloc_done();
#endif

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua resume returned %d", rv);

        switch (rv) {
            case LUA_YIELD:
                /*  yielded, let event handler do the rest job */
                /*  FIXME: add io cmd dispatcher here */

                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua thread yielded");

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                lua_settop(cc, 0);
                return NGX_AGAIN;

            case 0:
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua thread ended normally");

#if 0
                ngx_http_lua_dump_postponed(r);
#endif

                ngx_http_lua_del_thread(r, L, cc_ref, 0);
                ctx->cc_ref = LUA_NOREF;

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
                    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                            "lua thread aborting request with status %d",
                            ctx->exit_code);

                    ngx_http_lua_del_thread(r, L, cc_ref, 0);
                    ctx->cc_ref = LUA_NOREF;
                    ngx_http_lua_request_cleanup(r);

                    if ((ctx->exit_code == NGX_OK &&
                                ctx->entered_content_phase) ||
                                (ctx->exit_code >= NGX_HTTP_OK &&
                                ctx->exit_code < NGX_HTTP_SPECIAL_RESPONSE))
                    {
                        rc = ngx_http_lua_send_chain_link(r, ctx,
                                NULL /* indicate last_buf */);

                        if (rc == NGX_ERROR ||
                                rc >= NGX_HTTP_SPECIAL_RESPONSE)
                        {
                            return rc;
                        }
                    }

                    return ctx->exit_code;
                }

                /* ctx->exited == 0 */

                if (ctx->exec_uri.len) {
                    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                            "lua thread initiated internal redirect to %V",
                            &ctx->exec_uri);

                    ngx_http_lua_del_thread(r, L, cc_ref, 0);
                    ctx->cc_ref = LUA_NOREF;
                    ngx_http_lua_request_cleanup(r);

                    if (ctx->exec_uri.data[0] == '@') {
                        if (ctx->exec_args.len > 0) {
                            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                                    "query strings %V ignored when exec'ing "
                                    "named location %V",
                                    &ctx->exec_args, &ctx->exec_uri);
                        }

                        r->write_event_handler = ngx_http_request_empty_handler;

                        rc = ngx_http_named_location(r, &ctx->exec_uri);
                        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE)
                        {
                            return rc;
                        }

                        if (! ctx->entered_content_phase &&
                                r != r->connection->data)
                        {
                            /* XXX ensure the main request ref count
                             * is decreased because the current
                             * request will be quit */
                            r->main->count--;
                        }

                        return NGX_DONE;
                    }

                    dd("internal redirect to %.*s", (int) ctx->exec_uri.len,
                            ctx->exec_uri.data);

                    /* resume the write event handler */
                    r->write_event_handler = ngx_http_request_empty_handler;

                    rc = ngx_http_internal_redirect(r, &ctx->exec_uri,
                            &ctx->exec_args);

                    dd("internal redirect returned %d when in content phase? "
                            "%d", (int) rc, ctx->entered_content_phase);

                    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                        return rc;
                    }

                    dd("XXYY HERE %d\n", (int) r->main->count);

                    if (! ctx->entered_content_phase &&
                            r != r->connection->data)
                    {
                        /* XXX ensure the main request ref count
                         * is decreased because the current
                         * request will be quit */
                        r->main->count--;
                    }

                    return NGX_DONE;
                }
            }

            msg = "unknown reason";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "lua handler aborted: %s: %s",
                err, msg);

        ngx_http_lua_del_thread(r, L, cc_ref, 0);
        ctx->cc_ref = LUA_NOREF;
        ngx_http_lua_request_cleanup(r);

        dd("headers sent? %d", ctx->headers_sent ? 1 : 0);

        return ctx->headers_sent ? NGX_ERROR : NGX_HTTP_INTERNAL_SERVER_ERROR;

    } NGX_LUA_EXCEPTION_CATCH {
        dd("nginx execution restored");
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

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua run write event handler");

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

        return NGX_OK;
    }

    dd("waiting: %d, done: %d", (int) ctx->waiting,
            ctx->done);

    if (ctx->waiting && ! ctx->done) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua waiting for pending subrequests");

#if 0
        ngx_http_lua_dump_postponed(r);
#endif

        if (r == r->connection->data && r->postponed) {
            if (r->postponed->request) {
                ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua activating the next postponed request %V?%V",
                        &r->postponed->request->uri,
                        &r->postponed->request->args);

                r->connection->data = r->postponed->request;

#if defined(nginx_version) && nginx_version >= 8012
                ngx_http_post_request(r->postponed->request, NULL);
#else
                ngx_http_post_request(r->postponed->request);
#endif

            } else {
                ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                        "lua flushing postponed output");

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

            header[i].hash = 0;

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

        if (sr_headers->content_type.len) {
            lua_pushliteral(cc, "Content-Type"); /* header key */
            lua_pushlstring(cc, (char *) sr_headers->content_type.data,
                    sr_headers->content_type.len); /* head key value */
            lua_rawset(cc, -3); /* head */
        }

        if (sr_headers->content_length == NULL
            && sr_headers->content_length_n >= 0)
        {
            lua_pushliteral(cc, "Content-Length"); /* header key */

            lua_pushnumber(cc, sr_headers->content_length_n);
                /* head key value */

            lua_rawset(cc, -3); /* head */
        }

        /* to work-around an issue in ngx_http_static_module
         * (github issue #41) */
        if (sr_headers->location && sr_headers->location->value.len) {
            lua_pushliteral(cc, "Location"); /* header key */
            lua_pushlstring(cc, (char *) sr_headers->location->value.data,
                    sr_headers->location->value.len); /* head key value */
            lua_rawset(cc, -3); /* head */
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

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return NGX_DONE;
    }

    if (rc == NGX_DONE) {
        if (ctx->entered_content_phase) {
            ngx_http_finalize_request(r, rc);
        }

        return NGX_OK;
    }

    dd("entered content phase: %d", (int) ctx->entered_content_phase);

    if (ctx->entered_content_phase) {
        ngx_http_finalize_request(r, rc);
        return NGX_DONE;
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
    ngx_md5_t                     md5;
    u_char                        md5_buf[MD5_DIGEST_LENGTH];

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, buf, buf_len);
    ngx_md5_final(md5_buf, &md5);

    return ngx_hex_dump(dest, md5_buf, sizeof(md5_buf));
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


void
ngx_http_lua_set_multi_value_table(lua_State *L, int index)
{
    if (index < 0) {
        index = lua_gettop(L) + index + 1;
    }

    lua_pushvalue(L, -2); /* stack: table key value key */
    lua_rawget(L, index);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); /* stack: table key value */
        lua_rawset(L, index); /* stack: table */

    } else {
        if (! lua_istable(L, -1)) {
            /* just inserted one value */
            lua_createtable(L, 4, 0);
                /* stack: table key value value table */
            lua_insert(L, -2);
                /* stack: table key value table value */
            lua_rawseti(L, -2, 1);
                /* stack: table key value table */
            lua_insert(L, -2);
                /* stack: table key table value */

            lua_rawseti(L, -2, 2); /* stack: table key table */

            lua_rawset(L, index); /* stack: table */

        } else {
            /* stack: table key value table */
            lua_insert(L, -2); /* stack: table key table value */

            lua_rawseti(L, -2, lua_objlen(L, -2) + 1);
                /* stack: table key table  */
            lua_pop(L, 2); /* stack: table */
        }
    }
}


uintptr_t
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


/* XXX we also decode '+' to ' ' */
void
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


#if defined(NDK) && NDK
void
ngx_http_lua_inject_ndk_api(lua_State *L)
{
    lua_createtable(L, 0, 1);    /* ndk.* */

    lua_newtable(L);    /* .set_var */

    lua_createtable(L, 0, 2); /* metatable for .set_var */
    lua_pushcfunction(L, ngx_http_lua_ndk_set_var_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ndk_set_var_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "set_var");

    lua_getglobal(L, "package"); /* ndk package */
    lua_getfield(L, -1, "loaded"); /* ndk package loaded */
    lua_pushvalue(L, -3); /* ndk package loaded ndk */
    lua_setfield(L, -2, "ndk"); /* ndk package loaded */
    lua_pop(L, 2);

    lua_setglobal(L, "ndk");
}
#endif /* defined(NDK) && NDK */


void
ngx_http_lua_inject_time_api(lua_State *L)
{
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

    lua_pushcfunction(L, ngx_http_lua_ngx_http_time);
    lua_setfield(L, -2, "http_time");

	lua_pushcfunction(L, ngx_http_lua_ngx_parse_http_time);
    lua_setfield(L, -2, "parse_http_time");
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


void
ngx_http_lua_inject_log_api(lua_State *L)
{
    ngx_http_lua_inject_log_consts(L);

    lua_pushcfunction(L, ngx_http_lua_ngx_log);
    lua_setfield(L, -2, "log");

    lua_pushcfunction(L, ngx_http_lua_print);
    lua_setglobal(L, "print");
}


void
ngx_http_lua_inject_control_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_redirect);
    lua_setfield(L, -2, "redirect");

    lua_pushcfunction(L, ngx_http_lua_ngx_exec);
    lua_setfield(L, -2, "exec");

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "throw_error"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_exit);
    lua_setfield(L, -2, "exit");
}


void
ngx_http_lua_inject_string_api(lua_State *L)
{
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
}


void
ngx_http_lua_inject_subrequest_api(lua_State *L)
{
    lua_createtable(L, 0, 2 /* nrec */); /* .location */

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture);
    lua_setfield(L, -2, "capture");

    lua_pushcfunction(L, ngx_http_lua_ngx_location_capture_multi);
    lua_setfield(L, -2, "capture_multi");

    lua_setfield(L, -2, "location");
}


void
ngx_http_lua_inject_variable_api(lua_State *L)
{
    /* {{{ register reference maps */
    lua_newtable(L);    /* .var */

    lua_createtable(L, 0, 2 /* nrec */); /* metatable for .var */
    lua_pushcfunction(L, ngx_http_lua_var_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_var_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "var");
}


#if (NGX_PCRE)
void
ngx_http_lua_inject_regex_api(lua_State *L)
{
    /* ngx.re */

    lua_newtable(L);    /* .re */

    lua_pushcfunction(L, ngx_http_lua_ngx_re_match);
    lua_setfield(L, -2, "match");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_gmatch);
    lua_setfield(L, -2, "gmatch");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_sub);
    lua_setfield(L, -2, "sub");

    lua_pushcfunction(L, ngx_http_lua_ngx_re_gsub);
    lua_setfield(L, -2, "gsub");

    lua_setfield(L, -2, "re");
}
#endif /* NGX_PCRE */


void
ngx_http_lua_inject_req_api(lua_State *L)
{
    /* ngx.req table */

    lua_newtable(L);    /* .req */

    lua_pushcfunction(L, ngx_http_lua_ngx_req_header_clear);
    lua_setfield(L, -2, "clear_header");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_header_set);
    lua_setfield(L, -2, "set_header");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_headers);
    lua_setfield(L, -2, "get_headers");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_uri_args);
    lua_setfield(L, -2, "get_uri_args");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_uri_args);
    lua_setfield(L, -2, "get_query_args"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_post_args);
    lua_setfield(L, -2, "get_post_args");

    lua_setfield(L, -2, "req");
}


void
ngx_http_lua_inject_resp_header_api(lua_State *L)
{
    lua_newtable(L);    /* .header */

    lua_createtable(L, 0, 2); /* metatable for .header */
    lua_pushcfunction(L, ngx_http_lua_ngx_header_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_header_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "header");
}


void
ngx_http_lua_inject_misc_api(lua_State *L)
{
    /* ngx. getter and setter */
    lua_createtable(L, 0, 2); /* metatable for .ngx */
    lua_pushcfunction(L, ngx_http_lua_ngx_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);
}

