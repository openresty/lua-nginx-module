#!/bin/bash
script_dir=$(dirname $0)
root=$(readlink -f $script_dir/..)
testfile=${1:-$root/t/*.t}
cd $root
git submodule update --init
$script_dir/reindex $root/t/*.t
export PATH=$root/work/sbin:$PATH
killall nginx
prove -I$root/t/test-nginx/lib $testfile

