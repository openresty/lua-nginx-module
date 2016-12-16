# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "jo")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 11
matched: 1234
--- no_error_log
[error]



=== TEST 2: empty matched string
--- config
    location /re {
        content_by_lua '
            local s = "hello, world"
            local from, to, err = ngx.re.find(s, "[0-9]*")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 0
matched: 
--- no_error_log
[error]



=== TEST 3: multiple captures (with o)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([a-z]+).*?([0-9]{2})[0-9]+", "o")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello, 1234
--- no_error_log
[error]



=== TEST 4: not matched
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "foo")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 5: case sensitive by default
--- config
    location /re {
        content_by_lua '
            local from = ngx.re.find("hello, 1234", "HELLO")
            if from then
                ngx.say(from)
            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 6: case insensitive
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "HELLO", "i")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 5
matched: hello
--- no_error_log
[error]



=== TEST 7: UTF-8 mode
--- config
    location /re {
        content_by_lua '
            local s = "hello章亦春"
            local from, to, err = ngx.re.find(s, "HELLO.{2}", "iu")
            if not from then
                ngx.say("FAIL: ", err)
                return
            end

            ngx.say(string.sub(s, from, to))
        ';
    }
--- request
    GET /re
--- response_body_like chop
^(?:FAIL: bad argument \#2 to '\?' \(pcre_compile\(\) failed: this version of PCRE is not compiled with PCRE_UTF8 support in "HELLO\.\{2\}" at "HELLO\.\{2\}"\)|hello章亦)$
--- no_error_log
[error]



=== TEST 8: multi-line mode (^ at line head)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "^world", "m")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 7
to: 11
matched: world
--- no_error_log
[error]



=== TEST 9: multi-line mode (. does not match \n)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "m")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 5
matched: hello
--- no_error_log
[error]



=== TEST 10: single-line mode (^ as normal)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "^world", "s")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 11: single-line mode (dot all)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "s")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello
world
--- no_error_log
[error]



=== TEST 12: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "\\\\w     \\\\w", "x")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 2
matched: he
--- no_error_log
[error]



=== TEST 13: bad pattern
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "(abc")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)

                else
                    ngx.say("not matched.")
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
error: pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]



=== TEST 14: bad option
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "H")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
unknown flag "H"



=== TEST 15: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "a")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 16: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            local s = "1234, hello"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "a")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 4
matched: 1234
--- no_error_log
[error]



=== TEST 17: match with ctx but no pos
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local from, to = ngx.re.find("1234, hello", "([0-9]+)", "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 18: match with ctx and a pos
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 3 }
            local from, to, err = ngx.re.find("1234, hello", "([0-9]+)", "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 3
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 19: named subpatterns w/ extraction
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "(?<first>[a-z]+), [0-9]+")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello, 1234
--- no_error_log
[error]



=== TEST 20: bad UTF-8
--- config
    location = /t {
        content_by_lua '
            local target = "你好"
            local regex = "你好"

            local from, to, err = ngx.re.find(string.sub(target, 1, 4), regex, "u")

            if err then
                ngx.say("error: ", err)
                return
            end

            if m then
                ngx.say("matched: ", from)
            else
                ngx.say("not matched")
            end
        ';
    }
--- request
GET /t
--- response_body_like chop
^error: pcre_exec\(\) failed: -10$

--- no_error_log
[error]



=== TEST 21: UTF-8 mode without UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local s = "你好"
            local from, to, err = ngx.re.find(s, ".", "U")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- stap
probe process("$LIBPCRE_PATH").function("pcre_compile") {
    printf("compile opts: %x\n", $options)
}

probe process("$LIBPCRE_PATH").function("pcre_exec") {
    printf("exec opts: %x\n", $options)
}

--- stap_out
compile opts: 800
exec opts: 2000

--- request
    GET /re
--- response_body
from: 1
to: 3
matched: 你
--- no_error_log
[error]



=== TEST 22: just hit match limit
--- http_config
    lua_regex_match_limit 5000;
--- config
    location /re {
        content_by_lua_file html/a.lua;
    }

--- user_files
>>> a.lua
local re = [==[(?i:([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:=|<=>|r?like|sounds\s+like|regexp)([\s'\"`´’‘\(\)]*)?\2|([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:!=|<=|>=|<>|<|>|\^|is\s+not|not\s+like|not\s+regexp)([\s'\"`´’‘\(\)]*)?(?!\6)([\d\w]+))]==]

s = string.rep([[ABCDEFG]], 10)

local start = ngx.now()

local from, to, err = ngx.re.find(s, re, "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if not from then
    if err then
        ngx.say("error: ", err)
        return
    end
    ngx.say("failed to match.")
    return
end

--- request
    GET /re
--- response_body
error: pcre_exec() failed: -8
--- no_error_log
[error]



=== TEST 23: just not hit match limit
--- http_config
    lua_regex_match_limit 5100;
--- config
    location /re {
        content_by_lua_file html/a.lua;
    }

--- user_files
>>> a.lua
local re = [==[(?i:([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:=|<=>|r?like|sounds\s+like|regexp)([\s'\"`´’‘\(\)]*)?\2|([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:!=|<=|>=|<>|<|>|\^|is\s+not|not\s+like|not\s+regexp)([\s'\"`´’‘\(\)]*)?(?!\6)([\d\w]+))]==]

s = string.rep([[ABCDEFG]], 10)

local start = ngx.now()

local from, to, err = ngx.re.find(s, re, "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if not from then
    if err then
        ngx.say("error: ", err)
        return
    end
    ngx.say("failed to match")
    return
end

--- request
    GET /re
--- response_body
failed to match
--- no_error_log
[error]



=== TEST 24: specify the group (1)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 1)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 8
matched: 1
--- no_error_log
[error]



=== TEST 25: specify the group (0)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 0)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 11
matched: 1234
--- no_error_log
[error]



=== TEST 26: specify the group (2)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 2)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 9
to: 11
matched: 234
--- no_error_log
[error]



=== TEST 27: specify the group (3)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 3)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
error: nth out of bound
--- no_error_log
[error]



=== TEST 28: specify the group (4)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 4)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
error: nth out of bound
--- no_error_log
[error]



=== TEST 29: nil submatch (2nd)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])|(hello world)", "jo", nil, 2)
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched!
--- no_error_log
[error]



=== TEST 30: nil submatch (1st)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "(hello world)|([0-9])", "jo", nil, 1)
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched!
--- no_error_log
[error]



=== TEST 31: match with ctx and a pos (anchored by \G)
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 3 }
            local from, to, err = ngx.re.find("1234, hello", [[(\G[0-9]+)]], "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 3
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 32: default jit_stack_size too small
--- config
    location /re {
        content_by_lua_block {
            -- regex is taken from https://github.com/JuliaLang/julia/issues/8278
            local very_long_string = [[71.163.72.113 - - [30/Jul/2014:16:40:55 -0700] "GET emptymind.org/thevacantwall/wp-content/uploads/2013/02/DSC_006421.jpg HTTP/1.1" 200 492513 "http://images.search.yahoo.com/images/view;_ylt=AwrB8py9gdlTGEwADcSjzbkF;_ylu=X3oDMTI2cGZrZTA5BHNlYwNmcC1leHAEc2xrA2V4cARvaWQDNTA3NTRiMzYzY2E5OTEwNjBiMjc2YWJhMjkxMTEzY2MEZ3BvcwM0BGl0A2Jpbmc-?back=http%3A%2F%2Fus.yhs4.search.yahoo.com%2Fyhs%2Fsearch%3Fei%3DUTF-8%26p%3Dapartheid%2Bwall%2Bin%2Bpalestine%26type%3Dgrvydef%26param1%3D1%26param2%3Dsid%253Db01676f9c26355f014f8a9db87545d61%2526b%253DChrome%2526ip%253D71.163.72.113%2526p%253Dgroovorio%2526x%253DAC811262A746D3CD%2526dt%253DS940%2526f%253D7%2526a%253Dgrv_tuto1_14_30%26hsimp%3Dyhs-fullyhosted_003%26hspart%3Dironsource&w=588&h=387&imgurl=occupiedpalestine.files.wordpress.com%2F2012%2F08%2F5-peeking-through-the-wall.jpg%3Fw%3D588%26h%3D387&rurl=http%3A%2F%2Fwww.stopdebezetting.com%2Fwereldpers%2Fcompare-the-berlin-wall-vs-israel-s-apartheid-wall-in-palestine.html&size=49.0KB&name=...+%3Cb%3EApartheid+wall+in+Palestine%3C%2Fb%3E...+%7C+Or+you+go+peeking+through+the+%3Cb%3Ewall%3C%2Fb%3E&p=apartheid+wall+in+palestine&oid=50754b363ca991060b276aba291113cc&fr2=&fr=&tt=...+%3Cb%3EApartheid+wall+in+Palestine%3C%2Fb%3E...+%7C+Or+you+go+peeking+through+the+%3Cb%3Ewall%3C%2Fb%3E&b=0&ni=21&no=4&ts=&tab=organic&sigr=13evdtqdq&sigb=19k7nsjvb&sigi=12o2la1db&sigt=12lia2m0j&sign=12lia2m0j&.crumb=.yUtKgFI6DE&hsimp=yhs-fullyhosted_003&hspart=ironsource" "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.125 Safari/537.36]]
            local very_complicated_regex = [[([\d\.]+) ([\w.-]+) ([\w.-]+) (\[.+\]) "([^"\r\n]*|[^"\r\n\[]*\[.+\][^"]+|[^"\r\n]+.[^"]+)" (\d{3}) (\d+|-) ("(?:[^"]|\")+)"? ("(?:[^"]|\")+)"?]]
            local from, to, err = ngx.re.find(very_long_string, very_complicated_regex, "jo")
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        }
    }
--- request
    GET /re
--- response_body
error: pcre_exec() failed: -27
--- no_error_log
[error]



=== TEST 33: increase jit_stack_size
--- http_config
    init_by_lua_block {
        ngx.re.opt("jit_stack_size", 128 * 1024)
    }
--- config
    location /re {
        content_by_lua_block {
            -- regex is taken from https://github.com/JuliaLang/julia/issues/8278
            local very_long_string = [[71.163.72.113 - - [30/Jul/2014:16:40:55 -0700] "GET emptymind.org/thevacantwall/wp-content/uploads/2013/02/DSC_006421.jpg HTTP/1.1" 200 492513 "http://images.search.yahoo.com/images/view;_ylt=AwrB8py9gdlTGEwADcSjzbkF;_ylu=X3oDMTI2cGZrZTA5BHNlYwNmcC1leHAEc2xrA2V4cARvaWQDNTA3NTRiMzYzY2E5OTEwNjBiMjc2YWJhMjkxMTEzY2MEZ3BvcwM0BGl0A2Jpbmc-?back=http%3A%2F%2Fus.yhs4.search.yahoo.com%2Fyhs%2Fsearch%3Fei%3DUTF-8%26p%3Dapartheid%2Bwall%2Bin%2Bpalestine%26type%3Dgrvydef%26param1%3D1%26param2%3Dsid%253Db01676f9c26355f014f8a9db87545d61%2526b%253DChrome%2526ip%253D71.163.72.113%2526p%253Dgroovorio%2526x%253DAC811262A746D3CD%2526dt%253DS940%2526f%253D7%2526a%253Dgrv_tuto1_14_30%26hsimp%3Dyhs-fullyhosted_003%26hspart%3Dironsource&w=588&h=387&imgurl=occupiedpalestine.files.wordpress.com%2F2012%2F08%2F5-peeking-through-the-wall.jpg%3Fw%3D588%26h%3D387&rurl=http%3A%2F%2Fwww.stopdebezetting.com%2Fwereldpers%2Fcompare-the-berlin-wall-vs-israel-s-apartheid-wall-in-palestine.html&size=49.0KB&name=...+%3Cb%3EApartheid+wall+in+Palestine%3C%2Fb%3E...+%7C+Or+you+go+peeking+through+the+%3Cb%3Ewall%3C%2Fb%3E&p=apartheid+wall+in+palestine&oid=50754b363ca991060b276aba291113cc&fr2=&fr=&tt=...+%3Cb%3EApartheid+wall+in+Palestine%3C%2Fb%3E...+%7C+Or+you+go+peeking+through+the+%3Cb%3Ewall%3C%2Fb%3E&b=0&ni=21&no=4&ts=&tab=organic&sigr=13evdtqdq&sigb=19k7nsjvb&sigi=12o2la1db&sigt=12lia2m0j&sign=12lia2m0j&.crumb=.yUtKgFI6DE&hsimp=yhs-fullyhosted_003&hspart=ironsource" "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.125 Safari/537.36]]
            local very_complicated_regex = [[([\d\.]+) ([\w.-]+) ([\w.-]+) (\[.+\]) "([^"\r\n]*|[^"\r\n\[]*\[.+\][^"]+|[^"\r\n]+.[^"]+)" (\d{3}) (\d+|-) ("(?:[^"]|\")+)"? ("(?:[^"]|\")+)"?]]
            local from, to, err = ngx.re.find(very_long_string, very_complicated_regex, "jo")
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        }
    }
--- request
    GET /re
--- response_body
from: 1
to: 1563
--- no_error_log
[error]



=== TEST 34: jit_stack_size change disallowed once regex cache is populated
--- config
    location /re {
        content_by_lua_block {
            local status, err = pcall(ngx.re.opt, "jit_stack_size", 128 * 1024)
            if err then ngx.log(ngx.INFO, err) end
            local s = "hello, 1234"
            local from, to = ngx.re.find(s, "(hello world)|([0-9])", "jo")
            ngx.say("from: ", from)
            ngx.say("to: ", to)
        }
    }
--- request
    GET /re
--- response_body
from: 8
to: 8

--- grep_error_log eval
qr/Changing jit stack size is not allowed when some regexs have already been compiled and cached/

--- grep_error_log_out eval
["", "Changing jit stack size is not allowed when some regexs have already been compiled and cached\n"]




=== TEST 35: passing unknown options to ngx.re.opt throws an error
--- config
    location /re {
        content_by_lua_block {
            local status, err = pcall(ngx.re.opt, "foo", 123)
            ngx.say(err)
        }
    }
--- request
    GET /re
--- response_body
unrecognized option name
--- no_error_log
[error]
