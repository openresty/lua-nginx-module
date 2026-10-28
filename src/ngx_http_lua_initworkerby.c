
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#include "ngx_core.h"
#include "ngx_event.h"
#include "ngx_event_posted.h"
#include "ngx_event_timer.h"
#include "ngx_http.h"
#include "ngx_http_lua_common.h"
#include "ngx_http_request.h"
#include "ngx_process_cycle.h"
#include "ngx_string.h"
#include "ngx_time.h"
#include "ngx_times.h"
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pipe.h"


static u_char *ngx_http_lua_log_init_worker_error(ngx_log_t *log,
    u_char *buf, size_t len);

static void ngx_http_lua_init_worker_toggle_accept(
    ngx_cycle_t *cycle, ngx_uint_t arm);

static void ngx_http_lua_init_worker_pump(ngx_cycle_t *cycle,
    ngx_msec_t budget);

static void ngx_http_lua_init_worker_flush_timers(
    ngx_http_lua_main_conf_t *lmcf);


typedef struct {
    unsigned     done:1;
    unsigned     failed:1;
    unsigned     timeout:1;
} ngx_http_lua_init_worker_state_t;


static void ngx_http_lua_init_worker_pump_loop(ngx_cycle_t *cycle,
    ngx_http_lua_main_conf_t *lmcf,
    ngx_http_lua_init_worker_state_t *st);


static void
ngx_http_lua_init_worker_done(void *data)
{
    ngx_http_lua_init_worker_state_t *state = data;

    state->done = 1;
}


static void
ngx_http_lua_init_worker_pump(ngx_cycle_t *cycle, ngx_msec_t budget)
{
    ngx_msec_t                   timer;

    timer = ngx_event_find_timer();

    if (timer == NGX_TIMER_INFINITE || timer > budget) {
        timer = budget;
    }

    if (!ngx_queue_empty(&ngx_posted_next_events)) {
        ngx_event_move_posted_next(cycle);
        timer = 0;
    }

#ifdef HAVE_POSTED_DELAYED_EVENTS_PATCH
    if (!ngx_queue_empty(&ngx_posted_delayed_events)) {
        timer = 0;
    }
#endif

    (void) ngx_process_events(cycle, timer, NGX_UPDATE_TIME | NGX_POST_EVENTS);

    ngx_event_expire_timers();

    ngx_event_process_posted(cycle, &ngx_posted_events);

#ifdef HAVE_POSTED_DELAYED_EVENTS_PATCH
    ngx_event_process_posted(cycle, &ngx_posted_delayed_events);
#endif
}


static void
ngx_http_lua_init_worker_toggle_accept(ngx_cycle_t *cycle, ngx_uint_t arm)
{
    ngx_listening_t    *ls;
    ngx_connection_t   *c;
    ngx_event_t        *rev;
    ngx_uint_t          i;
    ngx_uint_t          flags;
#if (NGX_HAVE_EPOLLEXCLUSIVE)
    ngx_uint_t          exclusive;
#endif

    if (ngx_use_accept_mutex) {
        return;
    }

#if (NGX_HAVE_EPOLLEXCLUSIVE)
    {
        ngx_core_conf_t *ccf;

        ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx,
                                               ngx_core_module);
        exclusive = ((ngx_event_flags & NGX_USE_EPOLL_EVENT)
                     && ccf->worker_processes > 1);
    }
#endif

    ls = cycle->listening.elts;

    for (i = 0; i < cycle->listening.nelts; i++) {

        /* disarm every listener, not just HTTP ones: any pending
         * connection on an armed level-triggered listen fd would make the
         * pump spin at 100% CPU, and re-arming is faithful for all
         * subsystems since nginx arms all listeners via the same
         * subsystem-independent path in ngx_event.c */
#if (NGX_HAVE_REUSEPORT)
        if (ls[i].reuseport && ls[i].worker != ngx_worker) {
            /* other workers' sockets: ls[i].connection is NULL here */
            continue;
        }
#endif

        c = ls[i].connection;

        if (c == NULL) {
            continue;
        }

        rev = c->read;

        if (!arm) {
            if (rev->active
                && ngx_del_event(rev, NGX_READ_EVENT, 0) == NGX_ERROR)
            {
                ngx_log_error(NGX_LOG_ALERT, cycle->log, 0,
                              "init_worker: failed to disarm listen fd %d",
                              c->fd);
            }

            continue;
        }

        if (rev->active) {
            continue;
        }

        flags = 0;

#if (NGX_HAVE_EPOLLEXCLUSIVE)
        if (exclusive
#if (NGX_HAVE_REUSEPORT)
            /* upstream registers reuseport sockets with plain flags,
             * before the EPOLLEXCLUSIVE branch (ngx_event.c:907) */
            && !ls[i].reuseport
#endif
           )
        {
            flags = NGX_EXCLUSIVE_EVENT;
        }
#endif

        if (ngx_add_event(rev, NGX_READ_EVENT, flags) == NGX_ERROR) {
            ngx_log_error(NGX_LOG_ALERT, cycle->log, 0,
                          "init_worker: failed to re-arm listen fd %d, "
                          "worker will not accept on it", c->fd);
        }
    }
}


static void
ngx_http_lua_init_worker_flush_timers(ngx_http_lua_main_conf_t *lmcf)
{
    ngx_queue_t    *q;
    ngx_event_t    *ev;
    ngx_msec_int_t  remaining;

    while (!ngx_queue_empty(&lmcf->deferred_timers)) {
        q = ngx_queue_head(&lmcf->deferred_timers);
        ngx_queue_remove(q);

        ev = ngx_queue_data(q, ngx_event_t, queue);
        remaining = (ngx_msec_int_t) (ev->timer.key - ngx_current_msec);

        if (remaining <= 0) {
#ifdef HAVE_POSTED_DELAYED_EVENTS_PATCH
            ngx_post_event(ev, &ngx_posted_delayed_events);
#else
            ngx_add_timer(ev, 0);
#endif
            continue;
        }

        ngx_add_timer(ev, (ngx_msec_t) remaining);
    }
}


static void
ngx_http_lua_init_worker_pump_loop(ngx_cycle_t *cycle,
    ngx_http_lua_main_conf_t *lmcf, ngx_http_lua_init_worker_state_t *st)
{
    ngx_msec_t           deadline = 0, budget;
    ngx_uint_t           unlimited;

    unlimited = (lmcf->init_worker_timeout == 0);

    if (!unlimited) {
        ngx_time_update();
        deadline = ngx_current_msec + lmcf->init_worker_timeout;
    }

    ngx_http_lua_init_worker_toggle_accept(cycle, 0);

    for (;;) {

        if (st->done) {
            break;
        }

        if (ngx_terminate || ngx_quit || ngx_exiting) {
            ngx_log_error(NGX_LOG_WARN, cycle->log, 0,
                          "init_worker_by_lua* aborted by signal while "
                          "waiting for a yielded operation");
            break;
        }

        if (unlimited) {
            budget = NGX_TIMER_INFINITE;

        } else {
            if ((ngx_msec_int_t) (deadline - ngx_current_msec) <= 0) {
                st->timeout = 1;
                ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                              "init_worker_by_lua* timed out after %M ms",
                              lmcf->init_worker_timeout);
                break;
            }

            budget = deadline - ngx_current_msec;
        }

        ngx_http_lua_init_worker_pump(cycle, budget);
    }


    ngx_http_lua_init_worker_toggle_accept(cycle, 1);
}


ngx_int_t
ngx_http_lua_init_worker(ngx_cycle_t *cycle)
{
    char                        *rv;
    void                        *cur, *prev;
    ngx_uint_t                   i;
    ngx_conf_t                   conf;
    ngx_conf_file_t              cf_file;
    ngx_cycle_t                 *fake_cycle;
    ngx_module_t               **modules;
    ngx_open_file_t             *file, *ofile;
    ngx_list_part_t             *part;
    ngx_connection_t            *c = NULL;
    ngx_http_module_t           *module;
    ngx_http_request_t          *r = NULL;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_conf_ctx_t         *conf_ctx, http_ctx;
    ngx_http_lua_loc_conf_t     *top_llcf;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_core_loc_conf_t    *clcf, *top_clcf;
    ngx_pool_cleanup_t          *cln;
    lua_State                   *co;
    ngx_int_t                    rc;
    int                          co_ref = LUA_NOREF;

    ngx_http_lua_init_worker_state_t   st;

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);

    if (lmcf == NULL || lmcf->lua == NULL) {
        return NGX_OK;
    }

    /* lmcf != NULL && lmcf->lua != NULL */

#if !(NGX_WIN32)
    if (ngx_process == NGX_PROCESS_HELPER
#   ifdef HAVE_PRIVILEGED_PROCESS_PATCH
        && !ngx_is_privileged_agent
#   endif
       )
    {
        /* disable init_worker_by_lua* and destroy lua VM in cache processes */

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua close the global Lua VM %p in the "
                       "cache helper process %P", lmcf->lua, ngx_pid);

        lmcf->vm_cleanup->handler(lmcf->vm_cleanup->data);
        lmcf->vm_cleanup->handler = NULL;

        return NGX_OK;
    }

#   ifdef HAVE_NGX_LUA_PIPE
    if (ngx_http_lua_pipe_add_signal_handler(cycle) != NGX_OK) {
        return NGX_ERROR;
    }
#   endif

#endif  /* NGX_WIN32 */

#if (NGX_HTTP_LUA_HAVE_SA_RESTART)
    if (lmcf->set_sa_restart) {
        ngx_http_lua_set_sa_restart(ngx_cycle->log);
    }
#endif

    if (lmcf->init_worker_handler == NULL) {
        return NGX_OK;
    }

    conf_ctx = (ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index];
    http_ctx.main_conf = conf_ctx->main_conf;

    top_clcf = conf_ctx->loc_conf[ngx_http_core_module.ctx_index];
    top_llcf = conf_ctx->loc_conf[ngx_http_lua_module.ctx_index];

    ngx_memzero(&conf, sizeof(ngx_conf_t));

    conf.temp_pool = ngx_create_pool(NGX_CYCLE_POOL_SIZE, cycle->log);
    if (conf.temp_pool == NULL) {
        return NGX_ERROR;
    }

    conf.temp_pool->log = cycle->log;

    /* we fake a temporary ngx_cycle_t here because some
     * modules' merge conf handler may produce side effects in
     * cf->cycle (like ngx_proxy vs cf->cycle->paths).
     * also, we cannot allocate our temp cycle on the stack
     * because some modules like ngx_http_core_module reference
     * addresses within cf->cycle (i.e., via "&cf->cycle->new_log")
     */

    fake_cycle = ngx_palloc(cycle->pool, sizeof(ngx_cycle_t));
    if (fake_cycle == NULL) {
        goto failed;
    }

    ngx_memcpy(fake_cycle, cycle, sizeof(ngx_cycle_t));

    /*
     * nginx clears cycle->old_cycle after ngx_init_cycle() completes.
     * Since nginx 1.29.2, ngx_ssl_cache_fetch() accesses old_cycle->conf_ctx
     * without a NULL guard, so we must ensure old_cycle is non-NULL.
     * This avoids a NULL dereference when merge_loc_conf triggers
     * ngx_ssl_trusted_certificate.
     * Pointing to the current cycle is safe: the SSL cache is shared via
     * conf_ctx, so cert lookups still find previously loaded entries.
     */
    if (fake_cycle->old_cycle == NULL) {
        fake_cycle->old_cycle = cycle;
    }

    ngx_queue_init(&fake_cycle->reusable_connections_queue);

    if (ngx_array_init(&fake_cycle->listening, cycle->pool,
                       cycle->listening.nelts ? cycle->listening.nelts : 1,
                       sizeof(ngx_listening_t))
        != NGX_OK)
    {
        goto failed;
    }

    if (ngx_array_init(&fake_cycle->paths, cycle->pool,
                       cycle->paths.nelts ? cycle->paths.nelts : 1,
                       sizeof(ngx_path_t *))
        != NGX_OK)
    {
        goto failed;
    }

    part = &cycle->open_files.part;
    ofile = part->elts;

    if (ngx_list_init(&fake_cycle->open_files, cycle->pool,
                      part->nelts ? part->nelts : 1,
                      sizeof(ngx_open_file_t))
        != NGX_OK)
    {
        goto failed;
    }

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            ofile = part->elts;
            i = 0;
        }

        file = ngx_list_push(&fake_cycle->open_files);
        if (file == NULL) {
            goto failed;
        }

        ngx_memcpy(file, ofile, sizeof(ngx_open_file_t));
    }

    if (ngx_list_init(&fake_cycle->shared_memory, cycle->pool, 1,
                      sizeof(ngx_shm_zone_t))
        != NGX_OK)
    {
        goto failed;
    }

    conf.ctx = &http_ctx;
    conf.cycle = fake_cycle;
    conf.pool = fake_cycle->pool;
    conf.log = cycle->log;

    ngx_memzero(&cf_file, sizeof(cf_file));
    cf_file.file.name = cycle->conf_file;
    conf.conf_file = &cf_file;

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

#if (nginx_version >= 1009011)
    modules = cycle->modules;
#else
    modules = ngx_modules;
#endif

    for (i = 0; modules[i]; i++) {
        if (modules[i]->type != NGX_HTTP_MODULE) {
            continue;
        }

        module = modules[i]->ctx;

        if (module->create_srv_conf) {
            cur = module->create_srv_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            http_ctx.srv_conf[modules[i]->ctx_index] = cur;

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
        }

        if (module->create_loc_conf) {
            cur = module->create_loc_conf(&conf);
            if (cur == NULL) {
                return NGX_ERROR;
            }

            http_ctx.loc_conf[modules[i]->ctx_index] = cur;

            if (module->merge_loc_conf) {
                if (modules[i] == &ngx_http_lua_module) {
                    prev = top_llcf;

                } else if (modules[i] == &ngx_http_core_module) {
                    prev = top_clcf;

                } else {
                    prev = module->create_loc_conf(&conf);
                    if (prev == NULL) {
                        return NGX_ERROR;
                    }
                }

                rv = module->merge_loc_conf(&conf, prev, cur);
                if (rv != NGX_CONF_OK) {
                    goto failed;
                }
            }
        }
    }

    ngx_destroy_pool(conf.temp_pool);
    conf.temp_pool = NULL;

    c = ngx_http_lua_create_fake_connection(NULL);
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

#if (nginx_version >= 1009000)
    ngx_set_connection_log(r->connection, clcf->error_log);

#else
    ngx_http_set_connection_log(r->connection, clcf->error_log);
#endif

    ctx = ngx_http_lua_create_ctx(r);
    if (ctx == NULL) {
        goto failed;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_INIT_WORKER;
    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    r->read_event_handler = ngx_http_block_reading;

    if (lmcf->init_worker_handler(cycle->log, lmcf, lmcf->lua) != NGX_OK) {
        ngx_http_lua_set_req(lmcf->lua, NULL);
        ngx_http_lua_finalize_request(r, NGX_ERROR);
        return NGX_OK;
    }

    co_ref = ngx_http_lua_new_cached_thread(lmcf->lua, &co, lmcf, 1);

    lua_pop(lmcf->lua, 2);

    cln = ngx_pool_cleanup_add(r->pool, 0);
    if (cln == NULL) {
        goto runner_failed;
    }

    cln->handler = ngx_http_lua_request_cleanup_handler;
    cln->data = ctx;
    ctx->cleanup = &cln->handler;

    ngx_memzero(&st, sizeof(st));

    cln = ngx_pool_cleanup_add(r->pool, 0);
    if (cln == NULL) {
        goto runner_failed;
    }

    cln->handler = ngx_http_lua_init_worker_done;
    cln->data = &st;

    ctx->entered_content_phase = 1;

    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;
    ctx->cur_co_ctx->co_status = NGX_HTTP_LUA_CO_RUNNING;

    ngx_http_lua_set_req(co, r);
    ngx_http_lua_attach_co_ctx_to_L(co, ctx->cur_co_ctx);

    lua_xmove(lmcf->lua, co, 1);

#ifdef NGX_LUA_USE_ASSERT
    ctx->cur_co_ctx->co_top = 1;
#endif

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, 0);

    if (rc == NGX_AGAIN || rc == NGX_DONE) {
        ngx_http_lua_init_worker_pump_loop(cycle, lmcf, &st);

    } else {
        st.done = 1;
        st.failed = (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE);
    }

    if (!st.done) {
        ngx_log_error(NGX_LOG_ERR, cycle->log, 0,
                      "init_worker_by_lua* failed to complete");

        ngx_http_lua_request_cleanup(ctx, 1);
        ngx_http_lua_finalize_request(r, NGX_ERROR);

    } else if (rc != NGX_AGAIN && rc != NGX_DONE) {
        ngx_http_lua_finalize_request(r, rc);
    }

    ngx_http_lua_init_worker_flush_timers(lmcf);
    ngx_http_lua_set_req(lmcf->lua, NULL);

    if (st.failed || st.timeout) {
        if (lmcf->init_worker_abort_on_error) {
            return NGX_ERROR;
        }
    }
    return NGX_OK;

runner_failed:

    if (co_ref != LUA_NOREF) {
        ngx_http_lua_free_thread(r, lmcf->lua, co_ref, co, lmcf);
    }

    if (c != NULL) {
        ngx_http_lua_close_fake_connection(c);
    }

    return NGX_ERROR;

failed:

    if (conf.temp_pool) {
        ngx_destroy_pool(conf.temp_pool);
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
    const char *chunkname;

    if (lmcf->init_worker_chunkname == NULL) {
        chunkname = "=init_worker_by_lua";

    } else {
        chunkname = (const char *) lmcf->init_worker_chunkname;
    }

    status = luaL_loadbuffer(L, (char *) lmcf->init_worker_src.data,
                             lmcf->init_worker_src.len, chunkname);

    return ngx_http_lua_report(log, L, status, "init_worker_by_lua");
}


ngx_int_t
ngx_http_lua_init_worker_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->init_worker_src.data);

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


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
