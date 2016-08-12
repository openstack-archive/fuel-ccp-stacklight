--
--

local http = require 'socket.http'
local cjson = require 'cjson'

local write  = require 'io'.write
local flush  = require 'io'.flush

local kubelet_stats_host = read_config('host')
local kubelet_stats_port = read_config('port')

local summary_url = string.format('http://%s:%d/stats/summary',
    kubelet_stats_host, kubelet_stats_port)

local pods_stats = {}
local k8s_pod_cpu_usage_msg = {
    Type = 'metric',
    Timestamp = nil,
    Hostname = nil,
    Fields = {
        name = 'k8s_pod_cpu_usage',
        value = nil,
        dimensions = {'pod_name', 'pod_namespace'},
        pod_name = nil,
        pod_namespace = nil,
    }
}


--
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


--
function process_message()
    local doc, err_msg = send_stats_query()
    if not doc then
        -- error
        -- FIXME inject a check metric
        return -1, err_msg
    end

    local pods = doc.pods
    if pods == nil then
        return -1, "no pods in kubelet stats response"
    end

    local new_pods_stats = {}

    for _, pod in ipairs(doc.pods) do
        local pod_ref = pod['podRef']
        local pod_uid = pod_ref['uid']
        local pod_name = pod_ref['name']
        local pod_namespace = pod_ref['namespace']

        new_pods_stats[pod_uid] = {}
        local new_pod_stats = new_pods_stats[pod_uid]

        new_pod_stats.cpu = 0

        local containers = pod['containers']
        if containers ~= nil then
            for _, container in ipairs(containers) do
                local cpu_usage_core_ns = container['cpu']['usageCoreNanoSeconds']
                new_pod_stats.cpu = new_pod_stats.cpu + cpu_usage_core_ns
            end
        end

        local old_pod_stats = pods_stats[pod_uid]
        if old_pod_stats ~= nil then
            local cpu_usage = (new_pod_stats.cpu - old_pod_stats.cpu) / 1e4
            k8s_pod_cpu_usage_msg.Fields.value = cpu_usage
            k8s_pod_cpu_usage_msg.Fields.pod_name = pod_name
            k8s_pod_cpu_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_pod_cpu_usage_msg)
        end
    end

    pods_stats = new_pods_stats

    return 0
end
