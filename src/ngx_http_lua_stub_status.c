#include <ngx_core.h>
#include "ngx_http_lua_stub_status.h"

#if (NGX_STAT_STUB)

static int ngx_http_lua_stub_status(lua_State *L);


void
ngx_http_lua_inject_stub_status_api(lua_State *L) {
    lua_pushcfunction(L, ngx_http_lua_stub_status);
    lua_setfield(L, -2, "stub_status");
}

static int
ngx_http_lua_stub_status(lua_State *L) {
    lua_createtable(L, 0, 7);

    lua_pushinteger(L, *ngx_stat_active);
    lua_setfield(L, -2, "active");

    lua_pushinteger(L, *ngx_stat_accepted);
    lua_setfield(L, -2, "accepted");

    lua_pushinteger(L, *ngx_stat_handled);
    lua_setfield(L, -2, "handled");

    lua_pushinteger(L, *ngx_stat_requests);
    lua_setfield(L, -2, "requests");

    lua_pushinteger(L, *ngx_stat_reading);
    lua_setfield(L, -2, "reading");

    lua_pushinteger(L, *ngx_stat_writing);
    lua_setfield(L, -2, "writing");

    lua_pushinteger(L, *ngx_stat_waiting);
    lua_setfield(L, -2, "waiting");

    return 1;
}

#endif
