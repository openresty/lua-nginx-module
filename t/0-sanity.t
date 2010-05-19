# vi:ft=perl
use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: sanity (integer)
--- config
	location /lua {
		set_by_lua $res "return 1+1";
		echo $res;
	}
--- request
GET /lua
--- response_body
2



=== TEST 2: sanity (string)
--- config
	location /lua {
		set_by_lua $res "return 'hello' .. 'world'";
		echo $res;
	}
--- request
GET /lua
--- response_body
helloworld

