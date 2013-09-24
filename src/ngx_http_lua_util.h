
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_UTIL_H_INCLUDED_
#define _NGX_HTTP_LUA_UTIL_H_INCLUDED_


#include "ngx_http_lua_common.h"


#ifndef NGX_UNESCAPE_URI_COMPONENT
#define NGX_UNESCAPE_URI_COMPONENT  0
#endif

/* char whose address we use as the key in Lua vm registry for
 * user code cache table */
extern char ngx_http_lua_code_cache_key;

/* char whose address we use as the key in Lua vm registry for
 * all the "ngx.ctx" tables */
extern char ngx_http_lua_ctx_tables_key;

/* char whose address we use as the key in Lua vm registry for
 * regex cache table  */
extern char ngx_http_lua_regex_cache_key;

/* char whose address we use as the key in Lua vm registry for
 * socket connection pool table */
extern char ngx_http_lua_socket_pool_key;

/* char whose address we use as the key for the coroutine parent relationship */
extern char ngx_http_lua_coroutine_parents_key;

/* coroutine anchoring table key in Lua VM registry */
extern char ngx_http_lua_coroutines_key;

/* key to the metatable for ngx.req.get_headers() */
extern char ngx_http_lua_req_get_headers_metatable_key;


#ifndef ngx_str_set
#define ngx_str_set(str, text)                                               \
    (str)->len = sizeof(text) - 1; (str)->data = (u_char *) text
#endif


#define ngx_http_lua_context_name(c)                                         \
    ((c) == NGX_HTTP_LUA_CONTEXT_SET ? "set_by_lua*"                         \
     : (c) == NGX_HTTP_LUA_CONTEXT_REWRITE ? "rewrite_by_lua*"               \
     : (c) == NGX_HTTP_LUA_CONTEXT_ACCESS ? "access_by_lua*"                 \
     : (c) == NGX_HTTP_LUA_CONTEXT_CONTENT ? "content_by_lua*"               \
     : (c) == NGX_HTTP_LUA_CONTEXT_LOG ? "log_by_lua*"                       \
     : (c) == NGX_HTTP_LUA_CONTEXT_HEADER_FILTER ? "header_filter_by_lua*"   \
     : (c) == NGX_HTTP_LUA_CONTEXT_TIMER ? "ngx.timer"   \
     : "(unknown)")


#define ngx_http_lua_check_context(L, ctx, flags)                            \
    if (!((ctx)->context & (flags))) {                                       \
        return luaL_error(L, "API disabled in the context of %s",            \
                          ngx_http_lua_context_name((ctx)->context));        \
    }


#define ngx_http_lua_check_fake_request(L, r)                                \
    if ((r)->connection->fd == -1) {                                         \
        return luaL_error(L, "API disabled in the current context");         \
    }


#define ngx_http_lua_check_fake_request2(L, r, ctx)                          \
    if ((r)->connection->fd == -1) {                                         \
        return luaL_error(L, "API disabled in the context of %s",            \
                          ngx_http_lua_context_name((ctx)->context));        \
    }


lua_State * ngx_http_lua_new_state(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);

lua_State * ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *l,
    int *ref);

u_char * ngx_http_lua_rebase_path(ngx_pool_t *pool, u_char *src, size_t len);

ngx_int_t ngx_http_lua_send_header_if_needed(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx);

ngx_int_t ngx_http_lua_send_chain_link(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_chain_t *cl);

void ngx_http_lua_discard_bufs(ngx_pool_t *pool, ngx_chain_t *in);

ngx_int_t ngx_http_lua_add_copy_chain(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_chain_t ***plast, ngx_chain_t *in,
    ngx_int_t *eof);

void ngx_http_lua_reset_ctx(ngx_http_request_t *r, lua_State *L,
    ngx_http_lua_ctx_t *ctx);

void ngx_http_lua_generic_phase_post_read(ngx_http_request_t *r);

void ngx_http_lua_request_cleanup(ngx_http_lua_ctx_t *ctx, int foricible);

void ngx_http_lua_request_cleanup_handler(void *data);

ngx_int_t ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, volatile int nret);

ngx_int_t ngx_http_lua_wev_handler(ngx_http_request_t *r);

u_char * ngx_http_lua_digest_hex(u_char *dest, const u_char *buf,
    int buf_len);

void ngx_http_lua_set_multi_value_table(lua_State *L, int index);

void ngx_http_lua_unescape_uri(u_char **dst, u_char **src, size_t size,
    ngx_uint_t type);

uintptr_t ngx_http_lua_escape_uri(u_char *dst, u_char *src,
    size_t size, ngx_uint_t type);

void ngx_http_lua_inject_req_api(ngx_log_t *log, lua_State *L);

void ngx_http_lua_process_args_option(ngx_http_request_t *r,
    lua_State *L, int table, ngx_str_t *args);

ngx_int_t ngx_http_lua_open_and_stat_file(u_char *name,
    ngx_open_file_info_t *of, ngx_log_t *log);

ngx_chain_t * ngx_http_lua_chains_get_free_buf(ngx_log_t *log, ngx_pool_t *p,
    ngx_chain_t **free, size_t len, ngx_buf_tag_t tag);

void ngx_http_lua_create_new_global_table(lua_State *L, int narr, int nrec);

int ngx_http_lua_traceback(lua_State *L);

ngx_http_lua_co_ctx_t * ngx_http_lua_get_co_ctx(lua_State *L,
    ngx_http_lua_ctx_t *ctx);

ngx_http_lua_co_ctx_t * ngx_http_lua_create_co_ctx(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx);

ngx_int_t ngx_http_lua_run_posted_threads(ngx_connection_t *c, lua_State *L,
    ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx);

ngx_int_t ngx_http_lua_post_thread(ngx_http_request_t *r,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_co_ctx_t *coctx);

void ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *L,
    ngx_http_lua_ctx_t *ctx, ngx_http_lua_co_ctx_t *coctx);

void ngx_http_lua_rd_check_broken_connection(ngx_http_request_t *r);

ngx_int_t ngx_http_lua_test_expect(ngx_http_request_t *r);

ngx_int_t ngx_http_lua_check_broken_connection(ngx_http_request_t *r,
    ngx_event_t *ev);

void ngx_http_lua_finalize_request(ngx_http_request_t *r, ngx_int_t rc);

void ngx_http_lua_finalize_fake_request(ngx_http_request_t *r,
    ngx_int_t rc);

void ngx_http_lua_close_fake_connection(ngx_connection_t *c);

void ngx_http_lua_release_ngx_ctx_table(ngx_log_t *log, lua_State *L,
    ngx_http_lua_ctx_t *ctx);


#define ngx_http_lua_check_if_abortable(L, ctx)                             \
    if ((ctx)->no_abort) {                                                  \
        return luaL_error(L, "attempt to abort with pending subrequests");  \
    }


static ngx_inline void
ngx_http_lua_init_ctx(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx)
{
    ngx_memzero(ctx, sizeof(ngx_http_lua_ctx_t));
    ctx->ctx_ref = LUA_NOREF;
    ctx->entry_co_ctx.co_ref = LUA_NOREF;
    ctx->resume_handler = ngx_http_lua_wev_handler;
    ctx->request = r;
}


static ngx_inline ngx_http_lua_ctx_t *
ngx_http_lua_create_ctx(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t      *ctx;

    ctx = ngx_palloc(r->pool, sizeof(ngx_http_lua_ctx_t));
    if (ctx == NULL) {
        return NULL;
    }

    ngx_http_lua_init_ctx(r, ctx);

    ngx_http_set_ctx(r, ctx, ngx_http_lua_module);
    return ctx;
}


static ngx_inline ngx_http_request_t *
ngx_http_lua_get_req(lua_State *L)
{
    ngx_http_request_t    *r;

    lua_pushliteral(L, "__ngx_req");
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    return r;
}


static ngx_inline void
ngx_http_lua_set_req(lua_State *L, ngx_http_request_t *r)
{
    lua_pushliteral(L, "__ngx_req");
    lua_pushlightuserdata(L, r);
    lua_rawset(L, LUA_GLOBALSINDEX);
}


#define ngx_http_lua_hash_literal(s)                                        \
    ngx_http_lua_hash_str((u_char *) s, sizeof(s) - 1)


static ngx_inline ngx_uint_t
ngx_http_lua_hash_str(u_char *src, size_t n)
{
    ngx_uint_t  key;

    key = 0;

    while (n--) {
        key = ngx_hash(key, *src);
        src++;
    }

    return key;
}


extern ngx_uint_t  ngx_http_lua_location_hash;
extern ngx_uint_t  ngx_http_lua_content_length_hash;


#endif /* _NGX_HTTP_LUA_UTIL_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
