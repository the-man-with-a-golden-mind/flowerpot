--- Simple FlowerPot Test - No Middleware
-- Test basic request/response without middleware issues

local FlowerPot = require 'flowerpot_sync'
local Router = require 'flowerpot.router'

print("🌺 Simple FlowerPot Test - No Middleware\n")

local app = FlowerPot:new({ port = 8080 })
local router = Router:new({ prefix = '/api' })

-- Simple GET
router:get('/hello', function(req, res)
  print("Handler called for /api/hello")
  res:json({ message = 'Hello!' })
  print("Response sent")
end)

-- Simple POST
router:post('/users', function(req, res)
  print("Handler called for POST /api/users")
  local body = req:json()
  print("Body:", body and body.name or "nil")
  
  res:status(201):json({
    id = 123,
    name = body and body.name or 'Unknown',
  })
  print("Response sent")
end)

app:use(router:middleware())

-- 404 handler
app:use(function(req, res)
  print("404 handler called for:", req:path())
  res:status(404):json({ error = 'Not Found' })
end)

print("Starting server on :8080")
print("Try: curl http://localhost:8080/api/hello")
print("Try: curl -X POST -H 'Content-Type: application/json' -d '{\"name\":\"Alice\"}' http://localhost:8080/api/users\n")

app:listen()