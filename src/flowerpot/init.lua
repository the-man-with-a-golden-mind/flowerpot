--- FlowerPot HTTP Framework (Copas)
-- Concurrent connections via Copas (LuaSocket + coroutines + select)
-- Supports HTTP keep-alive with idle timeout between requests.
-- SSE-safe: once SSE starts, we stop the keep-alive loop.

local socket = require "socket"
local copas  = require "copas"

local FlowerPot = {}
FlowerPot.__index = FlowerPot

function FlowerPot:new(config)
  config = config or {}

  return setmetatable({
    _middleware = {},
    _errorHandler = nil,
    _config = {
      host = config.host or "*",
      port = tonumber(config.port or 9090),
      maxBodySize = config.maxBodySize or 10 * 1024 * 1024,
      maxConnections = config.maxConnections or 1000,
      reuseAddr = config.reuseAddr ~= false,
      keepAliveTimeout = tonumber(config.keepAliveTimeout or 15), -- seconds
    },
    _activeCount = 0,
  }, self)
end

function FlowerPot:use(fn)
  assert(type(fn) == "function", "Middleware must be a function")
  table.insert(self._middleware, fn)
  return self
end

function FlowerPot:onError(handler)
  self._errorHandler = handler
  return self
end

function FlowerPot:_handleError(err, req, res)
  print("[ERROR] " .. tostring(err))

  if self._errorHandler then
    pcall(self._errorHandler, err, req, res)
    return
  end

  if res and not res._headersSent then
    pcall(function()
      res:status(500):json({ error = "Internal Server Error" })
    end)
  end
end

function FlowerPot:_runMiddleware(req, res)
  local index = 1
  local middleware = self._middleware

  local function next()
    if index > #middleware then return false end

    local fn = middleware[index]
    index = index + 1

    local ok, result = xpcall(function()
      return fn(req, res, next)
    end, debug.traceback)

    if not ok then
      self:_handleError(result, req, res)
      return true
    end

    return result
  end

  return next()
end

-- Copas-friendly yield/sleep (used by SSE etc.)
function FlowerPot.yield()
  if copas and copas.sleep then return copas.sleep(0) end
end

function FlowerPot.sleep(seconds)
  if copas and copas.sleep then return copas.sleep(seconds or 0) end
end

local function lower(s)
  return (type(s) == "string" and s:lower()) or ""
end

function FlowerPot:_processConnection(client, server)
  local Request = require "flowerpot.request"

  while true do
    local req = Request:new(self._config.port, client, server, self)
    local res = req.response

    local method = req:method()

    if not method then
      -- If idle timeout occurred, we just close quietly.
      if req._lastErr == "idle" then
        pcall(function() client:close() end)
        return
      end

      -- If we got some garbage/partial HTTP, try sending 400 once.
      if req._firstLine then
        pcall(function()
          res:status(400):text("Bad Request")
        end)
      end

      pcall(function() client:close() end)
      return
    end

    local stopped = self:_runMiddleware(req, res)

    if not stopped and not res.closed then
      pcall(function()
        res:status(404):json({ error = "Not Found" })
      end)
    end

    if res._isSSE and not res.closed then
      return
    end

    -- Decide whether to close
    local reqConn = lower(req:header("connection", ""))
    local resConn = lower(res._headers["Connection"] or res._headers["connection"] or "")

    if reqConn == "close" or resConn == "close" then
      pcall(function() client:close() end)
      return
    end

    -- otherwise keep-alive, loop
  end
end

function FlowerPot:listen(callback)
  if callback then self:use(callback) end

  local server = assert(socket.bind(self._config.host, self._config.port))
  if self._config.reuseAddr then
    pcall(function() server:setoption("reuseaddr", true) end)
  end

  local ip, port = server:getsockname()
  print(("🌺 FlowerPot blooming on http://%s:%d (copas)"):format(ip, port))
  print("Max connections:", self._config.maxConnections)
  print("Keep-alive idle timeout:", self._config.keepAliveTimeout .. "s")

  copas.addserver(server, function(rawClient)
    if self._activeCount >= self._config.maxConnections then
      pcall(function() rawClient:close() end)
      return
    end

    self._activeCount = self._activeCount + 1
    local client = copas.wrap(rawClient)

    local ok, err = xpcall(function()
      self:_processConnection(client, server)
    end, debug.traceback)

    if not ok then
      print("Connection error:", err)
      pcall(function() client:close() end)
    end

    self._activeCount = self._activeCount - 1
  end)

  copas.loop()
end

return FlowerPot
