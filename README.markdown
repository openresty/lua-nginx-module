Name
====

lua-nginx-module - Embed the power of Lua into nginx

Status
======

This module is at its early phase of development but is already production
ready :)

Commit bit can be freely delivered at your request ;)

Synopsis
========

    # set search paths for pure Lua external libraries (';;' is the default path):
    lua_package_path '/foo/bar/?.lua;/blah/?.lua;;';
    
    # set search paths for Lua external libraries written in C (can also use ';;'):
    lua_package_cpath '/bar/baz/?.so;/blah/blah/?.so;;';
    
    server {
        location /inline_concat {
            # MIME type determined by default_type:
            default_type 'text/plain';

            set $a "hello";
            set $b "world";
            # inline lua script
            set_by_lua $res "return ngx.arg[1]..ngx.arg[2]" $a $b;
            echo $res;
        }

        location /rel_file_concat {
            set $a "foo";
            set $b "bar";
            # script path relative to nginx prefix
            # $ngx_prefix/conf/concat.lua contents:
            #
            #    return ngx.arg[1]..ngx.arg[2]
            #
            set_by_lua_file $res conf/concat.lua $a $b;
            echo $res;
        }

        location /abs_file_concat {
            set $a "fee";
            set $b "baz";
            # absolute script path not modified
            set_by_lua_file $res /usr/nginx/conf/concat.lua $a $b;
            echo $res;
        }

        location /lua_content {
            # MIME type determined by default_type:
            default_type 'text/plain';

            content_by_lua "ngx.say('Hello,world!')"
        }

        location /nginx_var {
            # MIME type determined by default_type:
            default_type 'text/plain';

            # try access /nginx_var?a=hello,world
            content_by_lua "ngx.print(ngx.var['arg_a'], '\\n')";
        }

        # transparent non-blocking I/O in Lua via subrequests
        location /lua {
            # MIME type determined by default_type:
            default_type 'text/plain';

            content_by_lua '
                local res = ngx.location.capture("/some_other_location")
                if res.status == 200 then
                    ngx.print(res.body)
                end';
        }

        # GET /recur?num=5
        location /recur {
            # MIME type determined by default_type:
            default_type 'text/plain';

           content_by_lua '
               local num = tonumber(ngx.var.arg_num) or 0
               ngx.say("num is: ", num)

               if num > 0 then
                   res = ngx.location.capture("/recur?num=" .. tostring(num - 1))
                   ngx.print("status=", res.status, " ")
                   ngx.print("body=", res.body)
               else
                   ngx.say("end")
               end
               ';
        }
    }

Nginx APIs for set_by_lua*
==========================

Read and write arbitrary nginx variables by name:

    value = ngx.var.some_nginx_variable_name
    ngx.var.some_nginx_variable_name = value

Index the input arguments to the directive:

    value = ngx.arg[n]

Nginx APIs for content_by_lua*
==============================

Read and write NginX variables
------------------------------

    value = ngx.var.some_nginx_variable_name
    ngx.var.some_nginx_variable_name = value

HTTP status constants
---------------------

    value = ngx.HTTP_OK
    value = ngx.HTTP_CREATED
    value = ngx.HTTP_MOVED_PERMANENTLY
    value = ngx.HTTP_MOVED_TEMPORARILY
    value = ngx.HTTP_NOT_MODIFIED
    value = ngx.HTTP_BAD_REQUEST
    value = ngx.HTTP_GONE
    value = ngx.HTTP_NOT_FOUND
    value = ngx.HTTP_NOT_ALLOWED
    value = ngx.HTTP_FORBIDDEN
    value = ngx.HTTP_INTERNAL_SERVER_ERROR
    value = ngx.HTTP_SERVICE_UNAVAILABLE

NginX log level constants
-------------------------

    log_level = ngx.STDERR
    log_level = ngx.EMERG
    log_level = ngx.ALERT
    log_level = ngx.CRIT
    log_level = ngx.ERR
    log_level = ngx.WARN
    log_level = ngx.NOTICE
    log_level = ngx.INFO
    log_level = ngx.DEBUG

print(a, b, ...)
----------------

Emit args concatenated to `error.log`.

ngx.send_headers()
------------------

Explicitly send headers.

ngx.print(a, b, ...)
--------------------

Emit args concatenated to the HTTP client (as response body).

ngx.log(log_level, ...)
-----------------------

Log args concatenated to error.log with the given logging level.

ngx.say(a, b, ...)
------------------

Just as `ngx.print` but also emit a trailing newline.

ngx.flush()
-----------

Force flushing the response outputs.

ngx.throw_error(status)
-----------------------

Throw out an error page and interrupts the execution of the current Lua thread,
status can be `ngx.HTTP_NOT_FOUND` or other HTTP status numbers.

ngx.eof()
---------

Explicitly specify the end of the response output stream.

ngx.escape_uri(str)
-------------------

Escape `str` as a URI component.

    newstr = ngx.escape_uri(str)

ngx.unescape_uri(str)
---------------------

Unescape `str` as a escaped URI component.

    newstr = ngx.unescape_uri(str)

ngx.location.capture(uri)
-------------------------

Issue a synchronous but still non-blocking subrequest using `uri` (e.g. /foo/bar).

    res = ngx.location.capture(uri)

Returns a Lua table with two slots (`res.status` and `res.body`).

Performance
===========

The Lua state (aka the Lua vm instance) is shared across all the requests
handled by a single nginx worker process to miminize memory use.

On a ThinkPad T400 2.96 GHz laptop, it's easy to achieve 25k req/sec using ab
w/o keepalive and 37k+ req/sec with keepalive.

You can get better performance when building this module
with LuaJIT 2.0.

Installation
============

1. Install lua into your system. At least Lua 5.1 is required.
Lua can be obtained freely from its project [homepage](http://www.lua.org/).

1. Download the latest version of the release tarball of this module from
lua-nginx-module [file list](http://github.com/chaoslawful/lua-nginx-module/downloads).

1. Grab the nginx source code from [nginx.net](http://nginx.net/), for example,
the version 0.8.41 (see nginx compatibility), and then build the source with
this module:

        $ wget 'http://sysoev.ru/nginx/nginx-0.8.41.tar.gz'
        $ tar -xzvf nginx-0.8.41.tar.gz
        $ cd nginx-0.8.41/
        
        # tell nginx's build system where to find lua:
        export LUA_LIB=/path/to/lua/lib
        export LUA_INC=/path/to/lua/include
        
        # or tell where to find LuaJIT when you want to use JIT instead
        # export LUAJIT_LIB=/path/to/luajit/lib
        # export LUAJIT_INC=/path/to/luajit/include/luajit-2.0
        
        # Here we assume you would install you nginx under /opt/nginx/.
        $ ./configure --prefix=/opt/nginx \
            --add-module=/path/to/ndk_devel_kit \
            --add-module=/path/to/echo-nginx-module \
            --add-module=/path/to/lua-nginx-module
        
        $ make -j2
        $ make install

Compatibility
=============

The following versions of Nginx should work with this module:

*   0.8.x (last tested version is 0.8.47)
*   0.7.x >= 0.7.46 (last tested version is 0.7.67)

Earlier versions of Nginx like 0.6.x and 0.5.x will **not** work.

If you find that any particular version of Nginx above 0.7.44 does not
work with this module, please consider reporting a bug.

Test Suite
==========

To run the test suite, you need the following nginx modules:

* test-nginx: <http://github.com/agentzh/test-nginx>
* echo-nginx-module: <http://github.com/agentzh/echo-nginx-module>
* drizzle-nginx-module: <http://github.com/chaoslawful/drizzle-nginx-module>
* rds-json-nginx-module: <http://github.com/agentzh/rds-json-nginx-module>
* set-misc-nginx-module: <http://github.com/agentzh/set-misc-nginx-module>
* memc-nginx-module: <http://github.com/agentzh/memc-nginx-module>
* srcache-nginx-module: <http://github.com/agentzh/srcache-nginx-module>
* ngx_auth_request: <http://mdounin.ru/hg/ngx_http_auth_request_module/>

These module's adding order is IMPORTANT! For filter modules's position in
filtering chain affects a lot. The correct configure adding order is:

1. ngx_devel_kit
2. set-misc-nginx-module
3. ngx_http_auth_request_module
4. echo-nginx-module
5. memc-nginx-module
6. lua-nginx-module (i.e. this module)
7. srcache-nginx-module
8. drizzle-nginx-module
9. rds-json-nginx-module

Todo
====

* Add directives to run lua codes when nginx stops/reloads
* Implement ngx.exec() functionality
* Deal with TCP 3-second delay problem under great connection harness

Future Plan
===========

* Add 'lua_require' directive to load module into main thread's globals
* Add Lua VM passive yield and resume (using debug hook)
* Make set_by_lua using the same mechanism as content_by_lua
* Integrate $request_body reading functionality

Known Issues
============

* Globals won't persist between requests, due to the one-coroutine-per-request
designing. Especially watch yourself when using `require()` to import modules,
use this form:

        local xxx = require('xxx')

instead of the old deprecated form:

        require('xxx')

The old form will cause module unusable in requests for the reason told
previously. If you have to stick with the old form, you can always force
loading module for every request by clean `package.loaded.<module>`, like this:

        package.loaded.xxx = nil
        require('xxx')

See Also
========

* ngx_devel_kit ( <http://github.com/simpl-it/ngx_devel_kit> )
* echo-nginx-module ( <http://github.com/agentzh/echo-nginx-module> )

Authors
=======

* chaoslawful (王晓哲) <chaoslawful at gmail dot com>
* agentzh (章亦春) <agentzh at gmail dot com>

Copyright & License
===================

    This module is licenced under the BSD license.

    Copyright (c) 2009, Taobao Inc., Alibaba Group ( http://www.taobao.com ).

    Copyright (C) 2009 by Xiaozhe Wang (chaoslawful) <chaoslawful@gmail.com>.

    Copyright (C) 2009 by Yichun Zhang (agentzh) <agentzh@gmail.com>.

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

        * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

        * Neither the name of the Taobao Inc. nor the names of its
        contributors may be used to endorse or promote products derived from
        this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
    TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

