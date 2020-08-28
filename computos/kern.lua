-- ComputOS core --

--== core kernel routines ==--
local k = {}
k._VERSION = "ComputOS 0.1.0"

-- retrieve a component proxy
function k.get(t)
  checkArg(1, t, "string")
  local c = component.list(t)()
  if not c then
    return nil
  end
  return component.proxy(c)
end

-- simple bootlogger
do
  local gpu, screen = k.get("gpu"), k.get("screen")
  function k.log()
  end
  if gpu and screen then
    screen = screen.address
    gpu.bind(screen)
    local w, h = gpu.maxResolution()
    gpu.setResolution(w, h)
    gpu.fill(1, 1, w, h, " ")
    local y = 0
    local function put(msg)
      if y == h then
        gpu.copy(1, 1, w, h, 0, -1)
        gpu.fill(1, h, w, 1, " ")
      else
        y = y + 1
      end
      gpu.set(1, y, msg)
    end
    function k.log(...)
      local msg = table.concat(table.pack(..., " "))
      for ln in msg:gmatch("[^\n]+") do
        put(ln)
      end
    end
  end
end

k.log("Starting ".. k._VERSION)

-- panics
local pull = computer.pullSignal
function k.error(msg)
  local tb = "traceback:"
  local i = 2
  while true do
    local info = debug.getinfo(i)
    if not info then break end
    tb = tb .. string.format("\n  %s:%s: in %s'%s':", info.source:sub(2), info.currentline or "C", (info.namewhat ~= "" and info.namewhat .. " ") or "", info.name or "?")
    i = i + 1
  end
  k.log(tb)
  k.log(msg)
  k.log("kernel panic!")
  while true do pull() end
end

-- read file contents
do
  local bfs = component.proxy(computer.getBootAddress())

  function k.readfile(file)
    checkArg(1, file, "string")
    local fd, err = bfs.open(file, "r")
    if not fd then
      return nil, err
    end
    local buf = ""
    repeat
      local c = bfs.read(fd, math.huge)
      buf = buf .. (c or "")
    until not c
    bfs.close(fd)
    return buf
  end
end

--== cooperative scheduler ==--
-- This scheduler is comparatively basic. Threads
-- are only resumed when a signal is received or
-- when they receive a message.

do
  local threads = {}
  local api = {}
  local pid = 0

  function api.new(func, name)
    local new = {
      coro = coroutine.create(func),
      name = name,
      started = computer.uptime(),
      runtime = 0
    }
    threads[pid + 1] = new
    pid = pid + 1
    return pid
  end

  function api.message(pid, ...)
    computer.pushSignal("ipc_message", pid, ...)
  end

  function api.info(pid)
    if not threads[pid] then
      return nil, "thread not found"
    end
    local t = threads[pid]
    return {
      name = t.name,
      started = t.started,
      runtime = t.runtime
    }
  end

  function api.loop()
    api.loop = nil
    while #threads > 0 do
    end
    k.error("all threads died")
  end

  k.sched = api
end

--== IPC callbacks ==--

local ipc = {}

k.error("premature exit!")
