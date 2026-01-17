--- Simple SSE Test (Copas-friendly)
-- Test Server-Sent Events

local FlowerPot = require "flowerpot"
local Router = require "flowerpot.router"

print("🌺 FlowerPot SSE Test\n")

local app = FlowerPot:new({ port = 8080 })
local router = Router:new()

-- SSE endpoint
router:get("/events", function(req, res)
  print("SSE connection started")

  res:initSSE()

  local ok = res:sendEvent({ message = "Connected!" }, "connected")
  if ok == false then
    print("Client disconnected immediately")
    return
  end

  print("Sent connected event")

  for i = 1, 100 do
    -- IMPORTANT: never busy-wait in Copas
    FlowerPot.sleep(1)

    -- sendEvent should return false when client disconnects
    local sent = res:sendEvent({
      count = i,
      time = os.date("%H:%M:%S"),
    }, "update")

    if sent == false then
      print("Client disconnected, stopping SSE loop at event", i)
      return
    end

    print("Sent event", i)
  end

  res:sendEvent({ message = "Done!" }, "close")
  print("SSE stream ended")

  res:endSSE()
end)

-- HTML page to test
router:get("/sse", function(req, res)
  res:html([[
<!DOCTYPE html>
<html>
<head>
  <title>SSE Test</title>
  <style>
    body { font-family: monospace; padding: 20px; }
    #events { background: #f0f0f0; padding: 10px; margin-top: 10px; }
    .event { padding: 5px; border-left: 3px solid #4CAF50; margin: 5px 0; }
  </style>
</head>
<body>
  <h1>🌺 FlowerPot SSE Test</h1>
  <button onclick="startSSE()">Start SSE Stream</button>
  <button onclick="stopSSE()">Stop SSE</button>
  <div id="events"></div>

  <script>
    let evtSource = null;

    function startSSE() {
      stopSSE();

      document.getElementById('events').innerHTML = '<p>Connecting...</p>';
      evtSource = new EventSource('/events');

      evtSource.addEventListener('connected', (e) => {
        const data = JSON.parse(e.data);
        addEvent('✅ ' + data.message);
      });

      evtSource.addEventListener('update', (e) => {
        const data = JSON.parse(e.data);
        addEvent('📊 Event #' + data.count + ' at ' + data.time);
      });

      evtSource.addEventListener('close', (e) => {
        const data = JSON.parse(e.data);
        addEvent('🔴 ' + data.message);
        stopSSE();
      });

      evtSource.onerror = () => {
        addEvent('❌ Connection error (browser will auto-retry unless closed)');
      };
    }

    function stopSSE() {
      if (evtSource) {
        evtSource.close();
        evtSource = null;
        addEvent('🛑 Closed by client');
      }
    }

    function addEvent(msg) {
      const div = document.createElement('div');
      div.className = 'event';
      div.textContent = msg;
      document.getElementById('events').appendChild(div);
    }
  </script>
</body>
</html>
  ]])
end)

app:use(router:middleware())

print("Server starting on http://localhost:8080")
print("Open http://localhost:8080/sse in browser\n")

app:listen()
