typedef struct { int dummy; } lua_State;


provider nginx_lua {
    probe http__lua__register__preload__package(lua_State *L, char *pkg);
};


#pragma D attributes Evolving/Evolving/Common      provider nginx provider
#pragma D attributes Private/Private/Unknown       provider nginx module
#pragma D attributes Private/Private/Unknown       provider nginx function
#pragma D attributes Private/Private/Common        provider nginx name
#pragma D attributes Evolving/Evolving/Common      provider nginx args

