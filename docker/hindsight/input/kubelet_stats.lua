--
--

local cjson = require 'cjson'
local date_time = require 'lpeg.date_time'
local http = require 'socket.http'

--local write  = require 'io'.write
--local flush  = require 'io'.flush

local kubelet_stats_host = read_config('host')
local kubelet_stats_port = read_config('port')

local summary_url = string.format('http://%s:%d/stats/summary',
    kubelet_stats_host, kubelet_stats_port)

local pods_stats = {}

-- message skeletons for each metric
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


-- Collect the statistics for a container
local function collect_container_stats(container, prev_stats, curr_stats)
    if container['cpu'] == nil then
        return nil
    end
    local cpu_scrape_time = date_time.rfc3339:match(container['cpu']['time'])
    curr_stats.cpu = {
        scrape_time = date_time.time_to_ns(cpu_scrape_time),
        value = container['cpu']['usageCoreNanoSeconds']
    }
    local cpu_usage
    if prev_stats ~= nil then
        local time_diff = curr_stats.cpu.scrape_time - prev_stats.cpu.scrape_time
        if time_diff > 0 then
            cpu_usage = 100 *
                (curr_stats.cpu.value - prev_stats.cpu.value) / time_diff
        end
    end
    return cpu_usage
end


-- Collect the statistics for a list of containers
local function collect_containers_stats(containers, prev_stats, curr_stats)
    local aggregated_cpu_usage
    for _, container in ipairs(containers) do
        local container_name = container['name']
        curr_stats[container_name] = {}
        local container_prev_stats
        if prev_stats ~= nil then
            container_prev_stats = prev_stats[container_name]
        end
        local cpu_usage = collect_container_stats(
            container, container_prev_stats, curr_stats[container_name])
        if cpu_usage ~= nil then
            aggregated_cpu_usage = (aggregated_cpu_usage or 0) + cpu_usage
        end
    end
    return aggregated_cpu_usage
end


-- Collect the statistics for a pod
local function collect_pod_stats(pod, prev_stats, curr_stats)
    return collect_containers_stats(pod['containers'] or {}, prev_stats, curr_stats)
end


-- Collect the statistics for a list of pods
local function collect_pods_stats(pods, prev_stats, curr_stats)
    local pods_count_total = 0
    local pods_count_by_ns = {}
    for _, pod in ipairs(pods) do
        local pod_ref = pod['podRef']
        local pod_uid = pod_ref['uid']
        local pod_name = pod_ref['name']
        local pod_namespace = pod_ref['namespace']

        curr_stats[pod_uid] = {}

        local pod_cpu_usage = collect_pod_stats(
            pod, prev_stats[pod_uid], curr_stats[pod_uid])

        if pod_cpu_usage ~= nil then
            k8s_pod_cpu_usage_msg.Fields.value = pod_cpu_usage
            k8s_pod_cpu_usage_msg.Fields.pod_name = pod_name
            k8s_pod_cpu_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_pod_cpu_usage_msg)
        end

        if pods_count_by_ns[pod_namespace] == nil then
            pods_count_by_ns[pod_namespace] = 1
        else
            pods_count_by_ns[pod_namespace] = pods_count_by_ns[pod_namespace] + 1
        end
        pods_count_total = pods_count_total + 1
    end
    for pod_namespace, pods_count in pairs(pods_count_by_ns) do
        k8s_pods_count_msg.Fields.value = pods_count
        k8s_pods_count_msg.Fields.pod_namespace = pod_namespace
        inject_message(k8s_pods_count_msg)
    end
    k8s_pods_count_total_msg.Fields.value = pods_count_total
    inject_message(k8s_pods_count_total_msg)
end


--
function process_message()
    local doc, err_msg = send_stats_query()
    if not doc then
        -- error
        -- FIXME inject a check metric
        return -1, err_msg
    end

    local pods = doc['pods']
    if pods == nil then
        return -1, "no pods in kubelet stats response"
    end

    local curr_stats = {}
    collect_pods_stats(pods, pods_stats, curr_stats)
    pods_stats = curr_stats

    return 0
end
