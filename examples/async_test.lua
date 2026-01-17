--- FlowerPot ASYNC Example
-- Shows concurrent SSE streams working!

local FlowerPot = require 'flowerpot'  -- ASYNC!
local Router = require 'flowerpot.router'

print("🌺 FlowerPot ASYNC - Concurrent SSE\n")

local app = FlowerPot:new({
  port = 8080,
  maxConnections = 100,
})

local router = Router:new()

-- Regular API endpoint
router:get('/api/hello', function(req, res)
  res:json({ message = 'Hello from async FlowerPot!' })
end)

-- SSE endpoint - multiple clients can connect!
router:get('/events', function(req, res)
  print("SSE client connected")
  
  res:initSSE()
  res:sendEvent({ message = 'Connected!' }, 'connected')
  
  -- Stream for 30 seconds
  for i = 1, 30 do
    FlowerPot.sleep(1)  -- Yields to other connections!
    
    local success, err = pcall(function()
      res:sendEvent({
        count = i,
        time = os.date('%H:%M:%S'),
      }, 'update')
    end)
    
    if not success then
      print("SSE client disconnected")
      break
    end
  end
  
  res:endSSE()
  print("SSE stream ended")
end)

-- HTML page
router:get('/', function(req, res)
  res:html([[
<!DOCTYPE html>
<html>
<head>
  <title>FlowerPot Async SSE</title>
  <style>
    body { font-family: monospace; padding: 20px; background: #1a1a2e; color: #eee; }
    h1 { color: #16c79a; }
    button { 
      background: #16c79a; 
      color: white; 
      border: none; 
      padding: 10px 20px; 
      margin: 5px;
      cursor: pointer;
      border-radius: 4px;
    }
    button:hover { background: #19d3ae; }
    .stream {
      background: #0f3460;
      padding: 10px;
      margin: 10px 0;
      border-radius: 4px;
      max-height: 200px;
      overflow-y: auto;
    }
    .event { 
      padding: 5px; 
      border-left: 3px solid #16c79a; 
      margin: 5px 0;
      background: rgba(22, 199, 154, 0.1);
    }
  </style>
</head>
<body>
  <h1>🌺 FlowerPot Async SSE Test</h1>
  <p>Open multiple streams - they ALL work concurrently!</p>
  
  <button onclick="addStream()">➕ Add Stream</button>
  <button onclick="clearStreams()">🗑️ Clear All</button>
  
  <div id="streams"></div>
  
  <script>
    let streamCount = 0;
    
    function addStream() {
      streamCount++;
      const id = 'stream-' + streamCount;
      
      const container = document.createElement('div');
      container.id = id;
      container.innerHTML = '<h3>Stream #' + streamCount + ' <button onclick="closeStream(\'' + id + '\')">❌ Close</button></h3><div class="stream" id="' + id + '-events"></div>';
      document.getElementById('streams').appendChild(container);
      
      const evtSource = new EventSource('/events');
      container.evtSource = evtSource;
      
      evtSource.addEventListener('connected', (e) => {
        addEvent(id, '✅ Connected');
      });
      
      evtSource.addEventListener('update', (e) => {
        const data = JSON.parse(e.data);
        addEvent(id, '📊 #' + data.count + ' at ' + data.time);
      });
      
      evtSource.onerror = () => {
        addEvent(id, '❌ Disconnected');
        evtSource.close();
      };
    }
    
    function addEvent(streamId, msg) {
      const div = document.createElement('div');
      div.className = 'event';
      div.textContent = msg;
      const events = document.getElementById(streamId + '-events');
      events.appendChild(div);
      events.scrollTop = events.scrollHeight;
    }
    
    function closeStream(id) {
      const container = document.getElementById(id);
      if (container.evtSource) {
        container.evtSource.close();
      }
      container.remove();
    }
    
    function clearStreams() {
      document.getElementById('streams').innerHTML = '';
      streamCount = 0;
    }
    
    // Auto-start one stream
    addStream();
  </script>
</body>
</html>
  ]])
end)

app:use(router:middleware())

print("Starting ASYNC server...")
print("Open http://localhost:8080")
print("Try opening multiple SSE streams - they ALL work at the same time!\n")

app:listen()