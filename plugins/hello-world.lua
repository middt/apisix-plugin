local core = require("apisix.core")
local plugin = require("apisix.plugin")

local plugin_name = "hello-world"

local schema = {
    type = "object",
    properties = {
        message = {type = "string", default = "Hello, APISIX!"}
    }
}

local _M = {
    version = 0.1,
    priority = 2000,  -- Set a priority for the plugin
    name = plugin_name,
    schema = schema
}

-- Function executed when a request hits APISIX
function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    -- Log the message to APISIX error log
    core.log.info("hello-world plugin access phase, message: ", conf.message)
    
    -- Add a header to the request
    core.response.set_header("X-Hello-World", conf.message)
    
    -- Return immediately if you want to stop the request processing
    -- return 200, { message = conf.message }
    
    -- Or continue to the next plugin or upstream
    return
end

return _M
