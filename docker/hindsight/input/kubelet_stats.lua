--
-- This sandbox queries the kubelet "stats" API to collect statistics on Kubernetes
-- pods and namespaces.
--
-- The sandbox injects Heka messages for the following metrics:
--
-- * k8s_check: Expresses the success or failure of the data collection.
-- * k8s_pods_count: The number of pods in a given namespace.
-- * k8s_pods_count_total: The total number of pods on the node.
-- * k8s_pod_cpu_usage: The CPU usage of a given pod. For example 50 means that
--   the pod consumes 50% of CPU. The value may be greater than 100 on
--   multicore nodes.
-- * k8s_namespace_cpu_usage: The CPU usage of all the pods of a given namespace.
-- * k8s_pods_cpu_usage: The CPU usage of all the pods on the node.
-- * k8s_pod_memory_usage: The memory in Bytes used by a given pod. For example
--   100000 means that the pod consumes 100000 Bytes of memory.
-- * k8s_namespace_memory_usage: The memory in Bytes used by all the pods of
--   a given namespace.
-- * k8s_pods_memory_usage: The memory in Bytes used by all the pods on the
--   node.
-- * k8s_pod_working_set: The working set in Bytes of a given pod.
-- * k8s_namespace_working_set: The working set in Bytes of all the pods of a
--   given namespace.
-- * k8s_pods_working_set: The working set in Bytes of all the pods on the
--   node.
-- * k8s_pod_major_page_faults: The number of major page faults per second
--   for a given pod.
-- * k8s_namespace_major_page_faults: The number of major page faults per second
--   for all the pods of a given namespace.
-- * k8s_pods_major_page_faults: The number of major page faults per second for
--   all the pods on the node.
-- * k8s_pod_page_faults: The number of minor page faults per second for
--   a given pod.
-- * k8s_namespace_page_faults: The number of minor page faults per second for
--   all the pods of a given namespace.
-- * k8s_pods_page_faults: The number of minor page faults per second for all
--   the pods on the node.
-- * k8s_pod_rx_bytes: The number of bytes per second received over the network
--   for a given pod.
-- * k8s_namespace_rx_bytes: The number of bytes per second received over the
--   network for all the pods of a given namespace.
-- * k8s_pods_rx_bytes: The number of bytes per second received over the
--   network for all the pods on the node.
-- * k8s_pod_tx_bytes: The number of bytes per second sent over the network
--   for a given pod.
-- * k8s_namespace_tx_bytes: The number of bytes per second sent over the
--   network for all the pods of a given namespace.
-- * k8s_pods_tx_bytes: The number of bytes per second sent over the
--   network for all the pods on the node.
-- * k8s_pod_rx_errors: The number of errors per second received over the network
--   for a given pod.
-- * k8s_namespace_rx_errors: The number of errors per second received over the
--   network for all the pods of a given namespace.
-- * k8s_pods_rx_errors: The number of errors per second received over the
--   network for all the pods on the node.
-- * k8s_pod_tx_errors: The number of errors per second sent over the network
--   for a given pod.
-- * k8s_namespace_tx_errors: The number of errors per second sent over the
--   network for all the pods of a given namespace.
-- * k8s_pods_tx_errors: The number of errors per second sent over the
--   network for all the pods on the node.
--
-- Configuration variables:
--
-- * kubernetes_host: The hostname or IP to use to access the Kubernetes
--   API. Optional. Default is "kubernetes".
-- * kubelet_stats_node: The name of the Kubernetes node onto which the
--   Kubelet to query runs. At init time the plugin uses the Kubernetes API
--   to get the corresponding internal IP address. Required.
-- * kubelet_stats_port: The port to use to access the Kubelet stats API.
--   Optional. Default value is 10255.
--
-- Configuration example:
--
--     filename = "kubelet_stats.lua"
--     kubelet_stats_node = "node1"
--     kubelet_stats_port = 10255
--     ticker_interval = 10 -- query Kubelet every 10 seconds
--


local cjson = require 'cjson'
local date_time = require 'lpeg.date_time'
local http = require 'socket.http'
local https = require 'ssl.https'
local io = require 'io'
local ltn12 = require 'ltn12'


local function read_file(path)
    local fh, err = io.open(path, 'r')
    if err then return nil, err end
    local content = fh:read('*all')
    fh:close()
    return content, nil
end


-- get the node IP for "node_name". Done by querying the Kubernetes API
local function get_node_ip_address(kubernetes_host, node_name)
    local token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
    local token, err_msg = read_file(token_path)
    if not token then
        return nil, err_msg
    end
    local url = string.format('https://%s/api/v1/nodes/%s',
        kubernetes_host, node_name)
    local resp_body = {}
    local res, code, headers, status = https.request {
        url = url,
        cafile = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
        headers = {
            Authorization = string.format('Bearer %s', token)
        },
        sink = ltn12.sink.table(resp_body)
    }
    if not res then
        return nil, code
    end
    local ok, doc = pcall(cjson.decode, table.concat(resp_body))
    if not ok then
        local err_msg = string.format(
            'HTTP response does not contain valid JSON: %s', doc)
        return nil, err_msg
    end
    local status = doc['status']
    if not status then
        return nil, 'HTTP JSON does not contain node status'
    end
    local addresses = status['addresses']
    if not addresses then
        return nil, 'HTTP JSON does not contain node addresses'
    end
    for _, address in ipairs(addresses) do
        if address['type'] == 'InternalIP' then
            return address['address'], ''
        end
    end
    return nil, string.format('No IP address found for %s', node_name)
end

local kubernetes_host = read_config('kubernetes_host') or 'kubernetes'
local kubelet_stats_port = read_config('kubelet_stats_port') or 10255
local kubelet_stats_node = read_config('kubelet_stats_node')
assert(kubelet_stats_node, 'kubelet_stats_node missing in plugin config')

local kubelet_stats_ip_address, err_msg = get_node_ip_address(
    kubernetes_host, kubelet_stats_node)
assert(kubelet_stats_ip_address, err_msg)

local summary_url = string.format('http://%s:%d/stats/summary',
    kubelet_stats_ip_address, kubelet_stats_port)

local pods_stats = {}

-- message skeletons for each metric type
local k8s_check_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_check',
        value = nil,
        dimensions = {'hostname'},
        hostname = nil
    }
}
local k8s_pod_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = nil,
        value = nil,
        dimensions = {'pod_name', 'pod_namespace', 'hostname'},
        hostname = nil,
        pod_name = nil,
        pod_namespace = nil
    }
}
local k8s_namespace_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = nil,
        value = nil,
        dimensions = {'pod_namespace', 'hostname'},
        hostname = nil,
        pod_namespace = nil
    }
}
local k8s_pods_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = nil,
        value = nil,
        dimensions = {'hostname'},
        hostname = nil
    }
}


-- inject a pod-level metric message
local function inject_pod_metric(name, value, hostname, pod_namespace, pod_name)
    k8s_pod_msg.Fields.name = name
    k8s_pod_msg.Fields.value = value
    k8s_pod_msg.Fields.hostname = hostname
    k8s_pod_msg.Fields.pod_namespace = pod_namespace
    k8s_pod_msg.Fields.pod_name = pod_name
    inject_message(k8s_pod_msg)
end


-- inject a namespace-level metric message
local function inject_namespace_metric(name, value, hostname, pod_namespace)
    k8s_namespace_msg.Fields.name = name
    k8s_namespace_msg.Fields.value = value
    k8s_namespace_msg.Fields.hostname = hostname
    k8s_namespace_msg.Fields.pod_namespace = pod_namespace
    inject_message(k8s_namespace_msg)
end


-- inject a node-level metric message
local function inject_pods_metric(name, value, hostname)
    k8s_pods_msg.Fields.name = name
    k8s_pods_msg.Fields.value = value
    k8s_pods_msg.Fields.hostname = hostname
    inject_message(k8s_pods_msg)
end


-- Send a "stats" query to kubelet, and return the JSON response in a Lua table
local function send_stats_query()
    local resp_body, resp_status = http.request(summary_url)
    if resp_body and resp_status == 200 then
        -- success
        local ok, doc = pcall(cjson.decode, resp_body)
        if ok then
            return doc, ''
        else
            local err_msg = string.format('HTTP response does not contain valid JSON: %s', doc)
            return nil, err_msg
        end
    else
        -- error
        local err_msg = resp_status
        if resp_body then
            err_msg = string.format('kubelet stats query error: [%s] %s',
                resp_status, resp_body)
        end
        return nil, err_msg
    end
end


-- Collect cpu statistics for a container
local function collect_container_cpu_stats(container_cpu, prev_stats, curr_stats)
    local cpu_usage
    if container_cpu then
        local cpu_scrape_time = date_time.rfc3339:match(container_cpu['time'])
        curr_stats.cpu = {
            scrape_time = date_time.time_to_ns(cpu_scrape_time),
            usage = container_cpu['usageCoreNanoSeconds']
        }
        if prev_stats and prev_stats.cpu then
            local time_diff = curr_stats.cpu.scrape_time - prev_stats.cpu.scrape_time
            if time_diff > 0 then
                cpu_usage = 100 *
                    (curr_stats.cpu.usage - prev_stats.cpu.usage) / time_diff
            end
        end
    end
    return cpu_usage
end


-- Collect memory statistics for a container
local function collect_container_memory_stats(container_memory, prev_stats, curr_stats)
    local memory_usage, major_page_faults, page_faults, working_set
    if container_memory then
        memory_usage = container_memory['usageBytes']
        working_set = container_memory['workingSetBytes']
        local memory_scrape_time = date_time.rfc3339:match(container_memory['time'])
        curr_stats.memory = {
            scrape_time = date_time.time_to_ns(memory_scrape_time),
            major_page_faults = container_memory['majorPageFaults'],
            page_faults = container_memory['pageFaults']
        }
        if prev_stats and prev_stats.memory then
            local time_diff = curr_stats.memory.scrape_time - prev_stats.memory.scrape_time
            if time_diff > 0 then
                major_page_faults = 1e9 *
                    (curr_stats.memory.major_page_faults -
                     prev_stats.memory.major_page_faults) / time_diff
                page_faults = 1e9 *
                    (curr_stats.memory.page_faults -
                     prev_stats.memory.page_faults) / time_diff
            end
        end
    end
    return memory_usage, major_page_faults, page_faults, working_set
end


-- Collect statistics for a container
local function collect_container_stats(container, prev_stats, curr_stats)
    -- cpu stats
    local cpu_usage =
        collect_container_cpu_stats(container['cpu'], prev_stats, curr_stats)
    -- memory stats
    local memory_usage, major_page_faults, page_faults, working_set =
        collect_container_memory_stats(container['memory'], prev_stats, curr_stats)
    return cpu_usage, memory_usage, major_page_faults, page_faults, working_set
end


-- Collect statistics for a group of containers
local function collect_containers_stats(containers, prev_stats, curr_stats)
    local aggregated_cpu_usage, aggregated_memory_usage,
        aggregated_major_page_faults, aggregated_page_faults,
        aggregated_working_set
    for _, container in ipairs(containers) do
        local container_name = container['name']
        curr_stats[container_name] = {}
        local container_prev_stats
        if prev_stats then
            container_prev_stats = prev_stats[container_name]
        end
        local cpu_usage, memory_usage, major_page_faults, page_faults, working_set =
            collect_container_stats(container,
                container_prev_stats, curr_stats[container_name])
        if cpu_usage then
            aggregated_cpu_usage = (aggregated_cpu_usage or 0) + cpu_usage
        end
        if memory_usage then
            aggregated_memory_usage = (aggregated_memory_usage or 0) + memory_usage
        end
        if major_page_faults then
            aggregated_major_page_faults = (aggregated_major_page_faults or 0) +
                major_page_faults
        end
        if page_faults then
            aggregated_page_faults = (aggregated_page_faults or 0) + page_faults
        end
        if working_set then
            aggregated_working_set = (aggregated_working_set or 0) + working_set
        end
    end
    return aggregated_cpu_usage, aggregated_memory_usage,
        aggregated_major_page_faults, aggregated_page_faults,
        aggregated_working_set
end


-- Collect statistics for a pod
local function collect_pod_stats(pod, prev_stats, curr_stats)
    curr_stats.containers = {}
    local containers_prev_stats
    if prev_stats then
        containers_prev_stats = prev_stats.containers
    end

    -- collect cpu and memory containers stats
    local cpu_usage, memory_usage, major_page_faults, page_faults, working_set =
        collect_containers_stats(pod['containers'] or {},
            containers_prev_stats, curr_stats.containers)

    -- collect network stats
    local rx_bytes, tx_bytes, rx_errors, tx_errors
    local pod_network = pod['network']
    if pod_network then
        local network_scrape_time = date_time.rfc3339:match(pod_network['time'])
        curr_stats.network = {
            scrape_time = date_time.time_to_ns(network_scrape_time),
            rx_bytes = pod_network['rxBytes'],
            tx_bytes = pod_network['txBytes'],
            rx_errors = pod_network['rxErrors'],
            tx_errors = pod_network['txErrors']
        }
        if prev_stats and prev_stats.network then
            local time_diff = curr_stats.network.scrape_time -
                prev_stats.network.scrape_time
            if time_diff > 0 then
                rx_bytes = 1e9 *
                    (curr_stats.network.rx_bytes -
                     prev_stats.network.rx_bytes) / time_diff
                tx_bytes = 1e9 *
                    (curr_stats.network.tx_bytes -
                     prev_stats.network.tx_bytes) / time_diff
                rx_errors = 1e9 *
                    (curr_stats.network.rx_errors -
                     prev_stats.network.rx_errors) / time_diff
                tx_errors = 1e9 *
                    (curr_stats.network.tx_errors -
                     prev_stats.network.tx_errors) / time_diff
            end
        end
    end

    return cpu_usage, memory_usage, major_page_faults, page_faults, working_set,
           rx_bytes, tx_bytes, rx_errors, tx_errors
end


-- Collect statistics for a group of pods
local function collect_pods_stats(node_name, pods, prev_stats, curr_stats)
    local pods_count_by_ns = {}
    local pods_stats_by_ns = {}

    local pods_count_total = 0
    local pods_cpu_usage = 0
    local pods_memory_usage = 0
    local pods_major_page_faults = 0
    local pods_page_faults = 0
    local pods_working_set = 0
    local pods_rx_bytes = 0
    local pods_tx_bytes = 0
    local pods_rx_errors = 0
    local pods_tx_errors = 0

    for _, pod in ipairs(pods) do
        local pod_ref = pod['podRef']
        local pod_uid = pod_ref['uid']
        local pod_name = pod_ref['name']
        local pod_namespace = pod_ref['namespace']

        curr_stats[pod_uid] = {}

        local pod_cpu_usage,
              pod_memory_usage,
              pod_major_page_faults,
              pod_page_faults,
              pod_working_set,
              pod_rx_bytes,
              pod_tx_bytes,
              pod_rx_errors,
              pod_tx_errors = collect_pod_stats(
                pod, prev_stats[pod_uid], curr_stats[pod_uid])

        if pod_cpu_usage then
            -- inject k8s_pod_cpu_usage metric
            inject_pod_metric('k8s_pod_cpu_usage',
                pod_cpu_usage, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {cpu_usage = pod_cpu_usage}
            else
                pods_stats_by_ns[pod_namespace].cpu_usage =
                    (pods_stats_by_ns[pod_namespace].cpu_usage or 0) + pod_cpu_usage
            end

            pods_cpu_usage = pods_cpu_usage + pod_cpu_usage
        end

        if pod_memory_usage then
            -- inject k8s_pod_memory_usage metric
            inject_pod_metric('k8s_pod_memory_usage',
                pod_memory_usage, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {memory_usage = pod_memory_usage}
            else
                pods_stats_by_ns[pod_namespace].memory_usage =
                    (pods_stats_by_ns[pod_namespace].memory_usage or 0) + pod_memory_usage
            end

            pods_memory_usage = pods_memory_usage + pod_memory_usage
        end

        if pod_major_page_faults then
            -- inject k8s_pod_major_page_faults metric
            inject_pod_metric('k8s_pod_major_page_faults',
                pod_major_page_faults, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {major_page_faults = pod_major_page_faults}
            else
                pods_stats_by_ns[pod_namespace].major_page_faults =
                    (pods_stats_by_ns[pod_namespace].major_page_faults or 0) + pod_major_page_faults
            end

            pods_major_page_faults = pods_major_page_faults + pod_major_page_faults
        end

        if pod_page_faults then
            -- inject k8s_pod_page_faults metric
            inject_pod_metric('k8s_pod_page_faults',
                pod_page_faults, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {page_faults = pod_page_faults}
            else
                pods_stats_by_ns[pod_namespace].page_faults =
                    (pods_stats_by_ns[pod_namespace].page_faults or 0) + pod_page_faults
            end

            pods_page_faults = pods_page_faults + pod_page_faults
        end

        if pod_working_set then
            -- inject k8s_pod_working_set metric
            inject_pod_metric('k8s_pod_working_set',
                pod_working_set, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {working_set = pod_working_set}
            else
                pods_stats_by_ns[pod_namespace].working_set =
                    (pods_stats_by_ns[pod_namespace].working_set or 0) + pod_working_set
            end

            pods_working_set = pods_working_set + pod_working_set
        end

        if pod_rx_bytes then
            -- inject k8s_pod_rx_bytes metric
            inject_pod_metric('k8s_pod_rx_bytes',
                pod_rx_bytes, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {rx_bytes = pod_rx_bytes}
            else
                pods_stats_by_ns[pod_namespace].rx_bytes =
                    (pods_stats_by_ns[pod_namespace].rx_bytes or 0) + pod_rx_bytes
            end

            pods_rx_bytes = pods_rx_bytes + pod_rx_bytes
        end

        if pod_tx_bytes then
            -- inject k8s_pod_tx_bytes metric
            inject_pod_metric('k8s_pod_tx_bytes',
                pod_tx_bytes, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {tx_bytes = pod_tx_bytes}
            else
                pods_stats_by_ns[pod_namespace].tx_bytes =
                    (pods_stats_by_ns[pod_namespace].tx_bytes or 0) + pod_tx_bytes
            end

            pods_tx_bytes = pods_tx_bytes + pod_tx_bytes
        end

        if pod_rx_errors then
            -- inject k8s_pod_rx_errors metric
            inject_pod_metric('k8s_pod_rx_errors',
                pod_rx_errors, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {rx_errors = pod_rx_errors}
            else
                pods_stats_by_ns[pod_namespace].rx_errors =
                    (pods_stats_by_ns[pod_namespace].rx_errors or 0) + pod_rx_errors
            end

            pods_rx_errors = pods_rx_errors + pod_rx_errors
        end

        if pod_tx_errors then
            -- inject k8s_pod_tx_errors metric
            inject_pod_metric('k8s_pod_tx_errors',
                pod_tx_errors, node_name, pod_namespace, pod_name)

            if not pods_stats_by_ns[pod_namespace] then
                pods_stats_by_ns[pod_namespace] = {tx_errors = pod_tx_errors}
            else
                pods_stats_by_ns[pod_namespace].tx_errors =
                    (pods_stats_by_ns[pod_namespace].tx_errors or 0) + pod_tx_errors
            end

            pods_tx_errors = pods_tx_errors + pod_tx_errors
        end

        if not pods_count_by_ns[pod_namespace] then
            pods_count_by_ns[pod_namespace] = 1
        else
            pods_count_by_ns[pod_namespace] = pods_count_by_ns[pod_namespace] + 1
        end
        pods_count_total = pods_count_total + 1
    end

    for pod_namespace, namespace_stats in pairs(pods_stats_by_ns) do
        if namespace_stats.cpu_usage then
            -- inject k8s_namespace_cpu_usage metric
            inject_namespace_metric('k8s_namespace_cpu_usage',
                namespace_stats.cpu_usage, node_name, pod_namespace)
        end
        if namespace_stats.memory_usage then
            -- inject k8s_namespace_memory_usage metric
            inject_namespace_metric('k8s_namespace_memory_usage',
                namespace_stats.memory_usage, node_name, pod_namespace)
        end
        if namespace_stats.major_page_faults then
            -- inject k8s_namespace_major_page_faults metric
            inject_namespace_metric('k8s_namespace_major_page_faults',
                namespace_stats.major_page_faults, node_name, pod_namespace)
        end
        if namespace_stats.page_faults then
            -- inject k8s_namespace_page_faults metric
            inject_namespace_metric('k8s_namespace_page_faults',
                namespace_stats.page_faults, node_name, pod_namespace)
        end
        if namespace_stats.working_set then
            -- inject k8s_namespace_working_set metric
            inject_namespace_metric('k8s_namespace_working_set',
                namespace_stats.working_set, node_name, pod_namespace)
        end
        if namespace_stats.rx_bytes then
            -- inject k8s_namespace_rx_bytes metric
            inject_namespace_metric('k8s_namespace_rx_bytes',
                namespace_stats.rx_bytes, node_name, pod_namespace)
        end
        if namespace_stats.tx_bytes then
            -- inject k8s_namespace_tx_bytes metric
            inject_namespace_metric('k8s_namespace_tx_bytes',
                namespace_stats.tx_bytes, node_name, pod_namespace)
        end
        if namespace_stats.rx_errors then
            -- inject k8s_namespace_rx_errors metric
            inject_namespace_metric('k8s_namespace_rx_errors',
                namespace_stats.rx_errors, node_name, pod_namespace)
        end
        if namespace_stats.tx_errors then
            -- inject k8s_namespace_tx_errors metric
            inject_namespace_metric('k8s_namespace_tx_errors',
                namespace_stats.tx_errors, node_name, pod_namespace)
        end
    end

    for pod_namespace, pods_count in pairs(pods_count_by_ns) do
        -- inject k8s_pods_count metric
        inject_namespace_metric('k8s_pods_count',
            pods_count, node_name, pod_namespace)
    end

    -- inject k8s_pods_count_total metric
    inject_pods_metric('k8s_pods_count_total', pods_count_total, node_name)

    -- inject k8s_pods_cpu_usage metric
    inject_pods_metric('k8s_pods_cpu_usage', pods_cpu_usage, node_name)

    -- inject k8s_pods_memory_usage metric
    inject_pods_metric('k8s_pods_memory_usage', pods_memory_usage, node_name)

    -- inject k8s_pods_major_page_faults metric
    inject_pods_metric('k8s_pods_major_page_faults', pods_major_page_faults, node_name)

    -- inject k8s_pods_page_faults metric
    inject_pods_metric('k8s_pods_page_faults', pods_page_faults, node_name)

    -- inject k8s_pods_working_set metric
    inject_pods_metric('k8s_pods_working_set', pods_working_set, node_name)

    -- inject k8s_pods_rx_bytes metric
    inject_pods_metric('k8s_pods_rx_bytes', pods_rx_bytes, node_name)

    -- inject k8s_pods_tx_bytes metric
    inject_pods_metric('k8s_pods_tx_bytes', pods_tx_bytes, node_name)

    -- inject k8s_pods_rx_errors metric
    inject_pods_metric('k8s_pods_rx_errors', pods_rx_errors, node_name)

    -- inject k8s_pods_tx_errors metric
    inject_pods_metric('k8s_pods_tx_errors', pods_tx_errors, node_name)
end


-- Function called every ticker interval. Queries the kubelet "stats" API,
-- does aggregations, and inject metric messages.
function process_message()
    local doc, err_msg = send_stats_query()
    if not doc then
        -- inject a k8s_check "failure" metric
        k8s_check_msg.Fields.value = 0
        k8s_check_msg.Fields.hostname = node_name
        inject_message(k8s_check_msg)
        return -1, err_msg
    end

    local pods = doc['pods']
    if not pods then
        return -1, "no pods in kubelet stats response"
    end

    local curr_stats = {}
    collect_pods_stats(doc['node']['nodeName'], pods, pods_stats, curr_stats)
    pods_stats = curr_stats

    -- inject a k8s_check "success" metric
    k8s_check_msg.Fields.value = 1
    k8s_check_msg.Fields.hostname = node_name
    inject_message(k8s_check_msg)

    return 0
end
