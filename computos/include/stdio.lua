-- standard I/O facilities --

local thd = include("thread")

local api = {}

function api.fopen(file, mode)
  checkArg(1, file, "string")
  checkArg(2, mode, "string", "nil")
  local drv_pid = thd.find("fsdrv")
  if not drv_pid then
    return nil, "filesystem driver thread not found"
  end
  send(drv_pid, "open", file)
  local resp
  repeat
    resp = wait()
  until resp[2] == drv_pid
  return resp[3], resp[4] -- will be `nil, "file not found"` on failure, pid of handler thread on success
end

function api.fread(pid, amt)
  checkArg(1, pid, "number")
  checkArg(2, amt, "number")
  if not thd.info(pid) then
    return nil, "handler thread not found"
  end
  send(pid, "read", amt)
  local resp
  repeat
    resp = wait()
  until resp[2] == pid
  return resp[3], resp[4]
end

function api.fwrite(pid, dat)
  checkArg(1, pid, "number")
  checkArg(2, dat, "string")
  if not thd.info(pid) then
    return nil, "handler thread not found"
  end
  send(pid, "write", dat)
  local resp
  repeat
    resp = wait()
  until resp[2] == pid
  return resp[3], resp[4]
end

function api.fclose(pid)
  checkArg(1, pid, "number")
  if not thd.info(pid) then
    return nil, "handler thread not found"
  end
  send(pid, "close")
  local resp
  repeat
    resp = wait()
  until resp[2] == pid
  return resp[3], resp[4]
end

function api.flist(dir)
  checkArg(1, dir, "string")
  local pid = thd.find("fsdrv")
  if not pid then
    return nil, "filesystem driver thread not found"
  end
  send(pid, "list", dir)
  local resp
  repeat
    resp = wait()
  until resp[2] == pid
  return table.unpack(resp, 3)
end

return api
