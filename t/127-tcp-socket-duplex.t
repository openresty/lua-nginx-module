# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * 2 * 3;

our $HtmlDir = html_dir;

log_level("error");
no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: lua_socket_duplex_for_pipeline_request
--- config
    server_tokens off;
    set $port $TEST_NGINX_SERVER_PORT;
    keepalive_requests 100000000;
    location /echo {
        content_by_lua 'ngx.print(ngx.req.get_uri_args()["data"])';
    }

    location /duplex {
        content_by_lua '
            local sock = ngx.socket.connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            local err 
            local max = 1
            local t = ngx.thread.spawn(function ()
                local i = 1
                while i <= max and not err do
                    local header, chunk_size, chunk_data
                    while not err do
                        header, err = sock:receive("*l")
                        if header and #header == 0 then
                            break
                        end 
                    end 
            
                    while not err and chunk_size ~= "0" do
                        chunk_size, err = sock:receive("*l")
                        if chunk_size and chunk_size ~= "0" then
                            chunk_data, err = sock:receive(tonumber(chunk_size, 16));
                            if chunk_data then
                                ngx.print(chunk_data)
                            end 
                        end 
                        sock:receive("*l")
                    end 
            
                    i = i + 1 
                end 
            end)
            
            local i = 1 
            while i <= max and not err do
                local bytes
                bytes, err = sock:send("GET /echo?data=" .. string.format("%08d", i) .. " HTTP/1.1\\r\\nHost: localhost\\r\\n\\r\\n")
                i = i + 1 
            end
            
            ngx.thread.wait(t)
            
            if err then
                ngx.print(err)
            end
            
            sock:close()
            ';
    }

--- request
GET /duplex
--- response_body eval
my $body = "";
for (my $i = 1; $i <= 1; $i++) {
    $body .= sprintf("%08d", $i);
}
$body

=== TEST 2: lua_socket_return_socket_busy_when_read_in_two_coroutines
--- config
    server_tokens off;
    set $port $TEST_NGINX_SERVER_PORT;

    location /socket_busy {
        content_by_lua '
            local err1, err2 
            local sock = ngx.socket.connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            sock:settimeout(150)
            local t = ngx.thread.spawn(function ()
                local data
                data, err1 = sock:receive("*l")
            end)
 
            data, err2 = sock:receive("*l")
            ngx.thread.wait(t)
            sock:close()
            ngx.print(err1, ", ", err2)
            ';
    }

--- request
GET /socket_busy
--- response_body_like chomp
socket busy

=== TEST 3: lua_socket_return_socket_busy_when_write_in_two_coroutines
--- config
    server_tokens off;
    set $port $TEST_NGINX_SERVER_PORT;

    location /socket_busy {
        content_by_lua '
            local err1, err2 
            local sock = ngx.socket.connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            sock:settimeout(100)
            local t = ngx.thread.spawn(function ()
                local bytes
                while not err1 do
                    bytes, err1 = sock:send("0")
                end
            end)
 
            while not err2 do
               local bytes
               bytes, err2 = sock:send("0")
            end

            ngx.thread.wait(t)
            sock:close()
            ngx.print(err1, ", ", err2)
            ';
    }

--- request
GET /socket_busy
--- response_body_like chomp
socket busy
