#!/bin/bash

GRAFANA_PORT="3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"

INFLUXDB_HOST="influxdb"
INFLUXDB_PORT="8086"
INFLUXDB_DATABASE="mcp"
INFLUXDB_USER=""
INFLUXDB_PASSWORD=""

DASHBOARD_LOCATION="/dashboards"

echo "Starting Grafana in the background"
set -m
exec /usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini cfg:default.paths.data=/var/lib/grafana cfg:default.paths.logs=/var/log/grafana &

echo "Waiting for Grafana to come up..."
until $(curl --fail --output /dev/null --silent http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@localhost:${GRAFANA_PORT}/api/org); do
    printf "."
    sleep 2
done

echo "Grafana is up and running."

echo "Creating InfluxDB datasource..."
curl -i -XPOST -H "Accept: application/json" -H "Content-Type: application/json" "http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@localhost:${GRAFANA_PORT}/api/datasources" -d '
{
    "name": "MCP InfluxDB",
    "type": "influxdb",
    "access": "proxy",
    "isDefault": true,
    "url": "'"http://${INFLUXDB_HOST}:${INFLUXDB_PORT}"'",
    "password": "'"${INFLUXDB_PASSWORD}"'",
    "user": "'"${INFLUXDB_USER}"'",
    "database": "'"${INFLUXDB_DATABASE}"'"
}'

echo ""
echo "Importing default dashboards..."
for dashboard in ${DASHBOARD_LOCATION}/*.json; do
    echo "Importing ${dashboard} ..."
    curl -i -XPOST --data "@${dashboard}" -H "Accept: application/json" -H "Content-Type: application/json" "http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@localhost:${GRAFANA_PORT}/api/dashboards/db"
    echo ""
    echo "Done importing ${dashboard}"
done

echo ""
echo "Bringing Grafana back to the foreground"
fg
