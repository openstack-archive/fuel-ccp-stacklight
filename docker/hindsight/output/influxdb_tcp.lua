--
-- Inspired from the lua_sandbox Postgres Output Example
-- https://github.com/mozilla-services/lua_sandbox/blob/f1ee9eb/docs/heka/output.md#example-postgres-output
--

local os = require 'os'
local http = require 'socket.http'

--local write  = require 'io'.write
--local flush  = require 'io'.flush

local influxdb_host = read_config('host') or error('influxdb host is required')
local influxdb_port = read_config('port') or error('influxdb port is required')

local batch_max_lines = read_config('batch_max_lines') or 3000
assert(batch_max_lines > 0, 'batch_max_lines must be greater than zero')

local db = read_config("database") or error("database config is required")

local write_url = string.format('http://%s:%d/write?db=%s', influxdb_host, influxdb_port, db)
local query_url = string.format('http://%s:%s/query', influxdb_host, influxdb_port)

local database_created = false

local buffer = {}
local buffer_len = 0


local function escape_string(str)
    return tostring(str):gsub("([ ,])", "\\%1")
end

local function encode_value(value)
    if type(value) == "number" then
        -- Always send numbers as formatted floats, so InfluxDB will accept
        -- them if they happen to change from ints to floats between
        -- points in time.  Forcing them to always be floats avoids this.
        return string.format("%.6f", value)
    elseif type(value) == "string" then
        -- string values need to be double quoted
        return '"' .. value:gsub('"', '\\"') .. '"'
    elseif type(value) == "boolean" then
        return '"' .. tostring(value) .. '"'
    end
end

local function write_batch()
    assert(buffer_len > 0)
    local body = table.concat(buffer, '\n')
    local resp_body, resp_status = http.request(write_url, body)
    if resp_body and resp_status == 204 then
        -- success
        buffer = {}
        buffer_len = 0
        return resp_body, ''
    else
        -- error
        local err_msg = resp_status
        if resp_body then
            err_msg = string.format('influxdb write error: [%s] %s',
                resp_status, resp_body)
        end
        return nil, err_msg
    end
end


local function create_database()
    -- query won't fail if database already exists
    local body = string.format('q=CREATE DATABASE %s', db)
    local resp_body, resp_status = http.request(query_url, body)
    if resp_body and resp_status == 200 then
        -- success
        return resp_body, ''
    else
        -- error
        local err_msg = resp_status
        if resp_body then
            err_msg = string.format('influxdb create database error [%s] %s',
                resp_status, resp_body)
        end
        return nil, err_msg
    end
end


-- return the value and index of the last field with a given name
local function read_field(name)
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


-- create a line for the current message, return nil and an error string
-- if the message is invalid
local function create_line()

    local tags = {}
    local dimensions, dimensions_index = read_field('dimensions')
    if dimensions then
        local i = 0
        repeat
            local tag_key = read_message('Fields[dimensions]', dimensions_index, i)
            if tag_key == nil then
                break
            end
            -- skip the plugin_running_on dimension
            if tag_key ~= 'plugin_running_on' then
                local variable_name = string.format('Fields[%s]', tag_key)
                local tag_val = read_message(variable_name, 0)
                if tag_val == nil then
                    -- the dimension is advertized in the "dimensions" field
                    -- but there is no field for it, so we consider the
                    -- entire message as invalid
                    return nil, string.format('dimension "%s" is missing', tag_key)
                end
                tags[escape_string(tag_key)] = escape_string(tag_val)
            end
            i = i + 1
        until false
    end

    if tags['dimensions'] ~= nil and dimensions_index == 0 then
        return nil, 'index of field "dimensions" should not be 0'
    end

    local name, name_index = read_field('name')
    if name == nil then
        -- "name" is a required field
        return nil, 'field "name" is missing'
    end
    if tags['name'] ~= nil and name_index == 0 then
        return nil, 'index of field "name" should not be 0'
    end

    local value, value_index = read_field('value')
    if value == nil then
        -- "value" is a required field
        return nil, 'field "value" is missing'
    end
    if tags['value'] ~= nil and value_index == 0 then
        return nil, 'index of field "value" should not be 0'
    end

    local tags_array = {}
    for tag_key, tag_val in pairs(tags) do
        table.insert(tags_array, string.format('%s=%s', tag_key, tag_val))
    end

    return string.format('%s,%s value=%s %d',
        escape_string(name),
        table.concat(tags_array, ','),
        encode_value(value),
        string.format('%d', read_message('Timestamp'))), ''
end


function process_message()

    if not database_created then
        local ok, err_msg = create_database()
        if not ok then
            return -3, err_msg  -- retry
        end
        database_created = true
    end

    local line, err_msg = create_line()
    if line == nil then
        -- the message is not valid, skip it
        return -2, err_msg  -- skip
    end

    buffer_len = buffer_len + 1
    buffer[buffer_len] = line

    if buffer_len > batch_max_lines then
        local ok, err_msg = write_batch()
        if not ok then
            buffer[buffer_len] = nil
            buffer_len = buffer_len - 1
            return -3, err_msg  -- retry
        end
        return 0
    end

    return -4 -- batching
end


function timer_event(ns)
    if buffer_len > 0 then
        local ok, _ = write_batch()
        if ok then
            update_checkpoint()
        end
    end
end
