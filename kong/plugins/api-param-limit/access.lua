local _M = {}

local path_params_mgr = require "kong.plugins.api-param-limit.path_params"
local validation = require "resty.validation"
--local cjson = require "cjson"
--local jsonschema = require 'jsonschema'

local function mysplit (inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local function set_default(result, location, name, param_type, default)
    kong.log.debug("[api-param-limit] set default value to  param [ name:"..name.." , default value:"..default.."]")
    local param_default = default
    if param_type == "number" then 
        local ok, e = validation.number(tonumber(param_default))
        if ok == false then
            kong.log.debug("[api-param-limit] check param "..name.." fail, ".."type must be number")
            table.insert(result, name .. "'s default value must be number")
            return
        end
        param_default = tonumber(param_default)
    end
    if location == "query" then
        local querys = kong.request.get_query(),
        kong.log.debug("[api-param-limit] set default value to query param [ name:"..name.." , default value:"..default.."]")
        querys[name]=param_default
        kong.service.request.set_query(querys)
    end
    if location == "head" then
        headers = kong.request.get_headers(),
        kong.log.debug("[api-param-limit] set default value to head param [ name:"..name.." , default value:"..default.."]")
        headers[name]=param_default
         kong.service.request.set_headers(headers)
    end
end

-- limit, 即插件中的param_limits配置中的一条，对应的请求参数信息就是limit里描述的name
-- result, 记录 check结果
-- param_value，请求参数实际值
-- param_name, 请求参数名称
local function check(limit, result, param_value, param_name)
    local param_type = limit.type
    local param_required = limit.required
    local param_default = limit.default
    local param_max = limit.max
    local param_min = limit.min
    local param_location = limit.location
    -- is empty value?
    local empty, e = validation.null(param_value)
    kong.log.debug("[api-param-limit] param check [name:"..param_name..", type:"..param_type.."]")
    -- required check
    if param_required then
        if empty then
            if param_default then
                kong.log.debug("[api-param-limit] param "..param_name.." is required, but is empty, set default value "..param_default)
                set_default(result, param_location, param_name, param_type, param_default)
            else
                kong.log.debug("[api-param-limit] param "..param_name.." is required, but is empty")
                table.insert(result, param_name .. " is required, but is empty and doesn't have default value")
            end
        end
    end

    -- type check
    kong.log.debug("[api-param-limit] check param "..param_name.."'s type")
    if param_type then
        if not empty and param_type == "string" then
            local ok, e = validation.string(param_value)
            if ok == false then
                kong.log.debug("[api-param-limit] check param "..param_name.." fail, ".."type "..type(param_value).."must be string")
                table.insert(result, param_name .. "must be string")
            end
        end
        if not empty and param_type == "number" then
            local ok, e = validation.number(tonumber(param_value))
            if ok == false then
                kong.log.debug("[api-param-limit] check param "..param_name.." fail, ".."type "..type(param_value).."must be number")
                table.insert(result, param_name .. " must be number")
            end
        end
    end
    -- min&max check
    kong.log.debug("[api-param-limit] check param "..param_name.."'s min value")
    if param_min then
        if not empty and param_type == "number" then
            kong.log.debug("[api-param-limit] check param "..param_name.."'s min start")
            local ok, e = validation.optional:min(param_min)(tonumber(param_value))
            if ok == false then
                kong.log.debug("[api-param-limit] check param "..param_name.." fail, must >= "..tostring(param_min))
                table.insert(result, param_name .. " must >= " .. tostring(param_min))
            end
        end
    end
    kong.log.debug("[api-param-limit] check param "..param_name.."'s max value")
    if param_max then
        if not empty and param_type == "number" then
            kong.log.debug("[api-param-limit] check param "..param_name.."'s max start")
            local ok, e = validation.optional:max(param_max)(tonumber(param_value))
            if ok == false then
                kong.log.debug("[api-param-limit] check param "..param_name.." fail, must <= "..tostring(param_max))
                table.insert(result, param_name .. " must <= " .. tostring(param_max))
            end
        end
    end
end

local function is_table_empty(t)
    return t == nil or next(t) == nil
end



local function request_validator(conf)
    local result = {}
    local param_limits = conf.param_limits
    local req_path = kong.request.get_path()
    
    kong.log.debug("[api-param-limit] real request from client is :"..req_path)
    local path_params_table = path_params_mgr.parse_params(conf.api_fr_path, req_path, conf.api_fr_params)
    for i,v in ipairs(path_params_table) do
        kong.log.debug("[api-param-limit] path params [ name:"..i.." value:"..v.."]")
    end
    
    kong.log.debug("[api-param-limit] start checking query param")
    for i, v in ipairs(param_limits) do
        local param_name = v.name
        local location = v.location
        local param_value = nil
        if location == "query" then
            param_value =  kong.request.get_query_arg(param_name)
        elseif location == "head" then
            param_value = kong.request.get_header(param_name)
        elseif location == "path" then
            param_value = path_params_table[param_name]
        end
        kong.log.debug("[api-param-limit] check query param. param name: "..param_name)
        check(v, result, param_value, param_name)
        if table.getn(result) > 0 then
            break
        end
    end

    if not is_table_empty(result) then
        return kong.response.exit(400, { message = result })
    end
end

function _M.execute(conf)
    request_validator(conf)
end

return _M
