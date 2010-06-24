#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"

static ngx_int_t ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr);
static ngx_int_t ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc);

// longjmp mark for restoring nginx execution after Lua VM crashing
jmp_buf ngx_http_lua_exception;

/**
 * Override default Lua panic handler, output VM crash reason to NginX error
 * log, and restore execution to the nearest jmp-mark.
 * 
 * @param l Lua state pointer
 * @retval Long jump to the nearest jmp-mark, never returns.
 * @note NginX request pointer should be stored in Lua thread's globals table
 * in order to make logging working.
 * */
int
ngx_http_lua_atpanic(lua_State *l)
{
    const char *s = luaL_checkstring(l, 1);
    ngx_http_request_t *r;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

    // log Lua VM crashing reason to error log
    if(r && r->connection && r->connection->log) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-atpanic) Lua VM crashed, reason: %s", s);
    } else {
        dd("(lua-atpanic) can't output Lua VM crashing reason to error log"
                " due to invalid logging context: %s", s);
    }

    // restore nginx execution
    longjmp(ngx_http_lua_exception, 1);
}

/**
 * Override Lua print function, output message to NginX error logs.
 *
 * @param l Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * @note NginX request pointer should be stored in Lua VM registry with key
 * 'ngx._req' in order to make logging working.
 * */
int
ngx_http_lua_print(lua_State *l)
{
    ngx_http_request_t *r;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

    if(r && r->connection && r->connection->log) {
		const char *s;

		// XXX: easy way to support multiple args, any serious performance penalties?
		lua_concat(l, lua_gettop(l));
		s = lua_tostring(l, -1);

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-print) %s", (s == NULL) ? "(null)" : s);
    } else {
        dd("(lua-print) can't output print content to error log due to invalid logging context!");
    }

    return 0;
}

/**
 * Send out headers
 * */
int
ngx_http_lua_ngx_send_headers(lua_State *l)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

	if(r) {
		ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
		if(ctx != NULL && ctx->headers_sent == 0) {
			ngx_http_lua_send_header_if_needed(r, ctx);
		}
	} else {
		dd("(lua-ngx-send-headers) can't find nginx request object!");
	}

	return 0;
}

/**
 * Output response body
 * */
int
ngx_http_lua_ngx_echo(lua_State *l)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

	if(r) {
		ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
		if(ctx != NULL && ctx->eof == 0) {
			const char *data;
			size_t len;
			ngx_buf_t *buf;
			ngx_chain_t *cl;

			// concatenate all args into single string
			// XXX: easy way to support multiple args, any serious performance penalties?
			lua_concat(l, lua_gettop(l));
			data = lua_tolstring(l, -1, &len);

			if(data) {
				buf = ngx_calloc_buf(r->pool);
				if(buf == NULL) {
					ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
							"(lua-ngx-echo) can't allocate memory for output buffer!");
				} else {
					// FIXME: need to copy the content first! as lua string
					// will be invalid when it's poped out from stack
					buf->start = buf->pos = (u_char*)data;
					buf->last = buf->end = (u_char*)(data + len);
					buf->memory = 1;

					cl = ngx_alloc_chain_link(r->pool);
					if(cl == NULL) {
						ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
								"(lua-ngx-echo) can't allocate memory for output chain-link!");
					} else {
						cl->next = NULL;
						cl->buf = buf;

						ngx_http_lua_send_chain_link(r, ctx, cl);
					}
				}
			}

			// clear args
			lua_settop(l, 0);
		}
	} else {
		dd("(lua-ngx-echo) can't find nginx request object!");
	}

	return 0;
}

/**
 * Force flush out response content
 * */
int
ngx_http_lua_ngx_flush(lua_State *l)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;
	ngx_buf_t *buf;
	ngx_chain_t *cl;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

	if(r) {
		ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
		if(ctx != NULL && ctx->eof == 0) {
			buf = ngx_calloc_buf(r->pool);
			if(buf == NULL) {
				ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
						"(lua-ngx-flush) can't allocate memory for output buffer!");
			} else {
				buf->flush = 1;
				buf->sync = 1;

				cl = ngx_alloc_chain_link(r->pool);
				if(cl == NULL) {
					ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
							"(lua-ngx-flush) can't allocate memory for output chain-link!");
				} else {
					cl->next = NULL;
					cl->buf = buf;

					ngx_http_lua_send_chain_link(r, ctx, cl);
				}
			}
		}
	} else {
		dd("(lua-ngx-flush) can't find nginx request object!");
	}

	return 0;
}

/**
 * Send last_buf, terminate output stream
 * */
int
ngx_http_lua_ngx_eof(lua_State *l)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

	if(r) {
		ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
		if(ctx != NULL && ctx->eof == 0) {
			ctx->eof = 1;	// set eof flag to prevent further output
			ngx_http_lua_send_chain_link(r, ctx, NULL/*indicate last_buf*/);
		}
	} else {
		dd("(lua-ngx-eof) can't find nginx request object!");
	}

	return 0;
}

int
ngx_http_lua_ngx_location_capture(lua_State *l)
{
	ngx_http_request_t *r;
    ngx_http_request_t                  *sr; /* subrequest object */
    ngx_http_post_subrequest_t          *psr;
	ngx_http_lua_ctx_t *sr_ctx;
	ngx_str_t uri, args;
	ngx_uint_t flags = 0;
	const char *p;
	size_t plen;
	int rc;

	lua_getglobal(l, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(l, -1);
    lua_pop(l, 1);

	if(r == NULL) {
		dd("(lua-ngx-location-capture) can't find nginx request object!");

		goto error;
	}

	p = luaL_checklstring(l, -1, &plen);
	if(p == NULL) {
		dd("(lua-ngx-location-capture) no valid uri found!");

		goto error;
	}

	uri.data = ngx_palloc(r->pool, plen);
	if(uri.data == NULL) {
		goto error;
	}
	uri.len = plen;

	ngx_memcpy(uri.data, p, plen);

    args.data = NULL;
    args.len = 0;

    if (ngx_http_parse_unsafe_uri(r, &uri, &args, &flags) != NGX_OK) {
		goto error;
    }

    psr = ngx_palloc(r->pool, sizeof(ngx_http_post_subrequest_t));
    if (psr == NULL) {
		goto error;
    }

	sr_ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
	if(sr_ctx == NULL) {
		goto error;
	}
	sr_ctx->capture = 1;

    psr->handler = ngx_http_lua_post_subrequest;
    psr->data = sr_ctx;

    rc = ngx_http_subrequest(r, &uri, &args, &sr, psr, 0);

    if (rc != NGX_OK) {
		goto error;
    }

	ngx_http_set_ctx(sr, sr_ctx, ngx_http_lua_module);

    rc = ngx_http_lua_adjust_subrequest(sr);

    if (rc != NGX_OK) {
		goto error;
    }

	lua_pushinteger(l, location_capture);
	return lua_yield(l, 1);

error:
	lua_pushnil(l);
	return 1;
}

static ngx_int_t
ngx_http_lua_adjust_subrequest(ngx_http_request_t *sr)
{
    ngx_http_core_main_conf_t   *cmcf;
    ngx_http_request_t          *r;


    /* we do not inherit the parent request's variables */
    cmcf = ngx_http_get_module_main_conf(sr, ngx_http_core_module);

    r = sr->parent;

    sr->header_in = r->header_in;

    /* XXX work-around a bug in ngx_http_subrequest */
    if (r->headers_in.headers.last == &r->headers_in.headers.part) {
        sr->headers_in.headers.last = &sr->headers_in.headers.part;
    }

    sr->variables = ngx_pcalloc(sr->pool, cmcf->variables.nelts
                                        * sizeof(ngx_http_variable_value_t));

    if (sr->variables == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_http_lua_post_subrequest(ngx_http_request_t *r, void *data, ngx_int_t rc)
{
    ngx_http_request_t          *pr;
    ngx_http_lua_ctx_t         *pr_ctx;
	ngx_http_lua_ctx_t	*ctx = data;

    pr = r->parent;

    pr_ctx = ngx_http_get_module_ctx(pr, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    pr_ctx->waiting = 0;
    pr_ctx->done = 1;

    pr->write_event_handler = ngx_http_lua_wev_handler;

	// capture subrequest response status
	if(rc == NGX_ERROR) {
		pr_ctx->sr_status = NGX_HTTP_INTERNAL_SERVER_ERROR;
	} else if(rc >= NGX_HTTP_SPECIAL_RESPONSE) {
		pr_ctx->sr_status = rc;
	} else {
		pr_ctx->sr_status = r->headers_out.status;
	}

	// copy subrequest response body
	pr_ctx->sr_body = ctx->body;

    /* ensure that the parent request is (or will be)
     *  posted out the head of the r->posted_requests chain */

    if (r->main->posted_requests
            && r->main->posted_requests->request != pr)
    {
        rc = ngx_http_lua_post_request_at_head(pr, NULL);
        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return rc;
}

// vi:ts=4 sw=4 fdm=marker

