#!/bin/bash

set -e

AUTO_DISCOVERY_PATH="$1"

#
# Install build dependencies
#

BUILD_DEPS="debhelper fakeroot g++ git libc6-dev make cmake"
apt-get update
apt-get install -y --no-install-recommends $BUILD_DEPS

#
# Install Snap and Snap plugins
#

export GOPATH="/go"
GOPATH_ORIG=$GOPATH

mkdir -p "$GOPATH/src" "$GOPATH/bin"
chmod -R 777 "$GOPATH"

export PATH=/usr/local/go/bin:$GOPATH/bin/:$PATH

GIT_OPTS="-q"

go get github.com/tools/godep

# Get Snap
go get -d github.com/intelsdi-x/snap

# Get Snap plugins

# https://github.com/intelsdi-x/snap-plugin-collector-cpu/commit/c4a90ddf785835a3d6d830eb0292aa418b2bcd9e
REFSPEC="c4a90ddf785835a3d6d830eb0292aa418b2bcd9e"
go get -d github.com/intelsdi-x/snap-plugin-collector-cpu
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-cpu
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-df/commit/411e248ccf2c3897548a08336470b6390e9f6e68
REFSPEC="411e248ccf2c3897548a08336470b6390e9f6e68"
go get -d github.com/intelsdi-x/snap-plugin-collector-df
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-df
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-disk/commit/8af1b89502c584aba37c18da1d12313cee53f8a0
REFSPEC="8af1b89502c584aba37c18da1d12313cee53f8a0"
go get -d github.com/intelsdi-x/snap-plugin-collector-disk
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-disk
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-interface/commit/d2c8ff6bdf6277b4d2f3c653d603fe6b65d3196a
REFSPEC="d2c8ff6bdf6277b4d2f3c653d603fe6b65d3196a"
go get -d github.com/intelsdi-x/snap-plugin-collector-interface
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-interface
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-load/commit/dc0b214ace415f31093fea2ba89384c7f994102e
REFSPEC="dc0b214ace415f31093fea2ba89384c7f994102e"
go get -d github.com/intelsdi-x/snap-plugin-collector-load
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-load
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-meminfo/commit/983c4ae32ef38cb1acd886309f97a389a264179b
REFSPEC="983c4ae32ef38cb1acd886309f97a389a264179b"
go get -d github.com/intelsdi-x/snap-plugin-collector-meminfo
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-meminfo
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-processes/commit/c07278cdbe8126ea5a32db7442796cde575070a0
REFSPEC="c07278cdbe8126ea5a32db7442796cde575070a0"
go get -d github.com/intelsdi-x/snap-plugin-collector-processes
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-processes
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-swap/commit/4afdd8658cef1bb5744b38c9a77aa4589afd5f8d
REFSPEC="4afdd8658cef1bb5744b38c9a77aa4589afd5f8d"
go get -d github.com/intelsdi-x/snap-plugin-collector-swap
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-swap
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-collector-smart/commit/5f06ea6af9da44cd46cf675a984d1a94f608249f
REFSPEC="5f06ea6af9da44cd46cf675a984d1a94f608249f"
go get -d github.com/intelsdi-x/snap-plugin-collector-smart
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-smart
git checkout ${GIT_OPTS} ${REFSPEC}
make deps

# https://github.com/intelsdi-x/snap-plugin-publisher-heka/commit/e95f8cc48edf29fc8fd8ab2fa3f0c6f6ab054674
REFSPEC="e95f8cc48edf29fc8fd8ab2fa3f0c6f6ab054674"
go get -d github.com/intelsdi-x/snap-plugin-publisher-heka
cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-publisher-heka
git checkout ${REFSPEC}
make deps

# Build Snap

# https://github.com/intelsdi-x/snap/commit/4e6b19df7b7b7d4300429ba22b766c2ac70d2e29
REFSPEC="4e6b19df7b7b7d4300429ba22b766c2ac70d2e29"
cd $GOPATH/src/github.com/intelsdi-x/snap
git checkout ${GIT_OPTS} ${REFSPEC}
make deps all install
cp build/plugin/* /usr/local/bin/
ln -s /usr/local/bin/snap-plugin-processor-passthru $AUTO_DISCOVERY_PATH
# the mock-file publisher plugin may be useful for debugging
ln -s /usr/local/bin/snap-plugin-publisher-mock-file $AUTO_DISCOVERY_PATH

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
# only the "root" can read
chmod u+s /usr/local/bin/snap-plugin-collector-processes

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-swap
make all
cp build/rootfs/snap-plugin-collector-swap /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-swap $AUTO_DISCOVERY_PATH

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-collector-smart
make all
cp build/rootfs/snap-plugin-collector-smart /usr/local/bin
ln -s /usr/local/bin/snap-plugin-collector-smart $AUTO_DISCOVERY_PATH
# the SMART plugin accesses files like /dev/sdX which root
# root user only can read
chmod u+s /usr/local/bin/snap-plugin-collector-smart

cd $GOPATH/src/github.com/intelsdi-x/snap-plugin-publisher-heka
make all
cp build/rootfs/snap-plugin-publisher-heka /usr/local/bin
ln -s /usr/local/bin/snap-plugin-publisher-heka $AUTO_DISCOVERY_PATH

#
# Clean up
#
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf $GOPATH_ORIG

exit 0
