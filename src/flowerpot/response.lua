--- FlowerPot Response

local ok, json = pcall(require, "dkjson")
if not ok then ok, json = pcall(require, "cjson") end
assert(ok and json, "Install dkjson or lua-cjson")

local function jsonEncode(v) return json.encode(v) end

local function sendAll(client, data)
  local i, n = 1, #data
  while i <= n do
    local sent, err, last = client:send(data, i)
    if not sent then
      if last and last > 0 then
        i = i + last
      else
        return nil, err
      end
    else
      i = i + sent
    end
  end
  return true
end

local function toHex(dec)
  local charset = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' }
  local tmp = {}
  repeat
    table.insert(tmp, 1, charset[dec % 16 + 1])
    dec = math.floor(dec / 16)
  until dec == 0
  return table.concat(tmp)
end

local STATUS_TEXT = {
  [100]='Continue',[101]='Switching Protocols',
  [200]='OK',[201]='Created',[202]='Accepted',
  [203]='Non-Authoritative Information',[204]='No Content',
  [205]='Reset Content',[206]='Partial Content',
  [300]='Multiple Choices',[301]='Moved Permanently',
  [302]='Found',[303]='See Other',[304]='Not Modified',
  [305]='Use Proxy',[307]='Temporary Redirect',
  [400]='Bad Request',[401]='Unauthorized',
  [402]='Payment Required',[403]='Forbidden',
  [404]='Not Found',[405]='Method Not Allowed',
  [406]='Not Acceptable',[407]='Proxy Authentication Required',
  [408]='Request Time-out',[409]='Conflict',
  [410]='Gone',[411]='Length Required',
  [412]='Precondition Failed',[413]='Request Entity Too Large',
  [414]='Request-URI Too Large',[415]='Unsupported Media Type',
  [416]='Requested range not satisfiable',[417]='Expectation Failed',
  [429]='Too Many Requests',
  [500]='Internal Server Error',[501]='Not Implemented',
  [502]='Bad Gateway',[503]='Service Unavailable',
  [504]='Gateway Time-out',[505]='HTTP Version not supported',
}

local Response = {}
Response.__index = Response

function Response:new(client, app)
  return setmetatable({
    _client = client,
    _app = app,
    _status = 200,
    _statusText = STATUS_TEXT[200],
    _headers = {},
    _headersSent = false,
    closed = false,
    _skipBody = false,
    _isSSE = false,
    _sseEventId = 0,
    _chunked = false,
    request = nil, -- assigned by Request:new
  }, self)
end

local function safeSend(self, data)
  if self.closed then return nil, "closed" end
  local ok2, err = sendAll(self._client, data)
  if not ok2 then
    self.closed = true
    self._isSSE = false
    pcall(function() self._client:close() end)
    return nil, err
  end
  return true
end

function Response:statusCode(code, text)
  assert(not self._headersSent, "Headers already sent")
  self._status = code
  self._statusText = text or STATUS_TEXT[code] or "Unknown"
  return self
end
function Response:status(code) return self:statusCode(code) end

function Response:addHeader(key, value)
  assert(not self._headersSent, "Headers already sent")
  self._headers[key] = value
  return self
end
function Response:addHeaders(headers)
  for k, v in pairs(headers) do self:addHeader(k, v) end
  return self
end
function Response:contentType(value) return self:addHeader("Content-Type", value) end
function Response:skipBody(skip) self._skipBody = skip ~= false end

function Response:_setDefaultHeader(k, v)
  if self._headers[k] == nil then
    self._headers[k] = v
  end
end

local function lower(s)
  return (type(s) == "string" and s:lower()) or ""
end

function Response:_sendHeaders(chunked, body)
  if self._headersSent or self.closed then return end

  self._chunked = chunked and true or false

  -- defaults
  self:_setDefaultHeader("Date", os.date('!%a, %d %b %Y %H:%M:%S GMT'))
  self:_setDefaultHeader("Content-Type", "text/html; charset=utf-8")

  -- For SSE: headers are handled by initSSE (no chunked / no content-length)
  if not self._isSSE then
    if chunked then
      -- chunked streaming
      if self._headers["Transfer-Encoding"] == nil and self._headers["Content-Length"] == nil then
        self._headers["Transfer-Encoding"] = "chunked"
      end
    else
      -- normal response: Content-Length unless user set framing explicitly
      if type(body) == "string"
        and self._headers["Content-Length"] == nil
        and self._headers["Transfer-Encoding"] == nil
      then
        self._headers["Content-Length"] = #body
      end

      -- keep-alive default (unless client asked close)
      if self._headers["Connection"] == nil then
        local reqConn = ""
        if self.request and self.request.header then
          reqConn = lower(self.request:header("connection", ""))
        end
        self._headers["Connection"] = (reqConn == "close") and "close" or "keep-alive"
      end
    end
  end

  local response = string.format("HTTP/1.1 %d %s\r\n", self._status, self._statusText)
  for name, value in pairs(self._headers) do
    if type(value) == "table" then
      for _, v in ipairs(value) do
        response = response .. name .. ": " .. v .. "\r\n"
      end
    else
      response = response .. name .. ": " .. value .. "\r\n"
    end
  end
  response = response .. "\r\n"

  local ok2, err = safeSend(self, response)
  if not ok2 then error("send headers failed: " .. tostring(err)) end
  self._headersSent = true
end

function Response:write(body, keepOpen)
  body = body or ""
  self:_sendHeaders(keepOpen, body)

  if self._skipBody or self.closed then return self end

  if keepOpen then
    -- chunked write
    if #body > 0 then
      local chunk = toHex(#body) .. "\r\n" .. body .. "\r\n"
      safeSend(self, chunk)
    end
  else
    -- normal write: DO NOT close socket here (keep-alive loop owns socket lifetime)
    safeSend(self, body)
    self.closed = true
  end

  return self
end

function Response:close()
  if self.closed then return self end

  if self._headersSent and self._chunked and (not self._skipBody) then
    safeSend(self, "0\r\n\r\n")
  end

  pcall(function() self._client:close() end)
  self.closed = true
  self._isSSE = false
  return self
end

function Response:json(data, statusCode)
  if statusCode then self:statusCode(statusCode) end
  local encoded = jsonEncode(data)
  self:contentType("application/json; charset=utf-8")
  return self:write(encoded)
end

function Response:html(html, statusCode)
  if statusCode then self:statusCode(statusCode) end
  self:contentType("text/html; charset=utf-8")
  return self:write(html)
end

function Response:text(text, statusCode)
  if statusCode then self:statusCode(statusCode) end
  self:contentType("text/plain; charset=utf-8")
  return self:write(text)
end

-- SSE: explicit headers, no chunked, no content-length
function Response:initSSE()
  self:statusCode(200)
  self._isSSE = true
  self._chunked = false

  self:addHeader("Content-Type", "text/event-stream; charset=utf-8")
  self:addHeader("Cache-Control", "no-cache")
  self:addHeader("Connection", "keep-alive")
  self:addHeader("X-Accel-Buffering", "no")
  self:_setDefaultHeader("Date", os.date('!%a, %d %b %Y %H:%M:%S GMT'))

  if not self._headersSent then
    local response = string.format("HTTP/1.1 %d %s\r\n", self._status, self._statusText)
    for name, value in pairs(self._headers) do
      if type(value) == "table" then
        for _, v in ipairs(value) do
          response = response .. name .. ": " .. v .. "\r\n"
        end
      else
        response = response .. name .. ": " .. value .. "\r\n"
      end
    end
    response = response .. "\r\n"
    safeSend(self, response)
    self._headersSent = true
  end

  if not self._skipBody and not self.closed then
    safeSend(self, ": SSE initialized\n\n")
  end

  self._sseEventId = 0
  return self
end

function Response:sendEvent(data, eventType, id)
  if not self._isSSE or self.closed then return false end
  if self._skipBody then return true end

  local message = ""
  if id then
    message = message .. "id: " .. tostring(id) .. "\n"
  else
    self._sseEventId = self._sseEventId + 1
    message = message .. "id: " .. self._sseEventId .. "\n"
  end
  if eventType then message = message .. "event: " .. eventType .. "\n" end
  if type(data) == "table" then data = jsonEncode(data) end
  for line in tostring(data):gmatch("[^\n]+") do
    message = message .. "data: " .. line .. "\n"
  end
  message = message .. "\n"

  local ok2 = safeSend(self, message)
  if not ok2 then
    self._isSSE = false
    self.closed = true
    return false
  end

  if self._app and self._app.yield then self._app.yield() end
  return true
end

function Response:endSSE()
  if self._isSSE and not self.closed then
    pcall(function() self._client:close() end)
    self.closed = true
    self._isSSE = false
  end
  return self
end

return Response
