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

local cjson = require 'cjson'

local inject_message = inject_message
local read_message = read_message
local string = string
local pcall = pcall

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

-- Return the value and index of the last field with a given name.
function read_field(name)
    local i = -1
    local value = nil
    local variable_name = string.format('Fields[%s]', name)
    repeat
        local tmp = read_message(variable_name, i + 1)
        if tmp == nil then
            break
        end
        value = tmp
        i = i + 1
    until false
    return value, i
end


-- Extract value(s) from the message. The value can be either a scalar value
-- or a table for multi-value metrics.Return nil and an error message on
-- failure. The argument "tags" is optional, it's used for sanity checks.
function read_values(tags)
    if not tags then
        tags = {}
    end
    local value
    local value_fields, value_fields_index = read_field('value_fields')
    if value_fields ~= nil then
        if tags['value_fields'] ~= nil and value_fields_index == 0 then
            return nil, 'index of field "value_fields" should not be 0'
        end
        local i = 0
        value = {}
        repeat
            local value_key = read_message(
                'Fields[value_fields]', value_fields_index, i)
            if value_key == nil then
                break
            end
            local value_val, value_index = read_field(value_key)
            if value_val == nil then
                return nil, string.format('field "%s" is missing', value_key)
            end
            if tags[value_key] ~= nil and value_index == 0 then
                return nil, string.format(
                    'index of field "%s" should not be 0', value_key)
            end
            value[value_key] = value_val
            i = i + 1
        until false
    else
        local value_index
        value, value_index = read_field('value')
        if value == nil then
            -- "value" is a required field
            return nil, 'field "value" is missing'
        end
        if tags['value'] ~= nil and value_index == 0 then
            return nil, 'index of field "value" should not be 0'
        end
    end
    return value, ''
end

return M
