
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"


static u_char * ngx_http_lua_log_init_worker_error(ngx_log_t *log,
    u_char *buf, size_t len);


ngx_int_t
ngx_http_lua_init_worker(ngx_cycle_t *cycle)
{
    char                        *rv;
    void                        *cur, *prev;
    ngx_uint_t                   i;
    ngx_conf_t                   conf;
    ngx_connection_t            *c = NULL;
    ngx_http_module_t           *module;
    ngx_http_request_t          *r = NULL;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_conf_ctx_t         *conf_ctx, http_ctx;
    ngx_http_lua_loc_conf_t     *llcf, *top_llcf;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_core_loc_conf_t    *clcf, *top_clcf;

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);

    if (lmcf == NULL
        || lmcf->init_worker_handler == NULL
        || lmcf->lua == NULL)
    {
        return NGX_OK;
    }

    conf_ctx = ((ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index]);
    http_ctx.main_conf = conf_ctx->main_conf;

    top_clcf = conf_ctx->loc_conf[ngx_http_core_module.ctx_index];
    top_llcf = conf_ctx->loc_conf[ngx_http_lua_module.ctx_index];

    ngx_memzero(&conf, sizeof(ngx_conf_t));

    conf.temp_pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, cycle->log);
    if (conf.temp_pool == NULL) {
        return NGX_ERROR;
    }

    conf.ctx = &http_ctx;
    conf.cycle = cycle;
    conf.pool = cycle->pool;
    conf.log = cycle->log;

    http_ctx.loc_conf = ngx_pcalloc(conf.pool,
                                    sizeof(void *) * ngx_http_max_module);
    if (http_ctx.loc_conf == NULL) {
        return NGX_ERROR;
    }

    http_ctx.srv_conf = ngx_pcalloc(conf.pool,
                                    sizeof(void *) * ngx_http_max_module);
    if (http_ctx.srv_conf == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; ngx_modules[i]; i++) {
        if (ngx_modules[i]->type != NGX_HTTP_MODULE) {
            continue;
        }

        module = ngx_modules[i]->ctx;

        if (module->create_srv_conf) {
            cur = module->create_srv_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            if (module->merge_srv_conf) {
                prev = module->create_srv_conf(&conf);
                if (prev == NULL) {
                    return NGX_ERROR;
                }

                rv = module->merge_srv_conf(&conf, prev, cur);
                if (rv != NGX_CONF_OK) {
                    goto failed;
                }
            }

            http_ctx.srv_conf[ngx_modules[i]->ctx_index] = cur;
        }

        if (module->create_loc_conf) {
            cur = module->create_loc_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            if (module->merge_loc_conf) {
                prev = module->create_loc_conf(&conf);
                if (prev == NULL) {
                    return NGX_ERROR;
                }

                rv = module->merge_loc_conf(&conf, prev, cur);
                if (rv != NGX_CONF_OK) {
                    goto failed;
                }
            }

            http_ctx.loc_conf[ngx_modules[i]->ctx_index] = cur;
        }
    }

    ngx_destroy_pool(conf.temp_pool);
    conf.temp_pool = NULL;

    c = ngx_http_lua_create_fake_connection();
    if (c == NULL) {
        goto failed;
    }

    c->log->handler = ngx_http_lua_log_init_worker_error;

    r = ngx_http_lua_create_fake_request(c);
    if (r == NULL) {
        goto failed;
    }

    r->main_conf = http_ctx.main_conf;
    r->srv_conf = http_ctx.srv_conf;
    r->loc_conf = http_ctx.loc_conf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    c->log->file = clcf->error_log->file;
    if (!(c->log->log_level & NGX_LOG_DEBUG_CONNECTION)) {
        c->log->log_level = clcf->error_log->log_level;
    }

    if (top_clcf->resolver) {
        clcf->resolver = top_clcf->resolver;
    }

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto failed;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_INIT_WORKER;
    ctx->cur_co_ctx = NULL;
    r->read_event_handler = ngx_http_block_reading;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    if (top_llcf->log_socket_errors != NGX_CONF_UNSET) {
        llcf->log_socket_errors = top_llcf->log_socket_errors;
    }

    ngx_http_lua_set_req(lmcf->lua, r);

    (void) lmcf->init_worker_handler(cycle->log, lmcf, lmcf->lua);

    ngx_destroy_pool(r->pool);
    ngx_destroy_pool(c->pool);
    return NGX_OK;

failed:

    if (conf.temp_pool) {
        ngx_destroy_pool(conf.temp_pool);
    }

    if (r && r->pool) {
        ngx_destroy_pool(r->pool);
    }

    if (c) {
        ngx_http_lua_close_fake_connection(c);
    }

    return NGX_ERROR;
}


ngx_int_t
ngx_http_lua_init_worker_by_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    int         status;

    status = luaL_loadbuffer(L, (char *) lmcf->init_worker_src.data,
                             lmcf->init_worker_src.len, "=init_worker_by_lua")
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_worker_by_lua");
}


ngx_int_t
ngx_http_lua_init_worker_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->init_worker_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_worker_by_lua_file");
}


static u_char *
ngx_http_lua_log_init_worker_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    return ngx_snprintf(buf, len, ", context: init_worker_by_lua*");
}
