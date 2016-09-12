#!/bin/bash

set -e

#
# Clean up
#
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*

exit 0
