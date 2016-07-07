#!/bin/bash

set -e

#
# Install build dependencies
#

BUILD_DEPS="git g++ make cmake"
apt-get update
apt-get install -y --no-install-recommends $BUILD_DEPS

#
# Build lua_sandbox
#

cd /tmp
git clone https://github.com/mozilla-services/lua_sandbox.git
cd lua_sandbox
# last tested commit
# https://github.com/mozilla-services/lua_sandbox/commit/f1ee9eb19f4d237b78b585a8b1c6d056e3b3c9fb
git checkout f1ee9eb19f4d237b78b585a8b1c6d056e3b3c9fb
mkdir release
cd release
cmake -DCMAKE_BUILD_TYPE=release ..
make
make install

#
# Build Hindsight
#

cd /tmp
git clone https://github.com/trink/hindsight
cd hindsight
# last tested commit
# https://github.com/trink/hindsight/commit/056321863d4e03f843bbac48ace3ed5e88e4b8fc
git checkout 056321863d4e03f843bbac48ace3ed5e88e4b8fc
mkdir release
cd release
cmake -DCMAKE_BUILD_TYPE=release ..
make
make install

#
# Create Hindsight dirs and copy lua_sandbox and Hindsight plugins
# into Hindsight's "run" directory
#

mkdir -p \
 /etc/hindsight \
 /var/lib/hindsight/output \
 /var/lib/hindsight/load/analysis \
 /var/lib/hindsight/load/input \
 /var/lib/hindsight/load/output \
 /var/lib/hindsight/run/analysis \
 /var/lib/hindsight/run/input \
 /var/lib/hindsight/run/output

cp /tmp/lua_sandbox/sandboxes/heka/input/heka_tcp.lua /var/lib/hindsight/run/input/
cp /tmp/lua_sandbox/sandboxes/heka/input/syslog_udp.lua /var/lib/hindsight/run/input/
cp /tmp/hindsight/sandboxes/input/prune_input.lua /var/lib/hindsight/run/input/

#
# Remove build directories
#
rm -rf /tmp/lua_sandbox /tmp/hindsight
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*

exit 0
