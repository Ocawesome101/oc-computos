-- init --

local bootfs = component.proxy(computer.getBootAddress())

local fd = assert(bootfs.open("/computos/kern.lua", "r"))

local data = ""
repeat
  local c = bootfs.read(fd, math.huge)
  data = data .. (c or "")
until not c

bootfs.close(fd)

assert(load(data, "=[ComputOS Kernel]", "bt", _G))()
