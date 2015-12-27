

/**
 * Copyright (C) Terry AN (anhk)
 **/

#include "ddebug.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_lfs.h"

#if (NGX_THREADS)

static int ngx_http_lua_ngx_lfs_read(lua_State *L)
{
    lua_pushlstring(L, "From LFS", strlen("From LFS"));
    return 1;
}

static int ngx_http_lua_ngx_lfs_write(lua_State *L)
{
    return 0;
}

void ngx_http_lua_inject_lfs_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 2 /* nrec */);    /* ngx.lfs. */

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_write);
    lua_setfield(L, -2, "write");

    lua_setfield(L, -2, "lfs");
}


#endif
