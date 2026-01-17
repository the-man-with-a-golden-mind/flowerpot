--- Test POST with middleware one by one

local FlowerPot = require 'flowerpot_sync'
local Router = require 'flowerpot.router'
local Middleware = require 'flowerpot.middleware'

print("🌺 Testing POST with each middleware\n")

local app = FlowerPot:new({ port = 8080 })
local router = Router:new({ prefix = '/api' })

router:post('/users', function(req, res)
  print("✓ POST handler called")
  local body = req:json()
  res:status(201):json({
    id = 123,
    name = body and body.name or 'unknown',
  })
  print("✓ Response sent")
end)

-- Comment/uncomment to test each one

print("Adding middleware:")

print("1. Logger...")
app:use(Middleware.logger())

print("2. CORS...")
app:use(Middleware.cors({ origin = '*' }))

print("3. Security headers...")
app:use(Middleware.securityHeaders())

print("4. Request ID...")
app:use(Middleware.requestId())

-- THIS ONE might be the problem:
print("5. Rate limit...")
app:use(Middleware.rateLimit({ max = 100 }))

-- OR THIS ONE:
print("6. Body limit...")
app:use(Middleware.bodyLimit(5 * 1024 * 1024))

app:use(router:middleware())

print("\nAll middleware added")
print("Test: curl -X POST -H 'Content-Type: application/json' -d '{\"name\":\"Alice\"}' http://localhost:8080/api/users\n")

app:listen()