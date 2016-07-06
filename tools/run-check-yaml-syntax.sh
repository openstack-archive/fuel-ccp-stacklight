#!/bin/bash

### Temp yaml syntax checker script.
set -e
for file in $(find . -name '*.yaml'); do
    yamllint -d relaxed $file
done
