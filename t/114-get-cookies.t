# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use t::TestNginxLua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => (2 * blocks() * repeat_each());

#no_diff();
#no_long_string();

our $dump_cookie_conf_def = <<'_EOC_';
location /get-cookies {
    content_by_lua '
        local c = ngx.req.get_cookies()
        for k, v in pairs(c) do
            if type(v) == \'table\' then
                ngx.say(string.format("key: %s value:", k))
                for vk, vv in pairs(v) do
                    ngx.say(string.format("    table[%d] = %s", vk, vv))
                end
            else
                ngx.say(string.format("key: %s value: %s", k, v))
            end
        end
    ';
}
_EOC_

run_tests();

__DATA__

=== TEST 1: simple cookie
--- config
    location /get-cookies {
        content_by_lua '
            ngx.say("foo: ", ngx.req.get_cookies()["foo"] or "nil")
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar
--- response_body
foo: bar

=== TEST 2: complex cookie
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: lastvisit=1251731074; sessionlogin=1251760758; username=; password=; remember_login=; admin_button=
--- response_body
key: password value: 
key: remember_login value: 
key: lastvisit value: 1251731074
key: sessionlogin value: 1251760758
key: admin_button value: 
key: username value: 

=== TEST 3: set true when a key do not have a value
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: a
--- response_body
key: a value: true

=== TEST 3:  key with a equal sign but do not speicfy a value
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: a=
--- response_body
key: a value: 

=== TEST 4: successive =
--- config
    location /get-cookies {
        content_by_lua '
            ngx.say("foo: ", ngx.req.get_cookies()["foo"] or "nil")
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie: foo=ba=r
--- response_body
foo: ba=r

=== TEST 5: leading spaces should be trimmed
--- config
    location /get-cookies {
        content_by_lua '
            ngx.say("foo: ", ngx.req.get_cookies()["foo"] or "nil")
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie:    foo= b
--- response_body
foo: b

=== TEST 5: trailing spaces which should be reserved
--- config
    location /get-cookies {
        content_by_lua '
            ngx.say("fo o : ", ngx.req.get_cookies()["fo o"] or "nil")
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie: fo o= b
--- response_body
fo o : b

=== TEST 6: , sperated values
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar,foo2=bar2, foo3=bar3;foo4 =a&b&c; foo5=a;b
--- response_body
key: foo value: bar
key: b value: true
key: foo3 value: bar3
key: foo5 value: a
key: foo4  value:
    table[1] = a
    table[2] = b
    table[3] = c
key: foo2 value: bar2

=== TEST 7: custom max 3 cookies
--- config
    location /get-cookies {
        content_by_lua '
            local c = ngx.req.get_cookies(4)
            for k, v in pairs(c) do
                if type(v) == \'table\' then
                    ngx.say(string.format("key: %s value:", k))
                    for vk, vv in pairs(v) do
                        ngx.say(string.format("    table[%d] = %s", vk, vv))
                    end
                else
                    ngx.say(string.format("key: %s value: %s", k, v))
                end
            end
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar;foo2=bar2&4; foo3=bar3&4;foo4 =a&b&c; foo5=a;b
--- response_body
key: foo3 value:
    table[1] = bar3
key: foo value: bar
key: foo2 value:
    table[1] = bar2
    table[2] = 4

=== TEST 8: limit cookies number by default
--- config
    location /get-cookies {
        content_by_lua '
            local c = ngx.req.get_cookies()
            local keys = {}
            for key, val in pairs(c) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", c[key])
            end
        ';
    }
--- request
GET /get-cookies
--- more_headers eval
my $s;
my $i = 1;
while ($i <= 205) {
    $s .= "x-$i=$i; ";
    $i++;
}
$s = "Cookie: " . $s;
$s
--- response_body eval
my %hash;
my $r;
my $j = 1;
while ($j <= 100) {
    $hash{"x-$j"} = $j;
    $j++;
}
foreach my $key ( sort keys %hash )
{
  $r .= $key . ": " . $hash{$key} . "\n";
}
$r

=== TEST 9: custom unlimit cookies(1)
--- config
    location /get-cookies {
        content_by_lua '
            local c = ngx.req.get_cookies(0)
            local keys = {}
            for key, val in pairs(c) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", c[key])
            end
        ';
    }
--- request
GET /get-cookies
--- more_headers eval
my $s;
my $i = 1;
while ($i <= 105) {
    $s .= "x-$i=$i; ";
    $i++;
}
$s = "Cookie: " . $s;
$s
--- response_body eval
my %hash;
my $r;
my $j = 1;
while ($j <= 105) {
    $hash{"x-$j"} = $j;
    $j++;
}
foreach my $key ( sort keys %hash )
{
  $r .= $key . ": " . $hash{$key} . "\n";
}
$r
=== TEST 10: custom unlimit cookies (2)
--- config
    location /get-cookies {
        content_by_lua '
            local c = ngx.req.get_cookies(-100)
            local keys = {}
            for key, val in pairs(c) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", c[key])
            end
        ';
    }
--- request
GET /get-cookies
--- more_headers eval
my $s;
my $i = 1;
while ($i <= 105) {
    $s .= "x-$i=$i; ";
    $i++;
}
$s = "Cookie: " . $s;
$s
--- response_body eval
my %hash;
my $r;
my $j = 1;
while ($j <= 105) {
    $hash{"x-$j"} = $j;
    $j++;
}
foreach my $key ( sort keys %hash )
{
  $r .= $key . ": " . $hash{$key} . "\n";
}
$r

=== TEST 11: empty cookie 
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: 
--- response_body

=== TEST 12: extra semicolon in the middle
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar; ;hello=foo
--- response_body
key: hello value: foo
key: foo value: bar

=== TEST 13: extra comma in the end
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar, hello=foo,
--- response_body
key: hello value: foo
key: foo value: bar

=== TEST 14: extra semicolon in the end
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar; hello=foo;
--- response_body
key: hello value: foo
key: foo value: bar

=== TEST 15: extra '&' in the end 
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar&123&hello&
--- response_body
key: foo value:
    table[1] = bar
    table[2] = 123
    table[3] = hello
    table[4] = 

=== TEST 16: request with mutiple cookies 
--- config eval
$::dump_cookie_conf_def
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar&123&hello
Cookie: foo2=bar2&1232&hello2
Cookie: foo3=bar3
--- response_body
key: foo3 value: bar3
key: foo value:
    table[1] = bar
    table[2] = 123
    table[3] = hello
key: foo2 value:
    table[1] = bar2
    table[2] = 1232
    table[3] = hello2

=== TEST 17: custom cookies limit request with mutiple cookies 
--- config
    location /get-cookies {
        content_by_lua '
            local c = ngx.req.get_cookies(5)
            for k, v in pairs(c) do
                if type(v) == \'table\' then
                    ngx.say(string.format("key: %s value:", k))
                    for vk, vv in pairs(v) do
                        ngx.say(string.format("    table[%d] = %s", vk, vv))
                    end
                else
                    ngx.say(string.format("key: %s value: %s", k, v))
                end
            end
        ';
    }
--- request
GET /get-cookies
--- more_headers
Cookie: foo=bar&123&hello
Cookie: foo2=bar2&1232&hello2
Cookie: foo3=bar3&43124&34&3
--- response_body
key: foo value:
    table[1] = bar
    table[2] = 123
    table[3] = hello
key: foo2 value:
    table[1] = bar2
    table[2] = 1232
