# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 6);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: read chunks (inline)
--- config
    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua '
            local chunk, eof = ngx.arg[1], ngx.arg[2]
            print("chunk: [", chunk, "], eof: ", eof)
        ';
    }
--- request
GET /read
--- response_body chop
hello worldhiya globe
--- error_log
chunk: [hello world], eof: false
chunk: [hiya globe], eof: false
chunk: [], eof: true
--- no_error_log
[error]



=== TEST 2: read chunks (file)
--- config
    location /read {
        echo -n hello world;
        echo -n hiya globe;

        body_filter_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
local chunk, eof = ngx.arg[1], ngx.arg[2]
print("chunk: [", chunk, "], eof: ", eof)
--- request
GET /read
--- response_body chop
hello worldhiya globe
--- error_log
chunk: [hello world], eof: false
chunk: [hiya globe], eof: false
chunk: [], eof: true
--- no_error_log
[error]

