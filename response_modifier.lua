local core = require("apisix.core")
local os_date = os.date
local cjson = require("cjson.safe")


local function generate_uuid()
    local random = math.random
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end
local plugin_name = "response_modifier"


local schema = {
    type = "object",
    properties = {
        response_bodies = {
            type = "object",
            additionalProperties = {
                type = "string"
            }
        }
    },
    required = {"response_bodies"}
}

local _M = {
    version = 0.1,
    priority = 1,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end
local function write_log_to_file(log_entry)
    local log_json = cjson.encode(log_entry)
    local log_date = os.date("%Y-%m-%d")
    local log_filepath = "/logs/responsemodifier-" .. log_date .. ".json"
    local file, err = io.open(log_filepath, "a")
    if not file then
        core.log.error("failed to open log file: ", err)
        return
    end

    file:write(log_json .. "\n")
    file:close()
end

local function async_write_log(log_entry)
    local delay = 0
    local handler = function(premature, log_entry)
        if premature then
            return
        end
        write_log_to_file(log_entry)
    end
    ngx.timer.at(delay, handler, log_entry)
end
function _M.header_filter(conf, ctx)
    local status = ngx.status
    local response_bodies = conf.response_bodies
    local body = response_bodies[tostring(status)]
    local headers = ngx.req.get_headers()
    log(conf,ctx,headers)
    ngx.log(ngx.WARN, "Header func response_bodies ", response_bodies[tostring(status)])
    ngx.log(ngx.WARN, "Header func Filter Giriş ", status)
    ngx.log(ngx.WARN, "Header func Body from response_bodies ", body)


    if body then
        ngx.header["Content-Type"] = "application/json"
        ngx.header.content_length = nil
        ngx.log(ngx.WARN, "Custom response header set for status: ", status)
    else
        ngx.log(ngx.WARN, "No custom response header modification for status: ", status)
    end
end
local function getCurrentTimeWithFixedOffset()
    -- Şu anki zamanı epoch cinsinden saniye olarak al
    local now = os.time()
    
    -- Hedef zaman dilimindeki saati hesapla (+03:00 zaman dilimi)
    local targetOffsetSeconds = 3 * 3600 -- +03:00 UTC'den 3 saat ileri
    local targetTime = os.date("!%Y-%m-%dT%H:%M:%S", now + targetOffsetSeconds)
    
    -- Sabit "+03:00" zaman dilimi ofsetini saatin sonuna ekle
    local timeWithFixedOffset = targetTime .. "+03:00"
    
    return timeWithFixedOffset
end
function _M.body_filter(conf, ctx)
    if ngx.arg[2] then
        local status_code = ngx.status
        local timestamp = getCurrentTimeWithFixedOffset()
        local body = ngx.arg[1]
        if status_code == 401 or status_code == 429 then
        local response_bodies = conf.response_bodies
        local bodylocal = response_bodies[tostring(status_code)]
        local json_body = cjson.decode(bodylocal)
        json_body.timestamp = timestamp
        json_body.id = generate_uuid()
        body = cjson.encode(json_body)
        end
          -- Değiştirilmiş yanıtı son kullanıcıya gönderme
          ngx.arg[1] = body
          ngx.arg[2] = true -- end of body
          -- Yanıtın gönderildiğini işaretleme
          log(conf,ctx,body)
          log(conf,ctx,"Completed")
end
end
function log(conf,ctx,body)
    local log_entry = {
        uri = ctx.var.uri,
        method = ctx.var.request_method,
        request_id = ctx.var.request_id,
        client_ip = ctx.var.remote_addr,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", ngx.time()),
        responsemodifier_request_url = conf.endpoint,
        responsemodifier_response_body = body,
        responsemodifier_response_code = ngx.status,
        plugin_name = "responsemodifier",
    }
    async_write_log(log_entry)
end
function _M.log(conf, ctx)
    ngx.log(ngx.WARN, "log phase, status: ", ngx.status)
end

return _M