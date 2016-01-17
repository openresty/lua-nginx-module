

/**
 * Copyright (C) Terry AN (anhk)
 **/

#ifndef _NGX_HTTP_LUA_LFS_H_INCLUDED_
#define _NGX_HTTP_LUA_LFS_H_INCLUDED_


#if (NGX_THREADS)
void ngx_http_lua_inject_lfs_api(lua_State *L);
#endif

#endif
