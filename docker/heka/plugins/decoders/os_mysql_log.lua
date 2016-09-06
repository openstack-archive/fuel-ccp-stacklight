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

local patt   = require 'os_patterns'
local utils  = require 'os_utils'

local msg = {
    Timestamp   = nil,
    Type        = 'log',
    Hostname    = nil,
    Payload     = nil,
    Pid         = nil,
    Fields      = {
        programname = 'mysql',
        severity_label = nil,
    },
    Severity    = nil,
}

-- mysqld logs are cranky, the hours have no leading zero and the "real" severity level is enclosed by square brackets...
-- 2016-07-28 11:09:24 139949080807168 [Note] InnoDB: Dumping buffer pool(s) not yet started

-- Different pieces of pattern
local sp = patt.sp
local colon = patt.colon
local p_timestamp = l.digit^-4 * l.S("-") * l.digit^-2 * l.S("-") * l.digit^-2
local p_date = l.digit^-2 * colon * l.digit^-2 * colon * l.digit^-2
local p_thread_id = l.digit^-15
local p_severity_label = l.P"[" * l.Cg(l.R("az", "AZ")^0 / string.upper, "SeverityLabel") * l.P"]"
local p_message = l.Cg(patt.Message, "Message")

local mysql_grammar = l.Ct(p_timestamp * sp^1 * p_date * sp^1 * p_thread_id * sp^1 * p_severity_label * sp^1 * p_message)


function process_message ()
    local log = read_message("Payload")
    local logger = read_message("Logger")

    local m = mysql_grammar:match(log)
    if not m then return -1 end

    msg.Logger = logger
    msg.Payload = m.Message
    msg.Fields.severity_label = m.SeverityLabel

    return utils.safe_inject_message(msg)
end
