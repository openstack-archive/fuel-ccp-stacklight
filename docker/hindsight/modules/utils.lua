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

local inject_message = inject_message
local read_message = read_message
local string = string
local pcall = pcall

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

-- Encode a Lua variable as JSON without raising an exception if the encoding
-- fails for some reason (for instance, the encoded buffer exceeds the sandbox
-- limit)
function safe_json_encode(v)
    local ok, data = pcall(cjson.encode, v)
    if not ok then
        return
    end
    return data
end

-- Call inject_message() wrapped by pcall()
function safe_inject_message(msg)
    local ok, err_msg = pcall(inject_message, msg)
    if not ok then
        return -1, err_msg
    else
        return 0
    end
end

-- Extract the metric value(s) from the message.
-- The value can be either a scalar value or a table for mulitvalue metrics.
-- Returns true plus the value or if it fails, returns false plus the error message.
function get_values_from_metric()
    if read_message('Fields[value_fields]') then
        value = {}
        local i = 0
        local val
        while true do
            local f = read_message("Fields[value_fields]", 0, i)
            if not f then
                break
            end
            val = read_message(string.format('Fields[%s]', f))
            if val ~= nil then
                value[f] = val
                i = i + 1
            end
        end
        if i == 0 then
           return false, 'Fields[value_fields] does not list any valid field'
        end
    else
        value = read_message("Fields[value]")
        if not value then
            return false, 'Fields[value] is missing'
        end
    end

    return true, value
end

return M
