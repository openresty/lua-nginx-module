Name
====

ngx_lua - Embed the Power of Lua into Nginx

Status
======

This module is still under active development but is already production
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

        location /request_body {
                # force reading request body (default off)
                lua_need_request_body on;

                content_by_lua 'ngx.print(ngx.var.request_body)';
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

        location /foo {
            rewrite_by_lua '
                res = ngx.location.capture("/memc",
                    { args = { cmd = 'incr', key = ngx.var.uri } }
                )
            ';

            proxy_pass http://blah.blah.com;
        }

        location /blah {
            access_by_lua '
                local res = ngx.location.capture("/auth")

                if res.status == ngx.HTTP_OK then
                    return
                end

                if res.status == ngx.HTTP_FORBIDDEN then
                    ngx.exit(res.status)
                end

                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            ';

            # proxy_pass/fastcgi_pass/postgres_pass/...
        }

        location /mixed {
            rewrite_by_lua_file /path/to/rewrite.lua;
            access_by_lua_file /path/to/access.lua;
            content_by_lua_file /path/to/content.lua;
        }

        # use nginx var in code path
        # WARN: contents in nginx var must be carefully filtered,
        # otherwise there'll be great security risk!
        location ~ ^/app/(.+) {
                content_by_lua_file /path/to/lua/app/root/$1.lua;
        }

        location / {
           lua_need_request_body on;

           client_max_body_size 100k;
           client_body_buffer_size 100k;

           access_by_lua '
               -- check the client IP addr is in our black list
               if ngx.var.remote_addr == "132.5.72.3" then
                   ngx.exit(ngx.HTTP_FORBIDDEN)
               end

               -- check if the request body contains bad words
               if ngx.var.request_body and
                        string.match(ngx.var.request_body, "fsck")
               then
                   return ngx.redirect("/terms_of_use.html")
               end

               -- tests passed
           ';

           # proxy_pass/fastcgi_pass/etc settings
        }
    }

Description
===========

This module embeds the Lua interpreter into the nginx core and integrates the powerful Lua threads (aka Lua coroutines) into the nginx event model
by means of nginx subrequests.

Unlike Apache's mod_lua and Lighttpd's mod_magnet, Lua code written atop this module can be 100% non-blocking on network traffic
as long as you use the `ngx.location.capture()` or
`ngx.location.capture_multi()` interfaces
to let the nginx core do all your
requests to mysql, postgresql, memcached,
upstream http web services, and etc etc etc (see
ngx_drizzle, ngx_postgres, ngx_memc, and ngx_proxy modules for details).

The Lua interpreter instance is shared across all
the requests in a single nginx worker process.

Request contexts are isolated from each other
by means of Lua (lightweight) threads (aka Lua coroutines).
And Lua modules loaded are persistent on
the nginx worker process level. So the memory
footprint is quite small even when your
nginx worker process is handling 10K requests at the same time.

We're already using this module very heavily
in our production web applications here in
Taobao.com, Alibaba Group.

Directives
==========

lua_code_cache
--------------
* **Syntax:** `lua_code_cache on | off`
* **Default:** `lua_code_cache on`
* **Context:** `main, server, location, location if`

Enable or disable the Lua code cache for `set_by_lua_file`,
`content_by_lua_file`, `rewrite_by_lua_file`, and
`access_by_lua_file`, and also force Lua module reloading on a per-request basis.

The Lua files referenced in `set_by_lua_file`,
`content_by_lua_file`, `access_by_lua_file`,
and `rewrite_by_lua_file` won't be cached at all,
and Lua's `package.loaded` table will be cleared
at every request's entry point (such that Lua modules
won't be cached either). So developers and enjoy
the PHP-way, i.e., edit-and-refresh.

But please note that Lua code inlined into nginx.conf
like those specified by `set_by_lua`, `content_by_lua`,
`access_by_lua`, and `rewrite_by_lua` will *always* be
cached because only nginx knows how to parse `nginx.conf`
and the only way to tell it to re-load the config file
is to send a `HUP` signal to it or just to restart it from scratch.

For now, ngx_lua does not support the "stat" mode like
Apache's `mod_lua`, but we will work on it in the future.

Disabling the Lua code cache is mainly used for Lua
development only because it has great
impact on the over-all performance and is strongly
discouraged for production uses. Also, race conditions
when reloading Lua modules are common for concurrent requests
when the code cache is off.

lua_package_path
----------------

* **Syntax:** `lua_package_path <lua-style-path-str>`
* **Default:** The content of LUA_PATH environ variable or Lua's compiled-in
defaults.
* **Context:** `main`

Set the Lua module searching path used by scripts specified by `set_by_lua*`,
`content_by_lua*` and others. The path string is in standard Lua path form, and `;;`
can be used to stand for the original path.

lua_package_cpath
-----------------

* **Syntax:** `lua_package_cpath <lua-style-cpath-str>`
* **Default:** The content of LUA_CPATH environ variable or Lua's compiled-in
defaults.
* **Context:** `main`

Set the Lua C-module searching path used by scripts specified by `set_by_lua*`,
`content_by_lua*` and others. The cpath string is in standard Lua cpath form, and `;;`
can be used to stand for the original cpath.

set_by_lua
----------

* **Syntax:** `set_by_lua $res <lua-script-str> [$arg1 $arg2 ...]`
* **Context:** `main | server | location | sif | lif`

Execute user code specified by `<lua-script-str>` with input arguments `$arg1
$arg2 ...`, and set the script's return value to `$res` in string form. In
`<lua-script-str>` code the input arguments can be retrieved from `ngx.arg`
table (index starts from `1` and increased sequentially).

`set_by_lua*` directives are designed to execute small and quick codes. Nginx
event loop is blocked during the code execution, so you'd better **NOT** call
anything that may be blocked or time-costy.

Note that `set_by_lua` can only output a value to a single nginx variable at
a time. But a work-around is also available by means of the ngx.var.xxx interface,
for example,

    location /foo {
        set $diff ''; # we have to predefine the $diff variable here

        set_by_lua $sum '
            local a = 32
            local b = 56

            ngx.var.diff = a - b;  -- write to $diff directly
            return a + b;          -- return the $sum value normally
        ';

        echo "sum = $sum, diff = $diff";
    }

set_by_lua_file
---------------

* **Syntax:** `set_by_lua_file $res <path-to-lua-script> [$arg1 $arg2 ...]`
* **Context:** `main | server | location | sif | lif`

Basically the same as `set_by_lua`, except the code to be executed is in the
file specified by `<path-lua-script>`.

When the Lua code cache is on (this is the default), the user code is loaded
once at the first request and cached. Nginx config must be reloaded if you
modified the file and expected to see updated behavior. You can disable the
Lua code cache by setting `lua_code_cache off;` in your nginx.conf.

content_by_lua
--------------

* **Syntax:** `content_by_lua <lua-script-str>`
* **Context:** `location | lif`
* **Phase:** `content`

Act as a content handler and execute user code specified by `<lua-script-str>`
for every request. The user code may call predefined APIs to generate response
content.

The use code is executed in a new spawned coroutine with independent globals
environment (i.e. a sandbox). I/O operations in user code should only be done
through predefined Nginx APIs, otherwise Nginx event loop may be blocked and
performance may drop off dramatically.

As predefined Nginx I/O APIs used coroutine yielding/resuming mechanism, the
user code should not call any modules that used coroutine API to prevent
obfuscating the predefined Nginx APIs (actually coroutine module is masked off
in `content_by_lua*` directives). This limitation is a little crucial, but
don't worry! We're working on a alternative coroutine implementation that can
be fit in the Nginx event framework. When it is done, the user code will be
able to use coroutine mechanism freely as in standard Lua again!

rewrite_by_lua
--------------

* **Syntax:** `rewrite_by_lua <lua-script-str>`
* **Context:** `location | lif`
* **Phase:** `rewrite tail`

Act as a rewrite phase handler and execute user code specified by `<lua-script-str>`
for every request. The user code may call predefined APIs to generate response
content.

This hook uses exactly the same mechamism as `content_by_lua` so all the nginx APIs defined there
are also available here.

Note that this handler always runs *after* the standard nginx rewrite module ( http://wiki.nginx.org/NginxHttpRewriteModule ). So the following will work as expected:

   location /foo {
       set $a 12; # create and initialize $a
       set $b ''; # create and initialize $b
       rewrite_by_lua 'ngx.var.b = tonumber(ngx.var.a) + 1';
       echo "res = $b";
   }

because `set $a 12` and `set $b ''` run before `rewrite_by_lua`.

On the other hand, the following will not work as expected:

    ?  location /foo {
    ?      set $a 12; # create and initialize $a
    ?      set $b ''; # create and initialize $b
    ?      rewrite_by_lua 'ngx.var.b = tonumber(ngx.var.a) + 1';
    ?      if ($b = '13') {
    ?         rewrite ^ /bar redirect;
    ?         break;
    ?      }
    ?
    ?      echo "res = $b";
    ?  }

because `if` runs *before* `rewrite_by_lua` even if it's put after `rewrite_by_lua` in the config.

The right way of doing this is as follows:

    location /foo {
        set $a 12; # create and initialize $a
        set $b ''; # create and initialize $b
        rewrite_by_lua '
            ngx.var.b = tonumber(ngx.var.a) + 1
            if ngx.var.b == 13 then
                return ngx.redirect("/bar");
            end
        ';

        echo "res = $b";
    }

It's worth mentioning that, the `ngx_eval` module can be
approximately implemented by `rewrite_by_lua`. For example,

    location / {
        eval $res {
            proxy_pass http://foo.com/check-spam;
        }
        if ($res = 'spam') {
            rewrite ^ /terms-of-use.html redirect;
        }

        fastcgi_pass ...;
    }

can be implemented in terms of `ngx_lua` like this

    location = /check-spam {
        internal;
        proxy_pass http://foo.com/check-spam;
    }

    location / {
        rewrite_by_lua '
            local res = ngx.location.capture("/check-spam")
            if res.body == "spam" then
                ngx.redirect("/terms-of-use.html")
            end
        ';

        fastcgi_pass ...;
    }

Just as any other rewrite-phase handlers, `rewrite_by_lua` also runs in subrequests.

Note that calling `ngx.exit(ngx.OK)` just returning from the current `rewrite_by_lua` handler, and the nginx request processing
control flow will still continue to the content handler. To terminate the current request from within the current `rewrite_by_lua` handler,
calling `ngx.exit(ngx.HTTP_OK)` for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` or its friends for failures.

access_by_lua
--------------

* **Syntax:** `access_by_lua <lua-script-str>`
* **Context:** `location | lif`
* **Phase:** `access tail`

Act as an access phase handler and execute user code specified by `<lua-script-str>`
for every request. The user code may call predefined APIs to generate response
content.

This hook uses exactly the same mechamism as `content_by_lua`
so all the nginx APIs defined there
are also available here.

Note that this handler always runs *after* the standard nginx
access module ( http://wiki.nginx.org/NginxHttpAccessModule ).
So the following will work as expected:

    location / {
        deny    192.168.1.1;
        allow   192.168.1.0/24;
        allow   10.1.1.0/16;
        deny    all;

        access_by_lua '
            local res = ngx.location.capture("/mysql", { ... })
            ...
        ';

        # proxy_pass/fastcgi_pass/...
    }

That is, if a client address appears in the blacklist, then
we don't have to bother sending a mysql query to do more
advanced authentication in `access_by_lua`.

It's worth mentioning that, the `ngx_auth_request` module can be
approximately implemented by `access_by_lua`. For example,

    location / {
        auth_request /auth;

        # proxy_pass/fastcgi_pass/postgres_pass/...
    }

can be implemented in terms of `ngx_lua` like this

    location / {
        access_by_lua '
            local res = ngx.location.capture("/auth")

            if res.status == ngx.HTTP_OK then
                return
            end

            if res.status == ngx.HTTP_FORBIDDEN then
                ngx.exit(res.status)
            end

            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        ';

        # proxy_pass/fastcgi_pass/postgres_pass/...
    }

Just as any other access-phase handlers, `access_by_lua` will NOT run in subrequests.

Note that calling `ngx.exit(ngx.OK)` just returning from the current `access_by_lua` handler, and the nginx request processing
control flow will still continue to the content handler. To terminate the current request from within the current `access_by_lua` handler,
calling `ngx.exit(ngx.HTTP_OK)` for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` or its friends for failures.

content_by_lua_file
-------------------

* **Syntax:** `content_by_lua_file <path-to-lua-script>`
* **Context:** `location | lif`
* **Phase:** `content`

Basically the same as `content_by_lua`, except the code to be executed is in
the file specified by `<path-lua-script>`.

Nginx variables can be used in <path-to-lua-script> string, in order to provide
greater flexibility in practice. But this feature must be used carefully, so is
not recommend for beginners.

When the Lua code cache is on (this is the default), the user code is loaded
once at the first request and cached. Nginx config must be reloaded if you
modified the file and expected to see updated behavior. You can disable the
Lua code cache by setting `lua_code_cache off;` in your nginx.conf.

rewrite_by_lua_file
-------------------

* **Syntax:** `rewrite_by_lua_file <path-to-lua-script>`
* **Context:** `location | lif`
* **Phase:** `rewrite tail`

Same as `rewrite_by_lua`, except the code to be executed is in
the file specified by `<path-lua-script>`.

Nginx variables can be used in <path-to-lua-script> string, in order to provide
greater flexibility in practice. But this feature must be used carefully, so is
not recommend for beginners.

When the Lua code cache is on (this is the default), the user code is loaded
once at the first request and cached. Nginx config must be reloaded if you
modified the file and expected to see updated behavior. You can disable the
Lua code cache by setting `lua_code_cache off;` in your nginx.conf.

access_by_lua_file
-------------------

* **Syntax:** `access_by_lua_file <path-to-lua-script>`
* **Context:** `location | lif`
* **Phase:** `access tail`

Same as `access_by_lua`, except the code to be executed is in the file
specified by `<path-lua-script>`.

Nginx variables can be used in <path-to-lua-script> string, in order to provide
greater flexibility in practice. But this feature must be used carefully, so is
not recommend for beginners.

When the Lua code cache is on (this is the default), the user code is loaded
once at the first request and cached. Nginx config must be reloaded if you
modified the file and expected to see updated behavior. You can disable the
Lua code cache by setting `lua_code_cache off;` in your nginx.conf.

lua_need_request_body
---------------------

* **Syntax:** `lua_need_request_body <on | off>`
* **Default:** `off`
* **Context:** `main | server | location`
* **Phase:** `depends on usage`

Force reading request body data or not. The client request body won't be read,
so you have to explicitly force reading the body if you need its content.

If you want to read the request body data from the `$request_body` variable, make sure that
your `client_max_body_size` setting is equal to
your `client_body_buffer_size` setting and
the capacity specified should hold the biggest
request body that your app allow.

If the current location defines `rewrite_by_lua` or `rewrite_by_lua_file`,
then the request body will be read just before the `rewrite_by_lua` or `rewrite_by_lua_file` code is run (and also at the
`rewrite` phase). Similarly, if only `content_by_lua` is specified,
the request body won't be read until the content handler's Lua code is
about to run (i.e., the request body will be read at the
content phase).

The same applies to `access_by_lua` and `access_by_lua_file`.

Nginx API for Lua
=================

Input arguments
---------------
* **Context:** `set_by_lua*`

Index the input arguments to the set_by_lua* directives:

    value = ngx.arg[n]

Here's an example

    location /foo {
        set $a 32;
        set $b 56;

        set_by_lua $res
            'return tonumber(ngx.arg[1]) + tonumber(ngx.arg[2])'
            $a $b;

        echo $sum;
    }

that outputs 88, the sum of 32 and 56.

Read and write Nginx variables
------------------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

    value = ngx.var.some_nginx_variable_name
    ngx.var.some_nginx_variable_name = value

Note that you can only write to nginx variables that are already defined.
For example:

    location /foo {
        set $my_var ''; # this line is required to create $my_var at config time
        content_by_lua '
            ngx.var.my_var = 123;
            ...
        ';
    }

That is, nginx variables cannot be created on-the-fly.

Core constants
---------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

    ngx.OK
    ngx.DONE
    ngx.AGAIN
    ngx.ERROR

HTTP method constants
---------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

    value = ngx.HTTP_GET
    value = ngx.HTTP_HEAD
    value = ngx.HTTP_PUT
    value = ngx.HTTP_POST
    value = ngx.HTTP_DELETE

HTTP status constants
---------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

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

Nginx log level constants
-------------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

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
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Emit args concatenated to `error.log`, with log level `ngx.NOTICE` and prefix `lua print: `.

It's equivalent to

    ngx.log(ngx.NOTICE, 'lua print: ', a, b, ...)

Nil arguments are accepted and result in literal "nil".

ngx.location.capture(uri, options?)
-----------------------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Issue a synchronous but still non-blocking "nginx subrequest" using `uri`.

Nginx subrequests provide a powerful way to make
non-blocking internal requests to other locations
configured with disk file directory or *any*
other nginx C modules like
`ngx_proxy`, `ngx_fastcgi`, `ngx_memc`,
`ngx_postgres`,
`ngx_drizzle`, and even `ngx_lua` itself and etc etc etc.

Also note that subrequests just mimic the HTTP
interface but there's *no*
extra HTTP/TCP traffic *nor* IPC involved. Everything
works internally, efficiently, on the C level.

Subrequests are completely different from HTTP 301/302 redirection (via `ngx.redirect()`) and internal redirection (via `ngx.exec()`).

Here's a basic example:

    res = ngx.location.capture(uri)

Returns a Lua table with three slots (`res.status`, `res.header`, and `res.body`).

`res.header` holds all the response headers of the
subrequest and it is a normal Lua table. For multi-value response headers,
the value is a Lua (array) table that holds all the values in the order that
they appear. For instance, if the subrequest response headers contains the following
lines:

    Set-Cookie: a=3
    Set-Cookie: foo=bar
    Set-Cookie: baz=blah

Then `res.header["Set-Cookie"]` will be evaluted to the table value
`{"a=3", "foo=bar", "baz=blah"}`.

URI query strings can be concatenated to URI itself, for instance,

    res = ngx.location.capture('/foo/bar?a=3&b=4')

Named locations like `@foo` are not allowed due to a limitation in
the nginx core. Use normal locations combined with the `internal` directive to
prepare internal-only locations.

An optional option table can be fed as the second
argument, which support various options like
`method`, `body`, `args`, and `share_all_vars`.
Issuing a POST subrequest, for example,
can be done as follows

    res = ngx.location.capture(
        '/foo/bar',
        { method = ngx.HTTP_POST, body = 'hello, world' }
    )

See HTTP method constants methods other than POST.
The `method` option is `ngx.HTTP_GET` by default.

The `share_all_vars` option can control whether to share nginx variables
among the current request and the new subrequest. If this option is set to `true`, then
the subrequest can see all the variable values of the current request while the current
requeset can also see any variable value changes made by the subrequest.
Note that variable sharing can have unexpected side-effects
and lead to confusing issues, use it with special
care. So, by default, the option is set to `false`.

The `args` option can specify extra url arguments, for instance,

    ngx.location.capture('/foo?a=1',
        { args = { b = 3, c = ':' } }
    )

is equivalent to

    ngx.location.capture('/foo?a=1&b=3&c=%3a')

that is, this method will autmotically escape argument keys and values according to URI rules and
concatenating them together into a complete query string. Because it's all done in hand-written C,
it should be faster than your own Lua code.

The `args` option can also take plain query string:

    ngx.location.capture('/foo?a=1',
        { args = 'b=3&c=%3a' } }
    )

This is functionally identical to the previous examples.

Note that, by default, subrequests issued by `ngx.location.capture` inherit all the
request headers of the current request. This may have unexpected side-effects on the
subrequest responses. For example, when you're using the standard `ngx_proxy` module to serve
your subrequests, then an "Accept-Encoding: gzip" header in your main request may result
in gzip'd responses that your Lua code is not able to handle properly. So always set
`proxy_pass_request_headers off` in your subrequest location to ignore the original request headers.
See <http://wiki.nginx.org/NginxHttpProxyModule#proxy_pass_request_headers> for more
details.

ngx.location.capture_multi({ {uri, options?}, {uri, options?}, ... })
---------------------------------------------------------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Just like `ngx.location.capture`, but supports multiple subrequests running in parallel.

This function issue several parallel subrequests specified by the input table, and returns their results in the same order. For example,

    res1, res2, res3 = ngx.location.capture_multi{
        { "/foo", { args = "a=3&b=4" } },
        { "/bar" },
        { "/baz", { method = ngx.HTTP_POST, body = "hello" } },
    }

    if res1.status == ngx.HTTP_OK then
        ...
    end

    if res2.body == "BLAH" then
        ...
    end

This function will not return until all the subrequests terminate. The total latency is the longest latency of the subrequests, instead of their sum.

The `ngx.location.capture` function is just a special form
of this function. Logically speaking, the `ngx.location.capture` can be implemented like this

    ngx.location.capture =
        function (uri, args)
            return ngx.location.capture_multi({ {uri, args} })
        end

ngx.status
----------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Read and write the response status. This should be called
before sending out the response headers.

    ngx.status = ngx.HTTP_CREATED
    status = ngx.status

ngx.header.HEADER
-----------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Set/add/clear response headers. Underscores (_) in the header names will be replaced by dashes (-) and the header names will be matched case-insentively.

    -- equivalent to ngx.header["Content-Type"] = 'text/plain'
    ngx.header.content_type = 'text/plain';

    ngx.header["X-My-Header"] = 'blah blah';

Multi-value headers can be set this way:

    ngx.header['Set-Cookie'] = {'a=32; path=/', 'b=4; path=/'}

will yield

    Set-Cookie: a=32; path=/
    Set-Cookie: b=4; path=/

in the response headers. Only array-like tables are accepted.

Note that, for those standard headers that only accepts a single value, like Content-Type, only the last element
in the (array) table will take effect. So

    ngx.header.content_type = {'a', 'b'}

is equivalent to

    ngx.header.content_type = 'b'

Setting a slot to nil effectively removes it from the response headers:

    ngx.header["X-My-Header"] = nil;

same does assigning an empty table:

    ngx.header["X-My-Header"] = {};

`ngx.header` is not a normal Lua table so you cannot
iterate through it.

For reading request headers, use `ngx.var.http_HEADER`, that is, nginx's standard $http_HEADER variables:

    http://wiki.nginx.org/NginxHttpCoreModule#.24http_HEADER

Reading values from ngx.header.HEADER is not implemented yet, and usually you
shouldn't need it.

ngx.exec(uri, args)
-------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Does an internal redirect to uri with args.

    ngx.exec('/some-location');
    ngx.exec('/some-location', 'a=3&b=5&c=6');
    ngx.exec('/some-location?a=3&b=5', 'c=6');

Named locations are also supported, but query strings are ignored. For example

    location /foo {
        content_by_lua '
            ngx.exec("@bar");
        ';
    }

    location @bar {
        ...
    }

Note that this is very different from ngx.redirect() in that
it's just an internal redirect and no new HTTP traffic is involved.

This method never returns.

This method MUST be called before `ngx.send_headers()` or explicit response body
outputs by either `ngx.print` or `ngx.say`.

This method is very much like the `echo_exec`
directive in the ngx_echo module.

ngx.redirect(uri, status?)
--------------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Issue an HTTP 301 or 302 redirection to `uri`.

The optional `status` parameter specifies whether
301 or 302 to be used. It's 302 (ngx.HTTP_MOVED_TEMPORARILY) by default.

Here's a small example:

    return ngx.redirect("/foo")

which is equivalent to

    return ngx.redirect("http://localhost:1984/foo", ngx.HTTP_MOVED_TEMPORARILY)

assuming the current server name is `localhost` and it's listening on the `1984` port.

This method MUST be called before `ngx.send_headers()` or explicit response body
outputs by either `ngx.print` or `ngx.say`.

This method never returns.

This method is very much like the `rewrite` directive with the `redirect` modifier in the standard
`ngx_rewrite` module, for example, this nginx.conf snippet

    rewrite ^ /foo redirect;  # nginx config

is equivalent to the following Lua code

    return ngx.redirect('/foo');  -- lua code

while

    rewrite ^ /foo permanent;  # nginx config

is equivalent to

    return ngx.redirect('/foo', ngx.HTTP_MOVED_PERMANENTLY)  -- Lua code

ngx.send_headers()
------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Explicitly send out the response headers.

Usually you don't have to send headers yourself. ngx_lua
will automatically send out headers right before you
output contents via `ngx.say` or `ngx.print`.

Headers will also be sent automatically when `content_by_lua` exits normally.

ngx.print(a, b, ...)
--------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Emit args concatenated to the HTTP client (as response body).

Nil arguments are not allowed.

ngx.say(a, b, ...)
------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Just as `ngx.print` but also emit a trailing newline.

Nil arguments are not allowed.

ngx.log(log_level, ...)
-----------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Log args concatenated to error.log with the given logging level.

Nil arguments are accepted and result in literal "nil".

ngx.flush()
-----------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Force flushing the response outputs.

ngx.exit(status)
----------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Interrupts the execution of the current Lua thread and returns
status code to nginx.

The `status` argument can be `ngx.OK`, `ngx.ERROR`, `ngx.HTTP_NOT_FOUND`,
`ngx.HTTP_MOVED_TEMPORARILY`,
or other HTTP status numbers.

ngx.eof()
---------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Explicitly specify the end of the response output stream.

ngx.escape_uri(str)
-------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Escape `str` as a URI component.

    newstr = ngx.escape_uri(str)

ngx.unescape_uri(str)
---------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Unescape `str` as a escaped URI component.

    newstr = ngx.unescape_uri(str)

ngx.encode_base64(str)
----------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Encode `str` to a base64 digest

    newstr = ngx.encode_base64(str)

ngx.decode_base64(str)
----------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Decode `str` as a base64 digest to the raw form

    newstr = ngx.decode_base64(str)

ngx.today()
---------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Returns today's date (in the format `yyyy-mm-dd`) from nginx cached time (no syscall involved unlike Lua's date library).
.

This is the local time.

ngx.time()
-------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Returns the elapsed seconds from the epoch for the current timestamp from the nginx cached time (no syscall involved unlike Lua's date library).

ngx.localtime()
---------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Returns the current timestamp (in the format `yyyy-mm-dd hh:mm:ss`) of the nginx cached time (no syscall involved unlike Lua's date library).

This is the local time.

ngx.utctime()
-------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Returns the current timestamp (in the format `yyyy-mm-dd hh:mm:ss`) of the nginx cached time (no syscall involved unlike Lua's date library).

This is the UTC time.

ngx.cookie_time(sec)
--------------------
* **Context:** `set_by_lua*`, `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

Returns a formated string can be used as the cookie expiration time. The parameter `sec` is the timestamp in seconds (like those returned from `ngx.time`).

    ngx.say(ngx.cookie_time(1290079655))
        -- yields "Thu, 18-Nov-10 11:27:35 GMT"

ndk.set_var.DIRECTIVE
---------------------
* **Context:** `rewrite_by_lua*`, `access_by_lua*`, `content_by_lua*`

This mechanism allows calling other nginx C modules' directives that are
implemented by Nginx Devel Kit (NDK)'s set_var submodule's ndk_set_var_value.

For example, ngx_set_misc module's set_escape_uri, set_quote_sql_str, and etc.

For instance,

    local res = ndk.set_var.set_escape_uri('a/b');
    -- now res == 'a%2fb'

HTTP 1.0 support
----------------

Sometimes you may want to use nginx's standard `ngx_proxy` module to proxy requests to
another nginx machine configured by a location with `content_by_lua`. Because
`proxy_pass` only supports the HTTP 1.0 protocol, we have to know
the length of your response body and set the `Content-Length` header before emitting
any data out. `ngx_lua` will automatically recognize HTTP 1.0 requests and try to send out an appropriate `Content-Length` header for you, at the first invocation of `ngx.print()` and `ngx.say`, assuming all the response body data
is in a single call of `ngx.print()` or `ngx.say`. So if you want to
support HTTP 1.0 clients like `ngx_proxy`, do not
call `ngx.print()` or `ngx.say()` multiple times,
try buffering the output data yourself wherever needed.

Here is a small example:

On machine A:

    location /internal {
        rewrite ^/internal/(.*) /lua/$1 break;
        proxy_pass http://B;
    }

then on machine B:

    location = /lua/foo {
        content_by_lua '
            data = "hello, world"
            ngx.print(data)
        ';
    }

Then accessing machine A's /internal/foo using curl gives the result that we expect.

One caveat apples here: always send out the response body data in a single call of `ngx.print()` or `ngx.say()`, and subsequent calls of `ngx.print()` or `ngx.say()` will take no effect on the client side.

Performance
===========

The Lua state (aka the Lua vm instance) is shared across all the requests
handled by a single nginx worker process to miminize memory use.

On a ThinkPad T400 2.80 GHz laptop, it's easy to achieve 25k req/sec using ab
w/o keepalive and 37k+ req/sec with keepalive.

You can get better performance when building this module
with LuaJIT 2.0.

Installation
============

1. Ensure OpenSSL is installed on your system. For Ubuntu/Debian users, just install
the `libssl-dev` package. For Fedora/RHEL/CentOS users, just install the
`openssl-devel` package.

1. Install lua into your system. At least Lua 5.1 is required.
Lua can be obtained freely from its project [homepage](http://www.lua.org/).
For Ubuntu/Debian users, just install the liblua5.1-0-dev package (or something like that).

1. Download the latest version of the release tarball of the ngx_devel_kit (NDK) module from
lua-nginx-module [file list](http://github.com/simpl/ngx_devel_kit/downloads).

1. Download the latest version of the release tarball of this module from
lua-nginx-module [file list](http://github.com/chaoslawful/lua-nginx-module/downloads).

1. Grab the nginx source code from [nginx.net](http://nginx.net/), for example,
the version 0.8.54 (see nginx compatibility), and then build the source with
this module:

        $ wget 'http://sysoev.ru/nginx/nginx-0.8.54.tar.gz'
        $ tar -xzvf nginx-0.8.54.tar.gz
        $ cd nginx-0.8.54/

        # tell nginx's build system where to find lua:
        export LUA_LIB=/path/to/lua/lib
        export LUA_INC=/path/to/lua/include

        # or tell where to find LuaJIT when you want to use JIT instead
        # export LUAJIT_LIB=/path/to/luajit/lib
        # export LUAJIT_INC=/path/to/luajit/include/luajit-2.0

        # Here we assume you would install you nginx under /opt/nginx/.
        $ ./configure --prefix=/opt/nginx \
            --add-module=/path/to/ngx_devel_kit \
            --add-module=/path/to/lua-nginx-module

        $ make -j2
        $ make install

Compatibility
=============

The following versions of Nginx should work with this module:

*   0.9.x (last tested: 0.9.4)
*   0.8.x (last tested: 0.8.54)
*   0.7.x >= 0.7.46 (last tested: 0.7.68)

Earlier versions of Nginx like 0.6.x and 0.5.x will **not** work.

Note that `rewrite_by_lua` will NOT work for nginx 0.8.41 ~ 0.8.53.

If you find that any particular version of Nginx above 0.7.44 does not
work with this module, please consider reporting a bug.

Test Suite
==========

To run the test suite, you also need the following dependencies:

* Nginx version > 0.8.53

* Perl modules:
	* test-nginx: <http://github.com/agentzh/test-nginx>

* Nginx modules:
	* echo-nginx-module: <http://github.com/agentzh/echo-nginx-module>
	* drizzle-nginx-module: <http://github.com/chaoslawful/drizzle-nginx-module>
	* rds-json-nginx-module: <http://github.com/agentzh/rds-json-nginx-module>
	* set-misc-nginx-module: <http://github.com/agentzh/set-misc-nginx-module>
	* memc-nginx-module: <http://github.com/agentzh/memc-nginx-module>
	* srcache-nginx-module: <http://github.com/agentzh/srcache-nginx-module>
	* ngx_auth_request: <http://mdounin.ru/hg/ngx_http_auth_request_module/>

* C libraries:
	* yajl: <https://github.com/lloyd/yajl>

* Lua modules:
	* lua-yajl: <https://github.com/brimworks/lua-yajl>
		* Note: the compiled module has to be placed in '/usr/local/lib/lua/5.1/'

* Applications:
	* mysql: create database 'ngx_test', grant all privileges to user 'ngx_test', password is 'ngx_test'
	* memcached

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

TODO
====

* Add `ignore_resp_headers`, `ignore_resp_body`, and `ignore_resp` options to
`ngx.location.capture()` and ngx.location.capture_multi()` methods, to allow
micro performance tuning on the user side.
* Add directives to run lua codes when nginx stops/reloads.
* Deal with TCP 3-second delay problem under great connection harness.

Future Plan
===========

* Add the `lua_require` directive to load module into main thread's globals.
* Add the "cosocket" mechamism that will emulate a common set of Lua socket
API that will give you totally transparently non-blocking capability out of
the box by means of a completely new upstream layer atop the nginx event model
and no nginx subrequest overheads.
* Add Lua code automatic time slicing support by yielding and resuming
the Lua VM actively via Lua's debug hooks.
* Make set_by_lua using the same mechanism as content_by_lua.

Known Issues
============

* Because the standard Lua 5.1 interpreter's VM is not fully resumable, the
`ngx.location.capture()` and `ngx.location.capture_multi()` methods cannot be used within
the context of a Lua `pcall()` or `xpcall()`. If you're heavy on Lua exception model
based on Lua's `error()` and `pcall()`/`xpcall()`, use LuaJIT 2.0 instead because LuaJIT 2.0
supports fully resumable VM.

* The `ngx.location.capture` and `ngx.location.capture_multi` Lua methods cannot capture
locations configured by ngx_echo module's `echo_location`,
`echo_location_async`, `echo_subrequest`, or `echo_subrequest_async` directives. This
won't be fixed in the future due to technical problems :)

* The `ngx.location.capture` and `ngx.location.capture_multi` Lua methods cannot capture
locations with internal redirections for now. But this may get fixed in the future.

* **WATCH OUT: Globals WON'T persist between requests**, because of the one-coroutine-per-request
isolation design. Especially watch yourself when using `require()` to import modules, and
use this form:

        local xxx = require('xxx')

	instead of the old deprecated form:

        require('xxx')

	The old form will cause module unusable in requests for the reason told
	previously. If you have to stick with the old form, you can always force
	loading module for every request by clean `package.loaded.<module>`, like this:

        package.loaded.xxx = nil
        require('xxx')
* 64-bit Darwin OS needs special linking options to use LuaJIT. Change the line at the bottom of `config` file from

		CORE_LIBS="-Wl,-E $CORE_LIBS"

	to

		CORE_LIBS="-Wl,-E -Wl,-pagezero_size,10000 -Wl,-image_base,100000000 $CORE_LIBS"

See Also
========

* "Introduction to ngx_lua" ( <https://github.com/chaoslawful/lua-nginx-module/wiki/Introduction> )
* ngx_devel_kit ( <http://github.com/simpl/ngx_devel_kit> )
* echo-nginx-module ( <http://github.com/agentzh/echo-nginx-module> )
* drizzle-nginx-module ( <http://github.com/chaoslawful/drizzle-nginx-module> )
* postgres-nginx-module ( <http://github.com/FRiCKLE/ngx_postgres> )
* memc-nginx-module ( <http://github.com/agentzh/memc-nginx-module> )

Authors
=======

* chaoslawful (王晓哲) <chaoslawful at gmail dot com>
* Yichun "agentzh" Zhang (章亦春) <agentzh at gmail dot com>

Copyright & License
===================

    This module is licenced under the BSD license.

    Copyright (C) 2009, 2010, 2011, Taobao Inc., Alibaba Group ( http://www.taobao.com ).

    Copyright (C) 2009, 2010, 2011, by Xiaozhe Wang (chaoslawful) <chaoslawful@gmail.com>.

    Copyright (C) 2009, 2010, 2011, by Yichun "agentzh" Zhang (章亦春) <agentzh@gmail.com>.

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

        * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

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

