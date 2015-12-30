


#include "ddebug.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_lfs_fdpool.h"

#if (NGX_THREADS)
void ngx_http_lua_lfs_fdpool_cleanup(void *data)
{
    ngx_http_request_t *r = data;
    ngx_http_lua_ctx_t *ctx;
    ngx_http_lfs_cached_fd_t *cfd;
    ngx_uint_t i;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return;
    }
    cfd = ctx->lfs_post_closed->elts;
    for (i = 0; i < ctx->lfs_post_closed->nelts; i ++) {
        ngx_close_file(cfd[i].fd);
    }
}


int ngx_http_lua_lfs_fdpool_init(ngx_http_lua_ctx_t *ctx,
        ngx_http_request_t *r)
{
    ngx_http_cleanup_t *cln;
    if (ctx->lfs_post_closed != NULL) {
        return 0;
    }

    if ((cln = ngx_http_cleanup_add(r, 0)) == NULL) {
        return -1;
    }
    cln->handler = ngx_http_lua_lfs_fdpool_cleanup;
    cln->data = r;

    ctx->lfs_post_closed = ngx_array_create(r->pool, 8, sizeof(ngx_http_lfs_cached_fd_t));
    if (ctx->lfs_post_closed == NULL) {
        return -1;
    }

    return 0;
}

ngx_fd_t ngx_http_lua_lfs_fdpool_get(ngx_http_request_t *r, u_char *filename)
{
    ngx_http_lua_ctx_t *ctx;
    ngx_http_lfs_cached_fd_t *cfd;
    ngx_uint_t i;
    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return -1;
    }

    cfd = ctx->lfs_post_closed->elts;
    for (i = 0; i < ctx->lfs_post_closed->nelts; i ++) {
        if (ngx_strcmp(cfd[i].filename, filename) == 0) {
            return cfd[i].fd;
        }
    }
    return -1;
}


int ngx_http_lua_lfs_fdpool_add(ngx_http_request_t *r, u_char *filename, ngx_fd_t fd)
{
    ngx_http_lfs_cached_fd_t *cfd;
    ngx_http_lua_ctx_t *ctx;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return -1;
    }

    if ((cfd = ngx_array_push(ctx->lfs_post_closed)) == NULL) {
        return -1;
    }

    if ((cfd->filename = ngx_palloc(r->pool, ngx_strlen(filename) + 1)) == NULL) {
        return -1;
    }
    ngx_cpystrn(cfd->filename, filename, ngx_strlen(filename) + 1);
    cfd->fd = fd;


    return 0;
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
