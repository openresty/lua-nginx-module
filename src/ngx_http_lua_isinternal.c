#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_isinternal.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_req_isinternal(lua_State *L);


void
ngx_http_lua_inject_req_isinternal_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_req_isinternal);
    lua_setfield(L, -2, "is_internal");
}


static int
ngx_http_lua_req_isinternal(lua_State *L)
{
    ngx_http_request_t *r;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    if ( r->internal == 1 ) {
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}
