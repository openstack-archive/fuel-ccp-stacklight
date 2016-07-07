#!/bin/bash

set -e

AUTO_DISCOVERY_PATH="$1"

#
# Install build dependencies
#

BUILD_DEPS="ca-certificates curl debhelper fakeroot g++ gcc git libc6-dev make cmake patch"
apt-get update
apt-get install -y --no-install-recommends $BUILD_DEPS

#
# Install Go
#

GOLANG_VERSION="1.6.2"
GOLANG_DOWNLOAD_URL="https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz"
GOLANG_DOWNLOAD_SHA256="e40c36ae71756198478624ed1bb4ce17597b3c19d243f3f0899bb5740d56212a"

curl -fsSL ${GOLANG_DOWNLOAD_URL} -o golang.tar.gz
echo "${GOLANG_DOWNLOAD_SHA256} golang.tar.gz" | sha256sum -c -
tar -C /usr/local -xzf golang.tar.gz
rm golang.tar.gz

#
# Install Snap and Snap plugins
#

export GOPATH="/go"
GOPATH_ORIG=$GOPATH

mkdir -p "$GOPATH/src" "$GOPATH/bin"
chmod -R 777 "$GOPATH"

export PATH=/usr/local/go/bin:$GOPATH/bin/:$PATH

go get github.com/tools/godep

# Get Snap
go get -d github.com/intelsdi-x/snap

# Get Snap plugins
#REFSPEC=""
REFSPEC="dynamic-metrics"
go get -d github.com/intelsdi-x/snap-plugin-collector-cpu
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-cpu
git fetch https://github.com/obourdon/snap-plugin-collector-cpu ${REFSPEC}
git checkout FETCH_HEAD
#git checkout ${REFSPEC}
make deps

#REFSPEC=""
REFSPEC="all_in_1"
go get -d github.com/intelsdi-x/snap-plugin-collector-df
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-df
git fetch https://github.com/obourdon/snap-plugin-collector-df ${REFSPEC}
git checkout FETCH_HEAD
#git checkout ${REFSPEC}
make deps

REFSPEC="8af1b89502c584aba37c18da1d12313cee53f8a0"
# Dated Jul 11: Disk metrics should be dynamic (#10)
# Missing 1 PR: Default example task should work straight out of the box
# but this PR is not necessary for MCP
go get -d github.com/intelsdi-x/snap-plugin-collector-disk
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-disk
git checkout ${REFSPEC}
make deps

REFSPEC="d2c8ff6bdf6277b4d2f3c653d603fe6b65d3196a"
# Dated Jul 13: Merge pull request #12 from obourdon/dynamic_metrics
go get -d github.com/intelsdi-x/snap-plugin-collector-interface
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-interface
git checkout ${REFSPEC}
make deps

REFSPEC="dc0b214ace415f31093fea2ba89384c7f994102e"
# Dated Jun 17: Merge pull request #9 from marcin-krolik/kromar-fix-8
go get -d github.com/intelsdi-x/snap-plugin-collector-load
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-load
git checkout ${REFSPEC}
make deps

REFSPEC="983c4ae32ef38cb1acd886309f97a389a264179b"
# Dated Jul 11: Merge pull request #17 from obourdon/master
go get -d github.com/intelsdi-x/snap-plugin-collector-meminfo
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-meminfo
git checkout ${REFSPEC}
make deps

REFSPEC="44bba68fcee318e7f1eec70bdef988c67c77eb8e"
# Dated Jul 1: Merge pull request #15 from marcin-krolik/kromar-fix-13
go get -d github.com/intelsdi-x/snap-plugin-collector-processes
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-processes
git checkout ${REFSPEC}
make deps

#REFSPEC=""
REFSPEC="all_in_1"
go get -d github.com/intelsdi-x/snap-plugin-collector-smart
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-smart
git fetch https://github.com/obourdon/snap-plugin-collector-smart ${REFSPEC}
git checkout FETCH_HEAD
#git checkout ${REFSPEC}
make deps

#REFSPEC=""
REFSPEC="all_in_1"
# TODO: same issue for swap devices metrics names than for df partitions
go get -d github.com/intelsdi-x/snap-plugin-collector-swap
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-swap
git fetch https://github.com/obourdon/snap-plugin-collector-swap ${REFSPEC}
git checkout FETCH_HEAD
#git checkout ${REFSPEC}
make deps

# Build Snap
REFSPEC="5137f6cb389b3502b8d79d05aac2d5a6ecec1b41"
cd $GOPATH/src/github.com/intelsdi-x/snap
git checkout ${REFSPEC}
make deps all install
cp build/plugin/* /usr/local/bin/
ln -s /usr/local/bin/snap-processor-passthru $AUTO_DISCOVERY_PATH

# Build Snap plugins
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-cpu
make all
cp build/rootfs/snap-plugin-collector-cpu /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-cpu $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-df
make all
cp build/rootfs/snap-plugin-collector-df /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-df $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-disk
make all
cp build/rootfs/snap-plugin-collector-disk /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-disk $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-interface
make all
cp build/rootfs/snap-plugin-collector-interface /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-interface $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-load
make all
cp build/rootfs/snap-plugin-collector-load /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-load $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-meminfo
make all
cp build/rootfs/snap-plugin-collector-meminfo /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-meminfo $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-processes
make all
cp build/rootfs/snap-plugin-collector-processes /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-processes $AUTO_DISCOVERY_PATH
# the "processes" plugin accesses files like /proc/1/io which
# root user only can read
chmod u+s /usr/local/bin/snap-plugin-collector-processes

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-smart
make all
cp build/rootfs/snap-plugin-collector-smart /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-smart $AUTO_DISCOVERY_PATH
# the SMART plugin accesses files like /dev/sdX which root
# root user only can read
chmod u+s /usr/local/bin/snap-plugin-collector-smart

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-swap
make all
cp build/rootfs/snap-plugin-collector-swap /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-swap $AUTO_DISCOVERY_PATH

# Get Heka and build the minimun required for the Heka publisher plugin
REFSPEC="e8799385d16915a80b69061d05542da6342e58e4"
cd /tmp
git clone -b dev --single-branch https://github.com/mozilla-services/heka
cd heka
git checkout ${REFSPEC}
source env.sh  # changes GOPATH to /tmp/heka/build/heka
mkdir -p build
cd build
cmake ..
make message_matcher_parser

# Get and build Heka plugin
REFSPEC="463a89e3b4eaee6c4f177f3432b4dd2a518fcf86"
go get -d github.com/intelsdi-x/snap-plugin-publisher-heka
cd $GOPATH/src/github.com/intelsdi-x/snap
make deps
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-publisher-heka
git checkout ${REFSPEC}
make deps all
cp build/rootfs/snap-plugin-publisher-heka /usr/local/bin
ln -s /usr/local/bin/snap-plugin-publisher-heka $AUTO_DISCOVERY_PATH
rm -rf /tmp/heka

#
# Clean up
#
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf $GOPATH_ORIG
rm -rf /usr/local/go

exit 0
