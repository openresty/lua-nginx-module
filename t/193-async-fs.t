# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_EVENT_TYPE}
        && $ENV{TEST_NGINX_EVENT_TYPE} !~ /^kqueue|epoll|eventport$/)
    {
        $SkipReason = "unavailable for the event type '$ENV{TEST_NGINX_EVENT_TYPE}'";
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 7);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: open and close
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt")
        if not f then
            ngx.say("open failed: ", err)
            return
        end

        ngx.say("type: ", type(f))
        ngx.say("tostring: ", tostring(f):find("^file %(fd=") ~= nil)

        local ok, err = f:close()
        ngx.say("close: ", ok)
    }
}
--- user_files
>>> test.txt
hello world
--- request
GET /t
--- response_body
type: userdata
tostring: true
close: true



=== TEST 2: open + read
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        if not f then
            ngx.say("open failed: ", err)
            return
        end

        local data, err = f:read(4096)
        if not data then
            ngx.say("read failed: ", err)
            f:close()
            return
        end

        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
hello world
--- request
GET /t
--- response_body
data: [hello world
]



=== TEST 3: open + write + readback
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/out.txt"

        local f, err = ngx.fs.open(path, "w")
        if not f then
            ngx.say("open failed: ", err)
            return
        end

        local nbytes, err = f:write("hello async fs")
        if not nbytes then
            ngx.say("write failed: ", err)
            f:close()
            return
        end

        ngx.say("wrote ", nbytes, " bytes")
        f:close()

        local f2 = ngx.fs.open(path, "r")
        local data = f2:read(4096)
        ngx.say("readback: [", data, "]")
        f2:close()
    }
}
--- request
GET /t
--- response_body
wrote 14 bytes
readback: [hello async fs]



=== TEST 4: open nonexistent file
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/no_such_file.txt", "r")
        if not f then
            ngx.say("open failed: true")
            ngx.say("err type: ", type(err))
            return
        end

        ngx.say("should not reach here")
    }
}
--- request
GET /t
--- response_body
open failed: true
err type: string



=== TEST 5: invalid mode
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local ok, err = pcall(ngx.fs.open, "$TEST_NGINX_HTML_DIR/test.txt", "x")
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "invalid mode") ~= nil)
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 6: read with offset
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local data = f:read(5, 6)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
hello world
--- request
GET /t
--- response_body
data: [world]



=== TEST 7: read EOF returns empty string
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local data = f:read(4096, 99999)
        ngx.say("data len: ", #data)
        ngx.say("is empty: ", data == "")
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
data len: 0
is empty: true



=== TEST 8: write with offset (pwrite)
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/out.txt"

        local f = ngx.fs.open(path, "w+")

        local n1 = f:write("hello world")
        ngx.say("write1: ", n1)

        local n2 = f:write("nginx", 6)
        ngx.say("write2: ", n2)

        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- request
GET /t
--- response_body
write1: 11
write2: 5
data: [hello nginx]



=== TEST 9: write empty data returns 0
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/out.txt", "w")

        local nbytes, err = f:write("")
        ngx.say("nbytes: ", nbytes)
        ngx.say("err: ", err)
        f:close()
    }
}
--- request
GET /t
--- response_body
nbytes: 0
err: nil



=== TEST 10: append mode
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/out.txt"

        local f = ngx.fs.open(path, "w")
        f:write("hello")
        f:close()

        f = ngx.fs.open(path, "a")
        local nbytes = f:write(" world")
        ngx.say("append wrote: ", nbytes)
        f:close()

        f = ngx.fs.open(path, "r")
        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- request
GET /t
--- response_body
append wrote: 6
data: [hello world]



=== TEST 11: w mode truncates
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/test.txt"

        local f = ngx.fs.open(path, "w")
        f:write("new")
        f:close()

        f = ngx.fs.open(path, "r")
        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
this is old content that should be truncated
--- request
GET /t
--- response_body
data: [new]



=== TEST 12: r+ mode (read/write without truncation)
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/test.txt"

        local f = ngx.fs.open(path, "r+")

        local nbytes = f:write("HELLO")
        ngx.say("wrote: ", nbytes)

        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
hello world
--- request
GET /t
--- response_body
wrote: 5
data: [HELLO world
]



=== TEST 13: stat - regular file
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local info, err = ngx.fs.stat("$TEST_NGINX_HTML_DIR/test.txt")
        if not info then
            ngx.say("stat failed: ", err)
            return
        end

        ngx.say("is_file: ", info.is_file)
        ngx.say("is_dir: ", info.is_dir)
        ngx.say("is_link: ", info.is_link)
        ngx.say("size: ", info.size)
        ngx.say("has mtime: ", type(info.mtime) == "number")
        ngx.say("has atime: ", type(info.atime) == "number")
        ngx.say("has ctime: ", type(info.ctime) == "number")
        ngx.say("has mode: ", type(info.mode) == "number")
        ngx.say("has ino: ", type(info.ino) == "number")
        ngx.say("has uid: ", type(info.uid) == "number")
        ngx.say("has gid: ", type(info.gid) == "number")
        ngx.say("has nlink: ", type(info.nlink) == "number")
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
is_file: true
is_dir: false
is_link: false
size: 6
has mtime: true
has atime: true
has ctime: true
has mode: true
has ino: true
has uid: true
has gid: true
has nlink: true



=== TEST 14: stat - directory
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local info = ngx.fs.stat("$TEST_NGINX_HTML_DIR")

        ngx.say("is_file: ", info.is_file)
        ngx.say("is_dir: ", info.is_dir)
    }
}
--- request
GET /t
--- response_body
is_file: false
is_dir: true



=== TEST 15: stat - nonexistent path
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local info, err = ngx.fs.stat("$TEST_NGINX_HTML_DIR/no_such_file")
        if not info then
            ngx.say("stat failed: true")
            ngx.say("err type: ", type(err))
            return
        end
    }
}
--- request
GET /t
--- response_body
stat failed: true
err type: string



=== TEST 16: double close
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local ok, err = f:close()
        ngx.say("first close: ", ok)

        ok, err = f:close()
        ngx.say("second close ok: ", ok)
        ngx.say("second close err: ", err)

        ngx.say("tostring: ", tostring(f))
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
first close: true
second close ok: false
second close err: file already closed
tostring: file (closed)



=== TEST 17: open - missing path argument
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local ok, err = pcall(ngx.fs.open)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "expecting") ~= nil or string.find(err, "bad argument") ~= nil)
    }
}
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 18: read - invalid size
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local ok, err = pcall(f.read, f, 0)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "invalid size") ~= nil)
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 19: read - negative offset
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local ok, err = pcall(f.read, f, 10, -1)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "invalid offset") ~= nil)
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 20: write - negative offset
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/out.txt", "w")

        local ok, err = pcall(f.write, f, "data", -1)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "invalid offset") ~= nil)
        f:close()
    }
}
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 21: thread pool not found
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        if not f then
            ngx.say("open failed: true")
            ngx.say("has pool name: ", string.find(err, '"default_lua_io"', 1, true) ~= nil)
            ngx.say("has hint: ", string.find(err, "thread_pool") ~= nil)
            return
        end
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
open failed: true
has pool name: true
has hint: true



=== TEST 22: multiple sequential operations
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/seq.txt"

        local f = ngx.fs.open(path, "w")
        f:write("line1\n")
        f:close()

        f = ngx.fs.open(path, "a")
        f:write("line2\n")
        f:close()

        local info = ngx.fs.stat(path)
        ngx.say("size: ", info.size)

        f = ngx.fs.open(path, "r")
        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- request
GET /t
--- response_body
size: 12
data: [line1
line2
]



=== TEST 23: large file write and read
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/large.txt"
        local chunk = string.rep("A", 1024)
        local total = 1024

        local f = ngx.fs.open(path, "w")
        local written = 0
        for i = 0, total - 1 do
            local nbytes = f:write(chunk, i * 1024)
            written = written + nbytes
        end
        f:close()
        ngx.say("wrote: ", written)

        local info = ngx.fs.stat(path)
        ngx.say("file size: ", info.size)

        f = ngx.fs.open(path, "r")
        local data = f:read(1024 * 1024)
        ngx.say("read back: ", #data)
        ngx.say("match: ", data == string.rep("A", 1024 * 1024))
        f:close()
    }
}
--- request
GET /t
--- response_body
wrote: 1048576
file size: 1048576
read back: 1048576
match: true
--- timeout: 10



=== TEST 24: partial read
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local d1 = f:read(5)
        ngx.say("part1: [", d1, "]")

        local d2 = f:read(5, 5)
        ngx.say("part2: [", d2, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
helloworld
--- request
GET /t
--- response_body
part1: [hello]
part2: [world]



=== TEST 25: in access_by_lua_block
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    access_by_lua_block {
        local info = ngx.fs.stat("$TEST_NGINX_HTML_DIR/test.txt")
        ngx.ctx.file_size = info.size
    }

    content_by_lua_block {
        ngx.say("size: ", ngx.ctx.file_size)
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
size: 6



=== TEST 26: stat size matches written bytes
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/out.txt"
        local content = "exactly 30 bytes of content!!\n"

        local f = ngx.fs.open(path, "w")
        local nbytes = f:write(content)
        f:close()

        local info = ngx.fs.stat(path)
        ngx.say("written: ", nbytes)
        ngx.say("stat size: ", info.size)
        ngx.say("match: ", nbytes == info.size)
    }
}
--- request
GET /t
--- response_body
written: 30
stat size: 30
match: true



=== TEST 27: read - missing size argument
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        local ok, err = pcall(f.read, f)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "bad argument") ~= nil
                             or string.find(err, "number expected") ~= nil)
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 28: write - missing data argument
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/out.txt", "w")
        local ok, err = pcall(f.write, f)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "bad argument") ~= nil
                             or string.find(err, "string expected") ~= nil)
        f:close()
    }
}
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 29: stat - missing path argument
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local ok, err = pcall(ngx.fs.stat)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "bad argument") ~= nil
                             or string.find(err, "expecting") ~= nil)
    }
}
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 30: w+ mode
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "w+")

        f:write("new content")
        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()
    }
}
--- user_files
>>> test.txt
old content that should be gone
--- request
GET /t
--- response_body
data: [new content]



=== TEST 31: open error message includes path
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("/no/such/path/file.txt", "r")
        if not f then
            ngx.say("has path: ", string.find(err, "/no/such/path/file.txt") ~= nil)
            return
        end
    }
}
--- request
GET /t
--- response_body
has path: true



=== TEST 32: stat error message includes path
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local info, err = ngx.fs.stat("/no/such/path/file.txt")
        if not info then
            ngx.say("has path: ", string.find(err, "/no/such/path/file.txt") ~= nil)
            return
        end
    }
}
--- request
GET /t
--- response_body
has path: true



=== TEST 33: concurrent reads from uthreads
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local results = {}

        local function read_file(idx, path)
            local f = ngx.fs.open(path, "r")
            if not f then
                results[idx] = "open failed"
                return
            end

            local data = f:read(4096)
            f:close()
            results[idx] = data
        end

        local t1 = ngx.thread.spawn(read_file, 1, "$TEST_NGINX_HTML_DIR/a.txt")
        local t2 = ngx.thread.spawn(read_file, 2, "$TEST_NGINX_HTML_DIR/b.txt")
        ngx.thread.wait(t1)
        ngx.thread.wait(t2)

        ngx.say("a: [", results[1], "]")
        ngx.say("b: [", results[2], "]")
    }
}
--- user_files
>>> a.txt
content_a
>>> b.txt
content_b
--- request
GET /t
--- response_body
a: [content_a
]
b: [content_b
]



=== TEST 34: all 5 modes work
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/mode_test.txt"

        local modes = {"r", "w", "a", "r+", "w+"}
        for _, m in ipairs(modes) do
            if m == "r" or m == "r+" then
                local wf = ngx.fs.open(path, "w")
                wf:write("test")
                wf:close()
            end

            local f, err = ngx.fs.open(path, m)
            if not f then
                ngx.say("mode ", m, ": FAIL - ", err)
            else
                ngx.say("mode ", m, ": OK")
                f:close()
            end
        end
    }
}
--- request
GET /t
--- response_body
mode r: OK
mode w: OK
mode a: OK
mode r+: OK
mode w+: OK



=== TEST 35: write binary data
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/binary.bin"
        local bin = "\x00\x01\x02\xff\xfe\xfd\x00\x00"

        local f = ngx.fs.open(path, "w")
        local nbytes = f:write(bin)
        f:close()
        ngx.say("wrote: ", nbytes)

        f = ngx.fs.open(path, "r")
        local data = f:read(4096)
        f:close()
        ngx.say("read len: ", #data)
        ngx.say("match: ", data == bin)
    }
}
--- request
GET /t
--- response_body
wrote: 8
read len: 8
match: true



=== TEST 36: in rewrite_by_lua_block
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    rewrite_by_lua_block {
        local info = ngx.fs.stat("$TEST_NGINX_HTML_DIR/test.txt")
        ngx.ctx.is_file = info.is_file
    }

    content_by_lua_block {
        ngx.say("is_file: ", ngx.ctx.is_file)
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
is_file: true



=== TEST 37: GC auto-closes unclosed file, fd is reusable afterward
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        do
            local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
            local data = f:read(4096)
            ngx.say("data: [", data, "]")
        end

        collectgarbage()
        collectgarbage()

        local f2, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        if not f2 then
            ngx.say("reopen failed: ", err)
            return
        end

        local data2 = f2:read(4096)
        ngx.say("reopen data: [", data2, "]")
        f2:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
data: [hello
]
reopen data: [hello
]
--- error_log
auto-closing fd
--- no_error_log
[error]
[alert]



=== TEST 38: custom thread pool
--- main_config
    thread_pool mypool threads=4;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r", "mypool")
        if not f then
            ngx.say("open failed")
            return
        end

        ngx.say("type: ", type(f))
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
type: userdata



=== TEST 39: full cycle with custom pool, pool auto-inherited
--- main_config
    thread_pool fspool threads=8;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/out.txt"

        local f = ngx.fs.open(path, "w+", "fspool")

        local nbytes = f:write("custom pool test")
        ngx.say("wrote: ", nbytes)

        local data = f:read(4096)
        ngx.say("data: [", data, "]")
        f:close()

        local info = ngx.fs.stat(path, "fspool")
        ngx.say("size: ", info.size)
    }
}
--- request
GET /t
--- response_body
wrote: 16
data: [custom pool test]
size: 16



=== TEST 40: custom pool not found
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r", "nopool")
        if not f then
            ngx.say("open failed: true")
            ngx.say("has pool name: ", string.find(err, '"nopool"', 1, true) ~= nil)
            return
        end
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
open failed: true
has pool name: true



=== TEST 41: stat custom pool not found
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local info, err = ngx.fs.stat("$TEST_NGINX_HTML_DIR/test.txt", "badpool")
        if not info then
            ngx.say("stat failed: true")
            ngx.say("has pool name: ", string.find(err, '"badpool"', 1, true) ~= nil)
            return
        end
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
stat failed: true
has pool name: true



=== TEST 42: mix default and custom pools
--- main_config
    thread_pool default_lua_io threads=4;
    thread_pool iopool threads=8;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/test.txt"

        local f1 = ngx.fs.open(path, "r")
        local data1 = f1:read(4096)
        f1:close()

        local f2 = ngx.fs.open(path, "r", "iopool")
        local data2 = f2:read(4096)
        f2:close()

        ngx.say("default: [", data1, "]")
        ngx.say("iopool: [", data2, "]")
        ngx.say("match: ", data1 == data2)
    }
}
--- user_files
>>> test.txt
hello from both pools
--- request
GET /t
--- response_body
default: [hello from both pools
]
iopool: [hello from both pools
]
match: true



=== TEST 43: read on closed file
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        f:close()

        local ok, err = pcall(f.read, f, 4096)
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "closed") ~= nil)
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 44: write on closed file
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/out.txt", "w")
        f:close()

        local ok, err = pcall(f.write, f, "data")
        ngx.say("ok: ", ok)
        ngx.say("err match: ", string.find(err, "closed") ~= nil)
    }
}
--- request
GET /t
--- response_body
ok: false
err match: true



=== TEST 45: write then stat (size consistency loop)
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local path = "$TEST_NGINX_HTML_DIR/sized.txt"

        local sizes = {0, 1, 100, 1024, 4096}
        for _, sz in ipairs(sizes) do
            local f = ngx.fs.open(path, "w")
            f:write(string.rep("x", sz))
            f:close()

            local info = ngx.fs.stat(path)
            ngx.say("wrote ", sz, " -> stat size: ", info.size)
        end
    }
}
--- request
GET /t
--- response_body
wrote 0 -> stat size: 0
wrote 1 -> stat size: 1
wrote 100 -> stat size: 100
wrote 1024 -> stat size: 1024
wrote 4096 -> stat size: 4096



=== TEST 46: stat - is_link with symlink (lstat)
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local ffi = require "ffi"
        ffi.cdef[[int symlink(const char *target, const char *linkpath);
                   int unlink(const char *pathname);]]

        local target = "$TEST_NGINX_HTML_DIR/real.txt"
        local link = "$TEST_NGINX_HTML_DIR/link.txt"

        local f = ngx.fs.open(target, "w")
        f:write("target content")
        f:close()

        ffi.C.unlink(link)
        local rc = ffi.C.symlink(target, link)
        if rc ~= 0 then
            ngx.say("symlink failed")
            return
        end

        local info_link = ngx.fs.stat(link)
        ngx.say("link is_link: ", info_link.is_link)
        ngx.say("link is_file: ", info_link.is_file)

        local info_real = ngx.fs.stat(target)
        ngx.say("real is_link: ", info_real.is_link)
        ngx.say("real is_file: ", info_real.is_file)
    }
}
--- request
GET /t
--- response_body
link is_link: true
link is_file: false
real is_link: false
real is_file: true



=== TEST 47: close refused while read in flight (two uthreads)
--- no_http2
--- quic_max_idle_timeout: 5
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")

        local function reader()
            local data = f:read(4096)
            ngx.say("read: [", data, "]")
        end

        local t1 = ngx.thread.spawn(reader)
        local ok, err = f:close()
        ngx.say("close ok: ", ok)
        ngx.say("close err match: ", string.find(err, "in%-flight") ~= nil)

        ngx.thread.wait(t1)
        ok, err = f:close()
        ngx.say("final close: ", ok)
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
close ok: false
close err match: true
read: [hello
]
final close: true



=== TEST 48: kill uthread during open, aborted fd is closed
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local function do_open()
            local f, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
            if f then
                ngx.say("child opened")
                f:close()
            end
        end

        local t1 = ngx.thread.spawn(do_open)
        ngx.thread.kill(t1)
        ngx.say("killed")

        ngx.sleep(0.5)

        local f2, err = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        if not f2 then
            ngx.say("reopen failed: ", err)
            return
        end

        local data = f2:read(4096)
        ngx.say("reopen ok: ", data ~= nil)
        f2:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
killed
reopen ok: true
--- no_error_log
[error]
[alert]



=== TEST 49: fd not leaked after repeated kill-during-open cycles
--- main_config
    thread_pool default_lua_io threads=32;
--- config
location /t {
    content_by_lua_block {
        local function count_fds()
            local pid = ngx.worker.pid()
            local n = 0
            local p = io.popen("ls /proc/" .. pid .. "/fd 2>/dev/null | wc -l")
            if p then
                n = tonumber(p:read("*a")) or -1
                p:close()
            end
            return n
        end

        local before = count_fds()

        local N = 200
        for i = 1, N do
            local function do_open()
                local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
                if f then
                    local _ = f:read(4096)
                    f:close()
                end
            end

            local t = ngx.thread.spawn(do_open)
            ngx.thread.kill(t)
            t = nil
        end

        collectgarbage()
        collectgarbage()

        ngx.sleep(2)

        collectgarbage()
        collectgarbage()

        local after = count_fds()

        local delta = after - before
        ngx.say("iterations: ", N)
        ngx.say("fd delta acceptable: ", delta < 10)

        local f = ngx.fs.open("$TEST_NGINX_HTML_DIR/test.txt", "r")
        if not f then
            ngx.say("final open failed - fd leak!")
            return
        end

        local data = f:read(4096)
        ngx.say("final read ok: ", data ~= nil)
        f:close()
    }
}
--- user_files
>>> test.txt
hello
--- request
GET /t
--- response_body
iterations: 200
fd delta acceptable: true
final read ok: true
--- no_error_log
[error]
[alert]
--- timeout: 15
