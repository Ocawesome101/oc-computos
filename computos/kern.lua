--==-- ComputOS kernel --==--

--== core kernel routines ==--
k = {}
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
      msg = string.format("[%.2f] %s", computer.uptime(), msg)
      gpu.set(1, y, msg)
    end
    function k.log(...)
      local msg = table.concat(table.pack(...), " ")
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

k.log("core kernel routines")
-- read file contents
do
  local bfs = component.proxy(computer.getBootAddress())
  k.bfs = bfs

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
k.log("scheduler")
do
  local threads = {}
  local api = {}
  local pid = 0
  local current = 0

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

  function api.find(name)
    for i, t in pairs(threads) do
      if t.name == name then
        return i
      end
    end
    return nil, "thread not found"
  end

  function api.message(pid, ...)
    -- ipc_message(to, from, ...)
    computer.pushSignal("ipc_message", pid, current, ...)
  end

  function api.current()
    return current
  end

  function api.info(pid)
    pid = pid or current
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
      local sig = table.pack(computer.pullSignal())
      if sig[1] == "ipc_message" then
        local to = table.remove(sig, 2)
        if threads[to] then
          local t = threads[to]
          local start = computer.uptime()
          local ok, ret = coroutine.resume(t.coro, table.unpack(sig))
          t.runtime = t.runtime + (computer.uptime() - start)
          if (not ok and ret) or coroutine.status(t.coro) == "dead" then
            threads[to] = nil
          end
        end
      else
        for i, t in pairs(threads) do
          current = i
          local start = computer.uptime()
          local ok, ret = coroutine.resume(t.coro, table.unpack(sig))
          k.log(tostring(ok), tostring(ret))
          t.runtime = t.runtime + (computer.uptime() - start)
          if (not ok and ret) or coroutine.status(t.coro) == "dead" then
            if not ok and ret then
              k.log("thread died - " .. t.name .. ": " .. ret)
            else
              k.log("thread died - " .. t.name)
            end
            threads[i] = nil
          end
        end
      end
    end
    k.error("all threads died")
  end

  k.sched = api
end

--== sandboxing ==--
k.log("table.copy")
function table.copy(tbl)
  local seen = {}
  local function copy(t, to)
    to = to or {}
    for k, v in pairs(t) do
      if type(v) == "table" then
        if not seen[v] then
          seen[v] = {}
          to[k] = seen[v]
          copy(v, seen[v])
        end
      else
        to[k] = v
      end
    end
    return to
  end
  return copy(tbl)
end

function loadfile(file, mode, env)
  checkArg(1, file, "string")
  checkArg(2, mode, "string", "nil")
  checkArg(3, env, "table", "nil")
  local data, err = k.readfile(file)
  if not data then
    return nil, err
  end
  return load(data, "="..file, mode, env or _G)
end

k.log("loading init")
--== spawn init thread ==--
local ok, err = loadfile("/computos/init.lua")
if not ok then
  k.error(err)
end

k.sched.new(ok, "[init]")
computer.pushSignal("init")
k.sched.loop()
k.error("premature exit!")
