#include <ngx_atomic.h>
#include <ngx_http_lua_inject_stub_status.h>


extern ngx_atomic_t  *ngx_stat_accepted;
extern ngx_atomic_t  *ngx_stat_handled;
extern ngx_atomic_t  *ngx_stat_requests;
extern ngx_atomic_t  *ngx_stat_active;
extern ngx_atomic_t  *ngx_stat_reading;
extern ngx_atomic_t  *ngx_stat_writing;
extern ngx_atomic_t  *ngx_stat_waiting;


void
ngx_http_lua_inject_stub_status_api(lua_State *L) {
    lua_pushcfunction(L, ngx_http_lua_ngx_stub_status);
    lua_setfield(L, -2, "stub_status");
}

static int
ngx_http_lua_ngx_stub_status(lua_State *L) {
    ngx_atomic_int_t   ap, hn, ac, rq, rd, wr, wa;
    ap = *ngx_stat_accepted;
    hn = *ngx_stat_handled;
    ac = *ngx_stat_active;
    rq = *ngx_stat_requests;
    rd = *ngx_stat_reading;
    wr = *ngx_stat_writing;
    wa = *ngx_stat_waiting;

    lua_createtable(L, 0, 7);

    lua_pushinteger(L, ap);
    lua_setfield(L, -2, "accepted");

    lua_pushinteger(L, hn);
    lua_setfield(L, -2, "handled");

    lua_pushinteger(L, ac);
    lua_setfield(L, -2, "active");

    lua_pushinteger(L, rq);
    lua_setfield(L, -2, "requests");

    lua_pushinteger(L, rd);
    lua_setfield(L, -2, "reading");

    lua_pushinteger(L, wr);
    lua_setfield(L, -2, "writing");

    lua_pushinteger(L, wa);
    lua_setfield(L, -2, "waiting");

    return 1;
}
