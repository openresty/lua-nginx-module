#!/bin/bash

# Copyright, Aleksey Konovkin (alkon2000@mail.ru)
# BSD license type

download=0
if [ "$1" == "1" ]; then
  download=1
fi
build_deps=0

DIR="$(pwd)"

VERSION="1.13.6"
PCRE_VERSION="8.39"
LUAJIT_VERSION="2.1.0-beta2"

SUFFIX=""

BASE_PREFIX="$DIR/build"
INSTALL_PREFIX="$DIR/install"

PCRE_PREFIX="$DIR/build/pcre-$PCRE_VERSION"
JIT_PREFIX="$DIR/build/deps/luajit"

export LUAJIT_INC="$JIT_PREFIX/usr/local/include/luajit-2.1"
export LUAJIT_LIB="$JIT_PREFIX/usr/local/lib"

export LD_LIBRARY_PATH="$JIT_PREFIX/lib"

function clean() {
  rm -rf install  2>/dev/null
  rm -rf $(ls -1d build/* 2>/dev/null | grep -v deps)    2>/dev/null
  if [ $download -eq 1 ]; then
    rm -rf download 2>/dev/null
  fi
}

if [ "$1" == "clean" ]; then
  clean
  exit 0
fi

function build_luajit() {
  echo "Build luajit"
  cd LuaJIT-$LUAJIT_VERSION
  make -j 8 > /dev/null
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  DESTDIR="$JIT_PREFIX" make install > /dev/null
  cd ..
}

function build_cJSON() {
  echo "Build cjson"
  cd lua-cjson
  PREFIX="$JIT_PREFIX/usr/local" make > /dev/null
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  cd ..
}

function build_debug() {
  cd nginx-$VERSION$SUFFIX
  echo "Configuring debug nginx-$VERSION$SUFFIX"
  ./configure --prefix="$INSTALL_PREFIX/nginx-$VERSION$SUFFIX" \
              --with-pcre=$PCRE_PREFIX \
              --with-http_stub_status_module \
              --with-stream \
              --with-debug \
              --with-http_auth_request_module \
              --with-cc-opt="-O0" \
              --add-module=../ngx_devel_kit \
              --add-module=../../../lua-nginx-module \
              --add-module=../echo-nginx-module \
              --add-module=../memc-nginx-module >/dev/null 2>&1
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi

  echo "Build debug nginx-$VERSION$SUFFIX"
  make -j 8 > /dev/null 2>/dev/stderr

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install > /dev/null

  cd ..
}

function download_module() {
  if [ -e $DIR/../$2 ]; then
    echo "Get $DIR/../$2"
    dir=$(pwd)
    cd $DIR/..
    tar zcf $dir/$2.tar.gz $(ls -1d $2/* | grep -vE "(install$)|(build$)|(download$)|(.git$)")
    cd $dir
  else
    if [ $download -eq 1 ] || [ ! -e $2.tar.gz ]; then
      echo "Download $2 branch=$3"
      curl -s -L -O https://github.com/$1/$2/archive/$3.zip
      unzip -q $3.zip
      mv $2-$3 $2
      tar zcf $2.tar.gz $2
      rm -rf $2 $3.zip
    fi
  fi
}

function gitclone() {
  git clone $1 > /dev/null 2> /tmp/err
  if [ $? -ne 0 ]; then
    cat /tmp/err
  fi
}

function download_nginx() {
  if [ $download -eq 1 ] || [ ! -e nginx-$VERSION.tar.gz ]; then
    echo "Download nginx-$VERSION"
    curl -s -L -O http://nginx.org/download/nginx-$VERSION.tar.gz
  else
    echo "Get nginx-$VERSION.tar.gz"
  fi
}

function download_luajit() {
  if [ $download -eq 1 ] || [ ! -e LuaJIT-$LUAJIT_VERSION.tar.gz ]; then
    echo "Download LuaJIT-$LUAJIT_VERSION"
    curl -s -L -O http://luajit.org/download/LuaJIT-$LUAJIT_VERSION.tar.gz
  else
    echo "Get LuaJIT-$LUAJIT_VERSION.tar.gz"
  fi
}

function download_pcre() {
  if [ $download -eq 1 ] || [ ! -e pcre-$PCRE_VERSION.tar.gz ]; then
    echo "Download PCRE-$PCRE_VERSION"
    curl -s -L -O http://ftp.cs.stanford.edu/pub/exim/pcre/pcre-$PCRE_VERSION.tar.gz
  else
    echo "Get pcre-$PCRE_VERSION.tar.gz"
  fi
}

function extract_downloads() {
  cd download

  for d in $(ls -1 *.tar.gz)
  do
    echo "Extracting $d"
    tar zxf $d -C ../build --no-overwrite-dir --keep-old-files 2>/dev/null
  done

  cd ..
}

function download() {
  mkdir build                2>/dev/null
  mkdir build/deps           2>/dev/null

  mkdir download             2>/dev/null
  mkdir download/lua_modules 2>/dev/null

  cd download

  download_luajit
  download_pcre
  download_nginx

  download_module simpl       ngx_devel_kit                    master
  download_module openresty   lua-cjson                        master
  download_module openresty   echo-nginx-module                master
  download_module openresty   memc-nginx-module                master

  cd ..
}

function install_file() {
  echo "Install $1"
  if [ ! -e "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2" ]; then
    mkdir -p "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2"
  fi
  cp -r $3 $1 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2/"
}

function install_files() {
  for f in $(ls $1)
  do
    install_file $f $2 $3
  done
}

function build() {
  cd build

  patch -N -p0 < ../lua-cjson-Makefile.patch

  if [ $build_deps -eq 1 ] || [ ! -e deps/luajit ]; then
    build_luajit
  fi

  build_cJSON

  make clean > /dev/null 2>&1
  build_debug

  install_file  "$JIT_PREFIX/usr/local/lib"           .
  install_file  lua-cjson/cjson.so                    lib/lua/5.1

  cd ..
}

clean
download
extract_downloads
build

function install_resty_module() {
  if [ -e $DIR/../$2 ]; then
    echo "Get $DIR/../$2"
    dir=$(pwd)
    cd $DIR/..
    zip -qr $dir/$2.zip $(ls -1d $2/* | grep -vE "(install$)|(build$)|(download$)|(.git$)")
    cd $dir
  else
    if [ $6 -eq 1 ] || [ ! -e $2-$5.zip ] ; then
      echo "Download $2 branch=$5"
      rm -rf $2-$5 2>/dev/null
      curl -s -L -O https://github.com/$1/$2/archive/$5.zip
      mv $5.zip $2-$5.zip
    else
      echo "Get $2-$5"
    fi
  fi
  echo "Install $2/$3"
  if [ ! -e "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4" ]; then
    mkdir -p "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4"
  fi
  if [ -e $2-$5.zip ]; then
    unzip -q $2-$5.zip
    cp -r $2-$5/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2-$5
  elif [ -e $2-$5.tar.gz ]; then
    tar zxf $2-$5.tar.gz
    cp -r $2-$5/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2-$5
  elif [ -e $2.zip ]; then
    unzip -q $2.zip
    cp -r $2/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2
  elif [ -e $2.tar.gz ]; then
    tar zxf $2.tar.gz
    cp -r $2/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2
  fi
}

function make_dir() {
  mkdir $INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$1
}

cd "$DIR"

kernel_name=$(uname -s)
kernel_version=$(uname -r)

cd install

tar zcvf nginx-$VERSION$SUFFIX-$kernel_name-$kernel_version.tar.gz nginx-$VERSION$SUFFIX
rm -rf nginx-$VERSION$SUFFIX

cd ..

exit $r