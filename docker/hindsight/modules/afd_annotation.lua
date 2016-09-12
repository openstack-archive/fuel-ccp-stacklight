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

local string = require 'string'
local table = require 'table'

local utils = require 'stacklight.utils'
local consts = require 'stacklight.constants'
local afd = require 'stacklight.afd'

local M = {}
setfenv(1, M)

local statuses = {}

local annotation_msg = {
    Type = 'metric',
    Fields = {
        name = 'annotation',
        dimensions = {'source', 'hostname'},
        value_fields = {'title', 'tags', 'text'},
        title = nil,
        tags = nil,
        text = nil,
        source = nil,
        hostname = nil,
    }
}

function inject_afd_annotation(msg)
    local previous
    local text

    local source = afd.read_source(msg)
    local status = afd.read_status(msg)
    local hostname = afd.read_hostname(msg)
    local alarms = afd.extract_alarms(msg)

    if not source or not status or not alarms then
        return -1
    end

    if not statuses[source] then
        statuses[source] = {}
    end
    previous = statuses[source]

    text = table.concat(afd.alarms_for_human(alarms), '<br />')

    -- build the title
    if not previous.status and status == consts.OKAY then
        -- don't send an annotation when we detect a new cluster which is OKAY
        return 0
    elseif not previous.status then
        title = string.format('General status is %s',
                              consts.status_label(status))
    elseif previous.status ~= status then
        title = string.format('General status %s -> %s',
                              consts.status_label(previous.status),
                              consts.status_label(status))

      -- TODO(pasquier-s): generate an annotation when the set of alarms has
      -- changed. the following code generated an annotation whenever at least
      -- one value associated to an alarm was changing. This led to way too
      -- many annotations with alarms monitoring the CPU usage for instance.

--    elseif previous.text ~= text then
--        title = string.format('General status remains %s',
--                              consts.status_label(status))
    else
        -- nothing has changed since the last message
        return 0
    end

    annotation_msg.Fields.title = title
    annotation_msg.Fields.tags = source
    annotation_msg.Fields.text = text
    annotation_msg.Fields.source = source
    annotation_msg.Fields.hostname = hostname

    -- store the last status and alarm text for future messages
    previous.status = status
    previous.text = text

    return utils.safe_inject_message(annotation_msg)
end

return M
