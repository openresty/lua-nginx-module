
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_timer.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_probe.h"


typedef struct {
    int           co_ref;
    lua_State    *co;

    void        **main_conf;
    void        **srv_conf;
    void        **loc_conf;

    ngx_http_lua_main_conf_t    *lmcf;
} ngx_http_lua_timer_t;


static int ngx_http_lua_ngx_timer_at(lua_State *L);
static void ngx_http_lua_timer_handler(ngx_event_t *ev);
static u_char * ngx_http_lua_log_timer_error(ngx_log_t *log, u_char *buf,
    size_t len);


void
ngx_http_lua_inject_timer_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 1 /* nrec */);    /* ngx.timer. */

    lua_pushcfunction(L, ngx_http_lua_ngx_timer_at);
    lua_setfield(L, -2, "at");

    lua_setfield(L, -2, "timer");
}


static int
ngx_http_lua_ngx_timer_at(lua_State *L)
{
    int                      co_ref;
    u_char                  *p;
    lua_State               *mt;  /* the main thread */
    lua_State               *co;
    ngx_msec_t               delay;
    ngx_event_t             *ev;
    ngx_http_request_t      *r;
    ngx_http_lua_timer_t    *timer;
#if 0
    ngx_http_connection_t   *hc;
#endif

    ngx_http_lua_main_conf_t      *lmcf;
#if 0
    ngx_http_core_main_conf_t     *cmcf;
#endif

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting 2 arguments but got %d",
                          lua_gettop(L));
    }

    delay = (ngx_msec_t) (luaL_checknumber(L, 1) * 1000);

    luaL_argcheck(L, lua_isfunction(L, 2) && !lua_iscfunction(L, 2), 2,
                 "Lua function expected");

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request");
    }

    if (ngx_exiting) {
        lua_pushnil(L);
        lua_pushliteral(L, "process exiting");
        return 2;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    if (lmcf->pending_timers >= lmcf->max_pending_timers) {
        lua_pushnil(L);
        lua_pushliteral(L, "too many pending timers");
        return 2;
    }

    mt = lmcf->lua;

    co = lua_newthread(mt);

    /* stack: time func thread */

    ngx_http_lua_probe_user_coroutine_create(r, L, co);

    lua_createtable(co, 0, 0);  /* the new global table */

    /* co stack: global_tb */

    lua_createtable(co, 0, 1);  /* the metatable */
    lua_pushvalue(co, LUA_GLOBALSINDEX);
    lua_setfield(co, -2, "__index");
    lua_setmetatable(co, -2);

    /* co stack: global_tb */

    lua_replace(co, LUA_GLOBALSINDEX);

    /* co stack: <empty> */

    dd("stack top: %d", lua_gettop(L));

    lua_xmove(mt, L, 1);    /* move coroutine from main thread to L */

    /* L stack: time func thread */
    /* mt stack: empty */

    lua_pushvalue(L, 2);    /* copy entry function to top of L*/

    /* L stack: time func thread func */

    lua_xmove(L, co, 1);    /* move entry function from L to co */

    /* L stack: time func thread */
    /* co stack: func */

    lua_pushvalue(co, LUA_GLOBALSINDEX);
    lua_setfenv(co, -2);

    /* co stack: thread */

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);

    /* L stack: time func thread corountines */

    lua_pushvalue(L, -2);

    /* L stack: time func thread coroutines thread */

    co_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    /* L stack: time func thread */

    p = ngx_alloc(sizeof(ngx_event_t) + sizeof(ngx_http_lua_timer_t),
                  r->connection->log);
    if (p == NULL) {
        lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
        lua_rawget(L, LUA_REGISTRYINDEX);
        luaL_unref(L, -1, co_ref);
        return luaL_error(L, "no memory");
    }

    ev = (ngx_event_t *) p;

    ngx_memzero(ev, sizeof(ngx_event_t));

    p += sizeof(ngx_event_t);

    timer = (ngx_http_lua_timer_t *) p;

    timer->co_ref = co_ref;
    timer->co = co;
    timer->main_conf = r->main_conf;
    timer->srv_conf = r->srv_conf;
    timer->loc_conf = r->loc_conf;
    timer->lmcf = lmcf;

    ev->handler = ngx_http_lua_timer_handler;
    ev->data = timer;
    ev->log = ngx_cycle->log;

    lmcf->pending_timers++;

    ngx_add_timer(ev, delay);

    lua_pushinteger(L, 1);
    return 1;
}


static void
ngx_http_lua_timer_handler(ngx_event_t *ev)
{
    lua_State               *L;
    ngx_int_t                rc;
    ngx_log_t               *log;
    ngx_connection_t        *c = NULL, *saved_c = NULL;
    ngx_http_request_t      *r = NULL;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_cleanup_t      *cln;
    ngx_http_log_ctx_t      *logctx;
    ngx_http_lua_timer_t     timer;

    ngx_http_lua_main_conf_t        *lmcf;
    ngx_http_core_loc_conf_t        *clcf;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ngx.timer expired");

    ngx_memcpy(&timer, ev->data, sizeof(ngx_http_lua_timer_t));
    ngx_free(ev);
    ev = NULL;

    lmcf = timer.lmcf;

    lmcf->pending_timers--;

    if (lmcf->running_timers >= lmcf->max_running_timers) {
        ngx_log_error(NGX_LOG_ALERT, ngx_cycle->log, 0,
                      "%i lua_max_running_timers are not enough",
                      lmcf->max_running_timers);
        goto abort;
    }

    /* create the fake connection (we temporarily use a valid fd (0) to make
       ngx_get_connection happy) */

    if (ngx_cycle->files) {
        saved_c = ngx_cycle->files[0];
    }

    c = ngx_get_connection(0, ngx_cycle->log);

    if (ngx_cycle->files) {
        ngx_cycle->files[0] = saved_c;
    }

    if (c == NULL) {
        goto abort;
    }

    c->fd = -1;

    c->pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, c->log);
    if (c->pool == NULL) {
        goto abort;
    }

    log = ngx_pcalloc(c->pool, sizeof(ngx_log_t));
    if (log == NULL) {
        goto abort;
    }

    logctx = ngx_palloc(c->pool, sizeof(ngx_http_log_ctx_t));
    if (logctx == NULL) {
        goto abort;
    }

    dd("c pool allocated: %d", (int) (sizeof(ngx_log_t)
       + sizeof(ngx_http_log_ctx_t) + sizeof(ngx_http_request_t)));

    logctx->connection = c;
    logctx->request = NULL;
    logctx->current_request = NULL;

    c->log = log;
    c->log->connection = c->number;
    c->log->handler = ngx_http_lua_log_timer_error;
    c->log->data = logctx;
    c->log->action = NULL;

    c->log_error = NGX_ERROR_INFO;

#if 0
    c->buffer = ngx_create_temp_buf(c->pool, 2);
    if (c->buffer == NULL) {
        goto abort;
    }

    c->buffer->start[0] = CR;
    c->buffer->start[1] = LF;
#endif

    /* create the fake request */

    r = ngx_pcalloc(c->pool, sizeof(ngx_http_request_t));
    if (r == NULL) {
        goto abort;
    }

    c->requests++;
    logctx->request = r;
    logctx->current_request = r;

    r->pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, c->log);
    if (r->pool == NULL) {
        goto abort;
    }

    dd("r pool allocated: %d", (int) (sizeof(ngx_http_lua_ctx_t)
       + sizeof(void *) * ngx_http_max_module + sizeof(ngx_http_cleanup_t)));

#if 0
    hc = ngx_pcalloc(c->pool, sizeof(ngx_http_connection_t));
    if (hc == NULL) {
        goto abort;
    }

    r->header_in = c->buffer;
    r->header_end = c->buffer->start;

    if (ngx_list_init(&r->headers_out.headers, r->pool, 0,
                      sizeof(ngx_table_elt_t))
        != NGX_OK)
    {
        goto abort;
    }

    if (ngx_list_init(&r->headers_in.headers, r->pool, 0,
                      sizeof(ngx_table_elt_t))
        != NGX_OK)
    {
        goto abort;
    }
#endif

    r->ctx = ngx_pcalloc(r->pool, sizeof(void *) * ngx_http_max_module);
    if (r->ctx == NULL) {
        goto abort;
    }

#if 0
    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    r->variables = ngx_pcalloc(r->pool, cmcf->variables.nelts
                                        * sizeof(ngx_http_variable_value_t));
    if (r->variables == NULL) {
        goto abort;
    }
#endif

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto abort;
    }

    r->headers_in.content_length_n = 0;
    c->data = r;
#if 0
    hc->request = r;
    r->http_connection = hc;
#endif
    r->signature = NGX_HTTP_MODULE;
    r->connection = c;
    r->main = r;
    r->count = 1;

    r->method = NGX_HTTP_UNKNOWN;

    r->headers_in.keep_alive_n = -1;
    r->uri_changes = NGX_HTTP_MAX_URI_CHANGES + 1;
    r->subrequests = NGX_HTTP_MAX_SUBREQUESTS + 1;

    r->http_state = NGX_HTTP_PROCESS_REQUEST_STATE;
    r->discard_body = 1;

    r->main_conf = timer.main_conf;
    r->srv_conf = timer.srv_conf;
    r->loc_conf = timer.loc_conf;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    c->log->file = clcf->error_log->file;
    if (!(c->log->log_level & NGX_LOG_DEBUG_CONNECTION)) {
        c->log->log_level = clcf->error_log->log_level;
    }

    c->error = 1;

    ctx->cur_co_ctx = &ctx->entry_co_ctx;

    L = lmcf->lua;

    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        goto abort;
    }

    cln->handler = ngx_http_lua_request_cleanup;
    cln->data = r;
    ctx->cleanup = &cln->handler;

    ctx->entered_content_phase = 1;
    ctx->context = NGX_HTTP_LUA_CONTEXT_TIMER;

    r->read_event_handler = ngx_http_block_reading;

    ctx->cur_co_ctx->co_ref = timer.co_ref;
    ctx->cur_co_ctx->co = timer.co;
    ctx->cur_co_ctx->co_status = NGX_HTTP_LUA_CO_RUNNING;

    dd("r connection: %p, log %p", r->connection, r->connection->log);

    /*  save the request in coroutine globals table */
    lua_pushvalue(timer.co, LUA_GLOBALSINDEX);
    lua_pushlightuserdata(timer.co, &ngx_http_lua_request_key);
    lua_pushlightuserdata(timer.co, r);
    lua_rawset(timer.co, -3);
    lua_pop(timer.co, 1);
    /*  }}} */

    lmcf->running_timers++;

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    dd("timer lua run thread: %d", (int) rc);

    if (rc == NGX_ERROR || rc >= NGX_OK) {
        /* do nothing */

    } else if (rc == NGX_AGAIN) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 0);

    } else if (rc == NGX_DONE) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 1);
    } else {
        rc = NGX_OK;
    }

    ngx_http_lua_finalize_request(r, rc);
    return;

abort:
    if (timer.co_ref && timer.co) {
        lua_pushlightuserdata(timer.co, &ngx_http_lua_coroutines_key);
        lua_rawget(timer.co, LUA_REGISTRYINDEX);
        luaL_unref(timer.co, -1, timer.co_ref);
        lua_settop(timer.co, 0);
    }

    if (r && r->pool) {
        ngx_destroy_pool(r->pool);
    }

    if (c) {
        ngx_http_lua_close_fake_connection(c);
    }
}


static u_char *
ngx_http_lua_log_timer_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    return ngx_snprintf(buf, len, ", context: ngx.timer");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
