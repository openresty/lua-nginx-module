# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(2);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: env directive settings should be visiable to init_by_lua*
--- main_config
env MyTestSysEnv=hello;
--- http_config
    init_by_lua_block {
        package.loaded.foo = os.getenv("MyTestSysEnv")
    }

--- config
location /t {
    content_by_lua_block {
        ngx.say(package.loaded.foo)
        ngx.say(os.getenv("MyTestSysEnv"))
    }
}
--- request
GET /t
--- response_body
hello
hello
--- no_error_log
[error]
