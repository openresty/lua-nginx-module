

/**
 * Copyright (C) Terry AN (anhk)
 **/

#include "ddebug.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_lfs.h"

#if (NGX_THREADS)

#include "ngx_http_lua_lfs_fdpool.h"

/**
 * ctx for task thread
 **/
typedef struct _ngx_http_lua_lfs_task_read_ctx_s {
    ngx_fd_t fd;
    u_char *buff;
    ssize_t size;
    off_t offset;
    ssize_t length;
} ngx_http_lua_lfs_task_read_ctx_t;

typedef struct _ngx_http_lua_lfs_task_write_ctx_s {
    ngx_fd_t fd;
    u_char *buff;
    ssize_t size;
    off_t offset;
    ssize_t length;
} ngx_http_lua_lfs_task_write_ctx_t;

typedef struct _ngx_http_lua_lfs_task_copy_ctx_s {
    ngx_fd_t fd;
    ngx_fd_t fd2;
} ngx_http_lua_lfs_task_copy_ctx_t;

typedef struct _ngx_http_lua_lfs_task_status_ctx_s {
    ngx_str_t filename;
    ssize_t size;
    time_t atime;
    ngx_int_t used;
} ngx_http_lua_lfs_task_status_ctx_t;

typedef struct _ngx_http_lua_lfs_task_ctx_s {
    ngx_int_t op;
    lua_State *L;
    ngx_http_request_t *r;
    ngx_pool_t *pool;
    ngx_http_lua_co_ctx_t *coctx;

    union {
        ngx_http_lua_lfs_task_read_ctx_t read;
        ngx_http_lua_lfs_task_write_ctx_t write;
        ngx_http_lua_lfs_task_copy_ctx_t copy;
        ngx_http_lua_lfs_task_status_ctx_t status;
    };
} ngx_http_lua_lfs_task_ctx_t;


/**
 * create task
 **/
static ngx_thread_task_t *ngx_http_lua_lfs_create_task(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_ctx_t *ctx)
{
    ngx_thread_task_t *task;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;

    if ((task = ngx_thread_task_alloc(r->pool,
                    sizeof(ngx_http_lua_lfs_task_ctx_t))) == NULL) {
        return NULL;
    }

    task_ctx = task->ctx;

#if 0
    task_ctx->size = 0xFFFF;
    task_ctx->offset = -1;
    task_ctx->length = -1;
#endif
    task_ctx->L = L;
    task_ctx->r = r;
    task_ctx->coctx = ctx->cur_co_ctx;
    task_ctx->pool = r->pool;

    return task;
}

static int ngx_http_lua_lfs_post_task(ngx_thread_task_t *task)
{
    ngx_thread_pool_t *pool;
    ngx_str_t poolname = ngx_string("luafs"); /** TODO: luafs **/
    ngx_http_lua_lfs_task_ctx_t *task_ctx = task->ctx;

    ngx_http_lua_cleanup_pending_operation(task_ctx->coctx);
    task_ctx->coctx->cleanup = NULL;

    if ((pool = ngx_thread_pool_get((ngx_cycle_t*) ngx_cycle, &poolname)) == NULL) {
        return -1;
    }

    if (ngx_thread_task_post(pool, task) != NGX_OK) {
        return -1;
    }

    return 0;
}


/**
 * all the operate functions
 **/
typedef ngx_int_t (*check_argument)(ngx_http_request_t *r, lua_State *L);
typedef ngx_int_t (*task_init)(ngx_http_lua_lfs_task_ctx_t *task_ctx,
        ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, lua_State *L);
typedef void (*task_callback)(void *data, ngx_log_t *log);
typedef ngx_int_t (*event_callback)(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx);

typedef struct _ngx_http_lua_lfs_op_s {
    check_argument check_argument;
    task_init task_init;
    task_callback task_callback;
    event_callback event_callback;
} ngx_http_lua_lfs_op_t;

enum {
    LFS_READ = 0,
    LFS_WRITE,
    LFS_COPY,
    LFS_STATUS,
    LFS_TRUNCATE,
    LFS_DELETE,
} LFS_OPS;


static ngx_int_t ngx_http_lua_lfs_read_event(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx)
{
    ngx_int_t nrets = 0;
    if (task_ctx->read.length > 0) {
        nrets = 1;
        lua_pushlstring(task_ctx->L, (char*)task_ctx->read.buff, task_ctx->read.length);
    } else {
        nrets = 2;
        lua_pushnil(task_ctx->L);
        lua_pushstring(task_ctx->L, "no data");
    }
    return nrets;
}

static ngx_int_t ngx_http_lua_lfs_write_event(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx)
{
    ngx_int_t nrets = 0;
    if (task_ctx->write.length > 0) {
        nrets = 1;
        lua_pushboolean(task_ctx->L, 1);
    } else {
        nrets = 2;
        lua_pushboolean(task_ctx->L, 0);
        lua_pushstring(task_ctx->L, "write data failed");
    }

    return nrets;

}

static ngx_int_t ngx_http_lua_lfs_copy_event(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx)
{
    lua_pushboolean(task_ctx->L, 1);
    return 1; /** FIXME **/
}

static ngx_int_t ngx_http_lua_lfs_status_event(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx)
{
    if (task_ctx->status.size < 0) {
        lua_pushnil(task_ctx->L);
        return 1;
    }

    lua_pushnumber(task_ctx->L, task_ctx->status.size);
    if (task_ctx->status.atime < 0) {
        return 1;
    }
    lua_pushnumber(task_ctx->L, task_ctx->status.atime);

    if (task_ctx->status.used < 0) {
        return 2;
    }
    lua_pushnumber(task_ctx->L, task_ctx->status.used);

    return 3;
}


static ngx_int_t ngx_http_lua_lfs_event_process(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx);


/**
 * resume the lua VM, copied from ngx_http_lua_sleep.c
 **/
static ngx_int_t ngx_http_lua_lfs_event_resume(ngx_http_request_t *r)
{
    lua_State *vm;
    ngx_int_t rc, nrets;
    ngx_http_lua_ctx_t *ctx;
    ngx_connection_t *c;
    ngx_http_lua_co_ctx_t *coctx;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;

    r->main->blocked --;
    r->aio = 0;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return NGX_ERROR;
    }
    coctx = ctx->cur_co_ctx;
    task_ctx = coctx->data;

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

    nrets = ngx_http_lua_lfs_event_process(r, vm, task_ctx);

    rc = ngx_http_lua_run_thread(vm, r, ctx, nrets);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


/**
 * make direcotry
 **/
static int ngx_http_lua_lfs_make_directory(u_char *name, ngx_log_t *log)
{
    u_char *pos;
    u_char tmpname[BUFSIZ];
    if ((pos = (u_char*)strrchr((char*)name, '/')) != NULL) {
        ngx_cpystrn(tmpname, name, pos - name + 1);
        tmpname[pos - name] = 0;

        if (ngx_create_dir(tmpname, 0755) < 0) {
            if (errno != ENOENT) {
                return -1;
            }
            ngx_http_lua_lfs_make_directory(tmpname, log);
            if (ngx_create_dir(tmpname, 0755) < 0) {
                return -1;
            }
        }
    }
    return 0;
}

/**
 * open file
 **/
static int ngx_http_lua_lfs_open_file(u_char *pathname, int flags,
        int create, mode_t mode, ngx_log_t *log)
{
    ngx_fd_t fd;

    if ((fd = ngx_open_file(pathname, flags, create, mode)) < 0) {
        if (errno != ENOENT) {
            return -1;
        }
        if (ngx_http_lua_lfs_make_directory(pathname, log) != 0) {
            return -1;
        }
        return ngx_open_file(pathname, flags, create, mode);
    }
    return fd;
}


/**
 * check the arguments of read function
 **/
static ngx_int_t ngx_http_lua_lfs_read_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n < 1 && n > 3) {
        return luaL_error(L, "expected 1, 2 or 3 arguments, but seen %d", n);
    }

    if (!lua_isstring(L, 1)) {
        return luaL_error(L, "the first argument is expected string");
    }

    if (n >= 2 && !lua_isnumber(L, 2)) {
        return luaL_error(L, "the second argument is expected number");
    }

    if (n >= 3 && !lua_isnumber(L, 3)) {
        return luaL_error(L, "the third argument is expected number");
    }

    return 0;
}

/**
 * check the arguments of write function
 **/
static ngx_int_t ngx_http_lua_lfs_write_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n < 2 && n > 3) {
        return luaL_error(L, "expected 2 or 3 arguments, but seen %d", n);
    }

    if (!lua_isstring(L, 1) || !lua_isstring(L, 2)) {
        return luaL_error(L, "the first and second arguments are expected string");
    }

    if (n >= 3 && !lua_isnumber(L, 3)) {
        return luaL_error(L, "the third argument is expected number");
    }

    return 0;
}

/**
 * check the arguments of copy function
 **/
static ngx_int_t ngx_http_lua_lfs_copy_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n != 2) {
        return luaL_error(L, "expected 2 arguments, but seen %d", n);
    }

    if (!lua_isstring(L, 1) || !lua_isstring(L, 2)) {
        return luaL_error(L, "the first and second arguments are expected string");
    }

    return 0;
}

static ngx_int_t ngx_http_lua_lfs_status_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "expected 1 argument, but seen %d", n);
    }
    if (!lua_isstring(L, 1)) {
        return luaL_error(L, "the first argument is expected string");
    }
    return 0;
}

static ngx_int_t ngx_http_lua_lfs_truncate_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n < 1 || n > 2) {
        return luaL_error(L, "expected 1 or 2 arguments, but seen %d", n);
    }
    if (!lua_isstring(L, 1)) {
        return luaL_error(L, "the first argument is expected string");
    }

    if (n == 2 && !lua_isnumber(L, 2)) {
        return luaL_error(L, "the second argument is expected number");
    }
    return 0;
}

static ngx_int_t ngx_http_lua_lfs_delete_check_argument(ngx_http_request_t *r, lua_State *L)
{
    ngx_int_t n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "expected 1 argument, but seen %d", n);
    }

    if (!lua_isstring(L, 1)) {
        return luaL_error(L, "the first argument is expected string");
    }

    return 0;
}

static ngx_int_t ngx_http_lua_lfs_read_task_init(ngx_http_lua_lfs_task_ctx_t *task_ctx,
        ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_int_t n;
    ngx_str_t filename;

    task_ctx->read.size = 0xFFFF;
    task_ctx->read.offset = -1;
    task_ctx->read.length = -1;

    if ((n = lua_gettop(L)) >= 2) {
        task_ctx->read.size = (ssize_t) luaL_checknumber(L, 2);
        if (n == 3) {
            task_ctx->read.offset = (off_t) luaL_checknumber(L, 3);
        }
    }

    if ((task_ctx->read.buff = ngx_palloc(r->pool, task_ctx->read.size)) == NULL) {
        return luaL_error(L, "failed to allocate memory");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    if ((task_ctx->read.fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) < 0) {
        if ((task_ctx->read.fd = ngx_http_lua_lfs_open_file(filename.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return luaL_error(L, "open file %s error", filename.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, filename.data, task_ctx->read.fd);
    }

    return 0;
}


static ngx_int_t ngx_http_lua_lfs_write_task_init(ngx_http_lua_lfs_task_ctx_t *task_ctx,
        ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_int_t n;
    ngx_str_t filename;

    task_ctx->write.size = 0xFFFF;
    task_ctx->write.offset = -1;
    task_ctx->write.length = -1;

    if ((n = lua_gettop(L)) == 3) {
        task_ctx->write.offset = (off_t) luaL_checknumber(L, 3);
    }

    task_ctx->write.buff = (u_char*)lua_tolstring(L, 2, (size_t*)&task_ctx->write.size);
    if (task_ctx->write.size <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    if ((task_ctx->write.fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) < 0) {
        if ((task_ctx->write.fd = ngx_http_lua_lfs_open_file(filename.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return luaL_error(L, "open file %s error", filename.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, filename.data, task_ctx->write.fd);
    }

    return 0;
}

static ngx_int_t ngx_http_lua_lfs_copy_task_init(ngx_http_lua_lfs_task_ctx_t *task_ctx,
        ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_str_t src, dst;

    //task_ctx->copy.size = 0xFFFF;
    //task_ctx->copy.offset = -1;
    //task_ctx->copy.length = -1;

    src.data = (u_char*) lua_tolstring(L, 1, &src.len);
    dst.data = (u_char*) lua_tolstring(L, 2, &dst.len);

    if ((task_ctx->copy.fd = ngx_http_lua_lfs_fdpool_get(r, src.data)) < 0) {
        if ((task_ctx->copy.fd = ngx_http_lua_lfs_open_file(src.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return luaL_error(L, "open file %s error", src.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, src.data, task_ctx->copy.fd);
    }

    if ((task_ctx->copy.fd2 = ngx_http_lua_lfs_fdpool_get(r, dst.data)) < 0) {
        if ((task_ctx->copy.fd2 = ngx_http_lua_lfs_open_file(dst.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return luaL_error(L, "open file %s error", dst.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, dst.data, task_ctx->copy.fd2);
    }

    return 0;
}

static ngx_int_t ngx_http_lua_lfs_status_task_init(ngx_http_lua_lfs_task_ctx_t *task_ctx,
        ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    task_ctx->status.size = 0xFFFF;
    //task_ctx->status.offset = -1;
    //task_ctx->status.length = -1;

    task_ctx->status.filename.data = (u_char*)lua_tolstring(L, 1, &task_ctx->status.filename.len);
    if (task_ctx->status.filename.len <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    return 0;
}

/**
 * read function in task thread
 **/
static void ngx_http_lua_lfs_task_read(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    ngx_fd_t fd = task_ctx->read.fd;

    if (task_ctx->read.offset == -1) {
        task_ctx->read.length = read(fd, task_ctx->read.buff, task_ctx->read.size);
    } else {
        task_ctx->read.length = pread(fd, task_ctx->read.buff, task_ctx->read.size, 
                task_ctx->read.offset);
    }
}

static void ngx_http_lua_lfs_task_write(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    ngx_fd_t fd = task_ctx->write.fd;

    if (task_ctx->write.offset == -1) {
        task_ctx->write.length = write(fd, task_ctx->write.buff, task_ctx->write.size);
    } else {
        task_ctx->write.length = pwrite(fd, task_ctx->write.buff, task_ctx->write.size, 
                task_ctx->write.offset);
    }
}


static void ngx_http_lua_lfs_task_copy(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    ngx_fd_t fd_src = task_ctx->copy.fd;
    ngx_fd_t fd_dst = task_ctx->copy.fd2;
    off_t offset = 0;
    u_char buff[BUFSIZ*4];
    ngx_int_t ret;

    if (ftruncate(fd_dst, 0) != 0) {
        /** TODO **/
    }

    while (1) {
        ret = pread(fd_src, buff, BUFSIZ*4, offset);
        if (ret <= 0) {
            break;
        }
        ret = pwrite(fd_dst, buff, ret, offset); /** FIXME, loop-write **/
        offset += ret;
    }
}

static void ngx_http_lua_lfs_task_status(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    u_char *filename = task_ctx->status.filename.data;
    ngx_file_info_t st;

    task_ctx->status.used = -1;
    task_ctx->status.size = -1;
    task_ctx->status.atime = -1;

    if (ngx_file_info(filename, &st) != 0) {
        return;
    }

    task_ctx->status.atime = st.st_atime;

    if (ngx_is_dir(&st)) {
        struct statfs stfs;
        if (statfs((char*)filename, &stfs) != 0) {
            return;
        }
        task_ctx->status.size = stfs.f_bsize * (stfs.f_blocks - stfs.f_bfree);
        task_ctx->status.used = (stfs.f_blocks - stfs.f_bfree) * 100 / stfs.f_blocks;
        return;
    }
    task_ctx->status.size = st.st_size;
}

static void ngx_http_lua_lfs_task_event(ngx_event_t *ev)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = ev->data;
    ngx_http_request_t *r = task_ctx->r;
    ngx_connection_t *c = r->connection;
    ngx_http_log_ctx_t *log_ctx;
    ngx_http_lua_ctx_t *ctx;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return; /** FIXME **/
    }

    task_ctx->coctx->cleanup = NULL;
    task_ctx->coctx->data = task_ctx;

    if (c->fd != -1) {
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }
    ctx->cur_co_ctx = task_ctx->coctx;

    if (ctx->entered_content_phase) {
        ngx_http_lua_lfs_event_resume(r);
    } else {
        ctx->resume_handler = ngx_http_lua_lfs_event_resume;
        ngx_http_core_run_phases(r);
    }
    ngx_http_run_posted_requests(c);
}


static ngx_http_lua_lfs_op_t lfs_op[] = {
    { /** LFS_READ **/
        .check_argument = ngx_http_lua_lfs_read_check_argument,
        .task_init = ngx_http_lua_lfs_read_task_init,
        .task_callback = ngx_http_lua_lfs_task_read,
        .event_callback = ngx_http_lua_lfs_read_event,
    },
    { /** LFS_WRITE **/
        .check_argument = ngx_http_lua_lfs_write_check_argument,
        .task_init = ngx_http_lua_lfs_write_task_init,
        .task_callback = ngx_http_lua_lfs_task_write,
        .event_callback = ngx_http_lua_lfs_write_event,
    },
    { /** LFS_COPY **/
        .check_argument = ngx_http_lua_lfs_copy_check_argument,
        .task_init = ngx_http_lua_lfs_copy_task_init,
        .task_callback = ngx_http_lua_lfs_task_copy,
        .event_callback = ngx_http_lua_lfs_copy_event,
    },
    { /** LFS_STATUS **/
        .check_argument = ngx_http_lua_lfs_status_check_argument,
        .task_init = ngx_http_lua_lfs_status_task_init,
        .task_callback = ngx_http_lua_lfs_task_status,
        .event_callback = ngx_http_lua_lfs_status_event,
    },
    { /** LFS_TRUNCATE **/
        .check_argument = ngx_http_lua_lfs_truncate_check_argument,
    },
    { /** LFS_DELETE **/
        .check_argument = ngx_http_lua_lfs_delete_check_argument,
    },
};


static ngx_int_t ngx_http_lua_lfs_event_process(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_lfs_task_ctx_t *task_ctx)
{
    return lfs_op[task_ctx->op].event_callback(r, L, task_ctx);
}




static int ngx_http_lua_lfs_process(lua_State *L, int op)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;
    ngx_thread_task_t *task;
    ngx_int_t rc;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;

    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if ((rc = lfs_op[op].check_argument(r, L)) != 0) {
        return rc;
    }

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
            | NGX_HTTP_LUA_CONTEXT_ACCESS
            | NGX_HTTP_LUA_CONTEXT_CONTENT
            | NGX_HTTP_LUA_CONTEXT_TIMER);

    if (ngx_http_lua_lfs_fdpool_init(ctx, r) != 0) {
        return luaL_error(L, "create fd pool failed.");
    }

    if ((task = ngx_http_lua_lfs_create_task(r, L, ctx)) == NULL) {
        return luaL_error(L, "can't create task");
    }
    task_ctx = task->ctx;
    task_ctx->op = op;

    if ((rc = lfs_op[op].task_init(task_ctx, r, ctx, L)) != 0) {
        return luaL_error(L, "create task error.");
    }

    task->handler = lfs_op[op].task_callback;
    task->event.data = task->ctx;
    task->event.handler = ngx_http_lua_lfs_task_event;

    r->main->blocked ++;
    r->aio = 1;

    if (ngx_http_lua_lfs_post_task(task) != 0) {
        r->main->blocked --;
        r->aio = 0;
        return luaL_error(L, "post task error.");
    }
    return lua_yield(L, 0);
}

/**
 * ngx.lfs.read("/root/1.txt", size, offset)
 **/
static int ngx_http_lua_ngx_lfs_read(lua_State *L)
{
    return ngx_http_lua_lfs_process(L, LFS_READ);
}

/**
 * ngx.lfs.write("/root/1.txt", data, offset)
 **/
static int ngx_http_lua_ngx_lfs_write(lua_State *L)
{
    return ngx_http_lua_lfs_process(L, LFS_WRITE);
}

static int ngx_http_lua_ngx_lfs_copy(lua_State *L)
{
    return ngx_http_lua_lfs_process(L, LFS_COPY);
}

static int ngx_http_lua_ngx_lfs_truncate(lua_State *L)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;
    ngx_int_t rc;
    ngx_fd_t fd;
    ngx_str_t filename;
    off_t offset;

    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if ((rc = lfs_op[LFS_TRUNCATE].check_argument(r, L)) != 0) {
        return rc;
    }

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if (ngx_http_lua_lfs_fdpool_init(ctx, r) != 0) {
        return luaL_error(L, "create fd pool failed.");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    offset = (off_t) luaL_checknumber(L, 2);
    if (offset < 0) {
        offset = 0;
    }

    if ((fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) < 0) {
        if ((fd = ngx_http_lua_lfs_open_file(filename.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return luaL_error(L, "open file %s error", filename.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, filename.data, fd);
    }

    if (ftruncate(fd, offset) == 0) {
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

static int ngx_http_lua_ngx_lfs_delete(lua_State *L)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;
    ngx_int_t rc;
    ngx_fd_t fd;
    ngx_str_t filename;

    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if ((rc = lfs_op[LFS_DELETE].check_argument(r, L)) != 0) {
        return rc;
    }

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if (ngx_http_lua_lfs_fdpool_init(ctx, r) != 0) {
        return luaL_error(L, "create fd pool failed.");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return luaL_error(L, "the first argument is error.");
    }

    if ((fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) >= 0) {
        if (ftruncate(fd, 0) != 0) { /** FIXME **/ }
    }

    ngx_delete_file(filename.data); // FIXME
    lua_pushboolean(L, 1);
    return 1;
}


static int ngx_http_lua_ngx_lfs_status(lua_State *L)
{
    return ngx_http_lua_lfs_process(L, LFS_STATUS);
}

void ngx_http_lua_inject_lfs_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 6 /* nrec */); /* ngx.lfs. */

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_copy);
    lua_setfield(L, -2, "copy");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_truncate);
    lua_setfield(L, -2, "truncate");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_delete);
    lua_setfield(L, -2, "delete");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_status);
    lua_setfield(L, -2, "status");

    lua_setfield(L, -2, "lfs");
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
