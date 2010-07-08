#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_util.h"

static void ngx_http_lua_request_cleanup(void *data);
static ngx_int_t ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
		ngx_http_lua_ctx_t *ctx, int nret);

ngx_int_t
ngx_http_lua_content_by_chunk(
        lua_State *L,
        ngx_http_request_t *r
        )
{
    int cc_ref;
    lua_State *cc;
    ngx_http_lua_ctx_t *ctx;
    ngx_http_cleanup_t *cln;

    /*  {{{ new coroutine to handle request */
    cc = ngx_http_lua_new_thread(r, L, &cc_ref);
    if(cc == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "(lua-content-by-chunk) failed to create new coroutine to handle request!");
        return NGX_ERROR;
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
            return NGX_ERROR;
        }

        ngx_http_set_ctx(r, ctx, ngx_http_lua_module);
    }
    ctx->cc = cc;
    ctx->cc_ref = cc_ref;
    /*  }}} */

    /*  {{{ register request cleanup hooks */
    cln = ngx_http_cleanup_add(r, 0);
    cln->data = r;
    cln->handler = ngx_http_lua_request_cleanup;
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

	cc = ctx->cc;
	cc_ref = ctx->cc_ref;

    /*  run code */
    rc = lua_resume(cc, nret);

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
        msg = lua_tostring(cc, -1);

    } else {
        msg = "unknown reason";
    }

    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
            "content_by_lua prematurely ended: %s: %s",
            err, msg);

    ngx_http_lua_del_thread(r, L, cc_ref, 0);

    return ctx->headers_sent ? NGX_ERROR : NGX_HTTP_INTERNAL_SERVER_ERROR;
}


static void
ngx_http_lua_request_cleanup(void *data)
{
    ngx_http_request_t *r = data;
    ngx_http_lua_main_conf_t *lmcf;
    ngx_http_lua_ctx_t *ctx;
    lua_State *L;

    dd("(lua-request-cleanup) force request coroutine quit");

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    L = lmcf->lua;
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    /*  force coroutine handling the request quit */
    if (ctx != NULL) {
        lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
        lua_rawgeti(L, -1, ctx->cc_ref);

        if (lua_isthread(L, -1)) {
            /*  coroutine not finished yet, force quit */
            ngx_http_lua_del_thread(r, L, ctx->cc_ref, 1);
            ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
        }

        lua_pop(L, 2);
    }
}


void
ngx_http_lua_wev_handler(ngx_http_request_t *r)
{
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;
	ngx_http_lua_main_conf_t    *lmcf;
	lua_State                   *cc;
	ngx_chain_t	                *cl;
	size_t                       len;
	u_char                      *pos, *last;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
		goto error;
    }

    if (ctx->waiting && ! ctx->done) {
        if (r->main->posted_requests
                && r->main->posted_requests->request != r)
        {
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
	for(cl = ctx->sr_body; cl; cl = cl->next) {
		/*  ignore all non-memory buffers */
		len += cl->buf->last - cl->buf->pos;
	}

	if(len == 0) {
		pos = NULL;
	} else {
		last = pos = ngx_palloc(r->pool, len);
		if(pos == NULL) {
			goto error;
		}

		for(cl = ctx->sr_body; cl; cl = cl->next) {
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
	lua_pushlstring(cc, (const char*)pos, len);
	lua_setfield(cc, -2, "body");
	/*  }}} */

	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    rc = ngx_http_lua_run_thread(lmcf->lua, r, ctx, 1);

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

/*  vi:ts=4 sw=4 fdm=marker
*/

