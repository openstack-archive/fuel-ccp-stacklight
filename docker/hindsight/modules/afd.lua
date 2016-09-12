-- Copyright 2015 Mirantis, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local cjson = require 'cjson'
local string = require 'string'
local table = require 'table'

local utils = require 'stacklight.utils'
local constants = require 'stacklight.constants'

local read_message = read_message
local assert = assert
local ipairs = ipairs
local pcall = pcall

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function read_field(msg, name)
    return msg.Fields[name]
end

function read_status(msg)
    return read_field(msg, 'value')
end

function read_source(msg)
    return read_field(msg, 'source')
end

function extract_alarms(msg)
    local ok, payload = pcall(cjson.decode, msg.Payload)
    if not ok or not payload.alarms then
        return nil
    end
    return payload.alarms
end

-- return a human-readable message from an alarm table
-- for instance: "CPU load too high (WARNING, rule='last(load_midterm)>=5', current=7)"
function get_alarm_for_human(alarm)
    local metric
    if #(alarm.fields) > 0 then
        local fields = {}
        for _, field in ipairs(alarm.fields) do
            fields[#fields+1] = field.name .. '="' .. field.value .. '"'
        end
        metric = string.format('%s[%s]', alarm.metric, table.concat(fields, ','))
    else
        metric = alarm.metric
    end

    local host = ''
    if alarm.hostname then
        host = string.format(', host=%s', alarm.hostname)
    end

    return string.format(
        "%s (%s, rule='%s(%s)%s%s', current=%.2f%s)",
        alarm.message,
        alarm.severity,
        alarm['function'],
        metric,
        alarm.operator,
        alarm.threshold,
        alarm.value,
        host
    )
end

function alarms_for_human(alarms)
    local alarm_messages = {}
    local hint_messages = {}

    for _, v in ipairs(alarms) do
        if v.tags and v.tags.dependency_level and v.tags.dependency_level == 'hint' then
            hint_messages[#hint_messages+1] = get_alarm_for_human(v)
        else
            alarm_messages[#alarm_messages+1] = get_alarm_for_human(v)
        end
    end

    if #hint_messages > 0 then
        alarm_messages[#alarm_messages+1] = "Other related alarms:"
    end
    for _, v in ipairs(hint_messages) do
        alarm_messages[#alarm_messages+1] = v
    end

    return alarm_messages
end

local alarms = {}

-- append an alarm to the list of pending alarms
-- the list is sent when inject_afd_metric is called
function add_to_alarms(status, fn, metric, fields, tags, operator, value, threshold, window, periods, message)
    local severity = constants.status_label(status)
    assert(severity)
    alarms[#alarms+1] = {
        severity=severity,
        ['function']=fn,
        metric=metric,
        fields=fields or {},
        tags=tags or {},
        operator=operator,
        value=value,
        threshold=threshold,
        window=window or 0,
        periods=periods or 0,
        message=message
    }
end

function get_alarms()
    return alarms
end

function reset_alarms()
    alarms = {}
end

-- inject an AFD event into the Heka pipeline
function inject_afd_metric(msg_type, msg_tag_name, msg_tag_value, metric_name,
                           value, hostname, source)
    local payload

    if #alarms > 0 then
        payload = utils.safe_json_encode({alarms=alarms})
        reset_alarms()
        if not payload then
            return
        end
    else
        -- because cjson encodes empty tables as objects instead of arrays
        payload = '{"alarms":[]}'
    end

    local msg = {
        Type = msg_type,
        Payload = payload,
        Fields = {
            name = metric_name,
            value = value,
            hostname = hostname,
            source = source,
            dimensions = {msg_tag_name, 'hostname', 'source'},
        }
    }
    msg.Fields[msg_tag_name] = msg_tag_value

    local err_code, err_msg = utils.safe_inject_message(msg)

    if err_code ~= 0 then
        return nil, err_msg
    end

    return msg
end

MATCH = 1
NO_MATCH = 2
NO_DATA = 3
MISSING_DATA = 4

return M
