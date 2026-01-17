--- Debug Benchmark Server (Copas)
-- Tests real FlowerPot:listen() (Copas) and prints stats without overriding listen.

local copas = require "copas"

local FlowerPot  = require "flowerpot"
local Router     = require "flowerpot.router"
local Middleware = require "flowerpot.middleware"

print("🌺 Debug Benchmark Server (Copas)\n")

-- Track counters
local errorCount = 0
local successCount = 0

local app = FlowerPot:new({
  port = 8080,
  maxConnections = 1000,
  clientTimeout = 5,
  acceptTimeout = 0.001, -- may be ignored by Copas, ok to keep
})

-- Error handler
app:onError(function(err, req, res)
  errorCount = errorCount + 1
  -- print full errors only sometimes to avoid I/O overhead during benchmarks
  if errorCount <= 5 or (errorCount % 100 == 0) then
    print('[ERROR #' .. errorCount .. '] ' .. tostring(err))
  end
end)

-- Prepare static file
os.execute("mkdir -p public")

local html = assert(io.open("public/index.html", "w"))
html:write([[<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body><h1>FlowerPot Test</h1><p>Simple page for benchmarking.</p></body>
</html>]])
html:close()

-- Router
local router = Router:new({ prefix = "/api" })

router:get("/data", function(req, res)
  successCount = successCount + 1
  res:json({
    id = 1,
    name = "test",
    value = 123,
    active = true,
    items = {1, 2, 3},
  })
end)

app:use(router:middleware())

-- Static
app:use(Middleware.static("./public", {
  index = "index.html",
}))

-- 404
app:use(function(req, res)
  res:status(404):json({ error = "Not Found" })
end)

-- Stats printer (Copas thread)
local lastT = os.time()
local lastSuccess = 0
local lastError = 0

local function activeConnections(app)
  -- Prefer _activeCount (cheap + always there)
  local a = tonumber(app._activeCount) or 0

  -- If compat array exists, show it too
  local b = nil
  if type(app._connections) == "table" then
    b = #app._connections
  end

  return a, b
end

local function printStats()
  local now = os.time()
  if now > lastT then
    local reqPerSec = successCount - lastSuccess
    local errPerSec = errorCount - lastError

    local a, b = activeConnections(app)
    if b then
      print(string.format(
        "[STATS] Success: %d (+%d/s) | Errors: %d (+%d/s) | Active: %d | ConnsTbl: %d",
        successCount, reqPerSec, errorCount, errPerSec, a, b
      ))
    else
      print(string.format(
        "[STATS] Success: %d (+%d/s) | Errors: %d (+%d/s) | Active: %d",
        successCount, reqPerSec, errorCount, errPerSec, a
      ))
    end

    lastT = now
    lastSuccess = successCount
    lastError = errorCount
  end
end

-- Run stats loop without blocking the server loop
copas.addthread(function()
  while true do
    printStats()
    copas.sleep(0.2) -- print up to 5x/sec, but only increments each second in printStats()
  end
end)

print("🌺 Server on http://localhost:8080")
print("Test with:")
print("  wrk -t4 -c100 -d10s http://localhost:8080/")
print("  wrk -t4 -c100 -d10s http://localhost:8080/api/data")
print("Watch stats + errors.\n")

-- IMPORTANT: do NOT override listen; we want the real Copas-based server
app:listen()
