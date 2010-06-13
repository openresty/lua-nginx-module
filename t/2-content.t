# vi:ft=perl
use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: basic
--- config
	location /lua {
		content_by_lua 'ngx.echo("Hello, Lua!\n")';
	}
--- request
GET /lua
--- response_body
Hello, Lua!



=== TEST 2: variable
--- config
	location /lua1 {
		# NOTE: the newline escape sequence must be double-escaped, as nginx config
		# parser will unescape first!
		content_by_lua 'v = ngx.var["request_uri"] ngx.echo("request_uri: ", v, "\\n")';
	}
--- request
GET /lua1
--- response_body
request_uri: /lua1
--- ONLY



=== TEST 3: capture location
--- config
	location /other {
		echo "hello, world";
	}

	location /lua {
		content_by_lua 'res = ngx.location.capture("/other"); if res.status == "200" then ngx.echo(res.body) end';
	}
--- request
GET /lua
--- response_body
hello, world
--- SKIP

