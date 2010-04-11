#!/bin/bash

# this file is mostly meant to be used by the author himself.

version=${1:-0.8.30}
opts=$2

script_dir=$(dirname $0)
root=$(readlink -f $script_dir/..)
mkdir -p $root/{build,work}

cd $root/build
lwp-mirror "http://sysoev.ru/nginx/nginx-$version.tar.gz" nginx-$version.tar.gz
tar -xzvf nginx-$version.tar.gz

cd nginx-$version/
if [[ "$BUILD_CLEAN" -eq 1 || ! -f Makefile || "$root/config" -nt Makefile || "$root/util/build.sh" -nt Makefile ]]; then
	./configure --prefix=$root/work \
				--add-module=$root/../ngx_devel_kit \
				--add-module=$root/../echo-nginx-module \
				--add-module=$root \
				--with-debug \
				$opts
fi

if [ -f $root/work/sbin/nginx ]; then
    rm -f $root/work/sbin/nginx
fi

if [ -f $root/work/logs/nginx.pid ]; then
    kill `cat $root/work/logs/nginx.pid`
fi

make -j2
make install

