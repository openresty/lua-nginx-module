#!/bin/bash

#export CC=clang
export CC=gcc
export NGX_BUILD_CC=$CC

mkdir -p download-cache

export JOBS=$(nproc)
export NGX_BUILD_JOBS=$JOBS
export VALGRIND_INC=/usr/include/valgrind/

export LUAJIT_PREFIX=/opt/luajit21
export LUAJIT_LIB=$LUAJIT_PREFIX/lib
export LUAJIT_INC=$LUAJIT_PREFIX/include/luajit-2.1
export LUA_INCLUDE_DIR=$LUAJIT_INC

export PCRE2_VER=10.45
export PCRE2_PREFIX=/opt/pcre2
export PCRE2_LIB=$PCRE2_PREFIX/lib
export PCRE2_INC=$PCRE2_PREFIX/include

export OPENSSL_VER=3.5.0
export OPENSSL_PATCH_VER=3.5.0
export OPENSSL_PREFIX=/opt/ssl3
export OPENSSL_LIB=$OPENSSL_PREFIX/lib
export OPENSSL_INC=$OPENSSL_PREFIX/include

export LIBDRIZZLE_PREFIX=/opt/drizzle
export LIBDRIZZLE_INC=$LIBDRIZZLE_PREFIX/include/libdrizzle-1.0
export LIBDRIZZLE_LIB=$LIBDRIZZLE_PREFIX/lib
export DRIZZLE_VER=2011.07.21

#export TEST_NGINX_SLEEP=0.006
export NGINX_VERSION=1.27.1
#export NGX_BUILD_ASAN=1

export PATH=/opt/bin:$PWD/work/nginx/sbin:$PWD/openresty-devel-utils:$PATH

if [ ! -f /opt/bin/curl ]; then
    wget https://github.com/stunnel/static-curl/releases/download/8.14.1/curl-linux-x86_64-glibc-8.14.1.tar.xz
    tar -xf curl-linux-x86_64-glibc-8.14.1.tar.xz
    tar -xf curl-linux-x86_64-glibc-8.14.1.tar.xz
    sudo mkdir -p /opt/bin
    sudo mv curl /opt/bin/
fi

function git_download()
{
    dir=${!#}
    if [ ! -d $dir ]; then
        git clone $@
    fi
}

function download_deps()
{
    if [ ! -f download-cache/drizzle7-$DRIZZLE_VER.tar.gz ]; then
        wget -P download-cache https://github.com/openresty/openresty-deps-prebuild/releases/download/v20230902/drizzle7-$DRIZZLE_VER.tar.gz
    fi

    if [ ! -f download-cache/pcre2-$PCRE2_VER.tar.gz ]; then
       wget -P download-cache https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz
    fi

    if [ ! -f download-cache/openssl-$OPENSSL_VER.tar.gz ]; then
       wget -P download-cache https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz
    fi

    git_download https://github.com/openresty/test-nginx.git
    git_download https://github.com/openresty/openresty.git ../openresty
    git_download https://github.com/openresty/no-pool-nginx.git ../no-pool-nginx
    git_download https://github.com/openresty/openresty-devel-utils.git
    git_download https://github.com/openresty/mockeagain.git
    git_download https://github.com/openresty/lua-cjson.git lua-cjson
    git_download https://github.com/openresty/lua-upstream-nginx-module.git ../lua-upstream-nginx-module
    git_download https://github.com/openresty/echo-nginx-module.git ../echo-nginx-module
    git_download https://github.com/openresty/nginx-eval-module.git ../nginx-eval-module
    git_download https://github.com/simpl/ngx_devel_kit.git ../ndk-nginx-module
    git_download https://github.com/FRiCKLE/ngx_coolkit.git ../coolkit-nginx-module
    git_download https://github.com/openresty/headers-more-nginx-module.git ../headers-more-nginx-module
    git_download https://github.com/openresty/drizzle-nginx-module.git ../drizzle-nginx-module
    git_download https://github.com/openresty/set-misc-nginx-module.git ../set-misc-nginx-module
    git_download https://github.com/openresty/memc-nginx-module.git ../memc-nginx-module
    git_download https://github.com/openresty/rds-json-nginx-module.git ../rds-json-nginx-module
    git_download https://github.com/openresty/srcache-nginx-module.git ../srcache-nginx-module
    git_download https://github.com/openresty/redis2-nginx-module.git ../redis2-nginx-module
    git_download https://github.com/openresty/lua-resty-core.git ../lua-resty-core
    git_download https://github.com/openresty/lua-resty-lrucache.git ../lua-resty-lrucache
    git_download https://github.com/openresty/lua-resty-mysql.git ../lua-resty-mysql
    git_download https://github.com/openresty/lua-resty-string.git ../lua-resty-string
    git_download https://github.com/openresty/stream-lua-nginx-module.git ../stream-lua-nginx-module
    git_download -b v2.1-agentzh https://github.com/openresty/luajit2.git luajit2
}

function make_deps()
{
    if [ "$TEST_NGINX_BUILD_DEPS" = "n" ]; then
        return
    fi

    cd luajit2/
    make clean
    make -j"$JOBS" CCDEBUG=-g Q= PREFIX=$LUAJIT_PREFIX CC=$CC XCFLAGS="-DLUAJIT_USE_VALGRIND -I$VALGRIND_INC -DLUAJIT_USE_SYSMALLOC -DLUA_USE_APICHECK -DLUA_USE_ASSERT -msse4.2" > build.log 2>&1 || (cat build.log && exit 1)
    sudo make install PREFIX=$LUAJIT_PREFIX
    cd ..
 
    tar zxf download-cache/openssl-$OPENSSL_VER.tar.gz
    cd openssl-$OPENSSL_VER/
    patch -p1 < ../../openresty/patches/openssl-$OPENSSL_PATCH_VER-sess_set_get_cb_yield.patch > ssl.log
    ./config -DOPENSSL_TLS_SECURITY_LEVEL=1 shared enable-ssl3 enable-ssl3-method -g -O2 --prefix=$OPENSSL_PREFIX --libdir=lib -DPURIFY >> ssl.log
    make -j$JOBS >> ssl.log
    sudo make PATH=$PATH install_sw >> ssl.log
    cd ..
 
    tar zxf download-cache/pcre2-$PCRE2_VER.tar.gz;
    cd pcre2-$PCRE2_VER/;
    ./configure --prefix=$PCRE2_PREFIX --enable-jit --enable-utf
    sudo PATH=$PATH make install
    cd ..
 
    tar xzf download-cache/drizzle7-$DRIZZLE_VER.tar.gz && cd drizzle7-$DRIZZLE_VER
    ./configure --prefix=$LIBDRIZZLE_PREFIX --without-server
    make libdrizzle-1.0 -j$JOBS
    sudo make install-libdrizzle-1.0
    cd ..

    cd mockeagain/ && make CC=$CC -j$JOBS
    cd ..

    cd lua-cjson/ && make -j$JOBS && sudo make install
    cd ..
}

function make_ngx()
{
    if [ "$TEST_NGINX_FRESH_BUILD" = "y" ]; then
        rm -fr buildroot
    fi

    sh util/build.sh $NGINX_VERSION 2>&1 | tee build.log
}

download_deps
make_deps
make_ngx

find t -name "*.t" | xargs reindex >/dev/null 2>&1

#nginx -V

export LD_PRELOAD=$PWD/mockeagain/mockeagain.so
export LD_LIBRARY_PATH=$PWD/mockeagain:$LD_LIBRARY_PATH

#export ASAN_OPTIONS=detect_leaks=0,log_path=/tmp/asan/asan,log_exe_name=true
#export LD_PRELOAD=/lib64/libasan.so.5:$PWD/mockeagain/mockeagain.so

export LD_LIBRARY_PATH=$LUAJIT_LIB:$OPENSSL_LIB:$LD_LIBRARY_PATH
export TEST_NGINX_RESOLVER=8.8.4.4

#export TEST_NGINX_NO_CLEAN=1
#export TEST_NGINX_CHECK_LEAK=1
#export TEST_NGINX_CHECK_LEAK_COUNT=100
#export TEST_NGINX_TIMEOUT=5

#export TEST_NGINX_USE_VALGRIND=1
#export TEST_NGINX_VALGRIND_EXIT_ON_FIRST_ERR=1
#export TEST_NGINX_USE_HTTP2=1

export MALLOC_PERTURB_=33
export TEST_NGINX_HTTP3_CRT=$PWD/t/cert/http3/http3.crt
export TEST_NGINX_HTTP3_KEY=$PWD/t/cert/http3/http3.key
#export TEST_NGINX_USE_HTTP3=1

#export TEST_NGINX_VERBOSE=1

#export TEST_NGINX_EVENT_TYPE=poll
#export TEST_NGINX_POSTPONE_OUTPUT=1
#export MOCKEAGAIN=r
#export MOCKEAGAIN=w
#export MOCKEAGAIN=rw
#export MOCKEAGAIN_VERBOSE=1

ldd `which nginx`|grep -E 'luajit|ssl|pcre'
which nginx
nginx -V

#export TEST_NGINX_INIT_BY_LUA="debug.sethook(function () collectgarbage() end, 'l') jit.off() package.path = '/usr/share/lua/5.1/?.lua;$PWD/../lua-resty-core/lib/?.lua;$PWD/../lua-resty-lrucache/lib/?.lua;' .. (package.path or '') require 'resty.core' require('resty.core.base').set_string_buf_size(1) require('resty.core.regex').set_buf_grow_ratio(1)"


# comment out TEST_NGINX_RANDOMIZE when debugging one test case
export TEST_NGINX_RANDOMIZE=1
prove -j$JOBS -I. -Itest-nginx/inc -Itest-nginx/lib -r t/
