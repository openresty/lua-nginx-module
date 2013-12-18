
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_probe.h"


static void ngx_http_lua_content_phase_post_read(ngx_http_request_t *r);

#ifdef NGX_LUA_CAPTURE_DOWN_STREAMING
static ngx_int_t _is_chain_valid(ngx_chain_t * cl);
static ngx_int_t _is_last_chain_link(ngx_chain_t * cl);
static ngx_int_t _post_request_if_not_posted(ngx_http_request_t *r,
    ngx_http_posted_request_t *pr);
#endif

ngx_int_t
ngx_http_lua_content_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      co_ref;
    ngx_int_t                rc;
    lua_State               *co;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_cleanup_t      *cln;

    ngx_http_lua_loc_conf_t      *llcf;

    dd("content by chunk");

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

    } else {
        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->entered_content_phase = 1;

    /*  {{{ new coroutine to handle request */
    co = ngx_http_lua_new_thread(r, L, &co_ref);

    if (co == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                     "lua: failed to create new coroutine to handle request");

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

    /*  set closure's env table to new coroutine's globals table */
    lua_pushvalue(co, LUA_GLOBALSINDEX);
    lua_setfenv(co, -2);

    /*  save nginx request in coroutine globals table */
    ngx_http_lua_set_req(co, r);

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;

    /*  {{{ register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }
    /*  }}} */

    ctx->context = NGX_HTTP_LUA_CONTEXT_CONTENT;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->check_client_abort) {
        r->read_event_handler = ngx_http_lua_rd_check_broken_connection;

    } else {
        r->read_event_handler = ngx_http_block_reading;
    }

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    if (rc == NGX_ERROR || rc >= NGX_OK) {
        return rc;
    }

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_content_run_posted_threads(L, r, ctx, 0);
    }

    if (rc == NGX_DONE) {
        return ngx_http_lua_content_run_posted_threads(L, r, ctx, 1);
    }

    return NGX_OK;
}


#ifdef NGX_LUA_CAPTURE_DOWN_STREAMING
static ngx_int_t
_post_request_if_not_posted(ngx_http_request_t *r, ngx_http_posted_request_t *pr)
{
    ngx_http_posted_request_t  *p;

    /* Search request in the posted requests list, so that it would not be posted twice. */
    for (p = r->main->posted_requests; p; p = p->next) {
        if (p->request == r) {
            return NGX_OK;
        }
    }
    
    return ngx_http_post_request(r, pr);
}

static ngx_int_t
_is_chain_valid(ngx_chain_t * cl)
{
    /* For some reason, sometimes when cl->buf is cleaned, 1 is assigned to it. */
    return ((cl != NULL) && (cl->buf != NULL) && (cl->buf != (void *) 1));
}
static ngx_int_t
_is_last_chain_link(ngx_chain_t * cl)
{
    /* last_in_chain is for subrequests. */
    return cl->buf->last_in_chain || cl->buf->last_buf;
}
#endif

void
ngx_http_lua_content_wev_handler(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t rc;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    rc = ctx->resume_handler(r);

    if (rc == NGX_DONE) {
        return;
    }

#ifdef NGX_LUA_CAPTURE_DOWN_STREAMING
    if (ctx->current_subrequest && ctx->wakeup_subrequest) {
        /* Make sure that the subrequest continues */
        if (_post_request_if_not_posted(ctx->current_subrequest, NULL) != NGX_OK) {
            ngx_http_lua_finalize_request(r, NGX_ERROR);
        }
        /* Don't try to discard the last buffer, as it will cause a NULL dereference... */
        if (_is_chain_valid(ctx->current_subrequest_buffer) && (!_is_last_chain_link(ctx->current_subrequest_buffer))) {
            ngx_http_lua_discard_bufs(ctx->current_subrequest->pool, ctx->current_subrequest_buffer);
        }
        ctx->current_subrequest_buffer = NULL;
        ctx->wakeup_subrequest = 0;
    }
#endif
}


ngx_int_t
ngx_http_lua_content_handler(ngx_http_request_t *r)
{
    ngx_http_lua_loc_conf_t     *llcf;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua content handler, uri:\"%V\" c:%ud", &r->uri,
                   r->main->count);

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->content_handler == NULL) {
        dd("no content handler found");
        return NGX_DECLINED;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    dd("ctx = %p", ctx);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }
    }

    dd("entered? %d", (int) ctx->entered_content_phase);

    if (ctx->waiting_more_body) {
        return NGX_DONE;
    }

    if (ctx->entered_content_phase) {
        dd("calling wev handler");
        rc = ctx->resume_handler(r);
        dd("wev handler returns %d", (int) rc);
        return rc;
    }

    if (llcf->force_read_body && !ctx->read_body_done) {
        r->request_body_in_single_buf = 1;
        r->request_body_in_persistent_file = 1;
        r->request_body_in_clean_file = 1;

        rc = ngx_http_read_client_request_body(r,
                                       ngx_http_lua_content_phase_post_read);

        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
#if (nginx_version < 1002006) ||                                             \
        (nginx_version >= 1003000 && nginx_version < 1003009)
            r->main->count--;
#endif
            return rc;
        }

        if (rc == NGX_AGAIN) {
            ctx->waiting_more_body = 1;

            return NGX_DONE;
        }
    }

    dd("setting entered");

    ctx->entered_content_phase = 1;

    dd("calling content handler");
    return llcf->content_handler(r);
}


/* post read callback for the content phase */
static void
ngx_http_lua_content_phase_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->read_body_done = 1;

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;
        ngx_http_lua_finalize_request(r, ngx_http_lua_content_handler(r));

    } else {
        r->main->count--;
    }
}


ngx_int_t
ngx_http_lua_content_handler_file(ngx_http_request_t *r)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    u_char                          *script_path;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_str_t                        eval_src;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (ngx_http_complex_value(r, &llcf->content_src, &eval_src) != NGX_OK) {
        return NGX_ERROR;
    }

    script_path = ngx_http_lua_rebase_path(r->pool, eval_src.data,
            eval_src.len);

    if (script_path == NULL) {
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(L, script_path, llcf->content_src_key);
    if (rc != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  make sure we have a valid code chunk */
    assert(lua_isfunction(L, -1));

    return ngx_http_lua_content_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_content_handler_inline(ngx_http_request_t *r)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    L = ngx_http_lua_get_lua_vm(r, NULL);

    /*  load Lua inline script (w/ cache) sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(L, llcf->content_src.value.data,
                                       llcf->content_src.value.len,
                                       llcf->content_src_key,
                                       "content_by_lua");
    if (rc != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return ngx_http_lua_content_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_content_run_posted_threads(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, int n)
{
    ngx_int_t                        rc;
    ngx_http_lua_posted_thread_t    *pt;

    dd("run posted threads: %p", ctx->posted_threads);

    for ( ;; ) {
        pt = ctx->posted_threads;
        if (pt == NULL) {
            goto done;
        }

        ctx->posted_threads = pt->next;

        ngx_http_lua_probe_run_posted_thread(r, pt->co_ctx->co,
                                             (int) pt->co_ctx->co_status);

        dd("posted thread status: %d", pt->co_ctx->co_status);

        if (pt->co_ctx->co_status != NGX_HTTP_LUA_CO_RUNNING) {
            continue;
        }

        ctx->cur_co_ctx = pt->co_ctx;

        rc = ngx_http_lua_run_thread(L, r, ctx, 0);

        if (rc == NGX_AGAIN) {
            continue;
        }

        if (rc == NGX_DONE) {
            n++;
            continue;
        }

        if (rc == NGX_OK) {
            while (n > 0) {
                ngx_http_lua_finalize_request(r, NGX_DONE);
                n--;
            }

            return NGX_OK;
        }

        /* rc == NGX_ERROR || rc > NGX_OK */

        return rc;
    }

done:
    if (n == 1) {
        return NGX_DONE;
    }

    if (n == 0) {
        r->main->count++;
        return NGX_DONE;
    }

    /* n > 1 */

    do {
        ngx_http_lua_finalize_request(r, NGX_DONE);
    } while (--n > 1);

    return NGX_DONE;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
