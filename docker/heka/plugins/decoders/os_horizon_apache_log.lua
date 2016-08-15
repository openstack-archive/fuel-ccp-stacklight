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

local l      = require 'lpeg'
l.locale(l)

local dt     = require "date_time"
local common_log_format = require 'common_log_format'
local patt = require 'os_patterns'
local utils  = require 'os_utils'

local msg = {
    Timestamp   = nil,
    Type        = 'log',
    Hostname    = nil,
    Payload     = nil,
    Pid         = nil,
    Fields      = nil,
    Severity    = nil,
}

local severity_label = utils.severity_to_label_map[msg.Severity]

local access_log_pattern = read_config("access_log_pattern") or error(
    "access_log_pattern configuration must be specificed")
local access_log_grammar = common_log_format.build_apache_grammar(access_log_pattern)
local request_grammar = l.Ct(patt.http_request)

-- Since "common_log_format.build_apache_grammar", doesnt support ErrorLogFormat,
-- we have to create error log grammar by ourself. Example error log string:
-- 2016-08-15 10:46:27.679999 wsgi:error 340:140359488239360 Not Found: /favicon.ico

local sp = patt.sp
local colon = patt.colon
local p_timestamp = l.Cg(l.Ct(dt.rfc3339_full_date * (sp + l.P"T") * dt.rfc3339_partial_time * (dt.rfc3339_time_offset + dt.timezone_offset)^-1), "Timestamp")
local p_module = l.Cg(l.R("az")^0, "Module")
local p_errtype = l.Cg(l.R("az")^0, "ErrorType")
local p_pid = l.Cg(l.digit^-5, "Pid")
local p_tid = l.Cg(l.digit^-15, "TreadID")
local p_mess = l.Cg(patt.Message, "Message")
local error_log_grammar = l.Ct(p_timestamp * sp * p_module * colon * p_errtype * sp * p_pid * colon * p_tid * sp * p_mess)

function prepare_message (timestamp, pid, severity, severity_label, programname, payload)
    msg.Logger = 'openstack.horizon-apache'
    msg.Payload = payload
    msg.Timestamp = timestamp
    msg.Pid = pid
    msg.Severity = severity
    msg.Fields = {}
    msg.Fields.programname = programname
    msg.Fields.severity_label = severity_label
end

function process_message ()

    -- logger is either "horizon-access" or "horizon-error"
    local logger = read_message("Logger")
    local log = read_message("Payload")
    local m

    if logger == "horizon-access" then
        m = access_log_grammar:match(log)
        if m then
            prepare_message(m.Timestamp, m.Pid, "6", "INFO", logger, log)
            msg.Fields.http_status = m.status
            msg.Fields.http_response_time = m.request_time.value / 1e6 -- us to sec
            local request = m.request
            r = request_grammar:match(request)
            if r then
                msg.Fields.http_method = r.http_method
                msg.Fields.http_url = r.http_url
                msg.Fields.http_version = r.http_version
            end
        else
            return -1, string.format("Failed to parse %s log: %s", logger, string.sub(log, 1, 64))
        end
    elseif logger == "horizon-error" then
        m = error_log_grammar:match(log)
        if m then
            prepare_message(m.Timestamp, m.Pid, "3", "ERROR", logger, m.Message)
        else
            return -1, string.format("Failed to parse %s log: %s", logger, string.sub(log, 1, 64))
        end
    else
        error("Logger unknown")
    end

    return utils.safe_inject_message(msg)
end
