-- Copyright 2015-2016 Mirantis, Inc.
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
require "string"
local l      = require 'lpeg'
l.locale(l)
local dt     = require "date_time"

local patt   = require 'os_patterns'
local utils  = require 'os_utils'

local msg = {
    Timestamp   = nil,
    Type        = 'log',
    Hostname    = nil,
    Payload     = nil,
    Fields      = {},
    Severity    = nil,
}

-- ovs logs looks like this:
-- 2016-08-10T09:27:41Z|00038|connmgr|INFO|br-ex<->tcp:127.0.0.1:6633: 2 flow_mods 10 s ago (2 adds)

-- Different pieces of pattern
local sp = patt.sp
local colon = patt.colon
local pipe = patt.pipe
local dash = patt.dash

local p_timestamp = l.Cg(l.Ct(dt.rfc3339_full_date * (sp + l.P"T") * dt.rfc3339_partial_time * (dt.rfc3339_time_offset + dt.timezone_offset)^-1), "Timestamp")
local p_id = l.Cg(l.digit^-5, "Message_ID")
local p_module = l.Cg(l.R("az")^0, "Module")
local p_severity_label = l.Cg(l.R("AZ")^0, "SeverityLabel")
local p_message = l.Cg(patt.Message, "Message")

local ovs_grammar = l.Ct(p_timestamp * pipe * p_id * pipe * p_module * pipe * p_severity_label * pipe * p_message)
local pattern = read_config("heka_service_pattern") or "^k8s_(.-)%..*"


function process_message ()
    local cont_name = read_message("Fields[ContainerName]")
    local program = string.match(cont_name, pattern)
    local service = nil

    if program == nil then
        program = "unknown_program"
    else
        service = string.match(program, '(.-)%-.*')
    end

    --- If service is still nil, it means we fail to match current service
    --- using both patterns, so we set fallback one.
    if service == nil then
        service = "unknown_service"
    end

    local log = read_message("Payload")

    local m = ovs_grammar:match(log)
    if not m then return -1 end

    if m.SeverityLabel == "WARN" then
        m.SeverityLabel = "WARNING"
    end

    msg.Timestamp = m.Timestamp
    msg.Logger = service
    msg.Payload = m.Message
    msg.Severity = utils.label_to_severity_map[m.SeverityLabel] or 7
    msg.Fields.module = m.Module
    msg.Fields.message_id = m.Message_ID
    msg.Fields.programname = program
    msg.Fields.severity_label = m.SeverityLabel

    return utils.safe_inject_message(msg)
end
