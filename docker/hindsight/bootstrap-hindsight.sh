#!/bin/bash

# This script is used for bootstrapping
# Hindsight with proper directories contents
# when using emptydir Kubernetes volumes
# As these are created empty
# Hindsight will not start properly
# as files will be missing
# Therefore the need to run this script
# with the proper destination directory
# as its command line parameter

set -e

if [ $# -ne 1 ]; then
	echo "Usage: $0 directory"
	exit 1
fi

if [ ! -d "$1" ]; then
	echo "Error: $1 does not exist or is not a directory"
	exit 1
fi

SRC=/opt/ccp/hindsight
if [ ! -d "$SRC" ]; then
	echo "Error: $SRC does not exist or is not a directory"
	exit 1
fi

tar cf - -C $SRC . | tar xf - -C $1 --strip-components=1
