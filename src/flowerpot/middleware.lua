--- FlowerPot Middleware
-- Collection of common middleware utilities
--
-- @module flowerpot.middleware

local socket = require 'socket'

local Middleware = {}

--- Logger middleware
-- Logs each request with method, path, status, and duration
---@param options table|nil Options (logger, format)
---@return function middleware
function Middleware.logger(options)
  options = options or {}
  
  return function(req, res, next)
    local startTime = os.time()
    local method = req:method()
    local path = req:path()
    
    -- Continue processing
    next()
    
    -- Log after response
    local duration = os.time() - startTime
    local status = res._status or 200
    
    print(string.format('[%s] %s %s - %d (%ds)', 
      os.date('%Y-%m-%d %H:%M:%S'), method, path, status, duration))
  end
end

--- CORS middleware
-- Handles Cross-Origin Resource Sharing
---@param options table Options (origin, methods, headers, credentials, maxAge)
---@return function middleware
function Middleware.cors(options)
  options = options or {}
  local origin = options.origin or '*'
  local methods = options.methods or 'GET,HEAD,PUT,PATCH,POST,DELETE'
  local headers = options.headers or 'Content-Type,Authorization'
  local credentials = options.credentials or false
  local maxAge = options.maxAge or 86400
  
  return function(req, res, next)
    -- Set CORS headers
    res:addHeader('Access-Control-Allow-Origin', origin)
    res:addHeader('Access-Control-Allow-Methods', methods)
    res:addHeader('Access-Control-Allow-Headers', headers)
    
    if credentials then
      res:addHeader('Access-Control-Allow-Credentials', 'true')
    end
    
    -- Handle preflight requests
    if req:method() == 'OPTIONS' then
      res:addHeader('Access-Control-Max-Age', tostring(maxAge))
      res:status(204):write('')
      return true -- Stop processing
    end
    
    return next()
  end
end

--- Body size limiter middleware
-- Rejects requests exceeding max body size
---@param maxSize number Maximum body size in bytes
---@return function middleware
function Middleware.bodyLimit(maxSize)
  maxSize = maxSize or 1024 * 1024 -- 1MB default
  
  return function(req, res, next)
    local contentLength = req:contentLength()
    
    if contentLength > maxSize then
      res:status(413):json({
        error = 'Payload Too Large',
        maxSize = maxSize,
        received = contentLength
      })
      return true -- Stop processing
    end
    
    return next()
  end
end

--- Request timeout middleware
-- Sets a timeout for request processing
---@param seconds number Timeout in seconds
---@return function middleware
function Middleware.timeout(seconds)
  return function(req, res, next)
    local deadline = socket.gettime() + seconds
    
    -- Store original socket timeout
    local originalTimeout = req.client:getoption('timeout')
    req.client:settimeout(seconds)
    
    -- Wrap next() with timeout check
    local function timedNext()
      if socket.gettime() > deadline then
        res:status(408):json({ error = 'Request Timeout' })
        return true
      end
      return next()
    end
    
    local result = timedNext()
    
    -- Restore original timeout
    req.client:settimeout(originalTimeout)
    
    return result
  end
end

--- Static file serving middleware
-- Serves static files from a directory
---@param root string Root directory path
---@param options table|nil Options (index, maxAge, dotfiles)
---@return function middleware
function Middleware.static(root, options)
  options = options or {}
  local index = options.index or 'index.html'
  local maxAge = options.maxAge or 0
  local dotfiles = options.dotfiles or false
  
  -- Simple MIME type detection
  local function getMimeType(path)
    local ext = path:match('%.([^%.]+)$')
    if not ext then return 'application/octet-stream' end
    
    ext = ext:lower()
    local types = {
      html = 'text/html',
      htm = 'text/html',
      css = 'text/css',
      js = 'application/javascript',
      json = 'application/json',
      xml = 'application/xml',
      txt = 'text/plain',
      md = 'text/markdown',
      
      jpg = 'image/jpeg',
      jpeg = 'image/jpeg',
      png = 'image/png',
      gif = 'image/gif',
      svg = 'image/svg+xml',
      ico = 'image/x-icon',
      webp = 'image/webp',
      
      pdf = 'application/pdf',
      zip = 'application/zip',
      tar = 'application/x-tar',
      gz = 'application/gzip',
      
      mp3 = 'audio/mpeg',
      wav = 'audio/wav',
      ogg = 'audio/ogg',
      
      mp4 = 'video/mp4',
      webm = 'video/webm',
      
      woff = 'font/woff',
      woff2 = 'font/woff2',
      ttf = 'font/ttf',
      otf = 'font/otf',
    }
    
    return types[ext] or 'application/octet-stream'
  end
  
  return function(req, res, next)
    if req:method() ~= 'GET' and req:method() ~= 'HEAD' then
      return next()
    end
    
    local path = req:path()
    
    -- Block dotfiles if configured
    if not dotfiles and path:match('/%.') then
      return next()
    end
    
    -- Normalize path
    local filePath = root .. path
    
    -- Try index file for directories
    if path:sub(-1) == '/' then
      filePath = filePath .. index
    end
    
    -- Try to serve file
    local file, err = io.open(filePath, 'rb')
    if not file then
      return next() -- File not found, continue to next middleware
    end
    
    local content = file:read('*a')
    file:close()
    
    -- Set cache headers
    if maxAge > 0 then
      res:addHeader('Cache-Control', 'public, max-age=' .. maxAge)
    end
    
    -- Set content type
    local contentType = getMimeType(filePath)
    res:contentType(contentType)
    
    res:write(content)
    return true -- Stop processing
  end
end

--- Request ID middleware
-- Adds unique ID to each request
---@param options table|nil Options (header, generator)
---@return function middleware
function Middleware.requestId(options)
  options = options or {}
  local header = options.header or 'X-Request-ID'
  local generator = options.generator or function()
    -- Generate a simpler random ID (avoids 2^64 issue in Lua 5.4)
    return string.format('%08x%08x', 
      math.random(0, 0xFFFFFFFF), 
      math.random(0, 0xFFFFFFFF))
  end
  
  return function(req, res, next)
    local id = req:header(header) or generator()
    req.id = id
    res:addHeader(header, id)
    return next()
  end
end

--- Security headers middleware
-- Adds common security headers
---@param options table|nil Custom header values
---@return function middleware
function Middleware.securityHeaders(options)
  options = options or {}
  
  local defaults = {
    ['X-Content-Type-Options'] = 'nosniff',
    ['X-Frame-Options'] = 'SAMEORIGIN',
    ['X-XSS-Protection'] = '1; mode=block',
    ['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains',
    ['Referrer-Policy'] = 'strict-origin-when-cross-origin',
  }
  
  -- Merge with custom options
  for k, v in pairs(options) do
    defaults[k] = v
  end
  
  return function(req, res, next)
    for header, value in pairs(defaults) do
      if value ~= false then -- Allow disabling with false
        res:addHeader(header, value)
      end
    end
    return next()
  end
end

--- Compression middleware wrapper
-- Wraps Pegasus compress plugin as middleware
---@param options table|nil Options for compress plugin
---@return function middleware
function Middleware.compress(options)
  -- TODO: Implement native compression support
  -- For now, return a no-op middleware
  return function(req, res, next)
    -- Compression not yet implemented in standalone FlowerPot
    return next()
  end
end

--- Rate limiting middleware (simple in-memory)
-- WARNING: Not suitable for production with multiple workers
---@param options table Options (windowMs, max, keyGenerator)
---@return function middleware
function Middleware.rateLimit(options)
  options = options or {}
  local windowMs = options.windowMs or 60000 -- 1 minute
  local max = options.max or 100
  local keyGenerator = options.keyGenerator or function(req)
    return req:ip() or 'unknown'
  end
  
  local requests = {} -- { [key] = { count, resetTime } }
  
  return function(req, res, next)
    local key = keyGenerator(req)
    local now = socket.gettime() * 1000
    
    local record = requests[key]
    
    if not record or now > record.resetTime then
      -- New window
      requests[key] = {
        count = 1,
        resetTime = now + windowMs
      }
      res:addHeader('X-RateLimit-Limit', tostring(max))
      res:addHeader('X-RateLimit-Remaining', tostring(max - 1))
      return next()
    end
    
    if record.count >= max then
      -- Rate limit exceeded
      res:addHeader('X-RateLimit-Limit', tostring(max))
      res:addHeader('X-RateLimit-Remaining', '0')
      res:addHeader('Retry-After', tostring(math.ceil((record.resetTime - now) / 1000)))
      res:status(429):json({ error = 'Too Many Requests' })
      return true
    end
    
    -- Increment counter
    record.count = record.count + 1
    res:addHeader('X-RateLimit-Limit', tostring(max))
    res:addHeader('X-RateLimit-Remaining', tostring(max - record.count))
    
    return next()  -- FIXED: must return!
  end
end

--- Error handler middleware
-- Must be used AFTER all other middleware
---@param handler function|nil Custom error handler function(err, req, res)
---@return function middleware
function Middleware.errorHandler(handler)
  return function(req, res, next)
    local success, err = pcall(next)
    
    if not success then
      if handler then
        handler(err, req, res)
      else
        res:status(500):json({
          error = 'Internal Server Error',
          message = tostring(err)
        })
      end
      return true
    end
  end
end

--- Method override middleware
-- Allows using X-HTTP-Method-Override header or _method query/body param
---@return function middleware
function Middleware.methodOverride()
  return function(req, res, next)
    local override = req:header('X-HTTP-Method-Override')
    
    if not override then
      override = req:query('_method')
    end
    
    if not override then
      local body = req:body()
      if type(body) == 'table' then
        override = body._method
      end
    end
    
    if override then
      req._method = override:upper()
    end
    
    return next()
  end
end

return Middleware