#!/bin/bash
set -o pipefail
ns="${NS:-ccp}"
ip="${ESIP:-$(kubectl get pods --namespace $ns --selector=app=elasticsearch  --output=jsonpath={.items..status.podIP} 2>/dev/null)}"
type kubectl 2>/dev/null || ip="${ip:-localhost}"
index="${ESIND:-_all}"
size="${SIZE:-50}"
format="\(.Timestamp) \(.Hostname) \(.Logger).\(.programname) \(.severity_label) \(.python_module) [\(.request_id)] -- \(.Payload)"
search="${1:-/error|alert|trace.*|crit.*|fatal/}"
if [ -z "${ip}" ]; then
  echo "ES can't be found!" >&2
  exit 1
fi
if [ "${index}" = "_all" ]; then
  echo "Search in _all. See 'curl -s $ip:9200/_cat/indices' for the full list of indexes available."
  echo
fi
if [ -z "${1}" ]; then
  echo "Use default search pattern: ${search}"
  echo
fi

echo "${format}" | sed -e 's/\\(.//g;s/)//g'
curl -s -XPOST "$ip:9200/${index}/_search?analyze_wildcard=true&sort=Timestamp:asc&size=$size&q=${search}" |\
  jq -M ".hits.hits[]._source | \"${format}\"" |\
  perl -pe 's/^"?//;s/\\n"?$//'
if [ $? -ne 0 ]; then
  echo "Failed to query ES!" >&2
  exit 1
fi