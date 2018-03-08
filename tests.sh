#!/bin/bash

DIR=$(pwd)
nginx_fname=$(ls -1 $DIR/install/*.tar.gz)

[ -d install/tmp ] || mkdir install/tmp
tar zxf $nginx_fname -C install/tmp

folder="$(ls -1 $DIR/install/tmp | grep nginx)"

export PATH=$DIR/install/tmp/$folder/sbin:$PATH
export LD_LIBRARY_PATH=$DIR/install/tmp/$folder/lib

export LUA_CPATH=$DIR/install/tmp/$folder/lib/lua/5.1/cjson.so

ret=0

for t in $(ls t/*.t)
do
  echo "Tests : "$t
  prove $t
  if [ $? -ne 0 ]; then
    ret=$?
  fi
done

rm -rf t/servroot
rm -rf install/tmp

exit $ret