
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_async_fs.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"

#include <sys/stat.h>


#if (NGX_THREADS)

#include <ngx_thread.h>
#include <ngx_thread_pool.h>


#define NGX_HTTP_LUA_FS_OP_OPEN   0
#define NGX_HTTP_LUA_FS_OP_READ   1
#define NGX_HTTP_LUA_FS_OP_WRITE  2
#define NGX_HTTP_LUA_FS_OP_STAT   3

#define NGX_HTTP_LUA_FS_FILE_MT        "ngx_http_lua_fs_file"
#define NGX_HTTP_LUA_FS_POOL_NAME_MAX  64


typedef struct {
    ngx_fd_t     fd;
    ngx_uint_t   ninflight;
    unsigned     closed:1;
    unsigned     orphaned:1;
} ngx_http_lua_fs_fd_ref_t;


typedef struct {
    ngx_http_lua_fs_fd_ref_t  *ref;
    u_char                     pool_name[NGX_HTTP_LUA_FS_POOL_NAME_MAX];
    size_t                     pool_name_len;
} ngx_http_lua_fs_file_t;


typedef struct {
    ngx_uint_t               op;

    /* open params */
    u_char                  *path;
    int                      flags;
    int                      create_mode;

    /* read/write params */
    ngx_fd_t                 fd;
    u_char                  *buf;
    size_t                   size;
    off_t                    offset;

    ngx_http_lua_fs_fd_ref_t  *ref;

    ssize_t                  nbytes;
    ngx_fd_t                 result_fd;
    ngx_err_t                err;
    struct stat              fi;

    u_char                   pool_name[NGX_HTTP_LUA_FS_POOL_NAME_MAX];
    size_t                   pool_name_len;

    ngx_http_lua_co_ctx_t   *wait_co_ctx;

    unsigned                 is_abort:1;
} ngx_http_lua_fs_ctx_t;


static int ngx_http_lua_fs_open(lua_State *L);
static int ngx_http_lua_fs_stat(lua_State *L);

static int ngx_http_lua_fs_file_read(lua_State *L);
static int ngx_http_lua_fs_file_write(lua_State *L);
static int ngx_http_lua_fs_file_close(lua_State *L);
static int ngx_http_lua_fs_file_gc(lua_State *L);
static int ngx_http_lua_fs_file_tostring(lua_State *L);

static void ngx_http_lua_fs_thread_handler(void *data, ngx_log_t *log);
static void ngx_http_lua_fs_event_handler(ngx_event_t *ev);
static void ngx_http_lua_fs_cleanup(void *data);
static ngx_int_t ngx_http_lua_fs_resume(ngx_http_request_t *r);


static void
ngx_http_lua_fs_fd_ref_release(ngx_http_lua_fs_fd_ref_t *ref)
{
    if (!ref->closed) {
        ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0,
                      "lua async fs: auto-closing fd %d%s",
                      ref->fd,
                      ref->orphaned ? " (orphaned)" : "");

        close(ref->fd);
        ref->closed = 1;
    }

    ngx_free(ref);
}


static ngx_thread_task_t *
ngx_http_lua_fs_task_alloc(size_t size)
{
    ngx_thread_task_t  *task;

    task = ngx_calloc(sizeof(ngx_thread_task_t) + size, ngx_cycle->log);
    if (task == NULL) {
        return NULL;
    }

    task->ctx = task + 1;

    return task;
}


static void
ngx_http_lua_fs_task_free(ngx_http_lua_fs_ctx_t *fs_ctx)
{
    ngx_thread_task_t  *task;

    task = (ngx_thread_task_t *) fs_ctx - 1;
    ngx_free(task);
}


static void
ngx_http_lua_fs_free_bufs(ngx_http_lua_fs_ctx_t *fs_ctx)
{
    if (fs_ctx->path != NULL) {
        ngx_free(fs_ctx->path);
        fs_ctx->path = NULL;
    }

    if (fs_ctx->buf != NULL) {
        ngx_free(fs_ctx->buf);
        fs_ctx->buf = NULL;
    }
}


static void
ngx_http_lua_fs_thread_handler(void *data, ngx_log_t *log)
{
    ngx_http_lua_fs_ctx_t  *fs_ctx = data;

    switch (fs_ctx->op) {

    case NGX_HTTP_LUA_FS_OP_OPEN:
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                       "lua async fs: open \"%s\"", fs_ctx->path);

        fs_ctx->result_fd = open((const char *) fs_ctx->path,
                                 fs_ctx->flags, fs_ctx->create_mode);

        if (fs_ctx->result_fd == -1) {
            fs_ctx->err = ngx_errno;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_READ:
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, log, 0,
                       "lua async fs: pread fd=%d size=%uz offset=%O",
                       fs_ctx->fd, fs_ctx->size, fs_ctx->offset);

        fs_ctx->nbytes = pread(fs_ctx->fd, fs_ctx->buf,
                               fs_ctx->size, fs_ctx->offset);

        if (fs_ctx->nbytes == -1) {
            fs_ctx->err = ngx_errno;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_WRITE:
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, log, 0,
                       "lua async fs: pwrite fd=%d size=%uz offset=%O",
                       fs_ctx->fd, fs_ctx->size, fs_ctx->offset);

        fs_ctx->nbytes = pwrite(fs_ctx->fd, fs_ctx->buf,
                                fs_ctx->size, fs_ctx->offset);

        if (fs_ctx->nbytes == -1) {
            fs_ctx->err = ngx_errno;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_STAT:
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, log, 0,
                       "lua async fs: lstat \"%s\"", fs_ctx->path);

        if (lstat((const char *) fs_ctx->path, &fs_ctx->fi) == -1) {
            fs_ctx->err = ngx_errno;
        }

        break;

    default:
        ngx_log_error(NGX_LOG_ALERT, log, 0,
                      "lua async fs: unknown op %ui", fs_ctx->op);
        break;
    }
}


static ngx_int_t
ngx_http_lua_fs_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_connection_t            *c;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx,
                                 ctx->cur_co_ctx
                                     ->nresults_from_worker_thread);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua async fs run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_fs_push_stat_table(lua_State *L, struct stat *fi)
{
    lua_createtable(L, 0, 12);

    lua_pushinteger(L, (lua_Integer) fi->st_size);
    lua_setfield(L, -2, "size");

    lua_pushinteger(L, (lua_Integer) fi->st_mtime);
    lua_setfield(L, -2, "mtime");

    lua_pushinteger(L, (lua_Integer) fi->st_atime);
    lua_setfield(L, -2, "atime");

    lua_pushinteger(L, (lua_Integer) fi->st_ctime);
    lua_setfield(L, -2, "ctime");

    lua_pushinteger(L, (lua_Integer) fi->st_mode);
    lua_setfield(L, -2, "mode");

    lua_pushinteger(L, (lua_Integer) fi->st_ino);
    lua_setfield(L, -2, "ino");

    lua_pushinteger(L, (lua_Integer) fi->st_nlink);
    lua_setfield(L, -2, "nlink");

    lua_pushinteger(L, (lua_Integer) fi->st_uid);
    lua_setfield(L, -2, "uid");

    lua_pushinteger(L, (lua_Integer) fi->st_gid);
    lua_setfield(L, -2, "gid");

    lua_pushboolean(L, S_ISDIR(fi->st_mode));
    lua_setfield(L, -2, "is_dir");

    lua_pushboolean(L, S_ISREG(fi->st_mode));
    lua_setfield(L, -2, "is_file");

    lua_pushboolean(L, S_ISLNK(fi->st_mode));
    lua_setfield(L, -2, "is_link");
}


static void
ngx_http_lua_fs_abort_cleanup(ngx_http_lua_fs_ctx_t *fs_ctx)
{
    ngx_http_lua_fs_fd_ref_t  *ref;

    ref = fs_ctx->ref;

    if (ref != NULL) {
        ref->ninflight--;

        if (ref->orphaned && ref->ninflight == 0) {
            ngx_http_lua_fs_fd_ref_release(ref);
        }

        fs_ctx->ref = NULL;
    }

    if (fs_ctx->op == NGX_HTTP_LUA_FS_OP_OPEN
        && fs_ctx->err == 0
        && fs_ctx->result_fd != -1)
    {
        ngx_log_error(NGX_LOG_NOTICE, ngx_cycle->log, 0,
                      "lua async fs: closing leaked fd %d "
                      "from aborted open",
                      fs_ctx->result_fd);

        if (close(fs_ctx->result_fd) == -1) {
            ngx_log_error(NGX_LOG_ALERT, ngx_cycle->log, ngx_errno,
                          "lua async fs: close(%d) failed",
                          fs_ctx->result_fd);
        }
    }
}


static void
ngx_http_lua_fs_event_handler(ngx_event_t *ev)
{
    ngx_http_lua_fs_ctx_t        *fs_ctx;
    ngx_http_lua_fs_file_t       *file;
    ngx_http_lua_fs_fd_ref_t     *ref;
    lua_State                    *L;
    ngx_http_request_t           *r;
    ngx_connection_t             *c;
    ngx_http_lua_ctx_t           *ctx;
    int                           nresults;

    fs_ctx = ev->data;

    if (fs_ctx->is_abort) {
        ngx_http_lua_fs_abort_cleanup(fs_ctx);

        ngx_http_lua_fs_free_bufs(fs_ctx);
        ngx_http_lua_fs_task_free(fs_ctx);
        return;
    }

    L = fs_ctx->wait_co_ctx->co;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        goto failed;
    }

    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        goto failed;
    }

    if (fs_ctx->ref != NULL) {
        fs_ctx->ref->ninflight--;
        fs_ctx->ref = NULL;
    }

    switch (fs_ctx->op) {

    case NGX_HTTP_LUA_FS_OP_OPEN:
        if (fs_ctx->err) {
            lua_pushnil(L);
            lua_pushfstring(L, "open() \"%s\" failed (%d: %s)",
                            fs_ctx->path, (int) fs_ctx->err,
                            strerror(fs_ctx->err));
            nresults = 2;

        } else {
            ref = ngx_calloc(sizeof(ngx_http_lua_fs_fd_ref_t),
                             ngx_cycle->log);

            if (ref == NULL) {
                close(fs_ctx->result_fd);

                lua_pushnil(L);
                lua_pushliteral(L, "no memory for fd ref");
                nresults = 2;
                break;
            }

            ref->fd = fs_ctx->result_fd;

            file = (ngx_http_lua_fs_file_t *)
                       lua_newuserdata(L, sizeof(ngx_http_lua_fs_file_t));

            file->ref = ref;
            file->pool_name_len = fs_ctx->pool_name_len;
            ngx_memcpy(file->pool_name, fs_ctx->pool_name,
                       fs_ctx->pool_name_len);

            luaL_getmetatable(L, NGX_HTTP_LUA_FS_FILE_MT);
            lua_setmetatable(L, -2);

            nresults = 1;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_READ:
        if (fs_ctx->err) {
            lua_pushnil(L);
            lua_pushfstring(L, "pread() failed (%d: %s)",
                            (int) fs_ctx->err, strerror(fs_ctx->err));
            nresults = 2;

        } else if (fs_ctx->nbytes == 0) {
            lua_pushliteral(L, "");
            nresults = 1;

        } else {
            lua_pushlstring(L, (const char *) fs_ctx->buf,
                            (size_t) fs_ctx->nbytes);
            nresults = 1;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_WRITE:
        if (fs_ctx->err) {
            lua_pushnil(L);
            lua_pushfstring(L, "pwrite() failed (%d: %s)",
                            (int) fs_ctx->err, strerror(fs_ctx->err));
            nresults = 2;

        } else {
            lua_pushinteger(L, (lua_Integer) fs_ctx->nbytes);
            nresults = 1;
        }

        break;

    case NGX_HTTP_LUA_FS_OP_STAT:
        if (fs_ctx->err) {
            lua_pushnil(L);
            lua_pushfstring(L, "stat() \"%s\" failed (%d: %s)",
                            fs_ctx->path, (int) fs_ctx->err,
                            strerror(fs_ctx->err));
            nresults = 2;

        } else {
            ngx_http_lua_fs_push_stat_table(L, &fs_ctx->fi);
            nresults = 1;
        }

        break;

    default:
        lua_pushnil(L);
        lua_pushliteral(L, "unknown fs operation");
        nresults = 2;
        break;
    }

    ctx->cur_co_ctx = fs_ctx->wait_co_ctx;
    ctx->cur_co_ctx->nresults_from_worker_thread = nresults;
    ctx->cur_co_ctx->cleanup = NULL;

    ngx_http_lua_fs_free_bufs(fs_ctx);
    ngx_http_lua_fs_task_free(fs_ctx);

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_fs_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_fs_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
    return;

failed:

    ngx_http_lua_fs_abort_cleanup(fs_ctx);

    ngx_http_lua_fs_free_bufs(fs_ctx);
    ngx_http_lua_fs_task_free(fs_ctx);
}


static void
ngx_http_lua_fs_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t      *coctx = data;
    ngx_http_lua_fs_ctx_t      *fs_ctx;

    fs_ctx = coctx->data;
    fs_ctx->is_abort = 1;
}


static int
ngx_http_lua_fs_post_task(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_fs_ctx_t *fs_ctx, ngx_str_t *pool_name)
{
    ngx_thread_pool_t          *tp;
    ngx_thread_task_t          *task;
    ngx_http_lua_ctx_t         *ctx;
    ngx_http_lua_co_ctx_t      *coctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    tp = ngx_thread_pool_get((ngx_cycle_t *) ngx_cycle, pool_name);

    if (tp == NULL) {
        if (fs_ctx->ref != NULL) {
            fs_ctx->ref->ninflight--;
        }

        ngx_http_lua_fs_free_bufs(fs_ctx);
        ngx_http_lua_fs_task_free(fs_ctx);

        lua_pushnil(L);
        lua_pushfstring(L, "thread pool \"%s\" not found, "
                        "add \"thread_pool %s ...;\" to nginx.conf "
                        "and build nginx with --with-threads",
                        pool_name->data, pool_name->data);
        return 2;
    }

    task = (ngx_thread_task_t *) fs_ctx - 1;

    coctx = ctx->cur_co_ctx;

    fs_ctx->wait_co_ctx = coctx;
    fs_ctx->is_abort = 0;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_fs_cleanup;
    coctx->data = fs_ctx;

    task->handler = ngx_http_lua_fs_thread_handler;
    task->event.handler = ngx_http_lua_fs_event_handler;
    task->event.data = fs_ctx;

    if (ngx_thread_task_post(tp, task) != NGX_OK) {
        coctx->cleanup = NULL;
        coctx->data = NULL;

        if (fs_ctx->ref != NULL) {
            fs_ctx->ref->ninflight--;
        }

        ngx_http_lua_fs_free_bufs(fs_ctx);
        ngx_http_lua_fs_task_free(fs_ctx);

        lua_pushnil(L);
        lua_pushliteral(L, "thread pool task post failed");
        return 2;
    }

    return lua_yield(L, 0);
}


static int
ngx_http_lua_fs_open(lua_State *L)
{
    ngx_http_request_t         *r;
    ngx_http_lua_ctx_t         *ctx;
    ngx_thread_task_t          *task;
    ngx_http_lua_fs_ctx_t      *fs_ctx;
    const char                 *path;
    const char                 *mode;
    size_t                      path_len;
    int                         flags;
    int                         create_mode;
    ngx_str_t                   pool_name;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    if (lua_gettop(L) < 1) {
        return luaL_error(L, "expecting at least 1 argument (path)");
    }

    path = luaL_checklstring(L, 1, &path_len);
    mode = luaL_optstring(L, 2, "r");

    pool_name.data = (u_char *) luaL_optlstring(L, 3, "default_lua_io",
                                                &pool_name.len);

    if (pool_name.len >= NGX_HTTP_LUA_FS_POOL_NAME_MAX) {
        return luaL_error(L, "thread pool name too long");
    }

    create_mode = 0644;

    if (mode[0] == 'r' && mode[1] == '\0') {
        flags = O_RDONLY;

    } else if (mode[0] == 'w' && mode[1] == '\0') {
        flags = O_WRONLY | O_CREAT | O_TRUNC;

    } else if (mode[0] == 'a' && mode[1] == '\0') {
        flags = O_WRONLY | O_CREAT | O_APPEND;

    } else if (mode[0] == 'r' && mode[1] == '+' && mode[2] == '\0') {
        flags = O_RDWR;

    } else if (mode[0] == 'w' && mode[1] == '+' && mode[2] == '\0') {
        flags = O_RDWR | O_CREAT | O_TRUNC;

    } else {
        return luaL_error(L, "invalid mode \"%s\" "
                          "(expected \"r\", \"w\", \"a\", \"r+\", or \"w+\")",
                          mode);
    }

    task = ngx_http_lua_fs_task_alloc(sizeof(ngx_http_lua_fs_ctx_t));
    if (task == NULL) {
        return luaL_error(L, "no memory");
    }

    fs_ctx = task->ctx;
    ngx_memzero(fs_ctx, sizeof(ngx_http_lua_fs_ctx_t));

    fs_ctx->op = NGX_HTTP_LUA_FS_OP_OPEN;
    fs_ctx->flags = flags;
    fs_ctx->create_mode = create_mode;
    fs_ctx->result_fd = -1;

    fs_ctx->path = ngx_alloc(path_len + 1, ngx_cycle->log);
    if (fs_ctx->path == NULL) {
        ngx_http_lua_fs_task_free(fs_ctx);
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(fs_ctx->path, path, path_len);
    fs_ctx->path[path_len] = '\0';

    ngx_memcpy(fs_ctx->pool_name, pool_name.data, pool_name.len);
    fs_ctx->pool_name_len = pool_name.len;

    return ngx_http_lua_fs_post_task(L, r, fs_ctx, &pool_name);
}


static int
ngx_http_lua_fs_file_read(lua_State *L)
{
    ngx_http_request_t         *r;
    ngx_http_lua_ctx_t         *ctx;
    ngx_thread_task_t          *task;
    ngx_http_lua_fs_ctx_t      *fs_ctx;
    ngx_http_lua_fs_file_t     *file;
    lua_Integer                 size;
    lua_Integer                 offset;
    ngx_str_t                   pool_name;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    file = (ngx_http_lua_fs_file_t *)
               luaL_checkudata(L, 1, NGX_HTTP_LUA_FS_FILE_MT);

    if (file->ref->closed) {
        return luaL_error(L, "attempt to read from a closed file");
    }

    size = luaL_checkinteger(L, 2);
    offset = luaL_optinteger(L, 3, 0);

    if (size <= 0) {
        return luaL_error(L, "invalid size: %d", (int) size);
    }

    if (offset < 0) {
        return luaL_error(L, "invalid offset: %d", (int) offset);
    }

    pool_name.data = file->pool_name;
    pool_name.len = file->pool_name_len;

    task = ngx_http_lua_fs_task_alloc(sizeof(ngx_http_lua_fs_ctx_t));
    if (task == NULL) {
        return luaL_error(L, "no memory");
    }

    fs_ctx = task->ctx;
    ngx_memzero(fs_ctx, sizeof(ngx_http_lua_fs_ctx_t));

    fs_ctx->buf = ngx_alloc((size_t) size, ngx_cycle->log);
    if (fs_ctx->buf == NULL) {
        ngx_http_lua_fs_task_free(fs_ctx);
        return luaL_error(L, "no memory");
    }

    fs_ctx->op = NGX_HTTP_LUA_FS_OP_READ;
    fs_ctx->fd = file->ref->fd;
    fs_ctx->size = (size_t) size;
    fs_ctx->offset = (off_t) offset;
    fs_ctx->ref = file->ref;

    file->ref->ninflight++;

    return ngx_http_lua_fs_post_task(L, r, fs_ctx, &pool_name);
}


static int
ngx_http_lua_fs_file_write(lua_State *L)
{
    ngx_http_request_t         *r;
    ngx_http_lua_ctx_t         *ctx;
    ngx_thread_task_t          *task;
    ngx_http_lua_fs_ctx_t      *fs_ctx;
    ngx_http_lua_fs_file_t     *file;
    const char                 *data;
    size_t                      data_len;
    lua_Integer                 offset;
    ngx_str_t                   pool_name;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    file = (ngx_http_lua_fs_file_t *)
               luaL_checkudata(L, 1, NGX_HTTP_LUA_FS_FILE_MT);

    if (file->ref->closed) {
        return luaL_error(L, "attempt to write to a closed file");
    }

    data = luaL_checklstring(L, 2, &data_len);
    offset = luaL_optinteger(L, 3, 0);

    if (data_len == 0) {
        lua_pushinteger(L, 0);
        return 1;
    }

    if (offset < 0) {
        return luaL_error(L, "invalid offset: %d", (int) offset);
    }

    pool_name.data = file->pool_name;
    pool_name.len = file->pool_name_len;

    task = ngx_http_lua_fs_task_alloc(sizeof(ngx_http_lua_fs_ctx_t));
    if (task == NULL) {
        return luaL_error(L, "no memory");
    }

    fs_ctx = task->ctx;
    ngx_memzero(fs_ctx, sizeof(ngx_http_lua_fs_ctx_t));

    fs_ctx->buf = ngx_alloc(data_len, ngx_cycle->log);
    if (fs_ctx->buf == NULL) {
        ngx_http_lua_fs_task_free(fs_ctx);
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(fs_ctx->buf, data, data_len);

    fs_ctx->op = NGX_HTTP_LUA_FS_OP_WRITE;
    fs_ctx->fd = file->ref->fd;
    fs_ctx->size = data_len;
    fs_ctx->offset = (off_t) offset;
    fs_ctx->ref = file->ref;

    file->ref->ninflight++;

    return ngx_http_lua_fs_post_task(L, r, fs_ctx, &pool_name);
}


static int
ngx_http_lua_fs_file_close(lua_State *L)
{
    ngx_http_lua_fs_file_t  *file;

    file = (ngx_http_lua_fs_file_t *)
               luaL_checkudata(L, 1, NGX_HTTP_LUA_FS_FILE_MT);

    if (file->ref->closed) {
        lua_pushboolean(L, 0);
        lua_pushliteral(L, "file already closed");
        return 2;
    }

    if (file->ref->ninflight > 0) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "file has %d in-flight operation(s)",
                        (int) file->ref->ninflight);
        return 2;
    }

    if (close(file->ref->fd) == -1) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "close() failed (%d: %s)",
                        (int) ngx_errno, strerror(ngx_errno));
        return 2;
    }

    file->ref->closed = 1;

    lua_pushboolean(L, 1);
    return 1;
}


static int
ngx_http_lua_fs_stat(lua_State *L)
{
    ngx_http_request_t         *r;
    ngx_http_lua_ctx_t         *ctx;
    ngx_thread_task_t          *task;
    ngx_http_lua_fs_ctx_t      *fs_ctx;
    const char                 *path;
    size_t                      path_len;
    ngx_str_t                   pool_name;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_YIELDABLE);

    if (lua_gettop(L) < 1) {
        return luaL_error(L, "expecting at least 1 argument: path");
    }

    path = luaL_checklstring(L, 1, &path_len);

    pool_name.data = (u_char *) luaL_optlstring(L, 2, "default_lua_io",
                                                &pool_name.len);

    task = ngx_http_lua_fs_task_alloc(sizeof(ngx_http_lua_fs_ctx_t));
    if (task == NULL) {
        return luaL_error(L, "no memory");
    }

    fs_ctx = task->ctx;
    ngx_memzero(fs_ctx, sizeof(ngx_http_lua_fs_ctx_t));

    fs_ctx->op = NGX_HTTP_LUA_FS_OP_STAT;

    fs_ctx->path = ngx_alloc(path_len + 1, ngx_cycle->log);
    if (fs_ctx->path == NULL) {
        ngx_http_lua_fs_task_free(fs_ctx);
        return luaL_error(L, "no memory");
    }

    ngx_memcpy(fs_ctx->path, path, path_len);
    fs_ctx->path[path_len] = '\0';

    return ngx_http_lua_fs_post_task(L, r, fs_ctx, &pool_name);
}


static int
ngx_http_lua_fs_file_gc(lua_State *L)
{
    ngx_http_lua_fs_file_t  *file;

    file = (ngx_http_lua_fs_file_t *)
               luaL_checkudata(L, 1, NGX_HTTP_LUA_FS_FILE_MT);

    if (file->ref == NULL) {
        return 0;
    }

    if (file->ref->ninflight == 0) {
        ngx_http_lua_fs_fd_ref_release(file->ref);

    } else {
        file->ref->orphaned = 1;
    }

    file->ref = NULL;

    return 0;
}


static int
ngx_http_lua_fs_file_tostring(lua_State *L)
{
    ngx_http_lua_fs_file_t  *file;

    file = (ngx_http_lua_fs_file_t *)
               luaL_checkudata(L, 1, NGX_HTTP_LUA_FS_FILE_MT);

    if (file->ref == NULL || file->ref->closed) {
        lua_pushliteral(L, "file (closed)");

    } else {
        lua_pushfstring(L, "file (fd=%d)", file->ref->fd);
    }

    return 1;
}


void
ngx_http_lua_inject_async_fs_api(lua_State *L)
{
    luaL_newmetatable(L, NGX_HTTP_LUA_FS_FILE_MT);

    lua_pushcfunction(L, ngx_http_lua_fs_file_gc);
    lua_setfield(L, -2, "__gc");

    lua_pushcfunction(L, ngx_http_lua_fs_file_tostring);
    lua_setfield(L, -2, "__tostring");

    lua_createtable(L, 0, 3);

    lua_pushcfunction(L, ngx_http_lua_fs_file_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_fs_file_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, ngx_http_lua_fs_file_close);
    lua_setfield(L, -2, "close");

    lua_setfield(L, -2, "__index");

    lua_pop(L, 1);

    lua_createtable(L, 0, 2);

    lua_pushcfunction(L, ngx_http_lua_fs_open);
    lua_setfield(L, -2, "open");

    lua_pushcfunction(L, ngx_http_lua_fs_stat);
    lua_setfield(L, -2, "stat");

    lua_setfield(L, -2, "fs");
}


#else /* !NGX_THREADS */


void
ngx_http_lua_inject_async_fs_api(lua_State *L)
{
}


#endif /* NGX_THREADS */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
