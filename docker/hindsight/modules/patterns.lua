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

local l      = require 'lpeg'
l.locale(l)

local tonumber = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function anywhere (patt)
  return l.P {
    patt + 1 * l.V(1)
  }
end

sp = l.space

-- Pattern used to match a number
Number = l.P"-"^-1 * l.xdigit^1 * (l.S(".,") * l.xdigit^1 )^-1 / tonumber

return M
