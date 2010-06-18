# vi:ft=
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(100);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: basic
--- config
	location /lua {
		# NOTE: the newline escape sequence must be double-escaped, as nginx config
		# parser will unescape first!
		content_by_lua 'ngx.echo("Hello, Lua!\\n")';
	}
--- request
GET /lua
--- response_body
Hello, Lua!



=== TEST 2: variable
--- config
	location /lua {
		# NOTE: the newline escape sequence must be double-escaped, as nginx config
		# parser will unescape first!
		content_by_lua 'v = ngx.var["request_uri"] ngx.echo("request_uri: ", v, "\\n")';
	}
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 3: variable (file)
--- config
	location /lua {
		content_by_lua_file html/test.lua;
	}
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.echo("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 4: calc expression
--- config
	location /lua {
		content_by_lua_file html/calc.lua;
	}
--- user_files
>>> calc.lua
local function uri_unescape(uri)
	local function convert(hex)
		return string.char(tonumber("0x"..hex))
	end
	local s = string.gsub(uri, "%%([0-9a-fA-F][0-9a-fA-F])", convert)
	return s
end

local function eval_exp(str)
	return loadstring("return "..str)()
end

local exp_str = ngx.var["arg_exp"]
-- print("exp: '", exp_str, "'\n")
local status, res
status, res = pcall(uri_unescape, exp_str)
if not status then
	ngx.echo("error: ", res, "\n")
	return
end
status, res = pcall(eval_exp, res)
if status then
	ngx.echo("result: ", res, "\n")
else
	ngx.echo("error: ", res, "\n")
end
--- request
GET /lua?exp=1%2B2*math.sin(3)%2Fmath.exp(4)-math.sqrt(2)
--- response_body
result: -0.4090441561579



=== TEST 5: capture location
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

