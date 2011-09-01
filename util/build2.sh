#!/bin/bash

# this file is mostly meant to be used by the author himself.

version=${1:-0.8.41}
opts=$2

home=~
script_dir=$(dirname $0)
root=$(readlink -f $script_dir)
mkdir -p $root/{build,work}

cd $root/build

if [ ! -s "nginx-$version.tar.gz" ]; then
    if [ -f ~/work/nginx-$version.tar.gz ]; then
        cp ~/work/nginx-$version.tar.gz ./ || exit 1
    else
        wget "http://nginx.org/download/nginx-$version.tar.gz" -O nginx-$version.tar.gz || exit 1
        cp nginx-$version.tar.gz ~/work/
    fi

    tar -xzvf nginx-$version.tar.gz || exit 1
    cp $root/../no-pool-nginx/nginx-$version-no_pool.patch ./ || exit 1
    patch -p0 < nginx-$version-no_pool.patch || exit 1
    patch -p0 < $root/../ngx_openresty/patches/nginx-$version-request_body_preread_fix.patch || exit 1
    cd nginx-$version/
    patch -p1 -l < $root/../ngx_openresty/patches/nginx-$version-request_body_in_single_buf.patch || exit 1
    cd ..
    patch -p0 < $root/../ngx_openresty/patches/nginx-$version-no_error_pages.patch || exit 1
fi

                #--add-module=$root/../srcache-nginx-module \

cd nginx-$version/ || exit 1

if [[ "$BUILD_CLEAN" -eq 1 || ! -f Makefile || "$root/config" -nt Makefile || "$root/b.sh" -nt Makefile ]]; then
            #--without-pcre \
            #--without-http_rewrite_module \
    ./configure --prefix=$root/work \
            --with-cc-opt=$'-O0' \
            --with-ld-opt="-Wl,-rpath=/opt/drizzle/lib:/usr/local/lib:/home/lz/lib:/opt/luajit/lib" \
            --without-mail_pop3_module \
            --without-mail_imap_module \
            --without-mail_smtp_module \
            --without-http_upstream_ip_hash_module \
            --without-http_empty_gif_module \
            --without-http_memcached_module \
            --without-http_referer_module \
            --without-http_autoindex_module \
            --without-http_auth_basic_module \
            --without-http_userid_module \
            --add-module=$root/../ndk-nginx-module \
            --add-module=$root/../set-misc-nginx-module \
                --add-module=$home/work/nginx/ngx_http_auth_request_module-0.2 \
                --add-module=$root/../echo-nginx-module \
                --add-module=$root/../memc-nginx-module \
                --add-module=$root \
              --add-module=$root/../headers-more-nginx-module \
                --add-module=$root/../drizzle-nginx-module \
                --add-module=$home/work/nginx/ngx_http_upstream_keepalive-2ce9d8a1ca93 \
                --add-module=$root/../rds-json-nginx-module \
                $opts \
                --with-debug \
            || exit 1
fi

#if [ -f $root/work/sbin/nginx ]; then
    #rm -f $root/work/sbin/nginx
#fi

if [ -f $root/work/logs/nginx.pid ]; then
    kill `cat $root/work/logs/nginx.pid`
fi

make -j2 && make install

