--- Test POST without middleware

local FlowerPot = require 'flowerpot_sync'
local Router = require 'flowerpot.router'

print("🌺 Testing POST without middleware\n")

local app = FlowerPot:new({ port = 8080 })
local router = Router:new({ prefix = '/api' })

router:post('/users', function(req, res)
  print("POST handler called")
  
  print("About to parse JSON...")
  local body = req:json()
  print("JSON parsed:", body and "yes" or "nil")
  
  if body then
    print("Body.name:", body.name)
  end
  
  res:status(201):json({
    id = 123,
    name = body and body.name or 'unknown',
    received = true,
  })
  print("Response sent")
end)

app:use(router:middleware())

print("Server started on :8080")
print("Test with: curl -X POST -H 'Content-Type: application/json' -d '{\"name\":\"Alice\"}' http://localhost:8080/api/users\n")

app:listen()