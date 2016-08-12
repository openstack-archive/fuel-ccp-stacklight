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

    local pods = doc['pods']
    if pods == nil then
        return -1, "no pods in kubelet stats response"
    end

    local new_pods_stats = {}

    for _, pod in ipairs(pods) do
        local pod_ref = pod['podRef']
        local pod_uid = pod_ref['uid']
        local pod_name = pod_ref['name']
        local pod_namespace = pod_ref['namespace']

        local old_pod_stats = pods_stats[pod_uid]

        new_pods_stats[pod_uid] = {}
        local new_pod_stats = new_pods_stats[pod_uid]

        local pod_cpu_usage = 0

        for _, container in ipairs(pod['containers'] or {}) do
            local container_name = container['name']
            local cpu_scrape_time = date_time.rfc3339:match(container['cpu']['time'])
            new_pod_stats[container_name] = {
                cpu = {
                    scrape_time = date_time.time_to_ns(cpu_scrape_time),
                    value = container['cpu']['usageCoreNanoSeconds']
                }
            }
            local new_container_stats = new_pod_stats[container_name]
            if old_pod_stats ~= nil then
                local old_container_stats = old_pod_stats[container_name]
                if old_container_stats ~= nil then
                    local time_diff =
                        new_container_stats.cpu.scrape_time - old_container_stats.cpu.scrape_time
                    if time_diff > 0 then
                        local container_cpu_usage = 100 *
                            (new_container_stats.cpu.value - old_container_stats.cpu.value) /
                            time_diff
                        pod_cpu_usage = pod_cpu_usage + container_cpu_usage
                    end
                end
            end
        end

        if old_pod_stats ~= nil then
            k8s_pod_cpu_usage_msg.Fields.value = pod_cpu_usage
            k8s_pod_cpu_usage_msg.Fields.pod_name = pod_name
            k8s_pod_cpu_usage_msg.Fields.pod_namespace = pod_namespace
            inject_message(k8s_pod_cpu_usage_msg)
        end
    end

    pods_stats = new_pods_stats

    return 0
end
