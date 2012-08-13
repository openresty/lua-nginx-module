provider nginx_lua {
    probe http__lua__register__preload__package(void *L, char *pkg);
    probe http__lua__req__socket__consume__preread(ngx_http_request_t *r, char *data, size_t len);
};


#pragma D attributes Evolving/Evolving/Common      provider nginx_lua provider
#pragma D attributes Private/Private/Unknown       provider nginx_lua module
#pragma D attributes Private/Private/Unknown       provider nginx_lua function
#pragma D attributes Private/Private/Common        provider nginx_lua name
#pragma D attributes Evolving/Evolving/Common      provider nginx_lua args

