# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

log_level('notice');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5);

#no_diff();
#no_long_string();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    configure_by_lua_block {
        _G.configure_by = true
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("configure_by: ", configure_by)
        }
    }
--- request
GET /t
--- response_body
configure_by: true
--- no_error_log
[error]
[crit]
[alert]
[emerg]



=== TEST 2: duplicate
--- http_config
    configure_by_lua_block {

    }

    configure_by_lua_block {

    }
--- config
    location /t {
        return 200;
    }
--- must_die
--- error_log eval
qr/\[emerg\] .*? is duplicate/
--- no_error_log
[error]
[crit]
[alert]



=== TEST 3: wrong block
--- http_config
--- config
    location /t {
        configure_by_lua_block {

        }
    }
--- must_die
--- error_log eval
qr/\[emerg\] .*? directive is not allowed here/
--- no_error_log
[error]
[crit]
[alert]



=== TEST 4: print
--- http_config
    configure_by_lua_block {
        print("hello from configure_by_lua")
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure_by_lua:\d+: hello from configure_by_lua/
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 5: ngx.log
--- http_config
    configure_by_lua_block {
        ngx.log(ngx.NOTICE, "hello from ngx.log in configure_by_lua")
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure_by_lua:\d+: hello from ngx\.log in configure_by_lua/
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 6: ngx.get_phase
--- http_config
    configure_by_lua_block {
        ngx.log(ngx.NOTICE, "phase: ", ngx.get_phase())
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure_by_lua:\d+: phase: configure/
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 7: sanity (by_lua_file)
--- http_config
    configure_by_lua_file html/configure.lua;
--- config
    location /t {
        content_by_lua_block {
            ngx.say("configure_by: ", configure_by)
        }
    }
--- user_files
>>> configure.lua
_G.configure_by = true
--- request
GET /t
--- response_body
configure_by: true
--- no_error_log
[error]
[crit]
[alert]



=== TEST 8: duplicate (by_lua_file)
--- http_config
    configure_by_lua_file html/configure.lua;
    configure_by_lua_file html/configure.lua;
--- config
    location /t {
        return 200;
    }
--- user_files
>>> configure.lua
_G.configure_by = true
--- must_die
--- error_log eval
qr/\[emerg\] .*? is duplicate/
--- no_error_log
[error]
[crit]
[alert]



=== TEST 9: invalid directive argument (by_lua_file)
--- http_config
    configure_by_lua_file '';
--- config
    location /t {
        return 200;
    }
--- must_die
--- error_log eval
qr/\[error\] .*? invalid location config: no runnable Lua code in/
--- no_error_log
[crit]
[alert]
[emerg]



=== TEST 10: ngx.get_phase (by_lua_file)
--- http_config
    configure_by_lua_file html/configure.lua;
--- config
    location /t {
        return 200;
    }
--- user_files
>>> configure.lua
ngx.log(ngx.NOTICE, "phase: ", ngx.get_phase())
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure\.lua:\d+: phase: configure/
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 11: error in configure causes exit
--- http_config
    configure_by_lua_block {
        error("failed to configure")
    }
--- config
    location /t {
        return 200;
    }
--- must_die
--- error_log eval
qr/\[error\] .*? configure_by_lua:\d+: failed to configure/
--- no_error_log
[alert]
[emerg]



=== TEST 12: disabled API (ngx.timer.at)
--- http_config
    configure_by_lua_block {
        local pok, err = pcall(ngx.timer.at, 0, function() end)
        if not pok then
            print(err)
        end
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure_by_lua:\d+: no request/
--- no_error_log
[crit]
[alert]
[emerg]



=== TEST 13: disabled API (ngx.socket.tcp)
--- http_config
    configure_by_lua_block {
        local pok, err = pcall(ngx.socket.tcp)
        if not pok then
            print(err)
        end
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- error_log eval
qr/\[notice\] .*? configure_by_lua:\d+: no request/
--- no_error_log
[crit]
[alert]
[emerg]
