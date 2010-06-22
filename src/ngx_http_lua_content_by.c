#include "ngx_http_lua_content_by.h"
#include "ngx_http_lua_util.h"

static void ngx_http_lua_request_cleanup(void *data);

ngx_int_t
ngx_http_lua_content_by_chunk(
		lua_State *l,
		ngx_http_request_t *r
		)
{
	int rc;
	int cc_ref;
	lua_State *cc;
	ngx_http_lua_ctx_t *ctx;
	ngx_http_cleanup_t *cln;
	const char *err, *msg;

	// {{{ new coroutine to handle request
	cc = ngx_http_lua_new_thread(r, l, &cc_ref);
	if(cc == NULL) {
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"(lua-content-by-chunk) failed to create new coroutine to handle request!");
		return NGX_ERROR;
	}

	// move code closure to new coroutine
	lua_xmove(l, cc, 1);

	// set closure's env table to new coroutine's globals table
	lua_pushvalue(cc, LUA_GLOBALSINDEX);
	lua_setfenv(cc, -2);

	// save reference of code to ease forcing stopping
	lua_pushvalue(cc, -1);
	lua_setglobal(cc, GLOBALS_SYMBOL_RUNCODE);

	// save nginx request in coroutine globals table
	lua_pushlightuserdata(cc, r);
	lua_setglobal(cc, GLOBALS_SYMBOL_REQUEST);
	// }}}

	// {{{ initialize request context
	ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
	if(ctx == NULL) {
		ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
		ngx_http_set_ctx(r, ctx, ngx_http_lua_module);
	}
	ctx->cc = cc;
	ctx->cc_ref = cc_ref;
	// }}}

	// {{{ register request cleanup hooks
	cln = ngx_http_cleanup_add(r, 0);
	cln->data = r;
	cln->handler = ngx_http_lua_request_cleanup;
	// }}}

	// run code
	rc = lua_resume(cc, 0);

	switch(rc) {
		case LUA_YIELD:
			// yielded, let event handler do the rest job
			return NGX_AGAIN;
		case 0:
			// normal end
			ngx_http_lua_del_thread(r, l, cc_ref, 0);
			ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
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

	if(lua_isstring(cc, -1)) {
		msg = lua_tostring(cc, -1);
	} else {
		msg = "unknown reason";
	}

	ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
			"(lua-content-by-chunk) Request handler prematurely ended (rc = %d): %s: %s",
			rc, err, msg);

	ngx_http_lua_del_thread(r, l, cc_ref, 0);
	ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
	return NGX_ERROR;
}

static void
ngx_http_lua_request_cleanup(void *data)
{
	ngx_http_request_t *r = data;
	ngx_http_lua_main_conf_t *lmcf;
	ngx_http_lua_ctx_t *ctx;
	lua_State *l;

	dd("(lua-request-cleanup) force request coroutine quit");

	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	l = lmcf->lua;
	ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

	// force coroutine handling the request quit
	if(ctx != NULL) {
		lua_getfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
		lua_rawgeti(l, -1, ctx->cc_ref);

		if(lua_isthread(l, -1)) {
			// coroutine not finished yet, force quit
			ngx_http_lua_del_thread(r, l, ctx->cc_ref, 1);
			ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
		}

		lua_pop(l, 2);
	}
}

// vi:ts=4 sw=4 fdm=marker

