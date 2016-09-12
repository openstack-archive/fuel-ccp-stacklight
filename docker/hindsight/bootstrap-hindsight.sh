#!/bin/bash

tar cf - -C /opt/ccp/hindsight . 2>/dev/null| tar xf - -C /var/lib/hindsight 2>/dev/null
chown -R hindsight: /var/lib/hindsight/*
