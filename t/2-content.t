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
		content_by_lua 'ngx.echo("Hello, Lua!")';
	}
--- request
GET /lua
--- response_body eval: "Hello, Lua!"
--- SKIP



=== TEST 2: capture location
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

