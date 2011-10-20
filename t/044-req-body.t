# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 16);

#no_diff();
no_long_string();
#master_on();
#workers(2);
run_tests();

__DATA__

=== TEST 1: read buffered body
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world



=== TEST 2: read buffered body (timed out)
--- config
    client_body_timeout 1ms;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
    }
--- raw_request eval
"POST /test HTTP/1.1\r
Host: localhost\r
Content-Length: 100\r
Connection: close\r

hello, world"
--- response_body:
--- error_code:



=== TEST 3: read buffered body and then subrequest
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            local res = ngx.location.capture("/foo");
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo



=== TEST 4: first subrequest and then read buffered body
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        content_by_lua '
            local res = ngx.location.capture("/foo");
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo



=== TEST 5: read_body not allowed in set_by_lua
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        set_by_lua $has_read_body '
            return ngx.req.read_body and "defined" or "undef"
        ';
        echo "ngx.req.read_body: $has_read_body";
    }
--- request
GET /test
--- response_body
ngx.req.read_body: undef



=== TEST 6: read_body not allowed in set_by_lua
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        set $bool '';
        header_filter_by_lua '
             ngx.var.bool = (ngx.req.read_body and "defined" or "undef")
        ';
        content_by_lua '
            ngx.send_headers()
            ngx.say("ngx.req.read_body: ", ngx.var.bool)
        ';
    }
--- request
GET /test
--- response_body
ngx.req.read_body: undef



=== TEST 7: discard body
--- config
    location = /foo {
        content_by_lua '
            ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';

    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
"body: hiya, world\n"]



=== TEST 8: not discard body
--- config
    location = /foo {
        content_by_lua '
            -- ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
qr/400 Bad Request/]
--- error_code eval
[200, '']



=== TEST 9: read buffered body and retrieve the data
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world



=== TEST 10: read buffered body to file and call get_body_data
--- config
    client_body_in_file_only on;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }
--- request
POST /test
hello, world
--- response_body
nil



=== TEST 11: read buffered body to file and call get_body_file
--- config
    client_body_in_file_only on;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_file())
        ';
    }
--- request
POST /test
hello, world
--- response_body_like: client_body_temp/



=== TEST 12: read buffered body to memory and retrieve the file
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_file())
        ';
    }
--- request
POST /test
hello, world
--- response_body
nil



=== TEST 13: read buffered body to memory and reset it with data in memory
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
            ngx.say(ngx.var.echo_request_body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hiya, dear
hiya, dear
hiya, dear



=== TEST 14: read body to file and then override it with data in memory
--- config
    client_body_in_file_only on;

    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hello, baby")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
        ';
    }
--- request
POST /test
yeah
--- response_body
hello, baby
hello, baby



=== TEST 15: do not read the current request body but replace it with our own in memory
--- config
    client_body_in_file_only on;

    location = /test {
        content_by_lua '
            ngx.req.set_body_data("hello, baby")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /test\nyeah", "POST /test\nblah"]
--- response_body eval
["hello, baby
hello, baby
",
"hello, baby
hello, baby
"]



=== TEST 16: read buffered body to file and reset it to a new file
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file()
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
            ngx.var.new = ngx.req.get_body_file()
        ';
        #echo_request_body;
        proxy_pass http://127.0.0.1:$server_port/echo;
        #proxy_pass http://127.0.0.1:7890/echo;
        add_header X-Old $old;
        add_header X-New $new;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- user_files
>>> a.txt
Will you change this world?
--- raw_response_headers_like
X-Old: \S+/client_body_temp/\d+\r
.*?X-New: \S+/html/a\.txt\r
--- response_body
Will you change this world?



=== TEST 17: read buffered body to file and reset it to a new file
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file() or ""
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
            ngx.var.new = ngx.req.get_body_file()
        ';
        #echo_request_body;
        proxy_pass http://127.0.0.1:$server_port/echo;
        #proxy_pass http://127.0.0.1:7890/echo;
        add_header X-Old $old;
        add_header X-New $new;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world!
--- user_files
>>> a.txt
Will you change this world?
--- raw_response_headers_like
X-Old: \S+/client_body_temp/\d+\r
.*?X-New: \S+/html/a\.txt\r
--- response_body
Will you change this world?



=== TEST 18: read buffered body to file and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        content_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
            local b_file = ngx.var.realpath_root .. "/b.txt"
            ngx.req.set_body_file(b_file, true)
            ngx.say("a.txt exists: ", io.open(a_file) and "yes" or "no")
            ngx.say("b.txt exists: ", io.open(b_file) and "yes" or "no")
        ';
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- user_files
>>> a.txt
Will you change this world?
>>> b.txt
Sure I will!
--- response_body
a.txt exists: no
b.txt exists: yes



=== TEST 19: read buffered body to memoary and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
qr/500 Internal Server Error/]
--- error_code eval
[200, 500]



=== TEST 20: read buffered body to memoary and reset it to a new file (no auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, false)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
"Will you change this world?\n"]
--- error_code eval
[200, 200]



=== TEST 21: no request body and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, false)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
"Will you change this world?\n"]
--- error_code eval
[200, 200]
--- ONLY


=== TEST 22: no request body and reset it to a new file (no auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
qr/500 Internal Server Error/]
--- error_code eval
[200, 500]

