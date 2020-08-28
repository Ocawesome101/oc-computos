-- filesystem driver --

local thread = include("thread")

local ops = {}
local mnt = getState("mounts") or {}
setState("mounts", mnt)
local n = 0

local function segs(p)
  local ss = {}
  for s in p:gmatch("[^/]+") do
    ss[#ss + 1] = s
  end
  return ss
end

local function resolve(path)
  local seg = segs(path)
  if path == "/" then
    return mnt["/"]
  end
  for i=#seg, 1, -1 do
    local try = "/" .. table.concat(seg, "/", 1, i)
    local path = "/" .. table.concat(seg, "/", i + 1)
    if mnt[try] then
      return mnt[try], path
    end
  end
  return nil, "file not found"
end

function ops.open(f)
  local node, path = resolve(f)
  if not node then
    return nil, path
  end
  if not node.exists(path) then
    return nil, "file not found"
  end
  if node.isDirectory(path) then
    return nil, "cannot open a directory"
  end
  local fd = node.open(path, mode)
  -- TODO: possibly only allow the opening thread to do file ops?
  local function chld()
    while true do
      local sig = wait()
      local _, from, op, arg = table.unpack(sig)
      include("syslog").log("fd: call to", op)
      if op == "read" then
        local ok, data = pcall(node.read, fd, arg)
        send(from, ok and data or nil, data)
      elseif op == "write" then
        local ok, err = pcall(node.write, fd, arg)
        send(from, ok == false and nil or true, err)
      elseif op == "close" then
        pcall(node.close, fd)
        send(from, true)
        error("file descriptor closed")
      end
    end
  end
  local pid = spawn(chld, "hnd"..n)
  n = n + 1
  return pid
end

local function mount(ca)
  local prx = component.proxy(ca)
  mnt["/mnt/"..ca] = prx
end

local function unmount(ca)
  mnt["/mnt/"..ca] = nil
end

while true do
  local signal = sigwait()
  local sig, a1, a2, a3, a4 = table.unpack(signal)
  if sig == "component_removed" and a1 == "filesystem" then
    unmount(a2)
  elseif sig == "component_added" and a1 == "filesystem" then
    mount(a2)
  elseif sig == "ipc_message" then
    include("syslog").log("fsdrv: call to " .. a2)
    if ops[a2] then
      send(a1, ops[a2]())
    end
  end
end
