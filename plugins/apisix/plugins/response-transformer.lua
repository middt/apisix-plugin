--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core = require("apisix.core")
local http = require("resty.http")
local json = require("cjson")

local plugin_name = "response-transformer"

local schema = {
    type = "object",
    properties = {
        external_api_url = {
            type = "string",
            description = "URL of the external API to call"
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 5000,
            description = "Timeout for external API call in milliseconds"
        },
        forward_headers = {
            type = "array",
            items = {
                type = "string"
            },
            description = "Headers to forward to the external API"
        },
        method = {
            type = "string",
            enum = {"GET", "POST", "PUT", "PATCH"},
            default = "POST",
            description = "HTTP method to use when calling external API"
        },
        mode = {
            type = "string",
            enum = {"notify", "replace"},
            default = "notify",
            description = "notify: call external API and continue with upstream, replace: skip upstream and return external API response"
        }
    },
    required = {"external_api_url"}
}

local _M = {
    version = 0.1,
    priority = 10,  -- Very low priority - run after most other plugins
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    -- Add debug logging to see if plugin is being called
    core.log.error("response-transformer plugin access phase started, mode: ", conf.mode or "notify")
    
    -- Make external API call in access phase
    local success, response_body = call_external_api(conf, ctx)
    
    if conf.mode == "replace" and success then
        -- Skip upstream and return external API response
        core.log.error("Returning external API response, skipping upstream")
        return 200, response_body
    elseif conf.mode == "notify" or not conf.mode then
        -- Continue with normal upstream request
        core.log.error("External API notification sent, continuing with upstream")
        return
    else
        -- On error, continue with upstream
        core.log.error("External API call failed, continuing with upstream")
        return
    end
end

function call_external_api(conf, ctx)
    -- Add debug logging
    core.log.error("call_external_api started, URL: ", conf.external_api_url)
    
    -- Create HTTP client
    local httpc = http.new()
    httpc:set_timeout(conf.timeout or 5000)

    -- Prepare headers for external API call
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "APISIX-Response-Transformer/1.0"
    }

    -- Add forwarded headers if configured
    if conf.forward_headers then
        for _, header_name in ipairs(conf.forward_headers) do
            local header_value = ngx.var["http_" .. header_name:lower():gsub("-", "_")]
            if header_value then
                headers[header_name] = header_value
            end
        end
    end

    -- Get request body if it exists
    local request_body_data = ""
    if ngx.var.request_method ~= "GET" then
        ngx.req.read_body()
        request_body_data = ngx.req.get_body_data() or ""
    end

    -- Prepare request body - send request information
    local request_body = {
        request_uri = ngx.var.request_uri,
        request_method = ngx.var.request_method,
        request_headers = ngx.req.get_headers(),
        request_body = request_body_data,
        client_ip = core.request.get_ip(ctx),
        timestamp = ngx.time(),
        message = "Request notification from APISIX access phase"
    }

    core.log.error("Making external API call with data: ", json.encode(request_body))

    -- Make request to external API
    local res, err = httpc:request_uri(conf.external_api_url, {
        method = conf.method or "POST",
        body = json.encode(request_body),
        headers = headers,
        ssl_verify = false  -- You might want to make this configurable
    })

    if not res then
        core.log.error("Failed to call external API: ", err)
        httpc:close()
        return false, nil
    end

    -- Log the result
    core.log.error("External API call completed in access phase, status: ", res.status)
    core.log.error("External API response: ", res.body)
    httpc:close()
    
    if res.status == 200 then
        return true, res.body
    else
        return false, nil
    end
end

return _M 