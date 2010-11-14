/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#define DDEBUG 0

#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"

static void ngx_http_lua_request_cleanup(void *data);
static ngx_int_t ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int nret);


ngx_int_t
ngx_http_lua_content_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      cc_ref;
    lua_State               *cc;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_cleanup_t      *cln;

    /*  {{{ new coroutine to handle request */
    cc = ngx_http_lua_new_thread(r, L, &cc_ref);
    if (cc == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "(lua-content-by-chunk) failed to create new coroutine to handle request!");
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, cc, 1);

    /*  set closure's env table to new coroutine's globals table */
    lua_pushvalue(cc, LUA_GLOBALSINDEX);
    lua_setfenv(cc, -2);

    /*  save reference of code to ease forcing stopping */
    lua_pushvalue(cc, -1);
    lua_setglobal(cc, GLOBALS_SYMBOL_RUNCODE);

    /*  save nginx request in coroutine globals table */
    lua_pushlightuserdata(cc, r);
    lua_setglobal(cc, GLOBALS_SYMBOL_REQUEST);
    /*  }}} */

    /*  {{{ initialize request context */
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ngx_http_set_ctx(r, ctx, ngx_http_lua_module);
    }

    ctx->cc = cc;
    ctx->cc_ref = cc_ref;

    /*  }}} */

    /*  {{{ register request cleanup hooks */
    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    cln->handler = ngx_http_lua_request_cleanup;
    cln->data = r;
    ctx->cleanup = &cln->handler;
    /*  }}} */

    return ngx_http_lua_run_thread(L, r, ctx, 0);
}


static ngx_int_t
ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int nret)
{
    int                      rc;
    int                      cc_ref;
    lua_State               *cc;
    const char              *err, *msg;

    /* set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    NGX_LUA_EXCEPTION_TRY {
        cc = ctx->cc;
        cc_ref = ctx->cc_ref;

        /*  run code */
        rc = lua_resume(cc, nret);

        dd("lua resume returns %d", (int) rc);

        switch (rc) {
            case LUA_YIELD:
                /*  yielded, let event handler do the rest job */
                /*  FIXME: add io cmd dispatcher here */
                lua_settop(cc, 0);
                return NGX_AGAIN;
                break;

            case 0:
                /*  normal end */
                ngx_http_lua_del_thread(r, L, cc_ref, 0);

                if (ctx->cleanup) {
                    dd("cleaning up cleanup");
                    *ctx->cleanup = NULL;
                    ctx->cleanup = NULL;
                }

                ngx_http_lua_send_chain_link(r, ctx, NULL /* indicate last_buf */);
                return NGX_OK;
                break;

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
                    dd("run here...exiting...");

                    ngx_http_lua_del_thread(r, L, cc_ref, 0);

                    if (ctx->cleanup) {
                        *ctx->cleanup = NULL;
                        ctx->cleanup = NULL;
                    }

                    return ctx->exit_code;
                }

                if (ctx->exec_uri.len) {
                    ngx_http_lua_del_thread(r, L, cc_ref, 0);

                    if (ctx->cleanup) {
                        *ctx->cleanup = NULL;
                        ctx->cleanup = NULL;
                    }

                    if (ctx->exec_uri.data[0] == '@') {
                        if (ctx->exec_args.len > 0) {
                            ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                                    "query strings %V ignored when exec'ing named location %V",
                                    &ctx->exec_args, &ctx->exec_uri);
                        }

                        return ngx_http_named_location(r, &ctx->exec_uri);
                    }

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


static void
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

#if 0
        ngx_http_lua_send_chain_link(r, ctx, NULL /* indicate last_buf */);
#endif
    }

    lua_pop(L, 2);
}


void
ngx_http_lua_wev_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_main_conf_t    *lmcf;
    lua_State                   *cc;
    ngx_chain_t                 *cl;
    size_t                       len;
    u_char                      *pos, *last;
    ngx_http_headers_out_t      *sr_headers;
    ngx_list_part_t             *part;
    ngx_table_elt_t             *header;
    ngx_uint_t                   i;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        goto error;
    }

    dd("request done: %d", (int) r->done);
    dd("cleanup done: %p", ctx->cleanup);

#if 1
    if (ctx->cleanup == NULL) {
        return;
    }
#endif

    if (ctx->waiting && ! ctx->done) {
        if (r->main->posted_requests
                && r->main->posted_requests->request != r)
        {
            dd("postpone our wev handler");

#if defined(nginx_version) && nginx_version >= 8012
            ngx_http_post_request(r, NULL);
#else
            ngx_http_post_request(r);
#endif

            return;
        }
    }

    ctx->done = 0;

    len = 0;
    for (cl = ctx->sr_body; cl; cl = cl->next) {
        /*  ignore all non-memory buffers */
        len += cl->buf->last - cl->buf->pos;
    }

    if (len == 0) {
        pos = NULL;

    } else {
        last = pos = ngx_palloc(r->pool, len);
        if (pos == NULL) {
            goto error;
        }

        for (cl = ctx->sr_body; cl; cl = cl->next) {
            /*  ignore all non-memory buffers */
            last = ngx_copy(last, cl->buf->pos, cl->buf->last - cl->buf->pos);
        }
    }

    cc = ctx->cc;

    /*  {{{ construct ret value */
    lua_newtable(cc);

    /*  copy captured status */
    lua_pushinteger(cc, ctx->sr_status);
    lua_setfield(cc, -2, "status");

    /*  copy captured body */
    lua_pushlstring(cc, (const char *) pos, len);
    lua_setfield(cc, -2, "body");

    /* copy captured headers */

    lua_newtable(cc); /* res.header */

    sr_headers = ctx->sr_headers;

    if (sr_headers->content_length == NULL
        && sr_headers->content_length_n >= 0)
    {
        lua_pushliteral(cc, "Content-Length"); /* header key */
        lua_pushnumber(cc, sr_headers->content_length_n); /* head key value */
        lua_rawset(cc, -3); /* head */
    }

    if (sr_headers->content_type.len) {
        lua_pushliteral(cc, "Content-Type"); /* header key */
        lua_pushlstring(cc, (char *) sr_headers->content_type.data,
                sr_headers->content_type.len); /* head key value */
        lua_rawset(cc, -3); /* head */
    }

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

#if 1
        if (header[i].hash == 0) {
            continue;
        }
#endif

        lua_pushlstring(cc, (char *) header[i].key.data,
                header[i].key.len); /* header key */

        lua_pushlstring(cc, (char *) header[i].value.data,
                header[i].value.len); /* header key value */

        lua_rawset(cc, -3); /* head */
    }

    lua_setfield(cc, -2, "header");

    /*  }}} */

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    dd("about to run thread...");

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, 1);

    dd("already run thread...");

    if (rc == NGX_AGAIN || rc == NGX_DONE) {
        ctx->waiting = 1;
        ctx->done = 0;

    } else {
        ctx->waiting = 0;
        ctx->done = 1;

        ngx_http_finalize_request(r, rc);
    }

    return;

error:
    ngx_http_finalize_request(r,
            ctx->headers_sent ? NGX_ERROR: NGX_HTTP_INTERNAL_SERVER_ERROR);

    return;
}

