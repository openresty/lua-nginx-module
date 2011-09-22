#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_pcrefix.h"

#if (NGX_PCRE)

static ngx_pool_t *ngx_http_lua_pcre_pool;

static void *(*old_pcre_malloc)(size_t);
static void (*old_pcre_free)(void *ptr);


/* XXX: work-around to nginx regex subsystem, must init a memory pool
 * to use PCRE functions. As PCRE still has memory-leaking problems,
 * and nginx overwrote pcre_malloc/free hooks with its own static
 * functions, so nobody else can reuse nginx regex subsystem... */
static void *
ngx_http_lua_pcre_malloc(size_t size)
{
	if (ngx_http_lua_pcre_pool) {
		return ngx_palloc(ngx_http_lua_pcre_pool, size);
	}

	return NULL;
}


static void
ngx_http_lua_pcre_free(void *ptr)
{
	if (ngx_http_lua_pcre_pool) {
		ngx_pfree(ngx_http_lua_pcre_pool, ptr);
	}
}


void
ngx_http_lua_pcre_malloc_init(ngx_pool_t *pool)
{
	ngx_http_lua_pcre_pool = pool;

	old_pcre_malloc = pcre_malloc;
	old_pcre_free = pcre_free;

    pcre_malloc = ngx_http_lua_pcre_malloc;
    pcre_free = ngx_http_lua_pcre_free;
}


void
ngx_http_lua_pcre_malloc_done()
{
	ngx_http_lua_pcre_pool = NULL;

	pcre_malloc = old_pcre_malloc;
	pcre_free = old_pcre_free;
}

#endif /* NGX_PCRE */

/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

