<p align="center">
  <svg width="220" height="220" viewBox="0 0 220 220">
    <defs>
      <clipPath id="circle">
        <circle cx="110" cy="110" r="110"/>
      </clipPath>
    </defs>
    <image
      href="assets/flowerpot.png"
      width="220"
      height="220"
      clip-path="url(#circle)"
      style="image-rendering: pixelated;"
    />
  </svg>
</p>

# 🌺 FlowerPot

A small HTTP framework for Lua.
Calm. Predictable. Slightly dangerous if misused.

FlowerPot is built on Copas + LuaSocket and designed for people who:
- understand sockets,
- don’t panic when a client disconnects,
- prefer clarity over “clever”.

It does async.
It does SSE.
It does not pretend to be something else.


## Philosophy

FlowerPot exists because:
- concurrency should be explicit, not magical
- long-lived connections should not scare your server
- disconnects are a normal event, not an exception
- reading the source should answer most questions

No hidden schedulers.
No background threads.
No surprises.


## Installation

luarocks install flowerpot

This installs:
- luasocket
- copas
- dkjson

Nothing more. Nothing less.



## Quick Start

```
local FlowerPot = require "flowerpot"
local Router = require "flowerpot.router"

local app = FlowerPot:new({ port = 8080 })
local router = Router:new()

router:get("/hello", function(req, res)
  res:json({ message = "hello, world" })
end)

app:use(router:middleware())
app:listen()
```
Open:
http://localhost:8080/hello

If this surprises you, read the code again.


## Server-Sent Events (SSE)

SSE is not a hack here.
It is treated as a first-class transport.

```
router:get("/events", function(req, res)
  res:initSSE()

  for i = 1, 10 do
    FlowerPot.sleep(1)

    if res:sendEvent({ count = i }, "update") == false then
      return
    end
  end

  res:endSSE()
end)
```
Why this works:
- cooperative scheduling (Copas)
- no blocking writes
- immediate disconnect detection
- zero busy loops

If the client leaves, the server notices and moves on.

## Async Model

FlowerPot uses cooperative async:
- single Lua state
- event-driven sockets
- yielding via Copas
- FlowerPot.sleep() instead of timers

This means:
- SSE streams do not block API requests
- thousands of idle connections are cheap
- behavior is deterministic

No threads.
No locks.
No race conditions.

## Router

```
router:get("/user/{id}", function(req, res)
  res:json({ user = req:param("id") })
end)
```
Features:
- path params
- grouping
- prefixing
- clean middleware export

The router does not guess.
It matches.


## Middleware

```
local Middleware = require "flowerpot.middleware"

app:use(Middleware.static("./public"))

app:use(function(req, res)
  print(req.method, req.path)
end)
```
Middleware is just functions.
Order matters.
Nothing is hidden.



## Examples

examples/
- sse_test.lua
- async_test.lua
- stress_debug.lua

Run:
lua examples/sse_test.lua
lua examples/async_test.lua


## What FlowerPot Is Not

- not a full-stack framework
- not async/await
- not multithreaded
- not trying to be Express, Fastify or Phoenix

It is a small tool that does its job and gets out of the way.


## Performance Notes

FlowerPot prefers:
- stability over micro-benchmarks
- correctness over cleverness
- predictable failure modes

It handles thousands of concurrent connections just fine.


## Requirements

- Lua 5.1+
- LuaSocket
- Copas


## License

MIT.

Use it.
Break it.
Fix it.
Understand it.

If something explodes, the code will tell you why.
