
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_server_name_resolverby.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_util.h"


static char *ngx_http_lua_server_name_resolver_by_lua(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_lua_server_name_resolver_by_chunk(lua_State *L,
    ngx_http_request_t *r, ngx_str_t *host, ngx_str_t *val);


char *
ngx_http_lua_server_name_resolver_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_server_name_resolver_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


static char *
ngx_http_lua_server_name_resolver_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#ifndef NGX_HTTP_LUA_HAVE_SERVER_NAME_RESOLVER

    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                       "server_name_resolver_by_lua_block requires nginx "
                       "with the server_name_resolver hook in "
                       "ngx_http_core_main_conf_t");

    return NGX_CONF_ERROR;

#else

    size_t                     chunkname_len;
    ngx_str_t                 *value;
    ngx_http_lua_main_conf_t  *lmcf = conf;

    if (lmcf->server_name_resolver_src_key) {
        return "\"server_name_resolver_by_lua_block\" directive is duplicate";
    }

    value = cf->args->elts;

    lmcf->server_name_resolver_src = value[1];
    lmcf->server_name_resolver_src_ref = LUA_REFNIL;

    lmcf->server_name_resolver_src_key =
        ngx_http_lua_gen_chunk_cache_key(cf, "server_name_resolver_by_lua",
                                         value[1].data, value[1].len);
    if (lmcf->server_name_resolver_src_key == NULL) {
        return NGX_CONF_ERROR;
    }

    lmcf->server_name_resolver_chunkname =
        ngx_http_lua_gen_chunk_name(cf, "server_name_resolver_by_lua",
                                    sizeof("server_name_resolver_by_lua") - 1,
                                    &chunkname_len);
    if (lmcf->server_name_resolver_chunkname == NULL) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;

#endif
}


/*
 * Called by nginx during server selection, for a TLS SNI name or a request
 * host that matches no exact server_name.  The Lua chunk cannot yield.
 */

ngx_int_t
ngx_http_lua_server_name_resolver(ngx_connection_t *c, ngx_pool_t *pool,
    ngx_str_t *host, ngx_str_t *name)
{
    lua_State                  *L;
    ngx_int_t                   rc;
    ngx_str_t                   val;
    ngx_connection_t           *fc;
    ngx_http_request_t         *r;
    ngx_pool_cleanup_t         *cln;
    ngx_http_lua_ctx_t         *ctx;
    ngx_http_conf_ctx_t        *http_ctx;
    ngx_http_lua_main_conf_t   *lmcf;

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        return NGX_DECLINED;
    }

    *fc->log = *c->log;
    fc->log->action = "running server_name_resolver_by_lua*";

    rc = NGX_DECLINED;

    r = ngx_http_lua_create_fake_request(fc);
    if (r == NULL) {
        goto done;
    }

    http_ctx = (ngx_http_conf_ctx_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                                    ngx_http_module);

    r->main_conf = http_ctx->main_conf;
    r->srv_conf = http_ctx->srv_conf;
    r->loc_conf = http_ctx->loc_conf;

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto done;
    }

    cln = ngx_pool_cleanup_add(r->pool, 0);
    if (cln == NULL) {
        goto done;
    }

    cln->handler = ngx_http_lua_request_cleanup_handler;
    cln->data = ctx;
    ctx->cleanup = &cln->handler;

    ctx->context = NGX_HTTP_LUA_CONTEXT_SERVER_NAME_RESOLVER;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = ngx_http_lua_get_lua_vm(r, ctx);

    if (ngx_http_lua_cache_loadbuffer(fc->log, L,
                                lmcf->server_name_resolver_src.data,
                                lmcf->server_name_resolver_src.len,
                                &lmcf->server_name_resolver_src_ref,
                                lmcf->server_name_resolver_src_key,
                                (const char *)
                                    lmcf->server_name_resolver_chunkname)
        != NGX_OK)
    {
        goto done;
    }

    if (ngx_http_lua_server_name_resolver_by_chunk(L, r, host, &val) != NGX_OK
        || val.len == 0)
    {
        goto done;
    }

    name->data = ngx_pnalloc(pool, val.len);
    if (name->data == NULL) {
        rc = NGX_ERROR;
        goto done;
    }

    ngx_strlow(name->data, val.data, val.len);
    name->len = val.len;

    rc = NGX_OK;

done:

    if (r) {
        ngx_http_lua_free_fake_request(r);
    }

    ngx_http_lua_close_fake_connection(fc);

    return rc;
}


static ngx_int_t
ngx_http_lua_server_name_resolver_by_chunk(lua_State *L, ngx_http_request_t *r,
    ngx_str_t *host, ngx_str_t *val)
{
    size_t           len;
    u_char          *data, *err_msg;
    ngx_int_t        rc;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    val->data = NULL;
    val->len = 0;

    /*  set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    NGX_LUA_EXCEPTION_TRY {

        /* initialize nginx context in Lua VM, code chunk at stack top sp = 1 */
        ngx_http_lua_set_req(L, r);

#ifndef OPENRESTY_LUAJIT
        /* run the chunk in a new env that inherits the globals table */
        ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);
        lua_createtable(L, 0, 1);    /*  the metatable for the new env */
        ngx_http_lua_get_globals_table(L);
        lua_setfield(L, -2, "__index");
        lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
        lua_setfenv(L, -2);    /*  set new running env for the code closure */
#endif /* OPENRESTY_LUAJIT */

        /*  the host name is the only argument of the chunk */
        lua_pushlstring(L, (const char *) host->data, host->len);

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

        lua_pushcfunction(L, ngx_http_lua_traceback);
        lua_insert(L, 1);  /* put it under chunk and args */

        /*  protected call user code */
        rc = lua_pcall(L, 1, 1, 1);

        lua_remove(L, 1);  /* remove traceback function */

#if (NGX_PCRE)
        /* XXX: work-around to nginx regex subsystem */
        ngx_http_lua_pcre_malloc_done(old_pool);
#endif

        if (rc != 0) {
            /*  error occurred when running loaded code */
            err_msg = (u_char *) lua_tolstring(L, -1, &len);

            if (err_msg == NULL) {
                err_msg = (u_char *) "unknown reason";
                len = sizeof("unknown reason") - 1;
            }

            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "failed to run server_name_resolver_by_lua*: %*s",
                          len, err_msg);

            lua_settop(L, 0);    /*  clear remaining elems on stack */

            return NGX_ERROR;
        }

        /*  only a string answer names a server; anything else declines */
        if (lua_type(L, -1) == LUA_TSTRING) {
            data = (u_char *) lua_tolstring(L, -1, &len);

            val->data = ngx_palloc(r->pool, len);
            if (val->data == NULL) {
                lua_settop(L, 0);
                return NGX_ERROR;
            }

            ngx_memcpy(val->data, data, len);
            val->len = len;
        }

    } NGX_LUA_EXCEPTION_CATCH {

        dd("nginx execution restored");
        return NGX_ERROR;
    }

    /*  clear Lua stack */
    lua_settop(L, 0);

    return NGX_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
