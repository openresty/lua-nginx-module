provider nginx_lua {
    probe http__lua__info(char *s);

    /* lua_State *L */
    probe http__lua__register__preload__package(void *L, u_char *pkg);

    probe http__lua__req__socket__consume__preread(ngx_http_request_t *r,
            u_char *data, size_t len);

    /* lua_State *parent, lua_State *child */
    probe http__lua__user__coroutine__create(ngx_http_request_t *r,
            void *parent, void *child);

    /* lua_State *parent, lua_State *child */
    probe http__lua__user__coroutine__resume(ngx_http_request_t *r,
                                             void *parent, void *child);

    /* lua_State *parent, lua_State *child */
    probe http__lua__user__coroutine__yield(ngx_http_request_t *r,
                                            void *parent, void *child);

    /* lua_State *L */
    probe http__lua__entry__coroutine__yield(ngx_http_request_t *r,
                                             void *L);

    /* ngx_http_lua_socket_tcp_upstream_t *u */
    probe http__lua__socket__tcp__send__start(ngx_http_request_t *r,
            void *u, u_char *data, size_t len);

    /* ngx_http_lua_socket_tcp_upstream_t *u */
    probe http__lua__socket__tcp__receive__done(ngx_http_request_t *r,
            void *u, u_char *data, size_t len);

    /* ngx_http_lua_socket_tcp_upstream_t *u */
    probe http__lua__socket__tcp__setkeepalive__buf__unread(
            ngx_http_request_t *r, void *u, u_char *data, size_t len);
};


#pragma D attributes Evolving/Evolving/Common      provider nginx_lua provider
#pragma D attributes Private/Private/Unknown       provider nginx_lua module
#pragma D attributes Private/Private/Unknown       provider nginx_lua function
#pragma D attributes Private/Private/Common        provider nginx_lua name
#pragma D attributes Evolving/Evolving/Common      provider nginx_lua args

