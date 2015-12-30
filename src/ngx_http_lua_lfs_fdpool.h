

/**
 * Copyright (C) Terry AN (anhk)
 **/

#ifndef _NGX_HTTP_LUA_LFS_FDPOOL_H_INCLUDED_
#define _NGX_HTTP_LUA_LFS_FDPOOL_H_INCLUDED_


#if (NGX_THREADS)

/**
 * cached file descriptor
 **/
typedef struct _ngx_http_lfs_cached_fd_s {
    u_char *filename;
    ngx_fd_t fd;
} ngx_http_lfs_cached_fd_t;

void ngx_http_lua_lfs_fdpool_cleanup(void *data);
int ngx_http_lua_lfs_fdpool_init(ngx_http_lua_ctx_t *ctx, ngx_http_request_t *r);
ngx_fd_t ngx_http_lua_lfs_fdpool_get(ngx_http_request_t *r, u_char *filename);
int ngx_http_lua_lfs_fdpool_add(ngx_http_request_t *r, u_char *filename, ngx_fd_t fd);

#endif

#endif
