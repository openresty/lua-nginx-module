#!/bin/bash
script_dir=$(dirname $0)
root=$(readlink -f $script_dir/..)
cd $root
git submodule update
$script_dir/reindex $root/t/*.t
export PATH=$root/work/sbin:$PATH
killall nginx
prove -I$root/t/test-nginx/lib $root/t/*.t

