#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_req_body.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_read_body(lua_State *L);
static void ngx_http_lua_req_body_post_read(ngx_http_request_t *r);
static int ngx_http_lua_ngx_req_discard_body(lua_State *L);
static int ngx_http_lua_ngx_req_get_body_data(lua_State *L);
static int ngx_http_lua_ngx_req_get_body_file(lua_State *L);
static int ngx_http_lua_ngx_req_set_body_data(lua_State *L);
static void ngx_http_lua_pool_cleanup_file(ngx_pool_t *p, ngx_fd_t fd);


void
ngx_http_lua_inject_req_body_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_read_body);
    lua_setfield(L, -2, "read_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_discard_body);
    lua_setfield(L, -2, "discard_body");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_body_data);
    lua_setfield(L, -2, "get_body_data");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_body_file);
    lua_setfield(L, -2, "get_body_file");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_body_data);
    lua_setfield(L, -2, "set_body_data");
}


static int
ngx_http_lua_ngx_req_read_body(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    r->request_body_in_single_buf = 1;
    r->request_body_in_persistent_file = 1;
    r->request_body_in_clean_file = 1;

#if 0
    if (r->request_body_in_file_only) {
        r->request_body_file_log_level = 0;
    }
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "request context is null");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua start to read buffered request body");

    rc = ngx_http_read_client_request_body(r, ngx_http_lua_req_body_post_read);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to read request body");
    }

    if (rc == NGX_AGAIN) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua read buffered request body requires I/O interruptions");

        ctx->waiting_more_body = 1;
        ctx->req_read_body_done = 0;

        return lua_yield(L, 0);
    }

    /* rc == NGX_OK */

    ctx->req_read_body_done = 0;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua has read buffered request body in a single run");

    return 0;
}


static void
ngx_http_lua_req_body_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua req body post read");

    r->read_event_handler = ngx_http_block_reading;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    ctx->req_read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;

        if (ctx->entered_content_phase) {
            ngx_http_lua_wev_handler(r);

        } else {
            ngx_http_core_run_phases(r);
        }
    }
}


static int
ngx_http_lua_ngx_req_discard_body(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_int_t                    rc;
    int                          n;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    rc = ngx_http_discard_request_body(r);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to discard request body");
    }

    return 0;
}


static int
ngx_http_lua_ngx_req_get_body_data(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    size_t                       len;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r->request_body == NULL
        || r->request_body->temp_file
        || r->request_body->bufs == NULL)
    {
        lua_pushnil(L);
        return 1;
    }

    len = r->request_body->bufs->buf->last - r->request_body->bufs->buf->pos;

    if (len == 0) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlstring(L, (char *) r->request_body->bufs->buf->pos, len);
    return 1;
}


static int
ngx_http_lua_ngx_req_get_body_file(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r->request_body == NULL || r->request_body->temp_file == NULL) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlstring(L, (char *) r->request_body->temp_file->file.name.data,
                       r->request_body->temp_file->file.name.len);
    return 1;
}


static int
ngx_http_lua_ngx_req_set_body_data(lua_State *L)
{
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_request_body_t     *rb;
    ngx_chain_t                 *cl;
    ngx_temp_file_t             *tf;
    ngx_buf_t                   *b;
    ngx_str_t                    body;
#if 1
    ngx_int_t                    rc;
#endif

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting 1 arguments but seen %d", n);
    }

    body.data = (u_char *) luaL_checklstring(L, 1, &body.len);

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r->request_body == NULL) {

#if 1
        rc = ngx_http_discard_request_body(r);
        if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
            return luaL_error(L, "failed to discard request body");
        }
#endif

        rb = ngx_pcalloc(r->pool, sizeof(ngx_http_request_body_t));
        if (rb == NULL) {
            return luaL_error(L, "out of memory");
        }

        r->request_body = rb;

    } else {
        rb = r->request_body;
    }

    tf = rb->temp_file;

    if (tf) {
        if (tf->file.fd != NGX_INVALID_FILE) {

            dd("cleaning temp file %.*s", (int) tf->file.name.len,
                    tf->file.name.data);

            ngx_http_lua_pool_cleanup_file(r->pool, tf->file.fd);
            tf->file.fd = NGX_INVALID_FILE;

            dd("temp file cleaned: %.*s", (int) tf->file.name.len,
                    tf->file.name.data);
        }

        rb->temp_file = NULL;
    }

    if (rb->bufs) {
        for (cl = rb->bufs; cl; cl = cl->next) {
            if (cl->buf->temporary) {
                ngx_pfree(r->pool, cl->buf->start);
            }
        }

        rb->bufs->next = NULL;

        b = rb->bufs->buf;

        ngx_memzero(b, sizeof(ngx_buf_t));
        b->temporary = 1;
        b->start = ngx_palloc(r->pool, body.len);
        if (b->start == NULL) {
            return luaL_error(L, "out of memory");
        }
        b->end = b->start + body.len;

        b->pos = b->start;
        b->last = ngx_copy(b->pos, body.data, body.len);

    } else {

        rb->bufs = ngx_alloc_chain_link(r->pool);
        if (rb->bufs == NULL) {
            return luaL_error(L, "out of memory");
        }

        b = ngx_create_temp_buf(r->pool, body.len);
        b->last = ngx_copy(b->pos, body.data, body.len);

        rb->bufs->buf = b;
        rb->bufs->next = NULL;
    }

    return 0;
}


static void
ngx_http_lua_pool_cleanup_file(ngx_pool_t *p, ngx_fd_t fd)
{
    ngx_pool_cleanup_t       *c;
    ngx_pool_cleanup_file_t  *cf;

    for (c = p->cleanup; c; c = c->next) {
        if (c->handler == ngx_pool_cleanup_file
            || c->handler == ngx_pool_delete_file)
        {

            cf = c->data;

            if (cf->fd == fd) {
                c->handler(cf);
                c->handler = NULL;
                return;
            }
        }
    }
}

