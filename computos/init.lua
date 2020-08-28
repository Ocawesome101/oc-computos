--==-- ComputOS init --==--

local _IVERSION = "cInit 0.1.0"

k.log("init started:", _IVERSION)

-- driver sandbox: allow component, computer; disallow k
local drv_sb = table.copy(_G)
drv_sb.k = nil

k.log("driver sandbox created")

function send(pid, ...)
  checkArg(1, pid, "number")
  local ok, err = k.sched.message(pid, ...)
  if not ok then
    return nil, err
  end
  return true
end

-- wait for a signal
function sigwait(filter)
  checkArg(1, filter, "string", "nil")
  local sig
  repeat
    sig = table.pack(coroutine.yield())
  until (filter and sig[1] == filter) or ((not filter) and sig.n > 0)
  return sig
end

-- sigwait defaulting to ipc_message
function wait(filter)
  checkArg(1, filter, "string", "nil")
  filter = filter or "ipc_message"
  return sigwait(filter)
end

drv_sb.send = send
drv_sb.wait = wait
drv_sb.sigwait = sigwait
k.log("IPC calls created")

local user_sb = table.copy(_G)

-- user program sandbox: disallow computer, component, k; access some things through include()
user_sb._OSVERSION  = k._VERSION
user_sb.component   = nil
user_sb.computer    = nil
user_sb._VERSION    = _VERSION
user_sb.k           = nil

k.log("userspace sandbox created")

local inccache = {
  thread = {
    find = k.sched.find,
    info = k.sched.info
  },
  syslog = {
    log = k.log
  }
}

local incdir = "/computos/include/"

local function include(thing)
  checkArg(1, thing, "string")
  if inccache[thing] then
    return inccache[thing]
  end
  local call = assert(loadfile(string.format("%s/%s.lua", incdir, thing), "bt", drv_sb))
  local ok, ret = assert(pcall(call))
  inccache[thing] = ret
  return ret
end

-- driver state saving - if a driver crashes, it can reload its state
local state = {}
function drv_sb.setState(k, v)
  checkArg(1, k, "string")
  local dn = include("thread").info().name
  state[dn] = state[dn] or {}
  state[dn][k] = v
end
function drv_sb.getState(k)
  checkArg(1, k, "string")
  local dn = include("thread").info().name
  state[dn] = state[dn] or {}
  return state[dn][k] or nil
end
k.log("driver state saving implemented")

function spawn(func, name)
  checkArg(1, func, "function")
  checkArg(2, name, "string", "nil")
  name = name or k.sched.info().name .. "0"
  return k.sched.new(func, name)
end

drv_sb.spawn = spawn
drv_sb.include = include
user_sb.spawn = spawn
user_sb.include = include

k.log("include system created")

-- fallback filesystem component
local fbfs = k.bfs
-- fallback readfile
local fbrf = k.readfile

function k.readfile(file)
  if not inccache.stdio then -- prevent loops!
    return fbrf(file)
  end
  local stdio = include("stdio")
  local fd = stdio.fopen(file, "r")
  if not fd then
    return fbrf(file)
  end
  local data = ""
  repeat
    local c = stdio.fread(fd, math.huge)
    data = data .. (c or "")
  until not data
  stdio.fclose(fd)
  return data
end

user_sb.loadfile = function(f,m,e) return loadfile(f,m,e or user_sb) end
drv_sb.loadfile = function(f,m,e) return loadfile(f,m,e or drv_sb) end

local function start_drivers()
  local stdio = include("stdio")
  local files = stdio.flist("/computos/drivers/")
  files = files or fbfs.list("/computos/drivers")
  if not files then
    k.log("failed starting drivers: no drivers")
    return
  end
  files.n = nil
  for i, file in pairs(files) do
    local dn = file:match("(.+)%.lua$")
    if k.sched.find(dn) then -- driver already running!
      k.log("drv already running:", dn)
      goto cont
    end
    local ok, err = loadfile("/computos/drivers/"..file, "bt", drv_sb)
    if ok then
      k.log("starting driver:", dn)
      k.sched.new(ok, dn)
    else
      k.log("failed starting driver", file .. ":", err)
    end
    ::cont::
  end
end

k.log("free:", computer.freeMemory() // 1024, "k")
while true do start_drivers() coroutine.yield() end
