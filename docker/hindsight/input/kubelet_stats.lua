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
-- * k8s_pod_memory_usage: The memory in Bytes used by a given pod. For example
--   100000 means that the pod consumes 100000 Bytes of memory.
-- * k8s_namespace_memory_usage: The memory in Bytes used by all the pods of
--   a given namespace.
--


local cjson = require 'cjson'
local date_time = require 'lpeg.date_time'
local http = require 'socket.http'

local kubelet_stats_host = read_config('host')
local kubelet_stats_port = read_config('port')

local summary_url = string.format('http://%s:%d/stats/summary',
    kubelet_stats_host, kubelet_stats_port)

local pods_stats = {}

-- message skeletons for each metric
local k8s_check_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_check',
        value = nil
    }
}
local k8s_pods_count_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_pods_count',
        value = nil,
        dimensions = {'pod_namespace'},
        pod_namespace = nil,
    }
}
local k8s_pods_count_total_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_pods_count_total',
        value = nil
    }
}
local k8s_pod_cpu_usage_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_pod_cpu_usage',
        value = nil,
        dimensions = {'pod_name', 'pod_namespace'},
        pod_name = nil,
        pod_namespace = nil
    }
}
local k8s_namespace_cpu_usage_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_namespace_cpu_usage',
        value = nil,
        dimensions = {'pod_namespace'},
        pod_namespace = nil
    }
}
local k8s_pod_memory_usage_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_pod_memory_usage',
        value = nil,
        dimensions = {'pod_name', 'pod_namespace'},
        pod_name = nil,
        pod_namespace = nil
    }
}
local k8s_namespace_memory_usage_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_namespace_memory_usage',
        value = nil,
        dimensions = {'pod_namespace'},
        pod_namespace = nil
    }
}


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


-- Collect statistics for a container
local function collect_container_stats(container, prev_stats, curr_stats)
    local cpu_usage
    local container_cpu = container['cpu']
    if container_cpu ~= nil then
        local cpu_scrape_time = date_time.rfc3339:match(container_cpu['time'])
        curr_stats.cpu = {
            scrape_time = date_time.time_to_ns(cpu_scrape_time),
            value = container_cpu['usageCoreNanoSeconds']
        }
        if prev_stats ~= nil then
            local time_diff = curr_stats.cpu.scrape_time - prev_stats.cpu.scrape_time
            if time_diff > 0 then
                cpu_usage = 100 *
                    (curr_stats.cpu.value - prev_stats.cpu.value) / time_diff
            end
        end
    end
    local memory_usage
    local container_memory = container['memory']
    if container_memory ~= nil then
        memory_usage = container_memory['usageBytes']
    end
    return cpu_usage, memory_usage
end


-- Collect statistics for a group of containers
local function collect_containers_stats(containers, prev_stats, curr_stats)
    local aggregated_cpu_usage
    local aggregated_memory_usage
    for _, container in ipairs(containers) do
        local container_name = container['name']
        curr_stats[container_name] = {}
        local container_prev_stats
        if prev_stats ~= nil then
            container_prev_stats = prev_stats[container_name]
        end
        local cpu_usage, memory_usage = collect_container_stats(
            container, container_prev_stats, curr_stats[container_name])
        if cpu_usage ~= nil then
            aggregated_cpu_usage = (aggregated_cpu_usage or 0) + cpu_usage
        end
        if memory_usage ~= nil then
            aggregated_memory_usage = (aggregated_memory_usage or 0) + memory_usage
        end
    end
    return aggregated_cpu_usage, aggregated_memory_usage
end


-- Collect statistics for a pod
local function collect_pod_stats(pod, prev_stats, curr_stats)
    return collect_containers_stats(pod['containers'] or {}, prev_stats, curr_stats)
end


-- Collect statistics for a group of pods
local function collect_pods_stats(pods, prev_stats, curr_stats)
    local pods_count_total = 0
    local pods_count_by_ns = {}
    local pods_stats_by_ns = {}

    for _, pod in ipairs(pods) do
        local pod_ref = pod['podRef']
        local pod_uid = pod_ref['uid']
        local pod_name = pod_ref['name']
        local pod_namespace = pod_ref['namespace']

        curr_stats[pod_uid] = {}

        local pod_cpu_usage, pod_memory_usage = collect_pod_stats(
            pod, prev_stats[pod_uid], curr_stats[pod_uid])

        if pod_cpu_usage ~= nil then
            -- inject k8s_pod_cpu_usage metric
            k8s_pod_cpu_usage_msg.Fields.value = pod_cpu_usage
            k8s_pod_cpu_usage_msg.Fields.pod_name = pod_name
            k8s_pod_cpu_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_pod_cpu_usage_msg)

            if pods_stats_by_ns[pod_namespace] == nil then
                pods_stats_by_ns[pod_namespace] = {cpu = pod_cpu_usage}
            else
                pods_stats_by_ns[pod_namespace].cpu =
                    (pods_stats_by_ns[pod_namespace].cpu or 0) + pod_cpu_usage
            end
        end

        if pod_memory_usage ~= nil then
            -- inject k8s_pod_memory_usage metric
            k8s_pod_memory_usage_msg.Fields.value = pod_memory_usage
            k8s_pod_memory_usage_msg.Fields.pod_name = pod_name
            k8s_pod_memory_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_pod_memory_usage_msg)

            if pods_stats_by_ns[pod_namespace] == nil then
                pods_stats_by_ns[pod_namespace] = {memory = pod_memory_usage}
            else
                pods_stats_by_ns[pod_namespace].memory =
                    (pods_stats_by_ns[pod_namespace].memory or 0) + pod_memory_usage
            end
        end

        if pods_count_by_ns[pod_namespace] == nil then
            pods_count_by_ns[pod_namespace] = 1
        else
            pods_count_by_ns[pod_namespace] = pods_count_by_ns[pod_namespace] + 1
        end
        pods_count_total = pods_count_total + 1
    end

    for pod_namespace, namespace_stats in pairs(pods_stats_by_ns) do
        if namespace_stats.cpu ~= nil then
            -- inject k8s_namespace_cpu_usage metric
            k8s_namespace_cpu_usage_msg.Fields.value = namespace_stats.cpu
            k8s_namespace_cpu_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_namespace_cpu_usage_msg)
        end
        if namespace_stats.memory ~= nil then
            -- inject k8s_namespace_memory_usage metric
            k8s_namespace_memory_usage_msg.Fields.value = namespace_stats.memory
            k8s_namespace_memory_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_namespace_memory_usage_msg)
        end
    end

    for pod_namespace, pods_count in pairs(pods_count_by_ns) do
        -- inject k8s_pods_count metric
        k8s_pods_count_msg.Fields.value = pods_count
        k8s_pods_count_msg.Fields.pod_namespace = pod_namespace
        inject_message(k8s_pods_count_msg)
    end

    -- inject k8s_pods_count_total metric
    k8s_pods_count_total_msg.Fields.value = pods_count_total
    inject_message(k8s_pods_count_total_msg)
end


-- Function called every ticker interval. Queries the kubelet "stats" API,
-- does aggregations, and inject metric messages.
function process_message()
    local doc, err_msg = send_stats_query()
    if not doc then
        -- inject a k8s_check "failure" metric
        k8s_check_msg.Fields.value = 0
        inject_message(k8s_check_msg)
        return -1, err_msg
    end

    local pods = doc['pods']
    if pods == nil then
        return -1, "no pods in kubelet stats response"
    end

    local curr_stats = {}
    collect_pods_stats(pods, pods_stats, curr_stats)
    pods_stats = curr_stats

    -- inject a k8s_check "success" metric
    k8s_check_msg.Fields.value = 1
    inject_message(k8s_check_msg)

    return 0
end
