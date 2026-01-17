--- FlowerPot Request
-- Standalone HTTP request parser

local socket = require "socket"

local ok, json = pcall(require, "dkjson")
if not ok then ok, json = pcall(require, "cjson") end
assert(ok and json, "Install dkjson or lua-cjson")

local Response = require "flowerpot.response"

local function normalizePath(path)
  path = path:gsub('\\', '/'):gsub('^/*', '/'):gsub('(/%.%.?)$', '%1/')
  path = path:gsub('/%./', '/'):gsub('/+', '/')

  while true do
    local first, last = path:find('/[^/]+/%.%./')
    if not first then break end
    path = path:sub(1, first) .. path:sub(last + 1)
  end

  while path:gsub('^/%.%.?/', '/') ~= path do
    path = path:gsub('^/%.%.?/', '/')
  end

  return path:gsub('/%.%.?$', '/')
end

-- - retries on timeout/wantread
-- - returns nil,"idle" if no full line arrives within keepAliveTimeout
local function recvLine(req, idleTimeout)
  local sock = req.client
  local start = socket.gettime()

  while true do
    local line, err = sock:receive("*l")
    if line then
      return line, nil
    end

    if err == "timeout" or err == "wantread" then
      if idleTimeout and (socket.gettime() - start) >= idleTimeout then
        return nil, "idle"
      end
      if req.app and req.app.yield then req.app.yield() end
    elseif err == "closed" then
      return nil, "closed"
    else
      return nil, err
    end
  end
end

local Request = {}
Request.__index = Request

function Request:new(port, client, server, app)
  local obj = {
    client = client,
    server = server,
    app = app,
    port = port,
    _rawIp = (client.getpeername and client:getpeername()) or nil,
    querystring = {},
    _firstLine = nil,
    _lastErr = nil,
    _method = nil,
    _path = nil,
    _headersParsed = false,
    _headers = {},
    _parsedBody = nil,
    _cookies = nil,
    _contentLength = 0,
    _contentDone = 0,
    pathParameters = {},
  }

  obj = setmetatable(obj, self)
  obj.response = Response:new(client, app)
  obj.response.request = obj

  return obj
end

function Request:parseFirstLine()
  if self._firstLine then return end

  local idleTimeout = (self.app and self.app._config and self.app._config.keepAliveTimeout) or nil
  local line, err = recvLine(self, idleTimeout)
  self._lastErr = err
  self._firstLine = line

  if not self._firstLine then return end

  local method, path = self._firstLine:match('^(%S+)%s+(%S+)%s+HTTP/%d%.%d')
  if not method then
    -- don't close here; framework decides
    return
  end

  self.response:skipBody(method == "HEAD")

  local filename, querystring = '', ''
  if #path > 0 then
    filename, querystring = path:match('^([^#?]+)[#|?]?(.*)')
    filename = normalizePath(filename)
  end

  self._path = filename
  self._method = method
  self.querystring = self:parseUrlEncoded(querystring)
end

function Request:parseUrlEncoded(data)
  local output = {}
  if not data then return output end

  for key, value in data:gmatch('([^=]*)=([^&]*)&?') do
    if key and value then
      local v = output[key]
      if not v then
        output[key] = value
      elseif type(v) == "string" then
        output[key] = { v, value }
      else
        v[#v + 1] = value
      end
    end
  end
  return output
end

function Request:path()
  self:parseFirstLine()
  return self._path
end

function Request:method()
  self:parseFirstLine()
  return self._method
end

function Request:headers()
  if self._headersParsed then return self._headers end

  self:parseFirstLine()

  local headers = setmetatable({}, {
    __index = function(self, key)
      if type(key) == "string" then
        return rawget(self, key:lower())
      end
    end
  })

  -- If first line wasn't parsed (idle/closed), just mark parsed and return empty.
  if not self._firstLine then
    self._headersParsed = true
    self._headers = headers
    self._contentLength = 0
    return headers
  end

  -- Read headers until empty line
  while true do
    local line, err = recvLine(self, nil) -- no idle timeout while we're mid-request
    self._lastErr = err

    if not line then
      break
    end

    if #line == 0 then
      break
    end

    local key, value = line:match('^([%w-]+):%s*(.*)%s*$')
    if key and value then
      key = key:lower()
      local v = headers[key]
      if not v then
        headers[key] = value
      elseif type(v) == "string" then
        headers[key] = { v, value }
      else
        v[#v + 1] = value
      end
    end
  end

  self._headersParsed = true
  self._contentLength = tonumber(headers["content-length"] or 0) or 0
  self._headers = headers

  return headers
end

function Request:receiveBody(size)
  if not self._headersParsed then
    self:headers()
  end

  local contentLength = self._contentLength
  local contentDone = self._contentDone
  size = size or contentLength

  if contentLength == 0 or contentDone >= contentLength then
    return false
  end

  local fetch = math.min(contentLength - contentDone, size)
  local data, err, partial = self.client:receive(fetch)

  if not data then
    if err == "timeout" and partial and #partial > 0 then
      data = partial
    else
      return nil
    end
  end

  self._contentDone = contentDone + #data
  return data
end

function Request:body()
  if self._parsedBody ~= nil then return self._parsedBody end

  local headers = self:headers()
  local contentType = headers['content-type'] or ''

  local rawBody = self:receiveBody()
  if not rawBody or rawBody == false then
    self._parsedBody = nil
    return nil
  end

  if contentType:find('application/json', 1, true) then
    self._parsedBody = json.decode(rawBody)
  elseif contentType:find('application/x-www-form-urlencoded', 1, true) then
    self._parsedBody = self:parseUrlEncoded(rawBody)
  else
    self._parsedBody = rawBody
  end

  return self._parsedBody
end

function Request:json()
  local body = self:body()
  return type(body) == 'table' and body or nil
end

function Request:form()
  local headers = self:headers()
  local contentType = headers['content-type'] or ''
  if contentType:find('application/x-www-form-urlencoded', 1, true) then
    return self:body()
  end
  return nil
end

function Request:post()
  if self:method() ~= 'POST' then return nil end
  return self:form()
end

function Request:query(key, default)
  local value = self.querystring[key]
  return value ~= nil and value or default
end

function Request:queries()
  return self.querystring
end

function Request:param(key, default)
  if not self.pathParameters then return default end
  local value = self.pathParameters[key]
  return value ~= nil and value or default
end

function Request:params()
  return self.pathParameters
end

function Request:header(key, default)
  local headers = self:headers()
  local value = headers[key]
  return value ~= nil and value or default
end

function Request:cookie(name, default)
  if not self._cookies then
    local cookieHeader = self:header('cookie', '')
    self._cookies = {}
    for pair in cookieHeader:gmatch('[^;]+') do
      local k, v = pair:match('^%s*([^=]+)=(.*)%s*$')
      if k and v then
        self._cookies[k] = v
      end
    end
  end

  local value = self._cookies[name]
  return value ~= nil and value or default
end

function Request:cookies()
  self:cookie('_')
  return self._cookies or {}
end

function Request:accepts(contentType)
  local accept = self:header('accept', '*/*')
  if accept:find(contentType, 1, true) then return true end
  if accept:find('*/*', 1, true) then return true end
  local mainType = contentType:match('^([^/]+)/')
  if mainType and accept:find(mainType .. '/%*', 1, true) then return true end
  return false
end

function Request:isXHR()
  return (self:header('x-requested-with', '')):lower() == 'xmlhttprequest'
end

function Request:isJSON()
  return (self:header('content-type', '')):find('application/json', 1, true) ~= nil
end

function Request:protocol()
  local forwarded = self:header('x-forwarded-proto', '')
  if forwarded ~= '' then return forwarded:lower() end
  if self.client.dohandshake then return 'https' end
  return 'http'
end

function Request:isSecure()
  return self:protocol() == 'https'
end

function Request:url()
  return self:protocol() .. '://' .. self:header('host', 'localhost') .. self:path()
end

function Request:baseUrl()
  return self:protocol() .. '://' .. self:header('host', 'localhost')
end

function Request:ip()
  local forwarded = self:header('x-forwarded-for', '')
  if forwarded ~= '' then return forwarded:match('^([^,]+)') end
  local realIP = self:header('x-real-ip', '')
  if realIP ~= '' then return realIP end
  return self._rawIp
end

function Request:contentLength()
  return tonumber(self:header('content-length', 0)) or 0
end

function Request:hasBody()
  return self:contentLength() > 0
end

return Request
