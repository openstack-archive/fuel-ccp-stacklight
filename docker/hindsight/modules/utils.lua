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

return M
