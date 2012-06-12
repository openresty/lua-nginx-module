/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_bodyfilterby.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_shdict.h"


static void ngx_http_lua_inject_body_filter_arg_api(lua_State *L,
       ngx_chain_t *in);
static void ngx_http_lua_body_filter_by_lua_env(lua_State *L,
        ngx_http_request_t *r, ngx_chain_t *in);
static int ngx_http_lua_body_filter_param_get(lua_State *L);


static ngx_http_output_body_filter_pt ngx_http_next_body_filter;


/* light user data key for the "ngx" table in the Lua VM regsitry */
static char ngx_http_lua_bodyfilterby_ngx_key;


/**
 * Set environment table for the given code closure.
 *
 * Before:
 *         | code closure | <- top
 *         |      ...     |
 *
 * After:
 *         | code closure | <- top
 *         |      ...     |
 * */
static void
ngx_http_lua_body_filter_by_lua_env(lua_State *L, ngx_http_request_t *r,
        ngx_chain_t *in)
{
    /*  set nginx request pointer to current lua thread's globals table */
    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_pushlightuserdata(L, r);
    lua_rawset(L, LUA_GLOBALSINDEX);

    /**
     * we want to create empty environment for current script
     *
     * setmetatable({}, {__index = _G})
     *
     * if a function or symbol is not defined in our env, __index will lookup
     * in the global env.
     *
     * all variables created in the script-env will be thrown away at the end
     * of the script run.
     * */
    lua_createtable(L, 0 /* narr */, 1 /* nrec */); /*  new empty environment */

    /*  {{{ initialize ngx.* namespace */
    lua_pushlightuserdata(L, &ngx_http_lua_bodyfilterby_ngx_key);
    lua_rawget(L, LUA_REGISTRYINDEX);

    ngx_http_lua_inject_body_filter_arg_api(L, in);

    lua_setfield(L, -2, "ngx");
    /*  }}} */

    /*  {{{ make new env inheriting main thread's globals table */
    lua_newtable(L);    /*  the metatable for the new env */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
}


ngx_int_t
ngx_http_lua_body_filter_by_chunk(lua_State *L, ngx_http_request_t *r,
        ngx_chain_t *in)
{
    ngx_int_t        rc;
    u_char          *err_msg;
    size_t           len;
    int              old_top;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    old_top = lua_gettop(L);

    /*  initialize nginx context in Lua VM, code chunk at stack top    sp = 1 */
    ngx_http_lua_body_filter_by_lua_env(L, r, in);

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

    /*  protected call user code */
    rc = lua_pcall(L, 0, 1, 0);

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    ngx_http_lua_pcre_malloc_done(old_pool);
#endif

    if (rc != 0) {
        /*  error occured when running loaded code */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run body_filter_by_lua*: %*s", len, err_msg);

        lua_settop(L, old_top);    /*  clear remaining elems on stack */

        return NGX_ERROR;
    }

    /* clear Lua stack */
    lua_settop(L, old_top);

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_body_filter_inline(ngx_http_request_t *r, ngx_chain_t *in)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf;
    char                        *err;

    dd("HERE");

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(L, llcf->body_filter_src.value.data,
            llcf->body_filter_src.value.len, llcf->body_filter_src_key,
            "body_filter_by_lua", &err, llcf->enable_code_cache ? 1 : 0);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "Failed to load Lua inlined code: %s", err);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    rc = ngx_http_lua_body_filter_by_chunk(L, r, in);

    dd("body filter by chunk returns %d", (int) rc);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_body_filter_file(ngx_http_request_t *r, ngx_chain_t *in)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    u_char                          *script_path;
    ngx_http_lua_main_conf_t        *lmcf;
    ngx_http_lua_loc_conf_t         *llcf;
    char                            *err;
    ngx_str_t                        eval_src;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    /* Eval nginx variables in code path string first */
    if (ngx_http_complex_value(r, &llcf->body_filter_src, &eval_src)
            != NGX_OK) {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
            eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    L = lmcf->lua;

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(L, script_path,
            llcf->body_filter_src_key, &err, llcf->enable_code_cache ? 1 : 0);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "Failed to load Lua inlined code: %s", err);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  make sure we have a valid code chunk */
    assert(lua_isfunction(L, -1));

    rc = ngx_http_lua_body_filter_by_chunk(L, r, in);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    ngx_http_cleanup_t          *cln;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua body filter for user lua code, uri \"%V\"", &r->uri);

    if (in == NULL) {
        return ngx_http_next_body_filter(r, in);
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->body_filter_handler == NULL) {
        dd("no body filter handler found");
        return ngx_http_next_body_filter(r, in);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        dd("setting new ctx: ctx = %p", ctx);

        ctx->cc_ref = LUA_NOREF;
        ctx->ctx_ref = LUA_NOREF;

        ngx_http_set_ctx(r, ctx, ngx_http_lua_module);
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup;
        cln->data = r;
        ctx->cleanup = &cln->handler;
    }

    dd("calling body filter handler");
    rc = llcf->body_filter_handler(r, in);
    if (rc != NGX_OK) {
        dd("calling body filter handler rc %d", (int)rc);
        return NGX_ERROR;
    }

    return ngx_http_next_body_filter(r, in);
}


ngx_int_t
ngx_http_lua_body_filter_init()
{
    dd("calling body filter init");
    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_lua_body_filter;

    return NGX_OK;
}


void
ngx_http_lua_inject_bodyfilterby_ngx_api(ngx_conf_t *cf, lua_State *L)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lua_pushlightuserdata(L, &ngx_http_lua_bodyfilterby_ngx_key);
    lua_createtable(L, 0 /* narr */, 69 /* nrec */);    /*  ngx.* */

    ngx_http_lua_inject_http_consts(L);
    ngx_http_lua_inject_core_consts(L);

    ngx_http_lua_inject_log_api(L);
    ngx_http_lua_inject_time_api(L);
    ngx_http_lua_inject_string_api(L);
#if (NGX_PCRE)
    ngx_http_lua_inject_regex_api(L);
#endif
    ngx_http_lua_inject_req_api_no_io(cf->log, L);
    ngx_http_lua_inject_resp_header_api(L);
    ngx_http_lua_inject_variable_api(L);
    ngx_http_lua_inject_shdict_api(lmcf, L);
    ngx_http_lua_inject_misc_api(L);

    lua_rawset(L, LUA_REGISTRYINDEX);
}


static void
ngx_http_lua_inject_body_filter_arg_api(lua_State *L, ngx_chain_t *in)
{
    lua_pushliteral(L, "arg");
    lua_newtable(L); /*  .arg table */

    lua_createtable(L, 0 /* narr */, 1 /* nrec */);    /*  the metatable */

    lua_pushlightuserdata(L, in);
    lua_pushcclosure(L, ngx_http_lua_body_filter_param_get, 1);

    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  tie the metatable to param table */

    lua_rawset(L, -3);    /*  set ngx.arg table */
}


static int
ngx_http_lua_body_filter_param_get(lua_State *L)
{
    u_char              *data, *p;
    size_t               size;
    ngx_chain_t         *cl;
    ngx_buf_t           *b;
    int                  idx;
    ngx_chain_t         *in;

    idx = luaL_checkint(L, 2);

    dd("index: %d", idx);

    if (idx != 1 && idx != 2) {
        lua_pushnil(L);
        return 1;
    }

    in = lua_touserdata(L, lua_upvalueindex(1));

    if (idx == 2) {
        /* asking for the eof argument */

        for (cl = in; cl; cl = cl->next) {
            if (cl->buf->last_buf) {
                lua_pushboolean(L, 1);
                return 1;
            }
        }

        lua_pushboolean(L, 0);
        return 1;
    }

    /* idx == 1 */

    size = 0;

    if (in->next == NULL) {

        dd("seen only single buffer");

        b = in->buf;
        lua_pushlstring(L, (char *) b->pos, b->last - b->pos);
        return 1;
    }

    dd("seen multiple buffers");

    for (cl = in; cl; cl = cl->next) {
        b = cl->buf;

        size += b->last - b->pos;

        if (b->last_buf) {
            break;
        }
    }

    data = (u_char *) lua_newuserdata(L, size);

    for (p = data, cl = in; cl; cl = cl->next) {
        b = cl->buf;
        p = ngx_copy(p, b->pos, b->last - b->pos);

        if (b->last_buf) {
            break;
        }
    }

    lua_pushlstring(L, (char *) data, size);
    return 1;
}

