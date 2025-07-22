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
local json = require("cjson.safe")
local ngx = ngx

local plugin_name = "upstream-response-transformer"

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
            description = "notify: log the response, replace: replace upstream response with external API response"
        },
        response_headers = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    name = {
                        type = "string",
                        description = "Name of the header to set"
                    },
                    mode = {
                        type = "string",
                        enum = {"replace", "notify", "empty"},
                        default = "replace",
                        description = "Header setting mode: replace (always set), notify (set on success), empty (set on failure)"
                    },
                    success_value = {
                        type = "string",
                        default = "true",
                        description = "Header value to set on successful external API call"
                    },
                    failure_value = {
                        type = "string",
                        default = "false",
                        description = "Header value to set on failed external API call"
                    }
                },
                required = {"name"}
            },
            description = "Array of response header configurations"
        }
    },
    required = {"external_api_url"}
}

local _M = {
    version = 0.1,
    priority = 10, -- Low priority to run after authentication plugins
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    core.log.info("upstream-response-transformer access phase started")
    
    -- Try different ways to get upstream info
    local upstream = ctx.matched_upstream or ctx.upstream or ctx.selected_upstream
    
    -- If no upstream found, try to get from matched_route
    if not upstream and ctx.matched_route then
        upstream = ctx.matched_route.value.upstream
    end
    
    if not upstream then
        core.log.error("No upstream configured")
        return 500, "No upstream configured"
    end
    
    -- Call upstream ourselves
    local upstream_response = call_upstream(ctx, upstream)
    if not upstream_response then
        core.log.error("Failed to call upstream")
        return 502, "Bad Gateway"
    end
    
    -- Call external API with upstream response
    local success, external_response = call_external_api(conf, ctx, upstream_response)
    
    -- Set response headers based on configuration
    if conf.response_headers then
        for _, header_config in ipairs(conf.response_headers) do
            local header_name = header_config.name
            local header_mode = header_config.mode or "replace"
            local success_value = header_config.success_value or "true"
            local failure_value = header_config.failure_value or "false"
            
            -- Set header based on mode and success/failure
            if header_mode == "replace" then
                -- Always set header regardless of external API result
                core.response.set_header(header_name, success and success_value or failure_value)
            elseif header_mode == "notify" and success then
                -- Only set header on successful external API call
                core.response.set_header(header_name, success_value)
            elseif header_mode == "empty" and not success then
                -- Only set header on failed external API call
                core.response.set_header(header_name, failure_value)
            end
        end
    end
    
    -- Handle response based on mode
    if conf.mode == "replace" and success and external_response then
        -- Return external API response
        core.log.info("Replacing upstream response with external API response")
        
        -- Parse external response if it's JSON
        local external_data = json.decode(external_response)
        if external_data then
            -- Set appropriate Content-Type for JSON response
            core.response.set_header("Content-Type", "application/json")
            return 200, external_data
        else
            -- For non-JSON response, try to preserve original content-type if it was JSON
            local original_content_type = nil
            for k, v in pairs(upstream_response.headers) do
                if k:lower() == "content-type" then
                    original_content_type = v
                    break
                end
            end
            
            if original_content_type and original_content_type:match("application/json") then
                core.response.set_header("Content-Type", "application/json")
            else
                core.response.set_header("Content-Type", "text/plain")
            end
            return 200, external_response
        end
    else
        -- Return original upstream response
        core.log.info("Returning original upstream response")
        
        -- Set upstream response headers (case-insensitive filtering)
        for k, v in pairs(upstream_response.headers) do
            local k_lower = k:lower()
            if k_lower ~= "content-length" and k_lower ~= "transfer-encoding" and 
               k_lower ~= "connection" and k_lower ~= "content-encoding" then
                core.response.set_header(k, v)
            end
        end
        
        -- Return upstream response
        return upstream_response.status, upstream_response.body
    end
end

function call_upstream(ctx, upstream)
    core.log.info("Calling upstream")
    
    -- Get upstream nodes
    local nodes = upstream.nodes
    if not nodes then
        core.log.error("No nodes found in upstream")
        return nil
    end
    
    -- Get first available node - handle different node formats
    local node_host, node_port
    
    for node_key, node_value in pairs(nodes) do
        if type(node_key) == "string" then
            -- Format: {"host:port" = weight}
            local host, port = node_key:match("^(.+):(%d+)$")
            if not host then
                host = node_key
                port = 80 -- default HTTP port
            end
            node_host = host
            node_port = tonumber(port)
            break
        elseif type(node_value) == "table" then
            -- Format: {[1] = {host="...", port="..."}}
            node_host = node_value.host
            node_port = node_value.port or 80
            break
        elseif type(node_key) == "number" and type(node_value) == "string" then
            -- Format: {[1] = "host:port"}
            local host, port = node_value:match("^(.+):(%d+)$")
            if not host then
                host = node_value
                port = 80
            end
            node_host = host
            node_port = tonumber(port)
            break
        end
    end
    
    if not node_host then
        core.log.error("No upstream node found")
        return nil
    end
    
    core.log.info("Calling upstream node: ", node_host, ":", node_port)
    
    -- Create HTTP client
    local httpc = http.new()
    httpc:set_timeout(30000) -- 30 second timeout for upstream
    
    -- Prepare request headers
    local headers = {}
    for k, v in pairs(ngx.req.get_headers()) do
        -- Skip some headers that should not be forwarded
        if k:lower() ~= "host" and k:lower() ~= "connection" then
            headers[k] = v
        end
    end
    headers["Host"] = node_host
    
    -- Get request body if exists
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    -- Build full URI
    local uri = ngx.var.request_uri
    local upstream_url = "http://" .. node_host .. ":" .. node_port .. uri
    
    core.log.info("Making upstream request to: ", upstream_url)
    
    -- Make request to upstream
    local res, err = httpc:request_uri(upstream_url, {
        method = ngx.var.request_method,
        body = body,
        headers = headers,
        ssl_verify = false
    })
    
    if not res then
        core.log.error("Failed to call upstream: ", err)
        httpc:close()
        return nil
    end
    
    core.log.info("Upstream response received, status: ", res.status)
    httpc:close()
    
    return {
        status = res.status,
        headers = res.headers,
        body = res.body
    }
end

function call_external_api(conf, ctx, upstream_response)
    core.log.info("Calling external API: ", conf.external_api_url)
    
    -- Create HTTP client
    local httpc = http.new()
    httpc:set_timeout(conf.timeout or 5000)
    
    -- Prepare headers for external API call
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "APISIX-Upstream-Response-Transformer/1.0"
    }
    
    -- Add forwarded headers if configured
    if conf.forward_headers then
        for _, header_name in ipairs(conf.forward_headers) do
            -- First check if it's in the upstream response headers
            local header_value = upstream_response.headers[header_name]
            
            -- If not found in response headers, check request headers
            if not header_value then
                header_value = ngx.var["http_" .. header_name:lower():gsub("-", "_")]
            end
            
            if header_value then
                headers[header_name] = header_value
            end
        end
    end
    
    -- Prepare request body with upstream response information
    local request_body = {
        upstream_status = upstream_response.status,
        upstream_headers = upstream_response.headers,
        upstream_body = upstream_response.body,
        request_uri = ngx.var.request_uri,
        request_method = ngx.var.request_method,
        client_ip = core.request.get_ip(ctx),
        timestamp = ngx.time(),
        message = "Upstream response notification from APISIX"
    }
    
    core.log.debug("Sending upstream response to external API")
    
    -- Make request to external API
    local res, err = httpc:request_uri(conf.external_api_url, {
        method = conf.method or "POST",
        body = json.encode(request_body),
        headers = headers,
        ssl_verify = false
    })
    
    if not res then
        core.log.error("Failed to call external API: ", err)
        httpc:close()
        return false, nil
    end
    
    core.log.info("External API call completed, status: ", res.status)
    httpc:close()
    
    if res.status == 200 then
        return true, res.body
    else
        return false, nil
    end
end

return _M 