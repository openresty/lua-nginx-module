<!---
Don't edit this file manually! Instead you should generate it by using:
    wiki2markdown.pl doc/HttpLuaModule.wiki
-->

Name
====

ngx_lua - Embed the power of Lua into Nginx

*This module is not distributed with the Nginx source.* See [the installation instructions](http://wiki.nginx.org/HttpLuaModule#Installation).

Status
======

This module is under active development and is production ready.

Version
=======

This document describes ngx_lua [v0.5.0rc28](https://github.com/chaoslawful/lua-nginx-module/tags) released on 16 May 2012.

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
            # inline Lua script
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
 
            content_by_lua "ngx.say('Hello,world!')";
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
             client_max_body_size 50k;
             client_body_buffer_size 50k;
 
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

               if num > 50 then
                   ngx.say("num too big")
                   return
               end

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

This module embeds Lua, via the standard Lua interpreter or LuaJIT, into Nginx and by leveraging Nginx's subrequests, allows the integration of the powerful Lua threads (Lua coroutines) into the Nginx event model.

Unlike [Apache's mod_lua](http://httpd.apache.org/docs/2.3/mod/mod_lua.html) and [Lighttpd's mod_magnet](http://redmine.lighttpd.net/wiki/1/Docs:ModMagnet), Lua code executed using this module can be *100% non-blocking* on network traffic as long as the [Nginx API for Lua](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) provided by this module is used to handle
requests to upstream services such as mysql, postgresql, memcached, redis, or upstream http web services. (See [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture), [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi), [ngx.socket.tcp](http://wiki.nginx.org/HttpLuaModule#ngx.socket.tcp), [HttpDrizzleModule](http://wiki.nginx.org/HttpDrizzleModule), [ngx_postgres](http://github.com/FRiCKLE/ngx_postgres/), [HttpMemcModule](http://wiki.nginx.org/HttpMemcModule), [HttpRedis2Module](http://wiki.nginx.org/HttpRedis2Module) and [HttpProxyModule](http://wiki.nginx.org/HttpProxyModule) modules for details).

The Lua interpreter or LuaJIT instance is shared across all the requests in a single nginx worker process but request contexts are segregated using lightweight Lua coroutines. 
Loaded Lua modules persist in the nginx worker process level resulting in a small memory footprint even when under heavy loads.

Directives
==========

lua_code_cache
--------------
**syntax:** *lua_code_cache on | off*

**default:** *lua_code_cache on*

**context:** *main, server, location, location if*

Enables or disables the Lua code cache for [set_by_lua_file](http://wiki.nginx.org/HttpLuaModule#set_by_lua_file),
[content_by_lua_file](http://wiki.nginx.org/HttpLuaModule#content_by_lua_file), [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file), and
[access_by_lua_file](http://wiki.nginx.org/HttpLuaModule#access_by_lua_file), and also force Lua module reloading on a per-request basis.

The Lua files referenced in [set_by_lua_file](http://wiki.nginx.org/HttpLuaModule#set_by_lua_file),
[content_by_lua_file](http://wiki.nginx.org/HttpLuaModule#content_by_lua_file), [access_by_lua_file](http://wiki.nginx.org/HttpLuaModule#access_by_lua_file),
and [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file) will not be cached
and the Lua `package.loaded` table will be cleared
at the entry point of every request (such that Lua modules
will not be cached either). With this in place, developers can adopt an edit-and-refresh approach.

Please note however, that Lua code inlined into nginx.conf
such as those specified by [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua), [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua),
[access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua), and [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) will *always* be
cached because only the Nginx config file parser can correctly parse the `nginx.conf`
file and the only ways to to reload the config file
are to send a `HUP` signal or to restart Nginx.

The ngx_lua module does not currently support the `stat` mode available with the 
Apache `mod_lua` module but this is planned for implementation in the future.

Disabling the Lua code cache is strongly
discouraged for production use and should only be used during 
development as it has a significant negative impact on overall performance.
In addition, race conditions when reloading Lua modules are common for concurrent requests
when the code cache is disabled.

lua_regex_cache_max_entries
---------------------------
**syntax:** *lua_regex_cache_max_entries &lt;num&gt;*

**default:** *lua_regex_cache_max_entries 1024*

**context:** *http*

Specifies the maximum number of entries allowed in the worker process level compiled regex cache.

The regular expressions used in [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match), [ngx.re.gmatch](http://wiki.nginx.org/HttpLuaModule#ngx.re.gmatch), [ngx.re.sub](http://wiki.nginx.org/HttpLuaModule#ngx.re.sub), and [ngx.re.gsub](http://wiki.nginx.org/HttpLuaModule#ngx.re.gsub) will be cached within this cache if the regex option `o` (i.e., compile-once flag) is specified.

The default number of entries allowed is 1024 and when this limit is reached, new regular expressions will not be cached (as if the `o` option was not specified) and there will be one, and only one, warning in the `error.log` file:


    2011/08/27 23:18:26 [warn] 31997#0: *1 lua exceeding regex cache max entries (1024), ...


Do not activate the `o` option for regular expressions (and/or `replace` string arguments for [ngx.re.sub](http://wiki.nginx.org/HttpLuaModule#ngx.re.sub) and [ngx.re.gsub](http://wiki.nginx.org/HttpLuaModule#ngx.re.gsub)) that are generated *on the fly* and give rise to infinite variations to avoid hitting the specified limit.

lua_package_path
----------------

**syntax:** *lua_package_path &lt;lua-style-path-str&gt;*

**default:** *The content of LUA_PATH environ variable or Lua's compiled-in defaults.*

**context:** *main*

Sets the Lua module search path used by scripts specified by [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua),
[content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) and others. The path string is in standard Lua path form, and `;;`
can be used to stand for the original search paths.

Since the `v0.5.0rc29` release, the special notation `$prefix` or `${prefix}` can be used in the search path string to indicate the path of the `server prefix` usually determined by the `-p PATH` command-line option while starting the Nginx server.

lua_package_cpath
-----------------

**syntax:** *lua_package_cpath &lt;lua-style-cpath-str&gt;*

**default:** *The content of LUA_CPATH environment variable or Lua's compiled-in defaults.*

**context:** *main*

Sets the Lua C-module search path used by scripts specified by [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua),
[content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) and others. The cpath string is in standard Lua cpath form, and `;;`
can be used to stand for the original cpath.

Since the `v0.5.0rc29` release, the special notation `$prefix` or `${prefix}` can be used in the search path string to indicate the path of the `server prefix` usually determined by the `-p PATH` command-line option while starting the Nginx server.

set_by_lua
----------

**syntax:** *set_by_lua $res &lt;lua-script-str&gt; [$arg1 $arg2 ...]*

**context:** *main, server, location, server if, location if*

**phase:** *rewrite*

Executes code specified in `<lua-script-str>` with optional input arguments `$arg1 $arg2 ...`, and returns string output to `$res`. 
The code in `<lua-script-str>` can make [API calls](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) and can retrieve input arguments from the `ngx.arg` table (index starts from `1` and increases sequentially).

This directive is designed to execute short, fast running code blocks as the Nginx event loop is blocked during code execution. Time consuming code sequences should therefore be avoided.

Note that I/O operations such as [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say), [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec), [echo](http://wiki.nginx.org/HttpEchoModule#echo) and similar are not permitted within the context of this directive.

In addition, note that this directive can only write out a value to a single Nginx variable at
a time. However, a workaround is possible using the [ngx.var.VARIABLE](http://wiki.nginx.org/HttpLuaModule#ngx.var.VARIABLE) interface.


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


This directive can be freely mixed with all directives of the [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule), [HttpSetMiscModule](http://wiki.nginx.org/HttpSetMiscModule), and [HttpArrayVarModule](http://wiki.nginx.org/HttpArrayVarModule) modules. All of these directives will run in the same order as they appear in the config file.


    set $foo 32;
    set_by_lua $bar 'tonumber(ngx.var.foo) + 1';
    set $baz "bar: $bar";  # $baz == "bar: 33"


Since the `0.5.0rc29` release, Nginx variable interpolation is disabled in the `<lua-script-str>` argument of this directive, and you can use the dollar sign character (`$`) directly.

This directive requires the [ngx_devel_kit](https://github.com/simpl/ngx_devel_kit) module.

set_by_lua_file
---------------
**syntax:** *set_by_lua_file $res &lt;path-to-lua-script-file&gt; [$arg1 $arg2 ...]*

**context:** *main, server, location, server if, location if*

**phase:** *rewrite*

Equivalent to [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua), except that the file specified by `<path-to-lua-script-file>` contains the Lua code to be executed.

Nginx variable interpolation is supported in the `<path-to-lua-script-file>` argument string of this directive. But special care must be taken for injection attacks.

When a relative path like `foo/bar.lua` is given, they will be turned into the absoluate path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached 
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by 
switching [lua_code_cache](http://wiki.nginx.org/HttpLuaModule#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

This directive requires the [ngx_devel_kit](https://github.com/simpl/ngx_devel_kit) module.

content_by_lua
--------------

**syntax:** *content_by_lua &lt;lua-script-str&gt;*

**context:** *location, location if*

**phase:** *content*

Acts as a "content handler" and executes Lua code string specified in `<lua-script-str>` for every request. 
The Lua code may make [API calls](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Do not use this directive and other content handler directives in the same location. For example, this directive and the [proxy_pass](http://wiki.nginx.org/HttpProxyModule#proxy_pass) directive should not be used in the same location.

content_by_lua_file
-------------------

**syntax:** *content_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *location, location if*

**phase:** *content*

Equivalent to [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua), except that the file specified by `<path-to-lua-script-file>` contains the Lua code to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absoluate path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached 
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by 
switching [lua_code_cache](http://wiki.nginx.org/HttpLuaModule#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

rewrite_by_lua
--------------

**syntax:** *rewrite_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *rewrite tail*

Acts as a rewrite phase handler and executes Lua code string specified in `<lua-script-str>` for every request.
The Lua code may make [API calls](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Note that this handler always runs *after* the standard [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule). So the following will work as expected:


       location /foo {
           set $a 12; # create and initialize $a
           set $b ""; # create and initialize $b
           rewrite_by_lua 'ngx.var.b = tonumber(ngx.var.a) + 1';
           echo "res = $b";
       }


because `set $a 12` and `set $b ""` run *before* [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua).

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


because `if` runs *before* [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) even if it is placed after [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) in the config.

The right way of doing this is as follows:


    location /foo {
        set $a 12; # create and initialize $a
        set $b ''; # create and initialize $b
        rewrite_by_lua '
            ngx.var.b = tonumber(ngx.var.a) + 1
            if tonumber(ngx.var.b) == 13 then
                return ngx.redirect("/bar");
            end
        ';
 
        echo "res = $b";
    }


Note that the [ngx_eval](http://www.grid.net.ru/nginx/eval.en.html) module can be approximated by using [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua). For example,


    location / {
        eval $res {
            proxy_pass http://foo.com/check-spam;
        }
 
        if ($res = 'spam') {
            rewrite ^ /terms-of-use.html redirect;
        }
 
        fastcgi_pass ...;
    }


can be implemented in `ngx_lua` as:


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


Just as any other rewrite phase handlers, [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) also runs in subrequests.

Note that when calling `ngx.exit(ngx.OK)` within a [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) handler, the nginx request processing control flow will still continue to the content handler. To terminate the current request from within a [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) handler, calling [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit) with status >= 200 (`ngx.HTTP_OK`) and status < 300 (`ngx.HTTP_SPECIAL_RESPONSE`) for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` (or its friends) for failures.

If the [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule)'s [rewrite](http://wiki.nginx.org/HttpRewriteModule#rewrite) directive is used to change the URI and initiate location re-lookups (internal redirections), then any [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) or [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file) code sequences within the current location will not be executed. For example,


    location /foo {
        rewrite ^ /bar;
        rewrite_by_lua 'ngx.exit(503)';
    }
    location /bar {
        ...
    }


Here the Lua code `ngx.exit(503)` will never run. This will be the case if `rewrite ^ /bar last` is used as this will similarly initiate an internal redirection. If the `break` modifier is used instead, there will be no internal redirection and the rewrite_by_lua code will be executed.

rewrite_by_lua_file
-------------------

**syntax:** *rewrite_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *rewrite tail*

Equivalent to [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua), except that the file specified by `<path-to-lua-script-file>` contains the Lua code to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absoluate path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached and the Nginx config must be reloaded each time the Lua source file is modified. The Lua code cache can be temporarily disabled during development by switching [lua_code_cache](http://wiki.nginx.org/HttpLuaModule#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

access_by_lua
-------------

**syntax:** *access_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *access tail*

Acts as an access phase handler and executes Lua code string specified in `<lua-script-str>` for every request.
The Lua code may make [API calls](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Note that this handler always runs *after* the standard [HttpAccessModule](http://wiki.nginx.org/HttpAccessModule). So the following will work as expected:


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


That is, if a client IP address is in the blacklist, it will be denied before the MySQL query for more complex authentication is executed by [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua).

Note that the [ngx_auth_request](http://mdounin.ru/hg/ngx_http_auth_request_module/) module can be approximated by using [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua):


    location / {
        auth_request /auth;
 
        # proxy_pass/fastcgi_pass/postgres_pass/...
    }


can be implemented in `ngx_lua` as:


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


As with other access phase handlers, [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua) will *not* run in subrequests.

Note that when calling `ngx.exit(ngx.OK)` within a [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua) handler, the nginx request processing control flow will still continue to the content handler. To terminate the current request from within a [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua) handler, calling [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit) with status >= 200 (`ngx.HTTP_OK`) and status < 300 (`ngx.HTTP_SPECIAL_RESPONSE`) for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` (or its friends) for failures.

access_by_lua_file
------------------

**syntax:** *access_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *access tail*

Equivalent to [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua), except that the file specified by `<path-to-lua-script-file>` contains the Lua code to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absoluate path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached 
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by switching [lua_code_cache](http://wiki.nginx.org/HttpLuaModule#lua_code_cache) `off` in `nginx.conf` to avoid repeatedly reloading Nginx.

header_filter_by_lua
--------------------

**syntax:** *header_filter_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *output-header-filter*

Uses Lua code specified in `<lua-script-str>` to define an output header filter. Note that the following API functions are currently disabled within this context:

* Output API functions (e.g., [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say) and [ngx.send_headers](http://wiki.nginx.org/HttpLuaModule#ngx.send_headers))
* Control API functions (e.g., [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit)) 
* Subrequest API functions (e.g., [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi))

Here is an example of overriding a response header (or adding one if absent) in our Lua header filter:


    location / {
        proxy_pass http://mybackend;
        header_filter_by_lua 'ngx.header.Foo = "blah"';
    }


This directive was first introduced in the `v0.2.1rc20` release.

header_filter_by_lua_file
-------------------------

**syntax:** *header_filter_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *output-header-filter*

Equivalent to [header_filter_by_lua](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua), except that the file specified by `<path-to-lua-script-file>` contains the Lua code to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absoluate path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.2.1rc20` release.

lua_need_request_body
---------------------

**syntax:** *lua_need_request_body &lt;on|off&gt;*

**default:** *off*

**context:** *main | server | location*

**phase:** *depends on usage*

Determines whether to force the request body data to be read before running rewrite/access/access_by_lua* or not. The Nginx core does not read the client request body by default and if request body data is required, then this directive should be turned `on` or the [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) function should be called within the Lua code.

To read the request body data within the [$request_body](http://wiki.nginx.org/HttpCoreModule#.24request_body) variable, 
[client_body_buffer_size](http://wiki.nginx.org/HttpCoreModule#client_body_buffer_size) must have the same value as [client_max_body_size](http://wiki.nginx.org/HttpCoreModule#client_max_body_size). Because when the content length exceeds [client_body_buffer_size](http://wiki.nginx.org/HttpCoreModule#client_body_buffer_size) but less than [client_max_body_size](http://wiki.nginx.org/HttpCoreModule#client_max_body_size), Nginx will automatically buffer the data into a temporary file on the disk, which will lead to empty value in the [$request_body](http://wiki.nginx.org/HttpCoreModule#.24request_body) variable.

If the current location includes [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) or [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file) directives,
then the request body will be read just before the [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) or [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file) code is run (and also at the
`rewrite` phase). Similarly, if only [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) is specified,
the request body will not be read until the content handler's Lua code is
about to run (i.e., the request body will be read during the content phase).

It is recommended however, to use the [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) and [ngx.req.discard_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.discard_body) functions for finer control over the request body reading process instead.

This also applies to [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua) and [access_by_lua_file](http://wiki.nginx.org/HttpLuaModule#access_by_lua_file).

lua_shared_dict
---------------

**syntax:** *lua_shared_dict &lt;name&gt; &lt;size&gt;*

**default:** *no*

**context:** *http*

**phase:** *depends on usage*

Declares a shared memory zone, `<name>`, to serve as storage for the shm-based Lua dictionary `ngx.shared.<name>`.

The `<size>` argument accepts size units such as `k` and `m`:


    http {
        lua_shared_dict dogs 10m;
        ...
    }


See [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) for details.

This directive was first introduced in the `v0.3.1rc22` release.

lua_socket_connect_timeout
--------------------------

**syntax:** *lua_socket_connect_timeout &lt;time&gt;*

**default:** *lua_socket_connect_timeout 60s*

**context:** *http, server, location*

This directive controls the default timeout value used in TCP/unix-domain socket object's [connect](http://wiki.nginx.org/HttpLuaModule#tcpsock:connect) method and can be overridden by the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

lua_socket_send_timeout
-----------------------

**syntax:** *lua_socket_send_timeout &lt;time&gt;*

**default:** *lua_socket_send_timeout 60s*

**context:** *http, server, location*

Controls the default timeout value used in TCP/unix-domain socket object's [send](http://wiki.nginx.org/HttpLuaModule#tcpsock:send) method and can be overridden by the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

lua_socket_send_lowat
---------------------

**syntax:** *lua_socket_send_lowat &lt;size&gt;*

**default:** *lua_socket_send_lowat 0*

**context:** *http, server, location*

Controls the `lowat` (low water) value for the cosocket send buffer.

lua_socket_read_timeout
-----------------------

**syntax:** *lua_socket_read_timeout &lt;time&gt;*

**default:** *lua_socket_read_timeout 60s*

**context:** *http, server, location*

**phase:** *depends on usage*

This directive controls the default timeout value used in TCP/unix-domain socket object's [receive](http://wiki.nginx.org/HttpLuaModule#tcpsock:receive) method and iterator functions returned by the [receiveuntil](http://wiki.nginx.org/HttpLuaModule#tcpsock:receiveuntil) method. This setting can be overridden by the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

lua_socket_buffer_size
----------------------

**syntax:** *lua_socket_buffer_size &lt;size&gt;*

**default:** *lua_socket_buffer_size 4k/8k*

**context:** *http, server, location*

Specifies the buffer size used by cosocket reading operations.

This buffer does not have to be that big to hold everything at the same time because cosocket supports 100% non-buffered reading and parsing. So even `1` byte buffer size should still work everywhere but the performance could be terrible.

This directive was first introduced in the `v0.5.0rc1` release.

lua_socket_pool_size
--------------------

**syntax:** *lua_socket_pool_size &lt;size&gt;*

**default:** *lua_socket_pool_size 30*

**context:** *http, server, location*

Specifies the size limit (in terms of connection count) for every cosocket connection pool associated with every remote server (i.e., identified by either the host-port pair or the unix domain socket file path).

Default to 30 connections for every pool.

When the connection pool is exceeding the size limit, the least recently used (idle) connection already in the pool will be closed automatically to make room for the current connection. 

Note that the cosocket connection pool is per nginx worker process rather than per nginx server instance, so so size limit specified here also applies to every single nginx worker process.

This directive was first introduced in the `v0.5.0rc1` release.

lua_socket_keepalive_timeout
----------------------------

**syntax:** *lua_socket_keepalive_timeout &lt;time&gt;*

**default:** *lua_socket_keepalive_timeout 60s*

**context:** *http, server, location*

This directive controls the default maximal idle time of the connections in the cosocket built-in connection pool. When this timeout reaches, idle connections will be closed automatically and removed from the pool. This setting can be overridden by cosocket objects' [setkeepalive](http://wiki.nginx.org/HttpLuaModule#tcpsock:setkeepalive) method.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, ie, "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

lua_http10_buffering
--------------------

**syntax:** *lua_http10_buffering on|off*

**default:** *lua_http10_buffering on*

**context:** *http, server, location, location-if*

Enables or disables the automatic response caching for HTTP 1.0 (or older) requests. This buffering mechanism is mainly used for HTTP 1.0 keep-alive which replies on a proper `Content-Length` response header.

If the Lua code explicitly sets a `Content-Length` response header before sending the headers (either explicity via [ngx.send_headers](http://wiki.nginx.org/HttpLuaModule#ngx.send_headers) or implicitly via the first [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say) or [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) call).

If you want to output huge response data in a streaming fashion (via the [ngx.flush](http://wiki.nginx.org/HttpLuaModule#ngx.flush) call, for example), then you MUST turn off this directive to prevent memory footprint boost.

This directive is turned `on` by default.

This directive was first introduced in the `v0.5.0rc19` release.

rewrite_by_lua_no_postpone
--------------------------

**syntax:** *rewrite_by_lua_no_postpone on|off*

**default:** *rewrite_by_lua_no_postpone off*

**context:** *http, server, location, location-if*

Controls whether or not to disable postponing [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) and [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file) directives to run at the end of the `rewrite` request-processing phase. By default, this directive is turned off and the Lua code is postponed to run at the end of the `rewrite` phase.

This directive was first introduced in the `v0.5.0rc29` release.

Nginx API for Lua
=================
Introduction
------------
The various `*_by_lua` and `*_by_lua_file` configuration directives serve as gateways to the Lua API within the `nginx.conf` file. The Nginx Lua API described below can only be called within the user Lua code run in the context of these configuration directives.

The API is exposed to Lua in the form of two standard packages `ngx` and `ndk`. These packages are in the default global scope within `ngx_lua` and are always available within `ngx_lua` directives.

The packages can be introduced into external Lua modules by using the [package.seeall](http://www.lua.org/manual/5.1/manual.html#pdf-package.seeall) option:


    module("my_module", package.seeall)

    function say(a) ngx.say(a) end


Alternatively, they can be imported to external Lua modules by using file scoped local Lua variables:


    local ngx = ngx
    module("my_module")

    function say(a) ngx.say(a) end


It is also possible to directly require the packages in external Lua modules:


    local ngx = require "ngx"
    local ndk = require "ndk"


The ability to require these packages was introduced in the `v0.2.1rc19` release.

Network I/O operations in user code should only be done through the Nginx Lua API calls as the Nginx event loop may be blocked and performance drop off dramatically otherwise. Disk operations with relatively small amount of data can be done using the standard Lua `io` library but huge file reading and writing should be avoided wherever possible as they may block the Nginx process significantly. Delegating all network and disk I/O operations to Nginx's subrequests (via the [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.catpure) method and similar) is strongly recommended for maximum performance.

ngx.arg
-------
**syntax:** *val = ngx.arg[index]*

**context:** *set_by_lua**

Index the input arguments to the [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua) and [set_by_lua_file](http://wiki.nginx.org/HttpLuaModule#set_by_lua_file) directives:


    value = ngx.arg[n]


Here is an example


    location /foo {
        set $a 32;
        set $b 56;
 
        set_by_lua $res
            'return tonumber(ngx.arg[1]) + tonumber(ngx.arg[2])'
            $a $b;
 
        echo $sum;
    }


that writes out `88`, the sum of `32` and `56`.

ngx.var.VARIABLE
----------------
**syntax:** *ngx.var.VAR_NAME*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Read and write Nginx variable values.


    value = ngx.var.some_nginx_variable_name
    ngx.var.some_nginx_variable_name = value


Note that only already defined nginx variables can be written to.
For example:


    location /foo {
        set $my_var ''; # this line is required to create $my_var at config time
        content_by_lua '
            ngx.var.my_var = 123;
            ...
        ';
    }


That is, nginx variables cannot be created on-the-fly.

Some special nginx variables like `$args` and `$limit_rate` can be assigned a value,
some are not, like `$arg_PARAMETER`.

Nginx regex group capturing variables `$1`, `$2`, `$3`, and etc, can be read by this
interface as well, by writing `ngx.var[1]`, `ngx.var[2]`, `ngx.var[3]`, and etc.

Setting `ngx.var.Foo` to a `nil` value will unset the `$Foo` Nginx variable. 


    ngx.var.args = nil


Core constants
--------------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**


      ngx.OK (0)
      ngx.ERROR (-1)
      ngx.AGAIN (-2)
      ngx.DONE (-4)
      ngx.DECLINED (-5)


Note that only three of these constants are utilized by the [Nginx API for Lua](http://wiki.nginx.org/HttpLuaModule#Nginx_API_for_Lua) (i.e., [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit) accepts `NGX_OK`, `NGX_ERROR`, and `NGX_DECLINED` as input).


      ngx.null


The `ngx.null` constant is a `NULL` light userdata which is usually used to represent nil values in Lua tables and etc. It is identical with the [lua-cjson](http://www.kyne.com.au/~mark/software/lua-cjson.php) library's `cjson.null` constant. This constant was first introduced in the `v0.5.0rc5` release.

The `ngx.DECLINED` constant was first introduced in the `v0.5.0rc19` release.

HTTP method constants
---------------------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**


      ngx.HTTP_GET
      ngx.HTTP_HEAD
      ngx.HTTP_PUT
      ngx.HTTP_POST
      ngx.HTTP_DELETE
      ngx.HTTP_OPTIONS   (first introduced in the v0.5.0rc24 release)


These constants are usually used in [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi) method calls.

HTTP status constants
---------------------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**


      value = ngx.HTTP_OK (200)
      value = ngx.HTTP_CREATED (201)
      value = ngx.HTTP_SPECIAL_RESPONSE (300)
      value = ngx.HTTP_MOVED_PERMANENTLY (301)
      value = ngx.HTTP_MOVED_TEMPORARILY (302)
      value = ngx.HTTP_SEE_OTHER (303)
      value = ngx.HTTP_NOT_MODIFIED (304)
      value = ngx.HTTP_BAD_REQUEST (400)
      value = ngx.HTTP_UNAUTHORIZED (401)
      value = ngx.HTTP_FORBIDDEN (403)
      value = ngx.HTTP_NOT_FOUND (404)
      value = ngx.HTTP_NOT_ALLOWED (405)
      value = ngx.HTTP_GONE (410)
      value = ngx.HTTP_INTERNAL_SERVER_ERROR (500)
      value = ngx.HTTP_METHOD_NOT_IMPLEMENTED (501)
      value = ngx.HTTP_SERVICE_UNAVAILABLE (503)
      value = ngx.HTTP_GATEWAY_TIMEOUT (504) (first added in the v0.3.1rc38 release)


Nginx log level constants
-------------------------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**


      ngx.STDERR
      ngx.EMERG
      ngx.ALERT
      ngx.CRIT
      ngx.ERR
      ngx.WARN
      ngx.NOTICE
      ngx.INFO
      ngx.DEBUG


These constants are usually used by the [ngx.log](http://wiki.nginx.org/HttpLuaModule#ngx.log) method.

print
-----
**syntax:** *print(...)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Writes argument values into the nginx `error.log` file with the `ngx.NOTICE` log level.

It is equivalent to


    ngx.log(ngx.NOTICE, ...)


Lua `nil` arguments are accepted and result in literal `"nil"` strings while Lua booleans result in literal `"true"` or `"false"` strings. And the `ngx.null` constant will yield the `"null"` string output.

There is a hard-coded length limitation on the error messages in the Nginx core. It is `2048` bytes at most, including the trailing newlines and the leading timestamps. You can manually modify this limit by modifying the `NGX_MAX_ERROR_STR` macro definition in the `src/core/ngx_log.h` file in the Nginx source tree. If the message size exceeds this limit, the Nginx core will truncate the message text automatically.

ngx.ctx
-------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

This table can be used to store per-request Lua context data and has a life time identical to the current request (as with the Nginx variables). 

Consider the following example,


    location /test {
        rewrite_by_lua '
            ngx.say("foo = ", ngx.ctx.foo)
            ngx.ctx.foo = 76
        ';
        access_by_lua '
            ngx.ctx.foo = ngx.ctx.foo + 3
        ';
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }


Then `GET /test` will yield the output


    foo = nil
    79


That is, the `ngx.ctx.foo` entry persists across the rewrite, access, and content phases of a request.

Every request, including subrequests, has its own copy of the table. For example:


    location /sub {
        content_by_lua '
            ngx.say("sub pre: ", ngx.ctx.blah)
            ngx.ctx.blah = 32
            ngx.say("sub post: ", ngx.ctx.blah)
        ';
    }
 
    location /main {
        content_by_lua '
            ngx.ctx.blah = 73
            ngx.say("main pre: ", ngx.ctx.blah)
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("main post: ", ngx.ctx.blah)
        ';
    }


Then `GET /main` will give the output


    main pre: 73
    sub pre: nil
    sub post: 32
    main post: 73


Here, modification of the `ngx.ctx.blah` entry in the subrequest does not affect the one in the parent request. This is because they have two separate versions of `ngx.ctx.blah`.

Internal redirection will destroy the original request `ngx.ctx` data (if any) and the new request will have an empty `ngx.ctx` table. For instance,


    location /new {
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }
 
    location /orig {
        content_by_lua '
            ngx.ctx.foo = "hello"
            ngx.exec("/new")
        ';
    }


Then `GET /orig` will give


    nil


rather than the original `"hello"` value.

Arbitrary data values, including Lua closures and nested tables, can be inserted into this "magic" table. It also allows the registration of custom meta methods.

Overriding `ngx.ctx` with a new Lua table is also supported, for example,


    ngx.ctx = { foo = 32, bar = 54 }


ngx.location.capture
--------------------
**syntax:** *res = ngx.location.capture(uri, options?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Issue a synchronous but still non-blocking *Nginx Subrequest* using `uri`.

Nginx's subrequests provide a powerful way to make non-blocking internal requests to other locations configured with disk file directory or *any* other nginx C modules like `ngx_proxy`, `ngx_fastcgi`, `ngx_memc`,
`ngx_postgres`, `ngx_drizzle`, and even `ngx_lua` itself and etc etc etc.

Also note that subrequests just mimic the HTTP interface but there is *no* extra HTTP/TCP traffic *nor* IPC involved. Everything works internally, efficiently, on the C level.

Subrequests are completely different from HTTP 301/302 redirection (via [ngx.redirect](http://wiki.nginx.org/HttpLuaModule#ngx.redirect)) and internal redirection (via [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec)).

Here is a basic example:


    res = ngx.location.capture(uri)


Returns a Lua table with three slots (`res.status`, `res.header`, and `res.body`).

`res.header` holds all the response headers of the
subrequest and it is a normal Lua table. For multi-value response headers,
the value is a Lua (array) table that holds all the values in the order that
they appear. For instance, if the subrequest response headers contain the following
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
argument, which supports the options:

* `method`
	specify the subrequest's request method, which only accepts constants like `ngx.HTTP_POST`.
* `body`
	specify the subrequest's request body (string value only).
* `args`
	specify the subrequest's URI query arguments (both string value and Lua tables are accepted)
* `ctx`
	specify a Lua table to be the [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx) table for the subrequest. It can be the current request's [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx) table, which effectively makes the parent and its subrequest to share exactly the same context table. This option was first introduced in the `v0.3.1rc25` release.
* `vars`
	take a Lua table which holds the values to set the specified Nginx variables in the subrequest as this option's value. This option was first introduced in the `v0.3.1rc31` release.
* `copy_all_vars`
	specify whether to copy over all the Nginx variable values of the current request to the subrequest in question. modifications of the nginx variables in the subrequest will not affect the current (parent) request. This option was first introduced in the `v0.3.1rc31` release.
* `share_all_vars`
	specify whether to share all the Nginx variables of the subrequest with the current (parent) request. modifications of the Nginx variables in the subrequest will affect the current (parent) request.

Issuing a POST subrequest, for example, can be done as follows


    res = ngx.location.capture(
        '/foo/bar',
        { method = ngx.HTTP_POST, body = 'hello, world' }
    )


See HTTP method constants methods other than POST.
The `method` option is `ngx.HTTP_GET` by default.

The `args` option can specify extra URI arguments, for instance,


    ngx.location.capture('/foo?a=1',
        { args = { b = 3, c = ':' } }
    )


is equivalent to


    ngx.location.capture('/foo?a=1&b=3&c=%3a')


that is, this method will automatically escape argument keys and values according to URI rules and
concatenating them together into a complete query string. The format for the Lua table passed as the `args` argument is identical to the format used in the [ngx.encode_args](http://wiki.nginx.org/HttpLuaModule#ngx.encode_args) method.

The `args` option can also take plain query strings:


    ngx.location.capture('/foo?a=1',
        { args = 'b=3&c=%3a' } }
    )


This is functionally identical to the previous examples.

The `share_all_vars` option controls whether to share nginx variables among the current request and its subrequests. 
If this option is set to `true`, then the current request and associated subrequests will share the same Nginx variable scope. Hence, changes to Nginx variables made by a subrequest will affect the current request.

Care should be taken in using this option as variable scope sharing can have unexpected side effects. The `args`, `vars`, or `copy_all_vars` options are generally preferable instead.

This option is set to `false` by default


    location /other {
        set $dog "$dog world";                  
        echo "$uri dog: $dog";                    
    }                                     
    
    location /lua {
        set $dog 'hello';
        content_by_lua '
            res = ngx.location.capture("/other",
                { share_all_vars = true });
                
            ngx.print(res.body)
            ngx.say(ngx.var.uri, ": ", ngx.var.dog)
        ';  
    }           


Accessing location `/lua` gives


    /other dog: hello world
    /lua: hello world


The `copy_all_vars` option provides a copy of the parent request's Nginx variables to subrequests when such subrequests are issued. Changes made to these variables by such subrequests will not affect the parent request or any other subrequests sharing the parent request's variables.


    location /other {
        set $dog "$dog world";
        echo "$uri dog: $dog";
    }

    location /lua {
        set $dog 'hello';
        content_by_lua '
            res = ngx.location.capture("/other",
                { copy_all_vars = true });

            ngx.print(res.body)
            ngx.say(ngx.var.uri, ": ", ngx.var.dog)
        ';
    }


Request `GET /lua` will give the output


    /other dog: hello world
    /lua: hello


Note that if both `share_all_vars` and `copy_all_vars` are set to true, then `share_all_vars` takes precedence.

In addition to the two settings above, it is possible to specify
values for variables in the subrequest using the `vars` option. These
variables are set after the sharing or copying of variables has been
evaluated, and provides a more efficient method of passing specific
values to a subrequest over encoding them as URL arguments and 
unescaping them in the Nginx config file.


    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog '';
        set $cat '';
        content_by_lua '
            res = ngx.location.capture("/other",
                { vars = { dog = "hello", cat = 32 }});

            ngx.print(res.body)
        ';
    }


Accessing `/lua` will yield the output


    dog = hello
    cat = 32


The `ctx` option can be used to specify a custom Lua table to serve as the [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx) table for the subrequest.


    location /sub {
        content_by_lua '                          
            ngx.ctx.foo = "bar";                  
        ';
    }   
    location /lua {
        content_by_lua '
            local ctx = {}                        
            res = ngx.location.capture("/sub", { ctx = ctx })
            
            ngx.say(ctx.foo);
            ngx.say(ngx.ctx.foo);                 
        ';                                        
    }


Then request `GET /lua` gives


    bar                                               
    nil


It is also possible to use this `ctx` option to share the same [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx) table between the current (parent) request and the subrequest:


    location /sub {
        content_by_lua '
            ngx.ctx.foo = "bar";
        ';
    }
    location /lua {
        content_by_lua '
            res = ngx.location.capture("/sub", { ctx = ngx.ctx })
            ngx.say(ngx.ctx.foo);
        ';
    }


Request `GET /lua` yields the output


    bar


Note that subrequests issued by [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) inherit all the
request headers of the current request by default and that this may have unexpected side effects on the
subrequest responses. For example, when using the standard `ngx_proxy` module to serve
subrequests, an "Accept-Encoding: gzip" header in the main request may result
in gzipped responses that cannot be handled properly in Lua code. Original request headers should be ignored by setting 
[proxy_pass_request_headers](http://wiki.nginx.org/HttpProxyModule#proxy_pass_request_headers) to `off` in subrequest locations.

There is a hard-coded upper limit on the number of concurrent subrequests every main request. In older versions of Nginx, the limit is `50`, which is then increased to `200` in recent Nginx `1.1.x` releases. You can manually edit this limit by modifying the definition of the `NGX_HTTP_MAX_SUBREQUESTS` macro in the `nginx/src/http/ngx_http_request.h` file in the Nginx source tree. When you are exceeding this limit, you will get the following error message in your `error.log` file:


    [error] 13983#0: *1 subrequests cycle while processing "/uri"


Please also refer to restrictions on [capturing locations that include Echo Module directives](http://wiki.nginx.org/HttpLuaModule#Locations_With_HttpEchoModule_Directives).

ngx.location.capture_multi
--------------------------
**syntax:** *res1, res2, ... = ngx.location.capture_multi({ {uri, options?}, {uri, options?}, ... })*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Just like [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture), but supports multiple subrequests running in parallel.

This function issues several parallel subrequests specified by the input table and returns their results in the same order. For example,


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


This function will not return until all the subrequests terminate.
The total latency is the longest latency of the individual subrequests rather than the sum.

Lua tables can be used for both requests and responses when the number of subrequests to be issued is not known in advance:


    -- construct the requests table
    local reqs = {}
    table.insert(reqs, { "/mysql" })
    table.insert(reqs, { "/postgres" })
    table.insert(reqs, { "/redis" })
    table.insert(reqs, { "/memcached" })
 
    -- issue all the requests at once and wait until they all return
    local resps = { ngx.location.capture_multi(reqs) }
 
    -- loop over the responses table
    for i, resp in ipairs(resps) do
        -- process the response table "resp"
    end


The [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) function is just a special form
of this function. Logically speaking, the [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) can be implemented like this


    ngx.location.capture =
        function (uri, args)
            return ngx.location.capture_multi({ {uri, args} })
        end


Please also refer to restrictions on [capturing locations that include Echo Module directives](http://wiki.nginx.org/HttpLuaModule#Locations_With_HttpEchoModule_Directives).

ngx.status
----------
**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Read and write the current request's response status. This should be called
before sending out the response headers.


    ngx.status = ngx.HTTP_CREATED
    status = ngx.status


ngx.header.HEADER
-----------------
**syntax:** *ngx.header.HEADER = VALUE*

**syntax:** *value = ngx.header.HEADER*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Set, add to, or clear the current request `HEADER` response header. Underscores (`_`) in the header names will be replaced by dashes (`-`) and the header names will be matched case-insensitively.


    -- equivalent to ngx.header["Content-Type"] = 'text/plain'
    ngx.header.content_type = 'text/plain';
 
    ngx.header["X-My-Header"] = 'blah blah';


Multi-value headers can be set this way:


    ngx.header['Set-Cookie'] = {'a=32; path=/', 'b=4; path=/'}


will yield


    Set-Cookie: a=32; path=/
    Set-Cookie: b=4; path=/


in the response headers. 

Only Lua tables are accepted (Only the last element in the table will take effect for standard headers such as `Content-Type` that only accept a single value).


    ngx.header.content_type = {'a', 'b'}


is equivalent to


    ngx.header.content_type = 'b'


Setting a slot to `nil` effectively removes it from the response headers:


    ngx.header["X-My-Header"] = nil;


The same applies to assigning an empty table:


    ngx.header["X-My-Header"] = {};


Setting `ngx.header.HEADER` after sending out response headers (either explicitly with [ngx.send_headers](http://wiki.nginx.org/HttpLuaModule#ngx.send_headers) or implicitly with [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) and similar) will throw out a Lua exception.

Reading `ngx.header.HEADER` will return the value of the response header named `HEADER`. 

Underscores (`_`) in the header names will also be replaced by dashes (`-`) and the header names will be matched case-insensitively. If the response header is not present at all, `nil` will be returned.

This is particularly useful in the context of [header_filter_by_lua](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua) and [header_filter_by_lua_file](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua_file), for example,


    location /test {
        set $footer '';

        proxy_pass http://some-backend;

        header_filter_by_lua '
            if ngx.header["X-My-Header"] == "blah" then
                ngx.var.footer = "some value"
            end
        ';

        echo_after_body $footer;
    }


For multi-value headers, all of the values of header will be collected in order and returned as a Lua table. For example, response headers


    Foo: bar
    Foo: baz


will result in


    {"bar", "baz"}


to be returned when reading `ngx.header.Foo`.

Note that `ngx.header` is not a normal Lua table and as such, it is not possible to iterate through it using the Lua `ipairs` function.

For reading *request* headers, use the [ngx.req.get_headers](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_headers) function instead.

ngx.req.set_uri
---------------
**syntax:** *ngx.req.set_uri(uri, jump?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Rewrite the current request's (parsed) URI by the `uri` argument. The `uri` argument must be a Lua string and cannot be of zero length, or a Lua exception will be thrown.

The optional boolean `jump` argument can trigger location rematch (or location jump) as [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule)'s [rewrite](http://wiki.nginx.org/HttpRewriteModule#rewrite) directive, that is, when `jump` is `true` (default to `false`), this function will never return and it will tell Nginx to try re-searching locations with the new URI value at the later `post-rewrite` phase and jumping to the new location.

Location jump will not be triggered otherwise, and only the current request's URI will be modified, which is also the default behavior. This function will return but with no returned values when the `jump` argument is `false` or absent altogether.

For example, the following nginx config snippet


    rewrite ^ /foo last;


can be coded in Lua like this:


    ngx.req.set_uri("/foo", true)


Similarly, Nginx config


    rewrite ^ /foo break;


can be coded in Lua as


    ngx.req.set_uri("/foo", false)


or equivalently,


    ngx.req.set_uri("/foo")


The `jump` can only be set to `true` in [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) and [rewrite_by_lua_file](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua_file). Use of jump in other contexts is prohibited and will throw out a Lua exception.

A more sophisticated example involving regex substitutions is as follows


    location /test {
        rewrite_by_lua '
            local uri = ngx.re.sub(ngx.var.uri, "^/test/(.*)", "$1", "o")
            ngx.req.set_uri(uri)
        ';
        proxy_pass http://my_backend;
    }


which is functionally equivalent to


    location /test {
        rewrite ^/test/(.*) /$1 break;
        proxy_pass http://my_backend;
    }


Note that it is not possible to use this interface to rewrite URI arguments and that [ngx.req.set_uri_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_uri_args) should be used for this instead. For instance, Nginx config


    rewrite ^ /foo?a=3? last;


can be coded as


    ngx.req.set_uri_args("a=3")
    ngx.req.set_uri("/foo", true)


or


    ngx.req.set_uri_args({a = 3})
    ngx.req.set_uri("/foo", true)


This interface was first introduced in the `v0.3.1rc14` release.

ngx.req.set_uri_args
--------------------
**syntax:** *ngx.req.set_uri_args(args)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Rewrite the current request's URI query arguments by the `args` argument. The `args` argument can be either a Lua string, as in


    ngx.req.set_uri_args("a=3&b=hello%20world")


or a Lua table holding the query arguments' key-value pairs, as in


    ngx.req.set_uri_args({ a = 3, b = "hello world" })


where in the latter case, this method will automatically escape argument keys and values according to the URI escaping rule.

Multi-value arguments are also supported:


    ngx.req.set_uri_args({ a = 3, b = {5, 6} })


which will result in a querystring like `a=3&b=5&b=6`.

This interface was first introduced in the `v0.3.1rc13` release.

See also [ngx.req.set_uri](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_uri).

ngx.req.get_uri_args
--------------------
**syntax:** *args = ngx.req.get_uri_args(max_args?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a Lua table holding all the current request URL query arguments.


    location = /test {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            for key, val in pairs(args) do
                if type(val) == "table" then
                    ngx.say(key, ": ", table.concat(val, ", "))
                else
                    ngx.say(key, ": ", val)
                end
            end
        ';
    }


Then `GET /test?foo=bar&bar=baz&bar=blah` will yield the response body


    foo: bar
    bar: baz, blah


Multiple occurrences of an argument key will result in a table value holding all the values for that key in order.

Keys and values are automatically unescaped according to URI escaping rules. In the settings above, `GET /test?a%20b=1%61+2` will yield:


    a b: 1a 2


Arguments without the `=<value>` parts are treated as boolean arguments. `GET /test?foo&bar` will yield:


    foo: true
    bar: true


That is, they will take Lua boolean values `true`. However, they are different from arguments taking empty string values. `GET /test?foo=&bar=` will give something like


    foo: 
    bar: 


Empty key arguments are discarded. `GET /test?=hello&=world` will yield an empty output for instance.

Updating query arguments via the nginx variable `$args` (or `ngx.var.args` in Lua) at runtime is also supported:


    ngx.var.args = "a=3&b=42"
    local args = ngx.req.get_uri_args()


Here the `args` table will always look like


    {a = 3, b = 42}


regardless of the actual request query string.

Note that a maximum of 100 request arguments are parsed by default (including those with the same name) and that additional request arguments are silently discarded to guard against potential denial of service attacks.

However, the optional `max_args` function argument can be used to override this limit:


    local args = ngx.req.get_uri_args(10)


This argument can be set to zero to remove the limit and to process all request arguments received:


    local args = ngx.req.get_uri_args(0)


Removing the `max_args` cap is strongly discouraged.

ngx.req.get_post_args
---------------------
**syntax:** *ngx.req.get_post_args(max_args?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a Lua table holding all the current request POST query arguments (of the MIME type `application/x-www-form-urlencoded`). Call [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) to read the request body first or turn on the [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) directive to avoid Lua exception errors.


    location = /test {
        content_by_lua '
            ngx.req.read_body()
            local args = ngx.req.get_post_args()
            for key, val in pairs(args) do
                if type(val) == "table" then
                    ngx.say(key, ": ", table.concat(val, ", "))
                else
                    ngx.say(key, ": ", val)
                end
            end
        ';
    }


Then


    # Post request with the body 'foo=bar&bar=baz&bar=blah'
    $ curl --data 'foo=bar&bar=baz&bar=blah' localhost/test


will yield the response body like


    foo: bar
    bar: baz, blah


Multiple occurrences of an argument key will result in a table value holding all of the values for that key in order.

Keys and values will be automatically unescaped according to URI escaping rules. 

With the settings above,


    # POST request with body 'a%20b=1%61+2'
    $ curl -d 'a%20b=1%61+2' localhost/test


will yield:


    a b: 1a 2


Arguments without the `=<value>` parts are treated as boolean arguments. `GET /test?foo&bar` will yield:


    foo: true
    bar: true


That is, they will take Lua boolean values `true`. However, they are different from arguments taking empty string values. `POST /test` with request body `foo=&bar=` will return something like


    foo: 
    bar: 


Empty key arguments are discarded. `POST /test` with body `=hello&=world` will yield empty outputs for instance.

Note that a maximum of 100 request arguments are parsed by default (including those with the same name) and that additional request arguments are silently discarded to guard against potential denial of service attacks.  

However, the optional `max_args` function argument can be used to override this limit:


    local args = ngx.req.get_post_args(10)


This argument can be set to zero to remove the limit and to process all request arguments received:


    local args = ngx.req.get_post_args(0)


Removing the `max_args` cap is strongly discouraged.

ngx.req.get_headers
-------------------
**syntax:** *headers = ngx.req.get_headers(max_headers?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a Lua table holding all the current request headers.


    local h = ngx.req.get_headers()
    for k, v in pairs(h) do
        ...
    end


To read an individual header:


    ngx.say("Host: ", ngx.req.get_headers()["Host"])


Note that the [ngx.var.HEADER](http://wiki.nginx.org/HttpLuaModule#ngx.var.VARIABLE) API call, which uses core [$http_HEADER](http://wiki.nginx.org/HttpCoreModule#.24http_HEADER) variables, may be more preferable for reading individual request headers.

For multiple instances of request headers such as:


    Foo: foo
    Foo: bar
    Foo: baz


the value of `ngx.req.get_headers()["Foo"]` will be a Lua (array) table such as:


    {"foo", "bar", "baz"}


Note that a maximum of 100 request headers are parsed by default (including those with the same name) and that additional request headers are silently discarded to guard against potential denial of service attacks.  

However, the optional `max_headers` function argument can be used to override this limit:


    local args = ngx.req.get_headers(10)


This argument can be set to zero to remove the limit and to process all request headers received:


    local args = ngx.req.get_headers(0)


Removing the `max_headers` cap is strongly discouraged.

ngx.req.set_header
------------------
**syntax:** *ngx.req.set_header(header_name, header_value)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Set the current request's request header named `header_name` to value `header_value`, overriding any existing ones.
None of the current request's subrequests will be affected.

Here is an example of setting the `Content-Length` header:


    ngx.req.set_header("Content-Type", "text/css")


The `header_value` can take an array list of values,
for example,


    ngx.req.set_header("Foo", {"a", "abc"})


will produce two new request headers:


    Foo: a
    Foo: abc


and old `Foo` headers will be overridden if there is any.

When the `header_value` argument is `nil`, the request header will be removed. So


    ngx.req.set_header("X-Foo", nil)


is equivalent to


    ngx.req.clear_header("X-Foo")


ngx.req.read_body
-----------------
**syntax:** *ngx.req.read_body()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Reads the client request body synchronously without blocking the Nginx event loop.


    ngx.req.read_body()
    local args = ngx.req.get_post_args()


If the request body is already read previously by turning on [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) or by using other modules, then this function does not run and returns immediately.

If the request body has already been explicitly discarded, either by the [ngx.req.discard_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.discard_body) function or other modules, this function does not run and returns immediately.

In case of errors, such as connection errors while reading the data, this method will throw out a Lua exception *or* terminate the current request with a 500 status code immediately.

The request body data read using this function can be retrieved later via [ngx.req.get_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_data) or, alternatively, the temporary file name for the body data cached to disk using [ngx.req.get_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_file). This depends on

1. whether the current request body is already larger than the [client_body_buffer_size](http://wiki.nginx.org/HttpCoreModule#client_body_buffer_size),
1. and whether [client_body_in_file_only](http://wiki.nginx.org/HttpCoreModule#client_body_in_file_only) has been switched on.

In cases where current request may have a request body and the request body data is not required, The [ngx.req.discard_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.discard_body) function must be used to explicitly discard the request body to avoid breaking things under HTTP 1.1 keepalive or HTTP 1.1 pipelining.

This function was first introduced in the `v0.3.1rc17` release.

ngx.req.discard_body
--------------------
**syntax:** *ngx.req.discard_body()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Explicitly discard the request body, i.e., read the data on the connection and throw it away immediately. Please note that ignoring request body is not the right way to discard it, and that this function must be called to avoid breaking things under HTTP 1.1 keepalive or HTTP 1.1 pipelining.

This function is an asynchronous call and returns immediately.

If the request body has already been read, this function does nothing and returns immediately.

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body).

ngx.req.get_body_data
---------------------
**syntax:** *data = ngx.req.get_body_data()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Retrieves in-memory request body data. It returns a Lua string rather than a Lua table holding all the parsed query arguments. Use the [ngx.req.get_post_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_post_args) function instead if a Lua table is required.

This function returns `nil` if
1. the request body has not been read,
1. the request body has been read into disk temporary files,
1. or the request body has zero size.

If the request body has not been read yet, call [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) first (or turned on [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) to force this module to read the request body automatically, but this is not recommended).

If the request body has been read into disk files, try calling the [ngx.req.get_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_file) function instead.

To force in-memory request bodies, try setting [client_body_buffer_size](http://wiki.nginx.org/HttpCoreModule#client_body_buffer_size) to the same size value in [client_max_body_size](http://wiki.nginx.org/HttpCoreModule#client_max_body_size).

Note that calling this function instead of using `ngx.var.request_body` or `ngx.var.echo_request-body` is more efficient because it can save one dynamic memory allocation and one data copy.

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.get_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_file).

ngx.req.get_body_file
---------------------
**syntax:** *file_name = ngx.req.get_body_file()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Retrieves the file name for the in-file request body data. Returns `nil` if the request body has not been read or has been read into memory.

The returned file is read only and is usually cleaned up automatically by Nginx's memory pool. It should not be manually modified, renamed, or removed in Lua code.

If the request body has not been read yet, call [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) first (or turned on [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) to force this module to read the request body automatically, but this is not recommended).

If the request body has been read into memory, try calling the [ngx.req.get_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_data) function instead.

To force in-file request bodies, try turning on [client_body_in_file_only](http://wiki.nginx.org/HttpCoreModule#client_body_in_file_only).

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.get_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_data).

ngx.req.set_body_data
---------------------
**syntax:** *ngx.req.set_body_data(data)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Set the current request's request body using the in-memory data specified by the `data` argument.

If the current request's request body has not been read, then it will be properly discarded. When the current request's request body has been read into memory or buffered into a disk file, then the old request body's memory will be freed or the disk file will be cleaned up immediately, respectively.

This function requires patching the Nginx core to function properly because the Nginx core does not allow modifying request bodies by the current design. Here is a patch for Nginx 1.0.11: [nginx-1.0.11-allow_request_body_updating.patch](https://github.com/agentzh/ngx_openresty/blob/master/patches/nginx-1.0.11-allow_request_body_updating.patch), and this patch should be applied cleanly to other releases of Nginx as well.

This patch has already been applied to [ngx_openresty](http://openresty.org/) 1.0.8.17 and above.

This function was first introduced in the `v0.3.1rc18` release.

See also [ngx.req.set_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_body_file).

ngx.req.set_body_file
---------------------
**syntax:** *ngx.req.set_body_file(file_name, auto_clean?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Set the current request's request body using the in-file data specified by the `file_name` argument.

If the optional `auto_clean` argument is given a `true` value, then this file will be automatically removed at request completion or the next time this function or [ngx.req.set_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_body_data) are called in the same request. The `auto_clean` is default to `false`.

Please ensure that the file specified by the `file_name` argument exists and is readable by an Nginx worker process by setting its permission properly to avoid Lua exception errors.

If the current request's request body has not been read, then it will be properly discarded. When the current request's request body has been read into memory or buffered into a disk file, then the old request body's memory will be freed or the disk file will be cleaned up immediately, respectively.

This function requires patching the Nginx core to function properly because the Nginx core does not allow modifying request bodies by the current design. Here is a patch for Nginx 1.0.9: [nginx-1.0.9-allow_request_body_updating.patch](https://github.com/agentzh/ngx_openresty/blob/master/patches/nginx-1.0.9-allow_request_body_updating.patch), and this patch should be applied cleanly to other releases of Nginx as well. 
This patch has already been applied to [ngx_openresty](http://openresty.org/) 1.0.8.17 and above.

This function was first introduced in the `v0.3.1rc18` release.

See also [ngx.req.set_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_body_data).

ngx.req.socket
--------------
**syntax:** *tcpsock, err = ngx.req.socket()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Returns a read-only cosocket object that wraps the downstream connection. Only [receive](http://wiki.nginx.org/HttpLuaModule#tcpsock:receive) and [receiveuntil](http://wiki.nginx.org/HttpLuaModule#tcpsock:receiveuntil) methods are supported on this object.

In case of error, `nil` will be returned as well as a string describing the error.

The socket object returned by this method is usually used to read the current request's body in a streaming fashion. Do not turn on the [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) directive, and do not mix this call with [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) and [ngx.req.discard_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.discard_body).

If there is any request body data that has been preread into the Nginx core's request header buffer, the resulting cosocket object will take care of that automatically. So there will not be any data loss due to potential body data prereading.

This function was first introduced in the `v0.5.0rc1` release.

ngx.req.clear_header
--------------------
**syntax:** *ngx.req.clear_header(header_name)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Clear the current request's request header named `header_name`. None of the current request's subrequests will be affected.

ngx.exec
--------
**syntax:** *ngx.exec(uri, args?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Does an internal redirect to `uri` with `args`.


    ngx.exec('/some-location');
    ngx.exec('/some-location', 'a=3&b=5&c=6');
    ngx.exec('/some-location?a=3&b=5', 'c=6');


Named locations are also supported, but query strings are ignored. For example,


    location /foo {
        content_by_lua '
            ngx.exec("@bar");
        ';
    }
 
    location @bar {
        ...
    }


The optional second `args` can be used to specify extra URI query arguments, for example:


    ngx.exec("/foo", "a=3&b=hello%20world")


Alternatively, a Lua table can be passed for the `args` argument for ngx_lua to carry out URI escaping and string concatenation automatically.


    ngx.exec("/foo", { a = 3, b = "hello world" })


The result is exactly the same as the previous example. The format for the Lua table passed as the `args` argument is identical to the format used in the [ngx.encode_args](http://wiki.nginx.org/HttpLuaModule#ngx.encode_args) method.

Note that this is very different from [ngx.redirect](http://wiki.nginx.org/HttpLuaModule#ngx.redirect) in that
it is just an internal redirect and no new HTTP traffic is involved.

This method never returns.

This method *must* be called before [ngx.send_headers](http://wiki.nginx.org/HttpLuaModule#ngx.send_headers) or explicit response body
outputs by either [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) or [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say).

It's strongly recommended to combine the `return` statement with this call, i.e., `return ngx.exec(...)`.

This method is similar to the [echo_exec](http://wiki.nginx.org/HttpEchoModule#echo_exec) directive of the [HttpEchoModule](http://wiki.nginx.org/HttpEchoModule).

ngx.redirect
------------
**syntax:** *ngx.redirect(uri, status?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Issue an `HTTP 301` or `302` redirection to `uri`.

The optional `status` parameter specifies whether
`301` or `302` to be used. It is `302` (`ngx.HTTP_MOVED_TEMPORARILY`) by default.

Here is an example assuming the current server name is `localhost` and that it is listening on Port 1984:


    return ngx.redirect("/foo")


which is equivalent to


    return ngx.redirect("http://localhost:1984/foo", ngx.HTTP_MOVED_TEMPORARILY)


We can also use the numberical code directly as the second `status` argument:


    return ngx.redirect("/foo", 301)


This method *must* be called before [ngx.send_headers](http://wiki.nginx.org/HttpLuaModule#ngx.send_headers) or explicit response body outputs by either [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) or [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say).

This method never returns.

This method is very much like the [rewrite](http://wiki.nginx.org/HttpRewriteModule#rewrite) directive with the `redirect` modifier in the standard
[HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule), for example, this `nginx.conf` snippet


    rewrite ^ /foo? redirect;  # nginx config


is equivalent to the following Lua code


    return ngx.redirect('/foo');  -- Lua code


while


    rewrite ^ /foo? permanent;  # nginx config


is equivalent to


    return ngx.redirect('/foo', ngx.HTTP_MOVED_PERMANENTLY)  -- Lua code


URI arguments can be specified as well, for example:


    return ngx.redirect('/foo?a=3&b=4')


It's strongly recommended to combine the `return` statement with this call, i.e., `return ngx.redirect(...)`.

ngx.send_headers
----------------
**syntax:** *ngx.send_headers()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Explicitly send out the response headers.

Note that there is normally no need to manually send out response headers as `ngx_lua` will automatically send headers out 
before content is output with [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say) or [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) or when [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) exits normally.

ngx.headers_sent
----------------
**syntax:** *value = ngx.headers_sent*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns `true` if the response headers have been sent (by ngx_lua), and `false` otherwise.

This API was first introduced in ngx_lua v0.3.1rc6.

ngx.print
---------
**syntax:** *ngx.print(...)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Emits arguments concatenated to the HTTP client (as response body). If response headers have not been sent, this function will send headers out first and then output body data.

Lua `nil` values will output `"nil"` strings and Lua boolean values will output `"true"` and `"false"` literal strings respectively.

Nested arrays of strings are permitted and the elements in the arrays will be sent one by one:


    local table = {
        "hello, ",
        {"world: ", true, " or ", false,
            {": ", nil}}
    }
    ngx.print(table)


will yield the output


    hello, world: true or false: nil


Non-array table arguments will cause a Lua exception to be thrown.

The `ngx.null` constant will yield the `"null"` string output.

This is an asynchronous call and will return immediately without waiting for all the data to be written into the system send buffer. To run in synchronous mode, call `ngx.flush(true)` after calling `ngx.print`. This can be particularly useful for streaming output. See [ngx.flush](http://wiki.nginx.org/HttpLuaModule#ngx.flush) for more details.

ngx.say
-------
**syntax:** *ngx.say(...)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Just as [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) but also emit a trailing newline.

ngx.log
-------
**syntax:** *ngx.log(log_level, ...)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Log arguments concatenated to error.log with the given logging level.

Lua `nil` arguments are accepted and result in literal `"nil"` string while Lua booleans result in literal `"true"` or `"false"` string outputs. And the `ngx.null` constant will yield the `"null"` string output.

The `log_level` argument can take constants like `ngx.ERR` and `ngx.WARN`. Check out [Nginx log level constants](http://wiki.nginx.org/HttpLuaModule#Nginx_log_level_constants) for details.

There is a hard-coded length limitation on the error messages in the Nginx core. It is `2048` bytes at most, including the trailing newlines and the leading timestamps. You can manually modify this limit by modifying the `NGX_MAX_ERROR_STR` macro definition in the `src/core/ngx_log.h` file in the Nginx source tree. If the message size exceeds this limit, the Nginx core will truncate the message text automatically.

ngx.flush
---------
**syntax:** *ngx.flush(wait?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Flushes response output to the client. 

`ngx.flush` accepts an optional boolean `wait` argument (Default: `false`) first introduced in the `v0.3.1rc34` release. When called with the default argument, it issues an asynchronous call (Returns immediately without waiting for output data to be written into the system send buffer). Calling the function with the `wait` argument set to `true` switches to synchronous mode. 

In synchronous mode, the function will not return until all output data has been written into the system send buffer or until the [send_timeout](http://wiki.nginx.org/HttpCoreModule#send_timeout) setting has expired. Note that using the Lua coroutine mechanism means that this function does not block the Nginx event loop even in the synchronous mode.

When `ngx.flush(true)` is called immediately after [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) or [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say), it causes the latter functions to run in synchronous mode. This can be particularly useful for streaming output.

Note that `ngx.flush` is non functional when in the HTTP 1.0 output buffering mode. See [HTTP 1.0 support](http://wiki.nginx.org/HttpLuaModule#HTTP_1.0_support).

ngx.exit
--------
**syntax:** *ngx.exit(status)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

When `status >= 200` (i.e., `ngx.HTTP_OK` and above), it will interrupt the execution of the current request and return status code to nginx.

When `status == 0` (i.e., `ngx.OK`), it will only quit the current phase handler (or the content handler if the [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) directive is used) and continue to run later phases (if any) for the current request.

The `status` argument can be `ngx.OK`, `ngx.ERROR`, `ngx.HTTP_NOT_FOUND`,
`ngx.HTTP_MOVED_TEMPORARILY`, or other [HTTP status constants](http://wiki.nginx.org/HttpLuaModule#HTTP_status_constants).

To return an error page with custom contents, use code snippets like this:


    ngx.status = ngx.HTTP_GONE
    ngx.say("This is our own content")
    -- to cause quit the whole request rather than the current phase handler
    ngx.exit(ngx.HTTP_OK)


The effect in action:


    $ curl -i http://localhost/test
    HTTP/1.1 410 Gone
    Server: nginx/1.0.6
    Date: Thu, 15 Sep 2011 00:51:48 GMT
    Content-Type: text/plain
    Transfer-Encoding: chunked
    Connection: keep-alive

    This is our own content


Number literals can be used directly as the argument, for instance,


    ngx.exit(501)


Note that while this method accepts all [HTTP status constants](http://wiki.nginx.org/HttpLuaModule#HTTP_status_constants) as input, it only accepts `NGX_OK` and `NGX_ERROR` of the [core constants](http://wiki.nginx.org/HttpLuaModule#core_constants).

It's strongly recommended to combine the `return` statement with this call, i.e., `return ngx.exit(...)`.

ngx.eof
-------
**syntax:** *ngx.eof()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Explicitly specify the end of the response output stream.

ngx.escape_uri
--------------
**syntax:** *newstr = ngx.escape_uri(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Escape `str` as a URI component.

ngx.unescape_uri
----------------
**syntax:** *newstr = ngx.unescape_uri(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Unescape `str` as an escaped URI component.

For example,


    ngx.say(ngx.unescape_uri("b%20r56+7"))


gives the output


    b r56 7


ngx.encode_args
---------------
**syntax:** *str = ngx.encode_args(table)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Encode the Lua table to a query args string according to the URI encoded rules.

For example,


    ngx.encode_args({foo = 3, ["b r"] = "hello world"})


yields


    foo=3&b%20r=hello%20world


The table keys must be Lua strings.

Multi-value query args are also supported. Just use a Lua table for the arg's value, for example:


    ngx.encode_args({baz = {32, "hello"}})


gives


    baz=32&baz=hello


If the value table is empty and the effect is equivalent to the `nil` value.

Boolean argument values are also supported, for instance,


    ngx.encode_args({a = true, b = 1})


yields


    a&b=1


If the argument value is `false`, then the effect is equivalent to the `nil` value.

This method was first introduced in the `v0.3.1rc27` release.

ngx.decode_args
---------------
**syntax:** *table = ngx.decode_args(str, max_args?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Decodes a URI encoded query-string into a Lua table. This is the inverse function of [ngx.encode_args](http://wiki.nginx.org/HttpLuaModule#ngx.encode_args).

The optional `max_args` argument can be used to specify the maximalnumber of arguments parsed from the `str` argument. By default, a maximum of 100 request arguments are parsed (including those with the same name) and that additional URI arguments are silently discarded to guard against potential denial of service attacks.

This argument can be set to zero to remove the limit and to process all request arguments received:


    local args = ngx.decode_args(str, 0)


Removing the `max_args` cap is strongly discouraged.

This method was introduced in the `v0.5.0rc29`.

ngx.encode_base64
-----------------
**syntax:** *newstr = ngx.encode_base64(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Encode `str` to a base64 digest.

ngx.decode_base64
-----------------
**syntax:** *newstr = ngx.decode_base64(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Decodes the `str` argument as a base64 digest to the raw form. Returns `nil` if `str` is not well formed.

ngx.crc32_short
---------------
**syntax:** *intval = ngx.crc32_short(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Calculates the CRC-32 (Cyclic Redundancy Code) digest for the `str` argument.

This method performs better on relatively short `str` inputs (i.e., less than 30 ~ 60 bytes), as compared to [ngx.crc32_long](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_long). The result is exactly the same as [ngx.crc32_long](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_long).

Behind the scene, it is just a thin wrapper around the `ngx_crc32_short` function defined in the Nginx core.

This API was first introduced in the `v0.3.1rc8` release.

ngx.crc32_long
--------------
**syntax:** *intval = ngx.crc32_long(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Calculates the CRC-32 (Cyclic Redundancy Code) digest for the `str` argument.

This method performs better on relatively long `str` inputs (i.e., longer than 30 ~ 60 bytes), as compared to [ngx.crc32_short](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_short).  The result is exactly the same as [ngx.crc32_short](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_short).

Behind the scene, it is just a thin wrapper around the `ngx_crc32_long` function defined in the Nginx core.

This API was first introduced in the `v0.3.1rc8` release.

ngx.hmac_sha1
-------------
**syntax:** *digest = ngx.hmac_sha1(secret_key, str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Computes the [HMAC-SHA1](http://en.wikipedia.org/wiki/HMAC) digest of the argument `str` and turns the result using the secret key `<secret_key>`.

The raw binary form of the `HMAC-SHA1` digest will be generated, use [ngx.encode_base64](http://wiki.nginx.org/HttpLuaModule#ngx.encode_base64), for example, to encode the result to a textual representation if desired.

For example,


    local key = "thisisverysecretstuff"
    local src = "some string we want to sign"
    local digest = ngx.hmac_sha1(key, src)
    ngx.say(ngx.encode_base64(digest))


yields the output


    R/pvxzHC4NLtj7S+kXFg/NePTmk=


This API requires the OpenSSL library enabled in the Nignx build (usually by passing the `--with-http_ssl_module` option to the `./configure` script).

This function was first introduced in the `v0.3.1rc29` release.

ngx.md5
-------
**syntax:** *digest = ngx.md5(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the hexadecimal representation of the MD5 digest of the `str` argument.

For example,


    location = /md5 {
        content_by_lua 'ngx.say(ngx.md5("hello"))';
    }


yields the output


    5d41402abc4b2a76b9719d911017c592


See [ngx.md5_bin](http://wiki.nginx.org/HttpLuaModule#ngx.md5_bin) if the raw binary MD5 digest is required.

ngx.md5_bin
-----------
**syntax:** *digest = ngx.md5_bin(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the binary form of the MD5 digest of the `str` argument.

See [ngx.md5](http://wiki.nginx.org/HttpLuaModule#ngx.md5) if the hexadecimal form of the MD5 digest is required.

ngx.sha1_bin
------------
**syntax:** *digest = ngx.sha1_bin(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the binary form of the SHA-1 digest of the `str` argument.

This function requires enabling SHA-1 support in your Nginx build (usually you just need to install OpenSSL to your system while building Nginx).

This function was first introduced in the `v0.5.0rc6`.

ngx.today
---------
**syntax:** *str = ngx.today()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns current date (in the format `yyyy-mm-dd`) from the nginx cached time (no syscall involved unlike Lua's date library).

This is the local time.

ngx.time
--------
**syntax:** *secs = ngx.time()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the elapsed seconds from the epoch for the current timestamp from the nginx cached time (no syscall involved unlike Lua's date library).

Updates of the Nginx time cache an be forced by calling [ngx.update_time](http://wiki.nginx.org/HttpLuaModule#ngx.update_time) first.

ngx.now
-------
**syntax:** *secs = ngx.now()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a floating-point number for the elapsed time in seconds (including microseconds as the decimal part) from the epoch for the current timestamp from the nginx cached time (no syscall involved unlike Lua's date library).

Use the Nginx core [timer_resolution](http://wiki.nginx.org/CoreModule#timer_resolution) directive to adjust the accuracy or forcibly update the Nginx time cache by calling [ngx.update_time](http://wiki.nginx.org/HttpLuaModule#ngx.update_time) first.

This API was first introduced in `v0.3.1rc32`.

ngx.update_time
---------------
**syntax:** *ngx.update_time()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Forcibly updates the Nginx current time cache. This call involves a syscall and thus has some overhead, so do not abuse it.

This API was first introduced in `v0.3.1rc32`.

ngx.localtime
-------------
**syntax:** *str = ngx.localtime()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the current timestamp (in the format `yyyy-mm-dd hh:mm:ss`) of the nginx cached time (no syscall involved unlike Lua's [os.date](http://www.lua.org/manual/5.1/manual.html#pdf-os.date) function).

This is the local time.

ngx.utctime
-----------
**syntax:** *str = ngx.utctime()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns the current timestamp (in the format `yyyy-mm-dd hh:mm:ss`) of the nginx cached time (no syscall involved unlike Lua's [os.date](http://www.lua.org/manual/5.1/manual.html#pdf-os.date) function).

This is the UTC time.

ngx.cookie_time
---------------
**syntax:** *str = ngx.cookie_time(sec)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a formated string can be used as the cookie expiration time. The parameter `sec` is the timestamp in seconds (like those returned from [ngx.time](http://wiki.nginx.org/HttpLuaModule#ngx.time)).


    ngx.say(ngx.cookie_time(1290079655))
        -- yields "Thu, 18-Nov-10 11:27:35 GMT"


ngx.http_time
-------------
**syntax:** *str = ngx.http_time(sec)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns a formated string can be used as the http header time (for example, being used in `Last-Modified` header). The parameter `sec` is the timestamp in seconds (like those returned from [ngx.time](http://wiki.nginx.org/HttpLuaModule#ngx.time)).


    ngx.say(ngx.http_time(1290079655))
        -- yields "Thu, 18 Nov 10 11:27:35 GMT"


ngx.parse_http_time
-------------------
**syntax:** *sec = ngx.parse_http_time(str)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Parse the http time string (as returned by [ngx.http_time](http://wiki.nginx.org/HttpLuaModule#ngx.http_time)) into seconds. Returns the seconds or `nil` if the input string is in bad forms.


    local time = ngx.parse_http_time("Thu, 18 Nov 10 11:27:35 GMT")
    if time == nil then
        ...
    end


ngx.is_subrequest
-----------------
**syntax:** *value = ngx.is_subrequest*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Returns `true` if the current request is an nginx subrequest, or `false` otherwise.

ngx.re.match
------------
**syntax:** *captures = ngx.re.match(subject, regex, options?, ctx?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Matches the `subject` string using the Perl-compatible regular expression `regex` with the optional `options`.

Only the first occurrence of the match is returned, or `nil` if no match is found. In case of fatal errors, like seeing bad `UTF-8` sequences in `UTF-8` mode, a Lua exception will be raised.

When a match is found, a Lua table `captures` is returned, where `captures[0]` holds the whole substring being matched, and `captures[1]` holds the first parenthesized subpattern's capturing, `captures[2]` the second, and so on.


    local m = ngx.re.match("hello, 1234", "[0-9]+")
    -- m[0] == "1234"



    local m = ngx.re.match("hello, 1234", "([0-9])[0-9]+")
    -- m[0] == "1234"
    -- m[1] == "1"


Unmatched subpatterns will have `nil` values in their `captures` table fields.


    local m = ngx.re.match("hello, world", "(world)|(hello)")
    -- m[0] == "hello"
    -- m[1] == nil
    -- m[2] == "hello"


Specify `options` to control how the match operation will be performed. The following option characters are supported:


    a             anchored mode (only match from the beginning)

    d             enable the DFA mode (or the longest token match semantics).
                  this requires PCRE 6.0+ or else a Lua exception will be thrown.
                  first introduced in ngx_lua v0.3.1rc30.

    i             caseless mode (similar to Perl's /i modifier)

    j             enable PCRE JIT compilation, this requires PCRE 8.21+ which
                  must be built with the --enable-jit option.
                  for optimum performance, this option should always be used  
                  together with the 'o' option.
                  first introduced in ngx_lua v0.3.1rc30.

    m             multi-line mode (similar to Perl's /m modifier)

    o             compile-once mode (similar to Perl's /o modifer),
                  to enable the worker-process-level compiled-regex cache

    s             single-line mode (similar to Perl's /s modifier)

    u             UTF-8 mode. this requires PCRE to be built with
                  the --enable-utf8 option or else a Lua exception will be thrown.

    x             extended mode (similar to Perl's /x modifier)


These options can be combined:


    local m = ngx.re.match("hello, world", "HEL LO", "ix")
    -- m[0] == "hello"



    local m = ngx.re.match("hello, 美好生活", "HELLO, (.{2})", "iu")
    -- m[0] == "hello, 美好"
    -- m[1] == "美好"


The `o` option is useful for performance tuning, because the regex pattern in question will only be compiled once, cached in the worker-process level, and shared among all requests in the current Nginx worker process. The upper limit of the regex cache can be tuned via the [lua_regex_cache_max_entries](http://wiki.nginx.org/HttpLuaModule#lua_regex_cache_max_entries) directive.

The optional fourth argument, `ctx`, can be a Lua table holding an optional `pos` field. When the `pos` field in the `ctx` table argument is specified, `ngx.re.match` will start matching from that offset. Regardless of the presence of the `pos` field in the `ctx` table, `ngx.re.match` will always set this `pos` field to the position *after* the substring matched by the whole pattern in case of a successful match. When match fails, the `ctx` table will be left intact.


    local ctx = {}
    local m = ngx.re.match("1234, hello", "[0-9]+", "", ctx)
         -- m[0] = "1234"
         -- ctx.pos == 4



    local ctx = { pos = 2 }
    local m = ngx.re.match("1234, hello", "[0-9]+", "", ctx)
         -- m[0] = "34"
         -- ctx.pos == 4


The `ctx` table argument combined with the `a` regex modifier can be used to construct a lexer atop `ngx.re.match`.

Note that, the `options` argument is not optional when the `ctx` argument is specified and that the empty Lua string (`""`) must be used as placeholder for `options` if no meaningful regex options are required.

This method requires the PCRE library enabled in Nginx.  ([Known Issue With Special PCRE Sequences](http://wiki.nginx.org/HttpLuaModule#Special_PCRE_Sequences)).

To confirm that PCRE JIT is indeed enabled, it's required to enable the debugging logs in your Nginx build (by passing the `--with-debug` option to your Nginx or ngx_openresty's `./configure` script) and enable the "debug" error log level in your `error_log` directive, and then you can see the following message if PCRE JIT actually works:


    pcre JIT compiling result: 1


This feature was introduced in the `v0.2.1rc11` release.

ngx.re.gmatch
-------------
**syntax:** *iterator = ngx.re.gmatch(subject, regex, options?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Similar to [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match), but returns a Lua iterator instead, so as to let the user programmer iterate all the matches over the `<subject>` string argument with the PCRE `regex`.

Here is a small exmple to demonstrate its basic usage:


    local iterator = ngx.re.gmatch("hello, world!", "([a-z]+)", "i")
    local m
    m = iterator()    -- m[0] == m[1] == "hello"
    m = iterator()    -- m[0] == m[1] == "world"
    m = iterator()    -- m == nil


More often we just put it into a Lua `for` loop:


    for m in ngx.re.gmatch("hello, world!", "([a-z]+)", "i")
        ngx.say(m[0])
        ngx.say(m[1])
    end


The optional `options` argument takes exactly the same semantics as the [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match) method.

The current implementation requires that the iterator returned should only be used in a single request. That is, one should *not* assign it to a variable belonging to persistent namespace like a Lua package.

This method requires the PCRE library enabled in Nginx.  ([Known Issue With Special PCRE Sequences](http://wiki.nginx.org/HttpLuaModule#Special_PCRE_Sequences)).

This feature was first introduced in the `v0.2.1rc12` release.

ngx.re.sub
----------
**syntax:** *newstr, n = ngx.re.sub(subject, regex, replace, options?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Substitutes the first match of the Perl-compatible regular expression `regex` on the `subject` argument string with the string or function argument `replace`. The optional `options` argument has exactly the same meaning as in [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match).

This method returns the resulting new string as well as the number of successful substitutions, or throw out a Lua exception when an error occurred (syntax errors in the `<replace>` string argument, for example).

When the `replace` is a string, then it is treated as a special template for string replacement. For example,


    local newstr, n = ngx.re.sub("hello, 1234", "([0-9])[0-9]", "[$0][$1]")
        -- newstr == "hello, [12][1]34"
        -- n == 1


where `$0` referring to the whole substring matched by the pattern and `$1` referring to the first parenthesized capturing substring.

Curly braces can also be used to disambiguate variable names from the background string literals: 


    local newstr, n = ngx.re.sub("hello, 1234", "[0-9]", "${0}00")
        -- newstr == "hello, 10034"
        -- n == 1


Literal dollar sign characters (`$`) in the `replace` string argument can be escaped by another dollar sign, for instance,


    local newstr, n = ngx.re.sub("hello, 1234", "[0-9]", "$$")
        -- newstr == "hello, $234"
        -- n == 1


Do not use backlashes to escape dollar signs; it will not work as expected.

When the `replace` argument is of type "function", then it will be invoked with the "match table" as the argument to generate the replace string literal for substitution. The "match table" fed into the `replace` function is exactly the same as the return value of [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match). Here is an example:


    local func = function (m)
        return "[" .. m[0] .. "][" .. m[1] .. "]"
    end
    local newstr, n = ngx.re.sub("hello, 1234", "( [0-9] ) [0-9]", func, "x")
        -- newstr == "hello, [12][1]34"
        -- n == 1


The dollar sign characters in the return value of the `replace` function argument are not special at all.

This method requires the PCRE library enabled in Nginx.  ([Known Issue With Special PCRE Sequences](http://wiki.nginx.org/HttpLuaModule#Special_PCRE_Sequences)).

This feature was first introduced in the `v0.2.1rc13` release.

ngx.re.gsub
-----------
**syntax:** *newstr, n = ngx.re.gsub(subject, regex, replace, options?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Just like [ngx.re.sub](http://wiki.nginx.org/HttpLuaModule#ngx.re.sub), but does global substitution.

Here is some examples:


    local newstr, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", "[$0,$1]", "i")
        -- newstr == "[hello,h], [world,w]"
        -- n == 2



    local func = function (m)
        return "[" .. m[0] .. "," .. m[1] .. "]"
    end
    local newstr, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", func, "i")
        -- newstr == "[hello,h], [world,w]"
        -- n == 2


This method requires the PCRE library enabled in Nginx.  ([Known Issue With Special PCRE Sequences](http://wiki.nginx.org/HttpLuaModule#Special_PCRE_Sequences)).

This feature was first introduced in the `v0.2.1rc15` release.

ngx.shared.DICT
---------------
**syntax:** *dict = ngx.shared.DICT*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Fetching the shm-based Lua dictionary object for the shared memory zone named `DICT` defined by the [lua_shared_dict](http://wiki.nginx.org/HttpLuaModule#lua_shared_dict) directive.

The resulting object `dict` has the following methods:

* [get](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.get)
* [set](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.set)
* [add](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.add)
* [replace](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.replace)
* [incr](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.incr)
* [delete](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.delete)
* [flush_all](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.flush_all)

Here is an example:


    http {
        lua_shared_dict dogs 10m;
        server {
            location /set {
                content_by_lua '
                    local dogs = ngx.shared.dogs
                    dogs:set("Jim", 8)
                    ngx.say("STORED")
                ';
            }
            location /get {
                content_by_lua '
                    local dogs = ngx.shared.dogs
                    ngx.say(dogs:get("Jim"))
                ';
            }
        }
    }


Let us test it:


    $ curl localhost/set
    STORED

    $ curl localhost/get
    8

    $ curl localhost/get
    8


The number `8` will be consistently output when accessing `/get` regardless of how many Nginx workers there are because the `dogs` dictionary resides in the shared memory and visible to *all* of the worker processes.

The shared dictionary will retain its contents through a server config reload (either by sending the `HUP` signal to the Nginx process or by using the `-s reload` command-line option).

The contents in the dictionary storage will be lost, however, when the Nginx server quits.

This feature was first introduced in the `v0.3.1rc22` release.

ngx.shared.DICT.get
-------------------
**syntax:** *value, flags = ngx.shared.DICT:get(key)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Retrieving the value in the dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) for the key `key`. If the key does not exist or has been expired, then `nil` will be returned.

The value returned will have the original data type when they were inserted into the dictionary, for example, Lua booleans, numbers, or strings.

The first argument to this method must be the dictionary object itself, for example,


    local cats = ngx.shared.cats
    local value, flags = cats.get(cats, "Marry")


or use Lua's syntactic sugar for method calls:


    local cats = ngx.shared.cats
    local value, flags = cats:get("Marry")


These two forms are fundamentally equivalent.

If the user flags is `0` (the default), then no flags value will be returned.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.set
-------------------
**syntax:** *success, err, forcible = ngx.shared.DICT:set(key, value, exptime?, flags?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Unconditionally sets a key-value pair into the shm-based dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT). Returns three values:

* `success`: boolean value to indicate whether the key-value pair is stored or not.
* `err`: textual error message, can be `"no memory"`.
* `forcible`: a boolean value to indicate whether other valid items have been removed forcibly when out of storage in the shared memory zone.

The `value` argument inserted can be Lua booleans, numbers, strings, or `nil`. Their value type will also be stored into the dictionary and the same data type can be retrieved later via the [get](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.get) method.

The optional `exptime` argument specifies expiration time (in seconds) for the inserted key-value pair. The time resolution is `0.001` seconds. If the `exptime` takes the value `0` (which is the default), then the item will never be expired.

The optional `flags` argument specifies a user flags value associated with the entry to be stored. It can also be retrieved later with the value. The user flags is stored as an unsigned 32-bit integer internally. Defaults to `0`. The user flags argument was first introduced in the `v0.5.0rc2` release.

When it fails to allocate memory for the current key-value item, then `set` will try removing existing items in the storage according to the Least-Recently Used (LRU) algorithm. Note that, LRU takes priority over expiration time here. If up to tens of existing items have been removed and the storage left is still insufficient (either due to the total capacity limit specified by [lua_shared_dict](http://wiki.nginx.org/HttpLuaModule#lua_shared_dict) or memory segmentation), then the `err` return value will be `no memory` and `success` will be `false`.

If this method succeeds in storing the current item by forcibly removing other not-yet-expired items in the dictionary via LRU, the `forcible` return value will be `true`. If it stores the item without forcibly removing other valid items, then the return value `forcible` will be `false`.

The first argument to this method must be the dictionary object itself, for example,


    local cats = ngx.shared.cats
    local succ, err, forcible = cats.set(cats, "Marry", "it is a nice cat!")


or use Lua's syntactic sugar for method calls:


    local cats = ngx.shared.cats
    local succ, err, forcible = cats:set("Marry", "it is a nice cat!")


These two forms are fundamentally equivalent.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.add
-------------------
**syntax:** *success, err, forcible = ngx.shared.DICT:add(key, value, exptime?, flags?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Just like the [set](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.set) method, but only stores the key-value pair into the dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) if the key does *not* exist.

If the `key` argument already exists in the dictionary (and not expired for sure), the `success` return value will be `false` and the `err` return value will be `"exists"`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.replace
-----------------------
**syntax:** *success, err, forcible = ngx.shared.DICT:replace(key, value, exptime?, flags?)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Just like the [set](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT.set) method, but only stores the key-value pair into the dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) if the key *does* exist.

If the `key` argument does *not* exist in the dictionary (or expired already), the `success` return value will be `false` and the `err` return value will be `"not found"`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.delete
----------------------
**syntax:** *ngx.shared.DICT:delete(key)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Unconditionally removes the key-value pair from the shm-based dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

It is equivalent to `ngx.shared.DICT:set(key, nil)`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.incr
--------------------
**syntax:** *newval, err = ngx.shared.DICT:incr(key, value)*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Increments the (numerical) value for `key` in the shm-based dictionary [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) by the step value `value`. Returns the new resulting number if the operation is successfully completed or `nil` and an error message otherwise.

The key must already exist in the dictionary, otherwise it will return `nil` and `"not found"`.

If the original value is not a valid Lua number in the dictionary, it will return `nil` and `"not a number"`.

The `value` argument can be any valid Lua numbers, like negative numbers or floating-point numbers.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.shared.DICT.flush_all
-------------------------
**syntax:** *ngx.shared.DICT:flush_all()*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

Flushes out all the items in the dictionary.

This feature was first introduced in the `v0.5.0rc17` release.

See also [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).

ngx.socket.tcp
--------------
**syntax:** *tcpsock = ngx.socket.tcp()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Creates and returns a TCP (or Unix Domain) socket object (also known as the "cosocket" object). The following methods are supported on this object:

* [connect](http://wiki.nginx.org/HttpLuaModule#tcpsock:connect)
* [send](http://wiki.nginx.org/HttpLuaModule#tcpsock:send)
* [receive](http://wiki.nginx.org/HttpLuaModule#tcpsock:receive)
* [close](http://wiki.nginx.org/HttpLuaModule#tcpsock:close)
* [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout)
* [setoption](http://wiki.nginx.org/HttpLuaModule#tcpsock:setoption)
* [receiveuntil](http://wiki.nginx.org/HttpLuaModule#tcpsock:receiveuntil)
* [setkeepalive](http://wiki.nginx.org/HttpLuaModule#tcpsock:setkeepalive)
* [getreusedtimes](http://wiki.nginx.org/HttpLuaModule#tcpsock:getreusedtimes)

It is intended to be compatible with the TCP API of the [LuaSocket](http://w3.impa.br/~diego/software/luasocket/tcp.html) library but is 100% nonblocking out of the box. Also, we introduce some new APIs to provide more functionalities.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:connect
---------------
**syntax:** *ok, err = tcpsock:connect(host, port)*

**syntax:** *ok, err = tcpsock:connect("unix:/path/to/unix-domain.socket")*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Attempts to connect a TCP socket object to a remote server or to a unix domain socket file nonblockingly.

Before actually resolving the host name and connecting to the remote backend, this method will always look up the connection pool for matched idle connections created by previous calls of this method (or the [ngx.socket.connect](http://wiki.nginx.org/HttpLuaModule#ngx.socket.connect) function).

Both IP addresses and domain names can be specified as the `host` argument. In case of domain names, this method will use Nginx core's dynamic resolver to parse the domain name nonblockingly and it is required to configure the [resolver](http://wiki.nginx.org/HttpCoreModule#resolver) directive in your `nginx.conf` file like this:


    resolver 8.8.8.8;  # use Google's public DNS nameserver


If the nameserver returns multiple IP addresses for the host name, this method will pick up one randomly.

In case of error, the method returns `nil` followed by a string describing the error. In case of success, the method returns `1`.

Here is an example for connecting to a TCP server:


    location /test {
        resolver 8.8.8.8;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("www.google.com", 80)
            if not ok then
                ngx.say("failed to connect to google: ", err)
                return
            end
            ngx.say("successfully connected to google!")
            sock:close()
        ';
    }


Connecting to a Unix Domain Socket file is also possible:


    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:/tmp/memcached.sock")
    if not ok then
        ngx.say("failed to connect to the memcached unix domain socket: ", err)
        return
    end


assuming that your memcached (or something else) is listening on the unix domain socket file `/tmp/memcached.sock`.

Timeout for the connecting operation is controlled by the [lua_socket_connect_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_connect_timeout) config directive and the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method. And the latter takes priority. For example:


    local sock = ngx.socket.tcp()
    sock:settimeout(1000)  -- one second timeout
    local ok, err = sock:connect(host, port)


It is important here to call the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method *before* calling this method.

Calling this method on an already connected socket object will cause the original connection to be closed first.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:send
------------
**syntax:** *bytes, err = tcpsock:send(data)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Sends data nonblockingly on the current TCP or Unix Domain Socket connection.

This method is a synchronous operation that will not return until *all* the data has been flushed into the system socket send buffer or an error occurs.

In case of success, it returns the total number of bytes that have been sent. Otherwise, it returns `nil` and a string describing the error.

The input argument `data` can either be a Lua string or a (nested) Lua table holding string fragments. In case of table arguments, this method will automatically copy all the string elements piece by piece to the underlying Nginx socket send buffers, which is usually optimal than doing string concatenation operations on the Lua land.

Timeout for the sending operation is controlled by the [lua_socket_send_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_send_timeout) config directive and the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method. And the latter takes priority. For example:


    sock:settimeout(1000)  -- one second timeout
    local bytes, err = sock:send(request)


It is important here to call the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method *before* calling this method.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:receive
---------------
**syntax:** *data, err, partial = tcpsock:receive(size)*

**syntax:** *data, err, partial = tcpsock:receive(pattern?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Receives data from the connected socket according to the reading pattern or size.

This method is a synchronous operation just like the [send](http://wiki.nginx.org/HttpLuaModule#tcpsock:send) method and is 100% nonblocking.

In case of success, it returns the data received; in case of error, it returns `nil` with a string describing the error and the partial data received so far.

If a number-like argument is specified (including strings that look like numbers), then it is interpreted as a size. This method will not return until it reads exactly this size of data or an error occurs.

If a non-number-like string argument is specified, then it is interpreted as a "pattern". The following patterns are supported:

* `'*a'`: reads from the socket until the connection is closed. No end-of-line translation is performed;
* `'*l'`: reads a line of text from the socket. The line is terminated by a `Line Feed` (LF) character (ASCII 10), optionally preceded by a `Carriage Return` (CR) character (ASCII 13). The CR and LF characters are not included in the returned line. In fact, all CR characters are ignored by the pattern.

If no argument is specified, then it is assumed to be the pattern `'*l'`, that is, the line reading pattern.

Timeout for the reading operation is controlled by the [lua_socket_read_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_read_timeout) config directive and the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method. And the latter takes priority. For example:


    sock:settimeout(1000)  -- one second timeout
    local line, err, partial = sock:receive()
    if not line then
        ngx.say("failed to read a line: ", err)
        return
    end
    ngx.say("successfully read a line: ", line)


It is important here to call the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method *before* calling this method.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:receiveuntil
--------------------
**syntax:** *iterator = tcpsock:receiveuntil(pattern)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

This method returns an iterator Lua function that can be called to read the data stream until it sees the specified pattern or an error occurs.

Here is an example for using this method to read a data stream with the boundary sequence `--abcedhb`:


    local reader = sock:receiveuntil("\r\n--abcedhb")
    local data, err, partial = reader()
    if not data then
        ngx.say("failed to read the data stream: ", err)
    end
    ngx.say("read the data stream: ", data)


When called without any argument, the iterator function returns the received data right *before* the specified pattern string in the incoming data stream. So for the example above, if the incoming data stream is `'hello, world! -agentzh\r\n--abcedhb blah blah'`, then the string `'hello, world! -agentzh'` will be returned.

In case of error, the iterator function will return `nil` along with a string describing the error and the partial data bytes that have been read so far.

The iterator function can be called multiple times and can be mixed safely with other cosocket method calls or other iterator function calls.

The iterator function behaves differently (i.e., like a real iterator) when it is called with a `size` argument. That is, it will read that `size` of data at earch invocation and will return `nil` at the last invocation (either sees the boundary pattern or meets an error). For the last successful invocation of the iterator function, the `err` return value will be `nil` too. The iterator function will automatically reset after its last successful invocation that returns `nil` data and `nil` error. Consider the following example:


    local reader = sock:receiveuntil("\r\n--abcedhb")

    while true then
        local data, err, partial = reader(4)
        if not data then
            if err then
                ngx.say("failed to read the data stream: ", err)
                break
            end

            ngx.say("read done")
            break
        end
        ngx.say("read chunk: [", data, "]")
    end


Then for the incoming data stream `'hello, world! -agentzh\r\n--abcedhb blah blah'`, we shall get the following output from the sample code above:


    read chunk: [hell]
    read chunk: [o, w]
    read chunk: [orld]
    read chunk: [! -a]
    read chunk: [gent]
    read chunk: [zh]
    read done


Note that, the actual data returned *might* be a little longer than the size limit specified by the `size` argument when your boundary pattern has ambiguity for streaming parsing. Near the boundary of the data stream, the data string actually returned could also be shorter than the size limit.

Timeout for the iterator function's reading operation is controlled by the [lua_socket_read_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_read_timeout) config directive and the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method. And the latter takes priority. For example:


    local readline = sock:receiveuntil("\r\n")

    sock:settimeout(1000)  -- one second timeout
    line, err, partial = readline()
    if not line then
        ngx.say("failed to read a line: ", err)
        return
    end
    ngx.say("successfully read a line: ", line)


It is important here to call the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method *before* calling the iterator function (note that the `receiveuntil` call is irrelevant here).

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:close
-------------
**syntax:** *ok, err = tcpsock:close()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Closes the current TCP or Unix Domain socket. It returns the `1` in case of success and returns `nil` with a string describing the error otherwise.

For socket objects that have invoked the [setkeepalive](http://wiki.nginx.org/HttpLuaModule#tcpsock:setkeepalive) method, there is no need to call this method on it because the socket object is already closed (and the current connection is saved into the builtin connection pool).

For socket objects that have not invoked [setkeepalive](http://wiki.nginx.org/HttpLuaModule#tcpsock:setkeepalive), they (and their connections) will be automatically closed when the socket object is released by the Lua GC (Garbage Collector) or the current client HTTP request finishes processing.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:settimeout
------------------
**syntax:** *tcpsock:settimeout(time)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Set the timeout value in milliseconds for subsequent socket operations ([connect](http://wiki.nginx.org/HttpLuaModule#tcpsock:connect), [receive](http://wiki.nginx.org/HttpLuaModule#tcpsock:receive), and iterators returned from [receiveuntil](http://wiki.nginx.org/HttpLuaModule#tcpsock:receiveuntil)).

Settings done by this method takes priority over those config directives, i.e., [lua_socket_connect_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_connect_timeout), [lua_socket_send_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_send_timeout), and [lua_socket_read_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_read_timeout).

Note that this method does *not* affect the [lua_socket_keepalive_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_keepalive_timeout) setting; the `timeout` argument to the [setkeepalive](http://wiki.nginx.org/HttpLuaModule#tcpsock:setkeepalive) method should be used for this purpose instead.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:setoption
-----------------
**syntax:** *tcpsock:setoption(option, value?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

This function is added for [LuaSocket](http://w3.impa.br/~diego/software/luasocket/tcp.html) API compatibility and does nothing for now. Its functionality will be implemented in future.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:setkeepalive
--------------------
**syntax:** *ok, err = tcpsock:setkeepalive(timeout?, size?)*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

Puts the current socket's connection into the cosocket built-in connection pool and keep it alive until other [connect](http://wiki.nginx.org/HttpLuaModule#tcpsock:connect) method calls request it or the associated maximal idle timeout is expired.

The first optional argument, `timeout`, can be used to specify the maximal idle timeout (in milliseconds) for the current connection. If omitted, the default setting in the [lua_socket_keepalive_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_keepalive_timeout) config directive will be used. If the `0` value is given, then the timeout interval is unlimited.

The second optional argument, `size`, can be used to specify the maximal number of connections allowed in the connection pool for the current server (i.e., the current host-port pair or the unix domain socket file path). Note that the size of the connection pool cannot be changed once the pool is created. When this argument is omitted, the default setting in the [lua_socket_pool_size](http://wiki.nginx.org/HttpLuaModule#lua_socket_pool_size) config directive will be used.

When the connection pool is exceeding the size limit, the least recently used (idle) connection already in the pool will be closed automatically to make room for the current connection.

Note that the cosocket connection pool is per Nginx worker process rather than per Nginx server instance, so the size limit specified here also applies to every single Nginx worker process.

Idle connections in the pool will be monitored for any exceptional events like connection abortion or unexpected incoming data on the line, in which cases the connection in question will be closed and removed from the pool.

In case of success, this method returns `1`; otherwise, it returns `nil` and a string describing the error.

This method also makes the current cosocket object enter the "closed" state, so you do not need to manually call the [close](http://wiki.nginx.org/HttpLuaModule#tcpsock:close) method on it afterwards.

This feature was first introduced in the `v0.5.0rc1` release.

tcpsock:getreusedtimes
----------------------
**syntax:** *count, err = tcpsock:getreusedtimes()*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

This method returns the (successfully) reused times for the current connection. In case of error, it returns `nil` and a string describing the error.

If the current connection does not come from the built-in connection pool, then this method always returns `0`, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

This feature was first introduced in the `v0.5.0rc1` release.

ngx.socket.connect
------------------
**syntax:** *tcpsock, err = ngx.socket.connect(host, port)*

**syntax:** *tcpsock, err = ngx.socket.connect("unix:/path/to/unix-domain.socket")*

**context:** *rewrite_by_lua*, access_by_lua*, content_by_lua**

This function is a shortcut for combining [ngx.socket.tcp()](http://wiki.nginx.org/HttpLuaModule#ngx.socket.tcp) and the [connect()](http://wiki.nginx.org/HttpLuaModule#tcpsock:connect) method call in a single operation. It is actually implemented like this:


    local sock = ngx.socket.tcp()
    local ok, err = sock:connect(...)
    if not ok then
        return nil, err
    end
    return sock


There is no way to use the [settimeout](http://wiki.nginx.org/HttpLuaModule#tcpsock:settimeout) method to specify connecting timeout for this method. You have to use the [lua_socket_connect_timeout](http://wiki.nginx.org/HttpLuaModule#lua_socket_connect_timeout) directive at configure time instead.

This feature was first introduced in the `v0.5.0rc1` release.

ndk.set_var.DIRECTIVE
---------------------
**syntax:** *res = ndk.set_var.DIRECTIVE_NAME*

**context:** *set_by_lua*, rewrite_by_lua*, access_by_lua*, content_by_lua*, header_filter_by_lua**

This mechanism allows calling other nginx C modules' directives that are implemented by [Nginx Devel Kit](https://github.com/simpl/ngx_devel_kit) (NDK)'s set_var submodule's `ndk_set_var_value`.

For example, the following [HttpSetMiscModule](http://wiki.nginx.org/HttpSetMiscModule) directives can be invoked this way:

* [set_quote_sql_str](http://wiki.nginx.org/HttpSetMiscModule#set_quote_sql_str)
* [set_quote_pgsql_str](http://wiki.nginx.org/HttpSetMiscModule#set_quote_pgsql_str)
* [set_quote_json_str](http://wiki.nginx.org/HttpSetMiscModule#set_quote_json_str)
* [set_unescape_uri](http://wiki.nginx.org/HttpSetMiscModule#set_unescape_uri)
* [set_escape_uri](http://wiki.nginx.org/HttpSetMiscModule#set_escape_uri)
* [set_encode_base32](http://wiki.nginx.org/HttpSetMiscModule#set_encode_base32)
* [set_decode_base32](http://wiki.nginx.org/HttpSetMiscModule#set_decode_base32)
* [set_encode_base64](http://wiki.nginx.org/HttpSetMiscModule#set_encode_base64)
* [set_decode_base64](http://wiki.nginx.org/HttpSetMiscModule#set_decode_base64)
* [set_encode_hex](http://wiki.nginx.org/HttpSetMiscModule#set_encode_base64)
* [set_decode_hex](http://wiki.nginx.org/HttpSetMiscModule#set_decode_base64)
* [set_sha1](http://wiki.nginx.org/HttpSetMiscModule#set_encode_base64)
* [set_md5](http://wiki.nginx.org/HttpSetMiscModule#set_decode_base64)

For instance,


    local res = ndk.set_var.set_escape_uri('a/b');
    -- now res == 'a%2fb'


Similarly, the following directives provided by [HttpEncryptedSessionModule](http://wiki.nginx.org/HttpEncryptedSessionModule) can be invoked from within Lua too:

* [set_encrypt_session](http://wiki.nginx.org/HttpEncryptedSessionModule#set_encrypt_session)
* [set_decrypt_session](http://wiki.nginx.org/HttpEncryptedSessionModule#set_decrypt_session)

This feature requires the [ngx_devel_kit](https://github.com/simpl/ngx_devel_kit) module.

HTTP 1.0 support
================

The HTTP 1.0 protocol does not support chunked outputs and always requires an
explicit `Content-Length` header when the response body is non-empty in order to support the HTTP 1.0 keep-alive (as required by the ApacheBench (ab) tool). So when
an HTTP 1.0 request is present and the [lua_http10_buffering](http://wiki.nginx.org/HttpLuaModule#lua_http10_buffering) directive is turned `on`, this module will automatically buffer all the
outputs of user calls of [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say) and [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) and
postpone sending response headers until it sees all the outputs in the response
body, and at that time ngx_lua can calculate the total length of the body and
construct a proper `Content-Length` header for the HTTP 1.0 client.

If the user Lua code sets the `Content-Length` response header itself, then the automatic buffering will be disabled even if the [lua_http10_buffering](http://wiki.nginx.org/HttpLuaModule#lua_http10_buffering) directive is turned `on`.

For big responses' streaming outputs, it's important to disable the [lua_http10_buffering](http://wiki.nginx.org/HttpLuaModule#lua_http10_buffering) directive, otherwise the memory usage will grow very quickly.

Note that, common HTTP benchmark tools like `ab` and `http_load` always issue
HTTP 1.0 requests by default. To force `curl` to send HTTP 1.0 requests, use
the `-0` option.

Data Sharing within an Nginx Worker
===================================

**NOTE: This mechanism behaves differently when code cache is turned off and should be considered a DIRTY TRICK. Note that backward compatibility is NOT guaranteed and that there may be other undesirable consequences. A new data sharing mechanism will be designed later.**

To globally share data among all the requests handled by the same nginx worker process, encapsulate the shared data into a Lua module, use the Lua `require` builtin to import the module, and then manipulate the shared data in Lua. This works because required Lua modules are loaded only once and all coroutines will share the same copy of the module. Note however that Lua global variables WILL NOT persist between requests because of the one-coroutine-per-request isolation design.

Here is a complete small example:


    -- mydata.lua
    module("mydata", package.seeall)
 
    local data = {
        dog = 3,
        cat = 4,
        pig = 5,
    }
 
    function get_age(name)
        return data[name]
    end


and then accessing it from `nginx.conf`:


    location /lua {
        content_lua_by_lua '
            local mydata = require("mydata")
            ngx.say(mydata.get_age("dog"))
        ';
    }


The `mydata` module in this example will only be loaded and run on the first request to the location `/lua`,
and all subsequent requests to the same nginx worker process will use the reloaded instance of the
module as well as the same copy of the data in it, until a `HUP` signal is sent to the Nginx master process to force a reload.
This data sharing technique is essential for high performance Lua applications based on this module.

Note that this data sharing is on a *per-worker* basis and not on a ''per-server' basis'. That is, when there are multiple nginx worker processes under an Nginx master, data sharing cannot cross the process boundary between these workers. 

If server wide data sharing is required:
1. Use the [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT) API provied by this module.
1. Use only a single nginx worker and a single server. This is however not recommended when there is a multi core CPU or multiple CPUs in a single machine.
1. Use data storage mechanisms such as `memcached`, `redis`, `MySQL` or `PostgreSQL`. [The ngx_openresty bundle](http://openresty.org) associated with this module comes with a set of companion Nginx modules that provide interfaces with these data storage mechanisms.  See the [HttpMemcModule](http://wiki.nginx.org/HttpMemcModule), [HttpRedis2Module](http://wiki.nginx.org/HttpRedis2Module), [HttpDrizzleModule](http://wiki.nginx.org/HttpDrizzleModule) and [HttpPostgresModule](http://github.com/FRiCKLE/ngx_postgres/) modules for details

Known Issues
============

Lua Coroutine Yielding/Resuming
-------------------------------
* As the module's predefined Nginx I/O API uses the coroutine yielding/resuming mechanism, user code should not call any Lua modules that use the Lua coroutine mechanism in order to prevent conflicts with the module's predefined Nginx API methods such as [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) (Actually, coroutine modules have been masked off in [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua) directives and others). This limitation is significant and work is ongoing on an alternative coroutine implementation that can fit into the Nginx event model to address this. When this is done, it will be possible to use the Lua coroutine mechanism freely as it is in standard Lua implementations.
* Lua's `dofile` builtin is implemented as a C function in both Lua 5.1 and LuaJIT 2.0 and when [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) is called, [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec), [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit) or [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body) or similar in the file to be loaded by `dofile`, a coroutine yield across the C function boundary will be initiated. This however is not allowed within ngx_lua and will usually result in error messages like `lua handler aborted: runtime error: attempt to yield across C-call boundary`. To avoid this, define a real Lua module and use the Lua `require` builtin instead.
* Because the standard Lua 5.1 interpreter's VM is not fully resumable, the methods [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture), [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi), [ngx.redirect](http://wiki.nginx.org/HttpLuaModule#ngx.redirect), [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec), and [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit) cannot be used within the context of a Lua [pcall()](http://www.lua.org/manual/5.1/manual.html#pdf-pcall) or [xpcall()](http://www.lua.org/manual/5.1/manual.html#pdf-xpcall) when the standard Lua 5.1 interpreter is used and the `attempt to yield across metamethod/C-call boundary` error will be produced. Please use LuaJIT 2.0, which supports a fully resumable VM, to avoid this.

Lua Variable Scope
------------------
Care should be taken when importing modules and this form should be used:


        local xxx = require('xxx')


	instead of the old deprecated form:


        require('xxx')


	If the old form is required, force reload the module for every request by using the `package.loaded.<module>` command:


        package.loaded.xxx = nil
        require('xxx')


It is recommended to always place the following piece of code at the end of Lua modules that use the [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) or [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi) directives to prevent casual use of module-level global variables that are shared among *all* requests:


    getmetatable(foo.bar).__newindex = function (table, key, val)
        error('Attempt to write to undeclared variable "' .. key .. '": '
                .. debug.traceback())
    end


Assuming the current Lua module is named `foo.bar`, this will guarantee that local variables in module `foo.bar` functions have been declared as "local". It prevents undesirable race conditions while accessing such variables. See [Data Sharing within an Nginx Worker](http://wiki.nginx.org/HttpLuaModule#Data_Sharing_within_an_Nginx_Worker) for the reasons behind this.

Locations Configured by Subrequest Directives of Other Modules
--------------------------------------------------------------
The [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi) directives cannot capture locations that include the [echo_location](http://wiki.nginx.org/HttpEchoModule#echo_location), [echo_location_async](http://wiki.nginx.org/HttpEchoModule#echo_location_async), [echo_subrequest](http://wiki.nginx.org/HttpEchoModule#echo_subrequest), or [echo_subrequest_async](http://wiki.nginx.org/HttpEchoModule#echo_subrequest_async) directives.


    location /foo {
        content_by_lua '
            res = ngx.location.capature("/bar")
        ';
    }
    location /bar {
        echo_location /blah;
    }
    location /blah {
        echo "Success!";
    }



    $ curl -i http://example.com/foo


will not work as expected.

Special PCRE Sequences
----------------------
PCRE sequences such as `\d`, `\s`, or `\w`, require special attention because in string literals, the backslash character, `\`, is stripped out by both the Lua language parser and by the Nginx config file parser before processing. So the following snippet will not work as expected:


    # nginx.conf
    ? location /test {
    ?     content_by_lua '
    ?         local regex = "\d+"  -- THIS IS WRONG!!
    ?         local m = ngx.re.match("hello, 1234", regex)
    ?         if m then ngx.say(m[0]) else ngx.say("not matched!") end
    ?     ';
    ? }
    # evaluates to "not matched!"


To avoid this, *double* escape the backslash:


    # nginx.conf
    location /test {
        content_by_lua '
            local regex = "\\\\d+"
            local m = ngx.re.match("hello, 1234", regex)
            if m then ngx.say(m[0]) else ngx.say("not matched!") end
        ';
    }
    # evaluates to "1234"


Here, `\\\\d+` is stripped down to `\\d+` by the Nginx config file parser and this is further stripped down to `\d+` by the Lua language parser before running.

Alternatively, the regex pattern can be presented as a long-bracketed Lua string literal by encasing it in "long brackets", `[[...]]`, in which case backslashes have to only be escaped once for the Nginx config file parser. 


    # nginx.conf
    location /test {
        content_by_lua '
            local regex = [[\\d+]]
            local m = ngx.re.match("hello, 1234", regex)
            if m then ngx.say(m[0]) else ngx.say("not matched!") end
        ';
    }
    # evaluates to "1234"


Here, `[[\\d+]]` is stripped down to `[[\d+]]` by the Nginx config file parser and this is processed correctly.

Note that a longer from of the long bracket, `[=[...]=]`, may be required if the regex pattern contains `[...]` sequences. 
The `[=[...]=]` form may be used as the default form if desired and it may help with readability if a space is inserted between the long brackets and the regex patterns.


    # nginx.conf
    location /test {
        content_by_lua '
            local regex = [=[ [0-9]+ ]=]
            local m = ngx.re.match("hello, 1234", regex)
            if m then ngx.say(m[0]) else ngx.say("not matched!") end
        ';
    }
    # evaluates to "1234"


An alternative approach to escaping PCRE sequences is to ensure that Lua code is placed in external script files and executed using the various `*_by_lua_file` directives. 
With this approach, the backslashes are only stripped by the Lua language parser and therefore only need to be escaped once each.


    -- test.lua
    local regex = "\\d+"
    local m = ngx.re.match("hello, 1234", regex)
    if m then ngx.say(m[0]) else ngx.say("not matched!") end
    -- evaluates to "1234"


Within external script files, PCRE sequences presented as long-bracketed Lua string literals do not require modification. 
 

    -- test.lua
    local regex = [[\d+]]
    local m = ngx.re.match("hello, 1234", regex)
    if m then ngx.say(m[0]) else ngx.say("not matched!") end
    -- evaluates to "1234"


Typical Uses
============

Just to name a few:

* Mashup'ing and processing outputs of various nginx upstream outputs (proxy, drizzle, postgres, redis, memcached, and etc) in Lua,
* doing arbitrarily complex access control and security checks in Lua before requests actually reach the upstream backends,
* manipulating response headers in an arbitrary way (by Lua)
* fetching backend information from external storage backends (like redis, memcached, mysql, postgresql) and use that information to choose which upstream backend to access on-the-fly,
* coding up arbitrarily complex web applications in a content handler using synchronous but still non-blocking access to the database backends and other storage,
* doing very complex URL dispatch in Lua at rewrite phase,
* using Lua to implement advanced caching mechanism for Nginx's subrequests and arbitrary locations.

The possibilities are unlimited as the module allows bringing together various elements within Nginx as well as exposing the power of the Lua language to the user. The module provides the full flexibility of scripting while offering performance levels comparable with native C language programs both in terms of CPU time as well as memory footprint. This is particularly the case when LuaJIT 2.0 is enabled. 

Other scripting language implementations typically struggle to match this performance level.

The Lua state (Lua VM instance) is shared across all the requests handled by a single nginx worker process to miminize memory use.

On a ThinkPad T400 2.80 GHz laptop, the HelloWorld example readily achieves 28k req/sec using `http_load -p 10`. By contrast, Nginx + php-fpm 5.2.8 + Unix Domain Socket yields 6k req/sec and [Node.js](http://nodejs.org/) v0.6.1 yields 10.2k req/sec for their HelloWorld equivalents.

This module performs best when built with [LuaJIT 2.0](http://luajit.org/luajit.html).

Nginx Compatibility
===================
The module is compatible with the following versions of Nginx:

*   1.1.x (last tested: 1.1.5)
*   1.0.x (last tested: 1.0.15)
*   0.9.x (last tested: 0.9.4)
*   0.8.x >= 0.8.54 (last tested: 0.8.54)

Code Repository
===============

The code repository of this project is hosted on github at [chaoslawful/lua-nginx-module](http://github.com/chaoslawful/lua-nginx-module).

Installation
============

The [ngx_openresty bundle](http://openresty.org) can be used to install Nginx, `ngx_lua`, either one of the standard Lua 5.1 interpreter or LuaJIT 2.0, as well as a package of powerful companion Nginx modules. The basic installation step is a simple `./configure --with-luajit && make && make install`.

Alternatively, `ngx_lua` can be manually compiled into Nginx:

1. Install LuaJIT 2.0 (Recommended) or Lua 5.1 (Lua 5.2 is *not* supported yet). Lua can be obtained free from the [the LuaJIT download page](http://luajit.org/download.html) or [the standard Lua homepage](http://www.lua.org/).  Some distribution package managers also distribute Lua and LuaJIT.
1. Download the latest version of the ngx_devel_kit (NDK) module [HERE](http://github.com/simpl/ngx_devel_kit/tags).
1. Download the latest version of this module [HERE](http://github.com/chaoslawful/lua-nginx-module/tags).
1. Download the latest version of Nginx [HERE](http://nginx.org/) (See [Nginx Compatibility](http://wiki.nginx.org/HttpLuaModule#Nginx_Compatibility))

Build the source with this module:


    wget 'http://nginx.org/download/nginx-1.0.15.tar.gz'
    tar -xzvf nginx-1.0.15.tar.gz
    cd nginx-1.0.15/
 
    # tell nginx's build system where to find lua:
    export LUA_LIB=/path/to/lua/lib
    export LUA_INC=/path/to/lua/include
 
    # or tell where to find LuaJIT when if using JIT instead
    # export LUAJIT_LIB=/path/to/luajit/lib
    # export LUAJIT_INC=/path/to/luajit/include/luajit-2.0
 
    # Here we assume Nginx is to be installed under /opt/nginx/.
    ./configure --prefix=/opt/nginx \
            --add-module=/path/to/ngx_devel_kit \
            --add-module=/path/to/lua-nginx-module
 
    make -j2
    make install


Bugs and Patches
================

Please report bugs or submit patches by:

1. Creating a ticket on the [GitHub Issue Tracker](http://github.com/chaoslawful/lua-nginx-module/issues) (Recommended)
1. Posting to the [Nginx Mailing List](http://mailman.nginx.org/mailman/listinfo/nginx) and also adding `[ngx_lua]` to the mail subject.

TODO
====

Short Term
----------
* implement the `ngx.sleep(time)` Lua API. (For now, use [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) with [HttpEchoModule](http://wiki.nginx.org/HttpEchoModule)'s [echo_sleep](http://wiki.nginx.org/HttpEchoModule#echo_sleep) config directive instead.)
* implement the `ngx.worker.get_pid()` Lua API. (For now, use `ngx.var.pid` directly.)
* implement [LuaSocket UDP API](http://w3.impa.br/~diego/software/luasocket/udp.html) in our cosocket API.
* implement the SSL cosocket API.
* implement the `ngx.re.split` method.
* use `ngx_hash_t` to optimize the built-in header look-up process for [ngx.req.set_header](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_header), [ngx.header.HEADER](http://wiki.nginx.org/HttpLuaModule#ngx.header.HEADER), and etc.
* add configure options for different strategies of handling the cosocket connection exceeding in the pools.
* add directives to run Lua codes when nginx stops/reloads.
* add APIs to access cookies as key/value pairs.
* add `ignore_resp_headers`, `ignore_resp_body`, and `ignore_resp` options to [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi) methods, to allow micro performance tuning on the user side.

Longer Term
-----------
* add the `lua_require` directive to load module into main thread's globals.
* add Lua code automatic time slicing support by yielding and resuming the Lua VM actively via Lua's debug hooks.
* make [set_by_lua](http://wiki.nginx.org/HttpLuaModule#set_by_lua), [header_filter_by_lua](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua), and their variants use the same mechanism as [content_by_lua](http://wiki.nginx.org/HttpLuaModule#content_by_lua), [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua), [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua), and their variants.
* add coroutine API back to the Lua user land.
* add `stat` mode similar to [mod_lua](http://httpd.apache.org/docs/2.3/mod/mod_lua.html).

Changes
=======

v0.4.1
------

1 February, 2012

* bugfix: [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit), [ngx.redirect](http://wiki.nginx.org/HttpLuaModule#ngx.redirect), [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec), and [ngx.req.set_uri(uri, true)](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_uri) could return (they should never return as per the documentation). this bug had appeared in ngx_lua v0.3.1rc4 and ngx_openresty 1.0.6.13. thanks [@cyberty](http://weibo.com/cyberty) for reporting it.
* bugfix: `ngx_http_lua_header_filter_init` was called with an argument which actually accepts none. this could cause compilation errors at least with gcc 4.3.4 as reported in [github issue #80](http://github.com/chaoslawful/lua-nginx-module/issues/80). thanks bigplum (Simon).
* bugfix: fixed all the warnings from the clang static analyzer.
* feature: allow use of the `DDEBUG` macro from the outside (via the `-D DDEBUG=1` C compiler opton).

v0.4.0
------

11 January, 2012

* bugfix: fixed a bug when the both the main request and the subrequest are POST requests with a body: we should not forward the main request's `Content-Length` headers to the user subrequests. thanks 朱峰.
* feature: implemented the API for reading response headers from within Lua: `value = ngx.header.HEADER`, see [ngx.header.HEADER](http://wiki.nginx.org/HttpLuaModule#ngx.header.HEADER).
* bugfix: fixed a bug when setting a multi-value response header to a single value (via writing to [ngx.header.HEADER](http://wiki.nginx.org/HttpLuaModule#ngx.header.HEADER)): the single value will be repeated on each old value.
* bugfix: fixed an issue in [ngx.redirect](http://wiki.nginx.org/HttpLuaModule#ngx.redirect), [ngx.exit](http://wiki.nginx.org/HttpLuaModule#ngx.exit), and [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec): these function calls would be intercepted by Lua `pcall`/`xpcall` because they used Lua exceptions; now they use Lua yield just as [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture). thanks @hugozhu for reporting this.
* feature: now we also return the `Last-Modified` header (if any) for the subrequest response object. thanks @cyberty and sexybabes.
* feature: now [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec) supports Lua table as the second args argument value. thanks sexybabes.
* feature: implemented the [ngx.headers_sent](http://wiki.nginx.org/HttpLuaModule#ngx.headers_sent) API to check if response headers are sent (by ngx_lua). thanks @hugozhu.
* feature: exposes the CRC-32 API of the Nginx core to the Lua land, in the form of the [ngx.crc32_short](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_short) and [ngx.crc32_long](http://wiki.nginx.org/HttpLuaModule#ngx.crc32_long) methods. thanks @Lance.
* feature: now for HTTP 1.0 requests, we disable the automatic full buffering mode if the user sets the `Content-Length` response header before sending out the headers. this allows streaming output for HTTP 1.0 requests if the content length can be calculated beforehand. thanks 李子义.
* bugfix: now we properly support setting the `Cache-Control` response header via the [ngx.header.HEADER](http://wiki.nginx.org/HttpLuaModule#ngx.header.HEADER) interface.
* bugfix: no longer set header hash to `1`. use the `ngx_hash_key_lc` instead.
* bugfix: calling [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec) to jump to a named location did not clear the context object of LuaNginxModule properly and might cause evil problems. thanks Nginx User.
* bugfix: now we explicitly clear all the modules' contexts before dump to named location with [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec).
* feature: implemented [ngx.req.set_uri](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_uri) and [ngx.req.set_uri_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_uri_args) to emulate [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule)'s [rewrite](http://wiki.nginx.org/HttpRewriteModule#rewrite) directive. thanks Vladimir Protasov (utros) and Nginx User.
* bugfix: now we skip rewrite phase Lua handlers altogether if [HttpRewriteModule](http://wiki.nginx.org/HttpRewriteModule)'s [rewrite](http://wiki.nginx.org/HttpRewriteModule#rewrite) directive issue a location re-lookup by changing URIs (but not including `rewrite ... break`). thanks Nginx User.
* feature: added constant `ngx.HTTP_METHOD_NOT_IMPLEMENTED (501)`. thanks Nginx User.
* feature: added new Lua functions [ngx.req.read_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.read_body), [ngx.req.discard_body](http://wiki.nginx.org/HttpLuaModule#ngx.req.discard_body), [ngx.req.get_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_data), and [ngx.req.get_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_body_file). thanks Tzury Bar Yochay for funding the development work.
* bugfix: fixed hanging issues when using [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec) within [rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) and [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua). thanks Nginx User for reporting it.
* feature: added new Lua API [ngx.req.set_body_file](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_body_file). thanks Tzury Bar Yochay for funding the development work.
* feature: added new Lua API [ngx.req.set_body_data](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_body_data). thanks Tzury Bar Yochay for funding the development work.
* bugfix: [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) should not skip requests with methods other than `POST` and `PUT`. thanks Nginx User.
* bugfix: no longer free request body buffers that are not allocated by ourselves.
* bugfix: now we allow setting [ngx.var.VARIABLE](http://wiki.nginx.org/HttpLuaModule#ngx.var.VARIABLE) to nil.
* feature: added new directive [lua_shared_dict](http://wiki.nginx.org/HttpLuaModule#lua_shared_dict).
* feature: added Lua API for the shm-based dictionary, see [ngx.shared.DICT](http://wiki.nginx.org/HttpLuaModule#ngx.shared.DICT).
* bugfix: fixed spots of -Werror=unused-but-set-variable warning issued by gcc 4.6.0.
* bugfix: [ndk.set_var.DIRECTIVE](http://wiki.nginx.org/HttpLuaModule#ndk.set_var.DIRECTIVE) had a memory issue and might pass empty argument values to the directive being called. thanks dannynoonan.
* feature: added the `ctx` option to [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture): you can now specify a custom Lua table to pass to the subrequest as its [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx). thanks @hugozhu.
* feature: added the [ngx.encode_args](http://wiki.nginx.org/HttpLuaModule#ngx.encode_args) method to encode a Lua code to a URI query string. thanks 郭颖 (0597虾).
* feature: [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.exec](http://wiki.nginx.org/HttpLuaModule#ngx.exec) now supports the same Lua args table format as in ngx.encode_args. thanks 郭颖 (0597虾).
* bugfix: `Cache-Control` header modification might introduce empty value headers when using with the standard HttpHeadersModule.
* feature: added [ngx.hmac_sha1](http://wiki.nginx.org/HttpLuaModule#ngx.hmac_sha1). thanks drdrxp.
* docs: documented the long-existent [ngx.md5](http://wiki.nginx.org/HttpLuaModule#ngx.md5) and [ngx.md5_bin](http://wiki.nginx.org/HttpLuaModule#ngx.md5_bin) APIs.
* docs: massive documentation improvements. thanks Nginx User.
* feature: added new regex options `j` and `d` to [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match), [ngx.re.gmatch](http://wiki.nginx.org/HttpLuaModule#ngx.re.gmatch), [ngx.re.sub](http://wiki.nginx.org/HttpLuaModule#ngx.re.sub), and [ngx.re.gsub](http://wiki.nginx.org/HttpLuaModule#ngx.re.gsub) so as to enable the PCRE JIT mode and DFA mode, respectively. thanks @姜大炮 for providing the patch.
* feature: added options `copy_all_vars` and `vars` to [ngx.location.capture](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture) and [ngx.location.capture_multi](http://wiki.nginx.org/HttpLuaModule#ngx.location.capture_multi). thanks Marcus Clyne for the patch.
* feature: added new Lua API [ngx.now](http://wiki.nginx.org/HttpLuaModule#ngx.now) to return the current time (including the milliseconds part as the decimal part). thanks 林青.
* feature: added new Lua API [ngx.update_time](http://wiki.nginx.org/HttpLuaModule#ngx.update_time) to forcibly updating Nginx's time cache.
* feature: added `wait` boolean argument to [ngx.flush](http://wiki.nginx.org/HttpLuaModule#ngx.flush) to support synchronous flushing: `ngx.flush(true)` will not return until all the data has been flushed into the system send buffer or the send timeout has expired.
* bugfix: now we check timed out downstream connections in our write event handler.
* feature: added constant `ngx.HTTP_GATEWAY_TIMEOUT (504)` per Fry-kun in [github issue #73](https://github.com/chaoslawful/lua-nginx-module/issues/73).
* bugfix: [ngx.var.VARIABLE](http://wiki.nginx.org/HttpLuaModule#ngx.var.VARIABLE) did not evaluate to `nil` when the Nginx variable's `valid` flag is `0`.
* bugfix: there were various places where we did not check the pointer returned by the memory allocator.
* bugfix: [ngx.req.set_header](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_header) and [ngx.req.clear_header](http://wiki.nginx.org/HttpLuaModule#ngx.req.clear_header) did not handle the `Accept-Encoding` request headers properly. thanks 天街夜色.
* bugfix: [ngx.req.set_header](http://wiki.nginx.org/HttpLuaModule#ngx.req.set_header) might cause invalid memory reads because Nginx request header values must be `NULL` terminated. thanks Maxim Dounin.
* bugfix: removing builtin headers via [ngx.req.clear_header](http://wiki.nginx.org/HttpLuaModule#ngx.req.clear_header) and its equivalent in huge request headers with 20+ entries could result in data loss. thanks Chris Dumoulin.
* bugfix: [ngx.req.get_uri_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_uri_args) and [ngx.req.get_post_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_post_args) now only parse up to `100` arguments by default. but one can specify the optional argument to these two methods to specify a custom maximum number of args. thanks Tzury Bar Yochay for reporting this.
* bugfix: [ngx.req.get_headers](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_headers) now only parse up to `100` request headers by default. but one can specify the optional argument to this method to specify a custom maximum number of headers.

v0.3.0
------

September 02, 2011

**New features**

* added the [header_filter_by_lua](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua) and [header_filter_by_lua_file](http://wiki.nginx.org/HttpLuaModule#header_filter_by_lua_file) directives. thanks Liseen Wan (万珣新).
* implemented the PCRE regex API for Lua: [ngx.re.match](http://wiki.nginx.org/HttpLuaModule#ngx.re.match), [ngx.re.gmatch](http://wiki.nginx.org/HttpLuaModule#ngx.re.gmatch), [ngx.re.sub](http://wiki.nginx.org/HttpLuaModule#ngx.re.sub), and [ngx.re.gsub](http://wiki.nginx.org/HttpLuaModule#ngx.re.gsub).
* now we add the `ngx` and `ndk` table into `package.loaded` such that the user can write `local ngx = require 'ngx'` and `local ndk = require 'ndk'`. thanks @Lance.
* added new directive [lua_regex_cache_max_entries](http://wiki.nginx.org/HttpLuaModule#lua_regex_cache_max_entries) to control the upper limit of the worker-process-level compiled-regex cache enabled by the `o` regex option.
* implemented the special [ngx.ctx](http://wiki.nginx.org/HttpLuaModule#ngx.ctx) Lua table for user programmers to store per-request Lua context data for their applications. thanks 欧远宁 for suggesting this feature.
* now [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print) and [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say) allow (nested) array-like table arguments. the array elements in them will be sent piece by piece. this will avoid string concatenation for templating engines like [ltp](http://www.savarese.com/software/ltp/).
* implemented the [ngx.req.get_post_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_post_args) method for fetching url-encoded POST query arguments from within Lua.
* implemented the [ngx.req.get_uri_args](http://wiki.nginx.org/HttpLuaModule#ngx.req.get_uri_args) method to fetch parsed URL query arguments from within Lua. thanks Bertrand Mansion (golgote).
* added new function [ngx.parse_http_time](http://wiki.nginx.org/HttpLuaModule#ngx.parse_http_time), thanks James Hurst.
* now we allow Lua boolean and `nil` values in arguments to [ngx.say](http://wiki.nginx.org/HttpLuaModule#ngx.say), [ngx.print](http://wiki.nginx.org/HttpLuaModule#ngx.print), [ngx.log](http://wiki.nginx.org/HttpLuaModule#ngx.log) and [print](http://wiki.nginx.org/HttpLuaModule#print).
* added support for user C macros `LUA_DEFAULT_PATH` and `LUA_DEFAULT_CPATH`. for now we can only define them in `ngx_lua`'s `config` file because nginx `configure`'s `--with-cc-opt` option hates values with double-quotes in them. sigh. This feature is used by [The ngx_openresty bundle](http://openresty.org) to bundle third party Lua libraries.

**Bug fixes**

* worked-around the "stack overflow" issue while using `luarocks.loader` and disabling [lua_code_cache](http://wiki.nginx.org/HttpLuaModule#lua_code_cache), as described as github issue #27. thanks Patrick Crosby.
* fixed the `zero size buf in output` alert while combining [lua_need_request_body](http://wiki.nginx.org/HttpLuaModule#lua_need_request_body) on + [access_by_lua](http://wiki.nginx.org/HttpLuaModule#access_by_lua)/[rewrite_by_lua](http://wiki.nginx.org/HttpLuaModule#rewrite_by_lua) + [proxy_pass](http://wiki.nginx.org/HttpProxyModule#proxy_pass)/[fastcgi_pass](http://wiki.nginx.org/HttpFcgiModule#fastcgi_pass). thanks Liseen Wan (万珣新).
* fixed issues with HTTP 1.0 HEAD requests.
* made setting `ngx.header.HEADER` after sending out response headers throw out a Lua exception to help debugging issues like github issue #49. thanks Bill Donahue (ikhoyo).
* fixed an issue regarding defining global variables in C header files: we should have defined the global `ngx_http_lua_exception` in a single compilation unit. thanks @姜大炮.

Test Suite
==========

The following dependencies are required to run the test suite:

* Nginx version >= 0.8.54

* Perl modules:
	* test-nginx: <http://github.com/agentzh/test-nginx> 

* Nginx modules:
	* echo-nginx-module: <http://github.com/agentzh/echo-nginx-module> 
	* drizzle-nginx-module: <http://github.com/chaoslawful/drizzle-nginx-module> 
	* rds-json-nginx-module: <http://github.com/agentzh/rds-json-nginx-module> 
	* set-misc-nginx-module: <http://github.com/agentzh/set-misc-nginx-module> 
	* headers-more-nginx-module: <http://github.com/agentzh/headers-more-nginx-module> 
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

The order in which these modules are added during configuration is important as the position of any filter module in the
filtering chain determines the final output. The correct adding order is:

1. ngx_devel_kit
1. set-misc-nginx-module
1. ngx_http_auth_request_module
1. echo-nginx-module
1. memc-nginx-module
1. lua-nginx-module (i.e. this module)
1. headers-more-nginx-module
1. srcache-nginx-module
1. drizzle-nginx-module
1. rds-json-nginx-module

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2009-2012, by Xiaozhe Wang (chaoslawful) <chaoslawful@gmail.com>.

Copyright (C) 2009-2012, by Zhang "agentzh" Yichun (章亦春) <agentzh@gmail.com>.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

See Also
========

* [lua-resty-memcached](http://github.com/agentzh/lua-resty-memcached) library based on ngx_lua cosocket.
* [lua-resty-redis](http://github.com/agentzh/lua-resty-redis) library based on ngx_lua cosocket.
* [lua-resty-mysql](http://github.com/agentzh/lua-resty-mysql) library based on ngx_lua cosocket.
* [lua-resty-upload](http://github.com/agentzh/lua-resty-upload) library based on ngx_lua cosocket.
* [lua-resty-string](http://github.com/agentzh/lua-resty-string) library based on [LuaJIT FFI](http://luajit.org/ext_ffi.html).
* [Routing requests to different MySQL queries based on URI arguments](http://openresty.org/#RoutingMySQLQueriesBasedOnURIArgs)
* [Dynamic Routing Based on Redis and Lua](http://openresty.org/#DynamicRoutingBasedOnRedis)
* [Using LuaRocks with ngx_lua](http://openresty.org/#UsingLuaRocks)
* [Introduction to ngx_lua](https://github.com/chaoslawful/lua-nginx-module/wiki/Introduction)
* [ngx_devel_kit](http://github.com/simpl/ngx_devel_kit)
* [HttpEchoModule](http://wiki.nginx.org/HttpEchoModule)
* [HttpDrizzleModule](http://wiki.nginx.org/HttpDrizzleModule)
* [postgres-nginx-module](http://github.com/FRiCKLE/ngx_postgres)
* [HttpMemcModule](http://wiki.nginx.org/HttpMemcModule)
* [The ngx_openresty bundle](http://openresty.org)

Translations
============
* [Chinese](http://wiki.nginx.org/HttpLuaModuleZh)

