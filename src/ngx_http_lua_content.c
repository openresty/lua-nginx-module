#include "ngx_http_lua_content.h"

ngx_int_t
ngx_http_lua_content_by_chunk(
		lua_State *l,
		ngx_http_request_t *r
		)
{
	// 1. prepare new env w/ ngx.* api
	// 2. reg cleanup handler for cur req
	// 3. create new coroutine & load code chunk onto its stack
	// 4. resume coroutine & block waiting
	// 5. when coroutine returned, check if it yielded actively, if so, inc ref cnt and ret NGX_DONE
	// 6. if coroutine ret normally or due to error occured, resp correspondingly and unref coroutine
	return NGX_OK;
}

// vi:ts=4 sw=4 fdm=marker

