--- FlowerPot Router
-- Enhanced routing with method handlers, groups, and middleware
--
-- @module flowerpot.router

local Router = {}
Router.__index = Router

--- Create a new router instance
---@param options table|nil Options (prefix, caseSensitive)
---@return Router
function Router:new(options)
  options = options or {}
  
  local router = setmetatable({
    routes = {},
    prefix = options.prefix or '',
    caseSensitive = options.caseSensitive or false,
    _middleware = {},
    groups = {},
  }, self)
  
  return router
end

--- Add middleware to this router
---@param fn function Middleware function
---@return Router self
function Router:use(fn)
  table.insert(self._middleware, fn)
  return self
end

--- Normalize path pattern
---@param pattern string Path pattern
---@return string normalized
function Router:_normalizePath(pattern)
  if not self.caseSensitive then
    pattern = pattern:lower()
  end
  
  -- Ensure leading slash
  if pattern:sub(1, 1) ~= '/' then
    pattern = '/' .. pattern
  end
  
  return pattern
end

--- Convert path pattern to Lua pattern with parameter extraction
---@param pattern string Path pattern with {param} syntax
---@return string luaPattern, table paramNames
function Router:_compilePattern(pattern)
  local params = {}
  
  -- Escape special characters except {param}
  local escaped = pattern:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', '%%%1')
  
  -- Convert {param} to capture groups
  local luaPattern = escaped:gsub('{([%w_]+)}', function(paramName)
    table.insert(params, paramName)
    return '([^/]+)'
  end)
  
  -- Match full path
  luaPattern = '^' .. luaPattern .. '$'
  
  return luaPattern, params
end

--- Add a route for specific HTTP method
---@param method string HTTP method (GET, POST, etc.)
---@param pattern string Path pattern
---@param handler function Route handler function(req, res)
---@return Router self
function Router:route(method, pattern, handler)
  pattern = self:_normalizePath(pattern)
  local luaPattern, params = self:_compilePattern(pattern)
  
  table.insert(self.routes, {
    method = method:upper(),
    pattern = pattern,
    luaPattern = luaPattern,
    params = params,
    handler = handler,
    middleware = {},
  })
  
  return self
end

--- Add GET route
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:get(pattern, handler)
  return self:route('GET', pattern, handler)
end

--- Add POST route
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:post(pattern, handler)
  return self:route('POST', pattern, handler)
end

--- Add PUT route
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:put(pattern, handler)
  return self:route('PUT', pattern, handler)
end

--- Add PATCH route
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:patch(pattern, handler)
  return self:route('PATCH', pattern, handler)
end

--- Add DELETE route
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:delete(pattern, handler)
  return self:route('DELETE', pattern, handler)
end

--- Add route for all methods
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:all(pattern, handler)
  return self:route('*', pattern, handler)
end

--- Create a route group with shared prefix/middleware
---@param prefix string Group path prefix
---@param callback function Setup function(router)
---@return Router self
function Router:group(prefix, callback)
  local groupRouter = Router:new({
    prefix = self.prefix .. prefix,
    caseSensitive = self.caseSensitive,
  })
  
  -- Copy parent middleware
  for _, mw in ipairs(self._middleware) do
    table.insert(groupRouter._middleware, mw)
  end
  
  callback(groupRouter)
  
  -- Merge routes into parent
  for _, route in ipairs(groupRouter.routes) do
    table.insert(self.routes, route)
  end
  
  return self
end

--- Match a request against routes
---@param req table Request object
---@return table|nil route, table|nil params
function Router:match(req)
  local method = req:method()
  local path = req:path()
  
  -- Apply prefix
  if self.prefix ~= '' then
    if path:sub(1, #self.prefix) ~= self.prefix then
      return nil
    end
    path = path:sub(#self.prefix + 1)
    if path == '' then
      path = '/'
    end
  end
  
  if not self.caseSensitive then
    path = path:lower()
  end
  
  -- Try to match routes
  for _, route in ipairs(self.routes) do
    -- Check method
    if route.method == '*' or route.method == method then
      -- Try to match pattern
      local matches = { path:match(route.luaPattern) }
      
      if #matches > 0 then
        -- Extract parameters
        local params = {}
        for i, paramName in ipairs(route.params) do
          params[paramName] = matches[i]
        end
        
        return route, params
      end
    end
  end
  
  return nil
end

--- Handle request through router
---@param req table Request object
---@param res table Response object
---@return boolean handled
function Router:handle(req, res)
  local route, params = self:match(req)
  
  if not route then
    return false
  end
  
  -- Set path parameters
  req.pathParameters = params
  
  -- Build middleware chain (router middleware + route middleware)
  local chain = {}
  for _, mw in ipairs(self._middleware) do
    table.insert(chain, mw)
  end
  for _, mw in ipairs(route.middleware) do
    table.insert(chain, mw)
  end
  table.insert(chain, route.handler)
  
  -- Execute chain
  local index = 1
  local function next()
    if index > #chain then
      return false
    end
    
    local fn = chain[index]
    index = index + 1
    
    return fn(req, res, next)
  end
  
  next()
  return true
end

--- Convert router to middleware function
---@return function middleware
function Router:middleware()
  return function(req, res, next)
    local handled = self:handle(req, res)
    if not handled then
      next()
    end
    return handled
  end
end

--- Named routes support
Router._namedRoutes = {}

--- Add a named route
---@param name string Route name
---@param method string HTTP method
---@param pattern string Path pattern
---@param handler function Route handler
---@return Router self
function Router:namedRoute(name, method, pattern, handler)
  self:route(method, pattern, handler)
  Router._namedRoutes[name] = {
    pattern = pattern,
    method = method,
  }
  return self
end

--- Generate URL for named route
---@param name string Route name
---@param params table|nil Path parameters
---@param query table|nil Query parameters
---@return string|nil url
function Router.url(name, params, query)
  local route = Router._namedRoutes[name]
  if not route then
    return nil
  end
  
  local url = route.pattern
  
  -- Replace parameters
  if params then
    for key, value in pairs(params) do
      url = url:gsub('{' .. key .. '}', tostring(value))
    end
  end
  
  -- Add query string
  if query and next(query) then
    local pairs = {}
    for key, value in pairs(query) do
      table.insert(pairs, key .. '=' .. tostring(value))
    end
    url = url .. '?' .. table.concat(pairs, '&')
  end
  
  return url
end

return Router