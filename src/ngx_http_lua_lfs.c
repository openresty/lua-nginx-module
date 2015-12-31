

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
typedef struct _ngx_http_lua_lfs_task_ctx_s {
    lua_State *L;
    ngx_http_request_t *r;
    ngx_pool_t *pool;
    union {
        struct {
            ngx_fd_t fd;
            u_char *buff;
        } desc;
        ngx_str_t filename;
    };
    ssize_t size;
    off_t offset;
    union {
        ssize_t length;
        ssize_t used;
    };
    ngx_http_lua_co_ctx_t *coctx;
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

    task_ctx->size = 0xFFFF;
    task_ctx->offset = -1;

    task_ctx->length = 0;
    task_ctx->L = L;
    task_ctx->r = r;
    task_ctx->coctx = ctx->cur_co_ctx;
    task_ctx->pool = r->pool;

    return task;
}

static int ngx_http_lua_lfs_post_task(ngx_thread_task_t *task)
{
    ngx_thread_pool_t *pool;
    ngx_str_t poolname = ngx_string("luafs");
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
typedef int (*check_argument)(ngx_http_request_t *r, lua_State *L);
typedef ngx_thread_task_t *(*task_create)(ngx_http_request_t *r, 
        ngx_http_lua_ctx_t *ctx, lua_State *L);
typedef void (*task_callback)(void *data, ngx_log_t *log);
typedef void (*event_callback)(ngx_event_t *ev);

typedef struct _ngx_http_lua_lfs_ops_s {
    check_argument check_argument;
    task_create task_create;
    task_callback task_callback;
    event_callback event_callback;
} ngx_http_lua_lfs_ops_t;

enum {
    LFS_READ = 0,
    LFS_WRITE,
    LFS_COPY,
    LFS_STATUS,
    LFS_TRUNCATE,
} LFS_OPS;


/**
 * resume the lua VM, copied from ngx_http_lua_sleep.c
 **/
static ngx_int_t ngx_http_lua_lfs_event_resume(ngx_http_request_t *r, int nrets)
{
    lua_State *vm;
    ngx_int_t rc;
    ngx_http_lua_ctx_t *ctx;
    ngx_connection_t *c;

    r->main->blocked --;
    r->aio = 0;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

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
static int ngx_http_lua_lfs_read_check_argument(ngx_http_request_t *r, lua_State *L)
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
static int ngx_http_lua_lfs_write_check_argument(ngx_http_request_t *r, lua_State *L)
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

static int ngx_http_lua_lfs_status_check_argument(ngx_http_request_t *r, lua_State *L)
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

static int ngx_http_lua_lfs_truncate_check_argument(ngx_http_request_t *r, lua_State *L)
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

static ngx_thread_task_t *ngx_http_lua_lfs_read_task_create(ngx_http_request_t *r, 
        ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_int_t n;
    ngx_thread_task_t *task;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;
    ngx_str_t filename;

    if ((task = ngx_http_lua_lfs_create_task(r, L, ctx)) == NULL) {
        return NULL; //luaL_error(L, "can't create task");
    }

    task_ctx = task->ctx;

    if ((n = lua_gettop(L)) >= 2) {
        task_ctx->size = (ssize_t) luaL_checknumber(L, 2);
        if (n == 3) {
            task_ctx->offset = (off_t) luaL_checknumber(L, 3);
        }
    }

    if ((task_ctx->desc.buff = ngx_palloc(r->pool, task_ctx->size)) == NULL) {
        return NULL; //luaL_error(L, "failed to allocate memory");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return NULL; //luaL_error(L, "the first argument is error.");
    }

    if ((task_ctx->desc.fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) < 0) {
        if ((task_ctx->desc.fd = ngx_http_lua_lfs_open_file(filename.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return NULL; //luaL_error(L, "open file %s error", filename.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, filename.data, task_ctx->desc.fd);
    }

    return task;
}


static ngx_thread_task_t *ngx_http_lua_lfs_write_task_create(ngx_http_request_t *r, 
        ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_int_t n;
    ngx_thread_task_t *task;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;
    ngx_str_t filename;

    if ((task = ngx_http_lua_lfs_create_task(r, L, ctx)) == NULL) {
        return NULL; //luaL_error(L, "can't create task");
    }
    task_ctx = task->ctx;

    if ((n = lua_gettop(L)) == 3) {
        task_ctx->offset = (off_t) luaL_checknumber(L, 3);
    }

    task_ctx->desc.buff = (u_char*)lua_tolstring(L, 2, (size_t*)&task_ctx->size);
    if (task_ctx->size <= 0) {
        return NULL; //luaL_error(L, "the first argument is error.");
    }

    filename.data = (u_char*) lua_tolstring(L, 1, &filename.len);
    if (filename.len <= 0) {
        return NULL; //luaL_error(L, "the first argument is error.");
    }

    if ((task_ctx->desc.fd = ngx_http_lua_lfs_fdpool_get(r, filename.data)) < 0) {
        if ((task_ctx->desc.fd = ngx_http_lua_lfs_open_file(filename.data, NGX_FILE_RDWR,
                        NGX_FILE_CREATE_OR_OPEN, NGX_FILE_DEFAULT_ACCESS, r->connection->log)) < 0) {
            return NULL; //luaL_error(L, "open file %s error", filename.data);
        }
        ngx_http_lua_lfs_fdpool_add(r, filename.data, task_ctx->desc.fd);
    }

    return task;
}

static ngx_thread_task_t *ngx_http_lua_lfs_status_task_create(ngx_http_request_t *r, 
        ngx_http_lua_ctx_t *ctx, lua_State *L)
{
    ngx_int_t n;
    ngx_thread_task_t *task;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;

    if ((task = ngx_http_lua_lfs_create_task(r, L, ctx)) == NULL) {
        return NULL;
    }
    task_ctx = task->ctx;

    task_ctx->filename.data = (u_char*)lua_tolstring(L, 1, &task_ctx->filename.len);

    return task;
}

/**
 * read function in task thread
 **/
static void ngx_http_lua_lfs_task_read(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    ngx_fd_t fd = task_ctx->desc.fd;

    if (task_ctx->offset == -1) {
        task_ctx->length = read(fd, task_ctx->desc.buff, task_ctx->size);
    } else {
        task_ctx->length = pread(fd, task_ctx->desc.buff, task_ctx->size, task_ctx->offset);
    }
}

static void ngx_http_lua_lfs_task_write(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    ngx_fd_t fd = task_ctx->desc.fd;

    if (task_ctx->offset == -1) {
        task_ctx->length = write(fd, task_ctx->desc.buff, task_ctx->size);
    } else {
        task_ctx->length = pwrite(fd, task_ctx->desc.buff, task_ctx->size, task_ctx->offset);
    }
}

static void ngx_http_lua_lfs_task_status(void *data, ngx_log_t *log)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = data;
    u_char *filename = task_ctx->filename.data;
    ngx_file_info_t st;

    task_ctx->offset = -1;
    task_ctx->size = -1;

    if (ngx_file_info(filename, &st) != 0) {
        return;
    }

    if (ngx_is_dir(&st)) {
        struct statfs stfs;
        if (statfs(filename, &stfs) != 0) {
            return;
        }
        task_ctx->size = stfs.f_bsize * (stfs.f_blocks - stfs.f_bfree);
        task_ctx->used = (stfs.f_blocks - stfs.f_bfree) * 100 / stfs.f_blocks;
        return;
    }
    task_ctx->size = st.st_size;
}


/**
 * read event function in main thread
 **/
static void ngx_http_lua_lfs_task_read_event(ngx_event_t *ev)
{
    ngx_int_t nrets = 0;
    ngx_http_lua_lfs_task_ctx_t *task_ctx = ev->data;
    ngx_http_request_t *r = task_ctx->r;
    ngx_connection_t *c = r->connection;
    ngx_http_log_ctx_t *log_ctx;
    ngx_http_lua_ctx_t *ctx;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        nrets = 2;
        lua_pushnil(task_ctx->L);
        lua_pushstring(task_ctx->L, "no ctx found.");
    } else if (task_ctx->length > 0) {
        nrets = 1;
        lua_pushlstring(task_ctx->L, (char*)task_ctx->desc.buff, task_ctx->length);
    } else {
        nrets = 2;
        lua_pushnil(task_ctx->L);
        lua_pushstring(task_ctx->L, "no data");
    }

    task_ctx->coctx->cleanup = NULL;

    if (c->fd != -1) {
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }
    ctx->cur_co_ctx = task_ctx->coctx;

    ngx_http_lua_lfs_event_resume(r, nrets);
    ngx_http_run_posted_requests(c);
}

static void ngx_http_lua_lfs_task_write_event(ngx_event_t *ev)
{
    ngx_int_t nrets = 0;
    ngx_http_lua_lfs_task_ctx_t *task_ctx = ev->data;
    ngx_http_request_t *r = task_ctx->r;
    ngx_connection_t *c = r->connection;
    ngx_http_log_ctx_t *log_ctx;
    ngx_http_lua_ctx_t *ctx;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        nrets = 2;
        lua_pushboolean(task_ctx->L, 0);
        lua_pushstring(task_ctx->L, "no ctx found.");
    } else if (task_ctx->length > 0) {
        nrets = 1;
        lua_pushboolean(task_ctx->L, 1);
    } else {
        nrets = 2;
        lua_pushboolean(task_ctx->L, 0);
        lua_pushstring(task_ctx->L, "write data failed");
    }

    task_ctx->coctx->cleanup = NULL;

    if (c->fd != -1) {
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }
    ctx->cur_co_ctx = task_ctx->coctx;

    ngx_http_lua_lfs_event_resume(r, nrets);
    ngx_http_run_posted_requests(c);
}

static void ngx_http_lua_lfs_task_status_event(ngx_event_t *ev)
{
    ngx_int_t nrets = 0;
    ngx_http_lua_lfs_task_ctx_t *task_ctx = ev->data;
    ngx_http_request_t *r = task_ctx->r;
    ngx_connection_t *c = r->connection;
    ngx_http_log_ctx_t *log_ctx;
    ngx_http_lua_ctx_t *ctx;

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        nrets = 2;
        lua_pushboolean(task_ctx->L, 0);
        lua_pushstring(task_ctx->L, "no ctx found.");
    } else if (task_ctx->used >= 0) {
        nrets = 2;
        lua_pushnumber(task_ctx->L, task_ctx->size);
        lua_pushnumber(task_ctx->L, task_ctx->used);
    } else {
        nrets = 1;
        lua_pushnumber(task_ctx->L, task_ctx->size);
    }

    task_ctx->coctx->cleanup = NULL;

    if (c->fd != -1) {
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }
    ctx->cur_co_ctx = task_ctx->coctx;

    ngx_http_lua_lfs_event_resume(r, nrets);
    ngx_http_run_posted_requests(c);
}

static void ngx_http_lua_lfs_task_copy(void *data, ngx_log_t *log)
{
}

static void ngx_http_lua_lfs_task_copy_event(ngx_event_t *ev)
{
}

static ngx_http_lua_lfs_ops_t lfs_ops[] = {
    { /** LFS_READ **/
        .check_argument = ngx_http_lua_lfs_read_check_argument,
        .task_create = ngx_http_lua_lfs_read_task_create,
        .task_callback = ngx_http_lua_lfs_task_read,
        .event_callback = ngx_http_lua_lfs_task_read_event,
    },
    { /** LFS_WRITE **/
        .check_argument = ngx_http_lua_lfs_write_check_argument,
        .task_create = ngx_http_lua_lfs_write_task_create,
        .task_callback = ngx_http_lua_lfs_task_write,
        .event_callback = ngx_http_lua_lfs_task_write_event,
    },
    { /** LFS_COPY **/
        .check_argument = NULL, 
        .task_create = NULL,
        .task_callback = ngx_http_lua_lfs_task_copy,
        .event_callback = ngx_http_lua_lfs_task_copy_event,
    },
    { /** LFS_STATUS **/
        .check_argument = ngx_http_lua_lfs_status_check_argument,
        .task_create = ngx_http_lua_lfs_status_task_create,
        .task_callback = ngx_http_lua_lfs_task_status,
        .event_callback = ngx_http_lua_lfs_task_status_event,

    },
    { /** LFS_TRUNCATE **/
        .check_argument = ngx_http_lua_lfs_truncate_check_argument,
    },
};


static int ngx_http_lua_lfs_process(lua_State *L, int ops)
{
    ngx_http_request_t *r;
    ngx_http_lua_ctx_t *ctx;
    ngx_thread_task_t *task;
    ngx_int_t rc;

    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if ((rc = lfs_ops[ops].check_argument(r, L)) != 0) {
        return rc;
    }

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    if (ngx_http_lua_lfs_fdpool_init(ctx, r) != 0) {
        return luaL_error(L, "create fd pool failed.");
    }

    if ((task = lfs_ops[ops].task_create(r, ctx, L)) == NULL) {
        return luaL_error(L, "create task error.");
    }

    task->handler = lfs_ops[ops].task_callback;
    task->event.data = task->ctx;
    task->event.handler = lfs_ops[ops].event_callback;

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
    return 0;
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

    if ((rc = lfs_ops[LFS_TRUNCATE].check_argument(r, L)) != 0) {
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

static int ngx_http_lua_ngx_lfs_status(lua_State *L)
{
    return ngx_http_lua_lfs_process(L, LFS_STATUS);
}


void ngx_http_lua_inject_lfs_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 5 /* nrec */); /* ngx.lfs. */

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_copy);
    lua_setfield(L, -2, "copy");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_truncate);
    lua_setfield(L, -2, "truncate");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_status);
    lua_setfield(L, -2, "status");

    lua_setfield(L, -2, "lfs");
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
