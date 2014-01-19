--[[
	TODO
	HTTP api may be broken?
	including file handles.
]]
-- HELPER FUNCTIONS
local function lines(str)
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
	helper((str:gsub("(.-)\r?\n", helper)))
	if t[#t] == "" then t[#t] = nil end
	return t
end

-- HELPER CLASSES/HANDLES
-- TODO Make more efficient, use love.filesystem.lines
local HTTPHandle
if _conf.enableAPI_http == true then
	function HTTPHandle(contents, status)
		local closed = false
		local lineIndex = 1
		local handle
		handle = {
			close = function()
				closed = true
			end,
			readLine = function()
				if closed then return end
				local str = contents[lineIndex]
				lineIndex = lineIndex + 1
				return str
			end,
			readAll = function()
				if closed then return end
				if lineIndex == 1 then
					lineIndex = #contents + 1
					return table.concat(contents, '\n')
				else
					local tData = {}
					local data = handle.readLine()
					while data ~= nil do
						table.insert(tData, data)
						data = handle.readLine()
					end
					return table.concat(tData, '\n')
				end
			end,
			getResponseCode = function()
				return status
			end
		}
		return handle
	end
end

local function FileReadHandle(path)
	local contents = {}
	for line in vfs.lines(path) do
		table.insert(contents, line)
	end
	local closed = false
	local lineIndex = 1
	local handle
	handle = {
		close = function()
			closed = true
		end,
		readLine = function()
			if closed then return end
			local str = contents[lineIndex]
			lineIndex = lineIndex + 1
			return str
		end,
		readAll = function()
			if closed then return end
			if lineIndex == 1 then
				lineIndex = #contents + 1
				return table.concat(contents, '\n')
			else
				local tData = {}
				local data = handle.readLine()
				while data ~= nil do
					table.insert(tData, data)
					data = handle.readLine()
				end
				return table.concat(tData, '\n')
			end
		end
	}
	return handle
end

local function FileBinaryReadHandle(path)
	local closed = false
	local File = vfs.newFile(path, "r")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		read = function()
			if closed or File:eof() then return end
			return string.byte(File:read(1))
		end
	}
	return handle
end

local function FileWriteHandle(path, append)
	local closed = false
	local File = vfs.newFile(path, append and "a" or "w")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		writeLine = function(data)
			if closed then error("Stream closed",2) end
			File:write(data .. (_conf.useCRLF == true and "\r\n" or "\n"))
		end,
		write = function(data)
			if closed then error("Stream closed",2) end
			File:write(data)
		end,
		flush = function()
			if File.flush then
				File:flush()
			else
				File:close()
				File = vfs.newFile(path, "a")
			end
		end
	}
	return handle
end

local function FileBinaryWriteHandle(path, append)
	local closed = false
	local File = vfs.newFile(path, append and "a" or "w")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		write = function(data)
			if closed then return end
			if type(data) ~= "number" then return end
			File:write(string.char(math.max(math.min(data,255),0)))
		end,
		flush = function()
			if File.flush then
				File:flush()
			else
				File:close()
				File = vfs.newFile(path, "a")
			end
		end
	}
	return handle
end

-- Needed for term.write
-- This serialzier is bad, it is supposed to be bad. Don't use it.
local function serializeImpl(t, tTracking)	
	local sType = type(t)
	if sType == "table" then
		if tTracking[t] ~= nil then
			return nil
		end
		tTracking[t] = true
		
		local result = "{"
		for k,v in pairs(t) do
			local cache1 = serializeImpl(k, tTracking)
			local cache2 = serializeImpl(v, tTracking)
			if cache1 ~= nil and cache2 ~= nil then
				result = result..cache1.."="..cache2..", "
			end
		end
		if result:sub(-2,-1) == ", " then result = result:sub(1,-3) end
		result = result.."}"
		return result
	elseif sType == "string" then
		return t
	elseif sType == "number" then
		if t == math.huge then
			return "Infinity"
		elseif t == -math.huge then
			return "-Infinity"
		else
			return tostring(t):gsub("^[^e.]+%f[^0-9.]","%1.0"):gsub("e%+","e"):upper()
		end
	elseif sType == "boolean" then
		return tostring(t)
	else
		return nil
	end
end

local function serialize(t)
	local tTracking = {}
	return serializeImpl(t, tTracking) or ""
end

api = {}
if _conf.compat_loadstringMask == true then
	function api.loadstring(str, source)
		source = source or "string"
		if type(str) ~= "string" and type(str) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
		if type(source) ~= "string" and type(source) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
		source = tostring(source)
		local file = love.filesystem.newFile(source,"w")
		file:write(str)
		file:close()
		local stat, f, err = pcall(function() return love.filesystem.load(source) end)
		love.filesystem.remove(source)
		if not stat then
			-- Fall back to old method.
			local f, err = loadstring(str, source)
			if f then
				setfenv(f, api.env)
			end
			return f, err
		end
		if f then
			setfenv(f, api.env)
		end
		return f, err
	end
else
	function api.loadstring(str, source)
		source = source or "string"
		if type(str) ~= "string" and type(str) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
		if type(source) ~= "string" and type(source) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
		local f, err = loadstring(str, source)
		if f then
			setfenv(f, api.env)
		end
		return f, err
	end
end

api.term = {}
function api.term.clear()
	for y = 1, Screen.height do
		for x = 1, Screen.width do
			Screen.textB[y][x] = " "
			Screen.backgroundColourB[y][x] = api.comp.bg
			Screen.textColourB[y][x] = 1 -- Don't need to bother setting text color
		end
	end
	Screen.dirty = true
end
function api.term.clearLine()
	for x = 1, Screen.width do
		Screen.textB[api.comp.cursorY][x] = " "
		Screen.backgroundColourB[api.comp.cursorY][x] = api.comp.bg
		Screen.textColourB[api.comp.cursorY][x] = 1 -- Don't need to bother setting text color
	end
	Screen.dirty = true
end
function api.term.getSize()
	return Screen.width, Screen.height
end
function api.term.getCursorPos()
	return api.comp.cursorX, api.comp.cursorY
end
function api.term.setCursorPos(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then error("Expected number, number",2) end
	api.comp.cursorX = math.floor(x)
	api.comp.cursorY = math.floor(y)
	Screen.dirty = true
end
function api.term.write(text)
	text = serialize(text)
	if api.comp.cursorY > Screen.height
		or api.comp.cursorY < 1 then return end

	for i = 1, #text do
		local char = string.sub(text, i, i)
		if api.comp.cursorX + i - 1 <= Screen.width
			and api.comp.cursorX + i - 1 >= 1 then
			Screen.textB[api.comp.cursorY][api.comp.cursorX + i - 1] = char
			Screen.textColourB[api.comp.cursorY][api.comp.cursorX + i - 1] = api.comp.fg
			Screen.backgroundColourB[api.comp.cursorY][api.comp.cursorX + i - 1] = api.comp.bg
		end
	end
	api.comp.cursorX = api.comp.cursorX + #text
	Screen.dirty = true
end
function api.term.setTextColor(num)
	if type(num) ~= "number" then error("Expected number",2) end
	if num < 1 or num >= 65536 then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	api.comp.fg = num
	Screen.dirty = true
end
function api.term.setBackgroundColor(num)
	if type(num) ~= "number" then error("Expected number",2) end
	if num < 1 or num >= 65536 then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	api.comp.bg = num
end
function api.term.isColor()
	return true
end
function api.term.setCursorBlink(bool)
	if type(bool) ~= "boolean" then error("Expected boolean",2) end
	api.comp.blink = bool
	Screen.dirty = true
end
function api.term.scroll(n)
	if type(n) ~= "number" then error("Expected number",2) end
	local textBuffer = {}
	local backgroundColourBuffer = {}
	local textColourBuffer = {}
	for y = 1, Screen.height do
		if y - n > 0 and y - n <= Screen.height then
			textBuffer[y - n] = {}
			backgroundColourBuffer[y - n] = {}
			textColourBuffer[y - n] = {}
			for x = 1, Screen.width do
				textBuffer[y - n][x] = Screen.textB[y][x]
				backgroundColourBuffer[y - n][x] = Screen.backgroundColourB[y][x]
				textColourBuffer[y - n][x] = Screen.textColourB[y][x]
			end
		end
	end
	for y = 1, Screen.height do
		if textBuffer[y] ~= nil then
			for x = 1, Screen.width do
				Screen.textB[y][x] = textBuffer[y][x]
				Screen.backgroundColourB[y][x] = backgroundColourBuffer[y][x]
				Screen.textColourB[y][x] = textColourBuffer[y][x]
			end
		else
			for x = 1, Screen.width do
				Screen.textB[y][x] = " "
				Screen.backgroundColourB[y][x] = api.comp.bg
				Screen.textColourB[y][x] = 1 -- Don't need to bother setting text color
			end
		end
	end
	Screen.dirty = true
end

function tablecopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        copy = orig
    end
    return copy
end

api.cclite = {}
api.cclite.peripherals = {}
if _conf.enableAPI_cclite == true then
	function api.cclite.peripheralAttach(sSide, sType)
		if type(sSide) ~= "string" or type(sType) ~= "string" then
			error("Expected string, string",2)
		end
		if not peripheral[sType] then
			error("No virtual peripheral of type " .. sType,2)
		end
		if api.cclite.peripherals[sSide] then
			error("Peripheral already attached to " .. sSide,2)
		end
		api.cclite.peripherals[sSide] = peripheral[sType](sSide)
		if api.cclite.peripherals[sSide] ~= nil then
			table.insert(Emulator.eventQueue, {"peripheral",sSide})
		else
			error("No peripheral added",2)
		end
	end
	function api.cclite.peripheralDetach(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if not api.cclite.peripherals[sSide] then
			error("No peripheral attached to " .. sSide,2)
		end
		api.cclite.peripherals[sSide] = nil
		table.insert(Emulator.eventQueue, {"peripheral_detach",sSide})
	end
	function api.cclite.call(sSide, sMethod, ...)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if type(sMethod) ~= "string" then error("Expected string, string",2) end
		if not api.cclite.peripherals[sSide] then error("No peripheral attached",2) end
		return api.cclite.peripherals[sSide].ccliteCall(sMethod, ...)
	end
end

if _conf.enableAPI_http == true then
	api.http = {}
	function api.http.request(sUrl, sParams)
		if type(sUrl) ~= "string" then
			error("String expected" .. (sUrl == nil and ", got nil" or ""),2)
		end
		local http = HttpRequest.new()
		local method = sParams and "POST" or "GET"

		http.open(method, sUrl, true)

		if method == "POST" then
			http.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			http.setRequestHeader("Content-Length", string.len(sParams))
		end

		http.onReadyStateChange = function()
			if http.status == 200 then
				local handle = HTTPHandle(lines(http.responseText), http.status)
				table.insert(Emulator.eventQueue, { "http_success", sUrl, handle })
			else
				 table.insert(Emulator.eventQueue, { "http_failure", sUrl })
			end
		end

		http.send(sParams)
	end
end

api.os = {}
function api.os.clock()
	return math.floor(os.clock()*20)/20
end
function api.os.time()
	return math.floor((os.clock()*0.02)%24*1000)/1000
end
function api.os.day()
	return math.floor(os.clock()*0.2/60)
end
function api.os.setComputerLabel(label)
	if type(label) ~= "string" and type(label) ~= "nil" then error("Expected string or nil",2) end
	api.comp.label = label
end
function api.os.getComputerLabel()
	return api.comp.label
end
function api.os.queueEvent(...)
	local event = { ... }
	if type(event[1]) ~= "string" then error("Expected string",2) end
	table.insert(Emulator.eventQueue, event)
end
function api.os.startTimer(nTimeout)
	if type(nTimeout) ~= "number" then error("Expected number",2) end
	nTimeout = math.ceil(nTimeout*20)/20
	if nTimeout < 0.05 then nTimeout = 0.05 end
	local timer = {
		expires = love.timer.getTime() + nTimeout,
	}
	table.insert(Emulator.actions.timers, timer)
	for k, v in pairs(Emulator.actions.timers) do
		if v == timer then return k end
	end
	return nil -- Error
end
function api.os.setAlarm(nTime)
	if type(nTime) ~= "number" then error("Expected number",2) end
	if nTime < 0 or nTime > 24 then
		error("Number out of range: " .. tostring(nTime))
	end
	local alarm = {
		time = nTime,
	}
	table.insert(Emulator.actions.alarms, alarm)
	for k, v in pairs(Emulator.actions.alarms) do
		if v == alarm then return k end
	end
	return nil -- Error
end
function api.os.shutdown()
	Emulator:stop()
end
function api.os.reboot()
	Emulator:stop(true) -- Reboots on next update/tick
end

api.peripheral = {}
function api.peripheral.isPresent(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	return api.cclite.peripherals[sSide] ~= nil
end
function api.peripheral.getType(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if api.cclite.peripherals[sSide] then return api.cclite.peripherals[sSide].getType() end
	return
end
function api.peripheral.getMethods(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if api.cclite.peripherals[sSide] then return api.cclite.peripherals[sSide].getMethods() end
	return
end
function api.peripheral.call(sSide, sMethod, ...)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if type(sMethod) ~= "string" then error("Expected string, string",2) end
	if not api.cclite.peripherals[sSide] then error("No peripheral attached",2) end
	return api.cclite.peripherals[sSide].call(sMethod, ...)
end
function api.peripheral.getNames()
	local names = {}
	for k,v in pairs(api.cclite.peripherals) do
		table.insert(names,k)
	end
	return names
end

api.fs = {}
function api.fs.combine(basePath, localPath)
	if type(basePath) ~= "string" or type(localPath) ~= "string" then
		error("Expected string, string",2)
	end
	local path = "/" .. basePath .. "/" .. localPath
	local tPath = {}
	for part in path:gmatch("[^/]+") do
   		if part ~= "" and part ~= "." then
   			if part == ".." and #tPath > 0 then
   				table.remove(tPath)
   			else
   				table.insert(tPath, part)
   			end
   		end
	end
	return table.concat(tPath, "/")
end

function api.fs.open(path, mode)
	if type(path) ~= "string" or type(mode) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if mode == "r" then
		return FileReadHandle(path)
	elseif mode == "rb" then
		return FileBinaryReadHandle(path)
	elseif mode == "w" or mode == "a" then
		return FileWriteHandle(path,mode == "a")
	elseif mode == "wb" or mode == "ab" then
		return FileBinaryWriteHandle(path,mode == "ab")
	else
		error("Unsupported mode",2)
	end
end
function api.fs.list(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	return vfs.getDirectoryItems(path)
end
function api.fs.exists(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = vfs.normalize(path)
	return vfs.exists(path)
end
function api.fs.isDir(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = vfs.normalize(path)
	return vfs.isDirectory(path)
end
function api.fs.isReadOnly(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	path = vfs.normalize(path)
	return path == "/rom" or string.sub(path, 1, 5) == "/rom/"
end
function api.fs.getName(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local fpath, name, ext = string.match(path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
	return name
end
function api.fs.getSize(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if vfs.exists(path) ~= true then
		error("No such file",2)
	end

	if vfs.isDirectory(path) then
		return 512
	end
	
	local size = vfs.getSize(path)
	if size == 0 then size = 512 end
	return math.ceil(size/512)*512
end

function api.fs.getFreeSpace(path)
	return math.huge
end

function api.fs.makeDir(path) -- All write functions are within data/
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if path == "/rom" or string.sub(path, 1, 5) == "/rom/" then
		error("Access Denied",2)
	end
	return vfs.createDirectory(path)
end

local function deltree(sFolder)
	local tObjects = vfs.getDirectoryItems(sFolder)

	if tObjects then
   		for _, sObject in pairs(tObjects) do
	   		local pObject =  sFolder.."/"..sObject

			if vfs.isDirectory(pObject) then
				deltree(pObject)
			end
			vfs.remove(pObject)
		end
	end
	return vfs.remove(sFolder)
end

local function copytree(sFolder, sToFolder)
	if not vfs.isDirectory(sFolder) then
		vfs.write(sToFolder, vfs.read(sFolder))
		return
	end
	vfs.createDirectory(sToFolder)
	local tObjects = vfs.getDirectoryItems(sFolder)

	if tObjects then
   		for _, sObject in pairs(tObjects) do
	   		local pObject =  sFolder.."/"..sObject
			local pToObject = sToFolder.."/"..sObject

			if vfs.isDirectory(pObject) then
				vfs.createDirectory(pToObject)
				copytree(pObject,pToObject)
			else
				vfs.write(pToObject, vfs.read(pObject))
			end
		end
	end
end

function api.fs.move(fromPath, toPath)
	if type(fromPath) ~= "string" or type(toPath) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = vfs.normalize(fromPath)
	toPath = vfs.normalize(toPath)
	if vfs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if vfs.exists(toPath) == true then
		error("File exists",2)
	end
	if fromPath == "/rom" or string.sub(fromPath, 1, 5) == "/rom/" or 
		toPath == "/rom" or string.sub(toPath, 1, 5) == "/rom/" then
		error("Access Deined",2)
	end
	copytree(fromPath, toPath)
	deltree(fromPath)
end

function api.fs.copy(fromPath, toPath)
	if type(fromPath) ~= "string" or type(toPath) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = vfs.normalize(fromPath)
	toPath = vfs.normalize(toPath)
	if vfs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if vfs.exists(toPath) == true then
		error("File exists",2)
	end
	if toPath == "/rom" or string.sub(toPath, 1, 5) == "/rom/" then
		error("Access Deined",2)
	end
	copytree(fromPath, toPath)
end

function api.fs.delete(path)
	if type(path) ~= "string" then error("Expected string",2) end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if path == "/rom" or string.sub(path, 1, 5) == "/rom/" then
		error("Access Deined",2)
	end
	deltree(path)
end

api.bit = {}
function api.bit.norm(val)
	while val < 0 do val = val + 4294967296 end
	return val
end
function api.bit.blshift(n, bits)
	return api.bit.norm(bit.lshift(n, bits))
end
function api.bit.brshift(n, bits)
	return api.bit.norm(bit.arshift(n, bits))
end
function api.bit.blogic_rshift(n, bits)
	return api.bit.norm(bit.rshift(n, bits))
end
function api.bit.bxor(m, n)
	return api.bit.norm(bit.bxor(m, n))
end
function api.bit.bor(m, n)
	return api.bit.norm(bit.bor(m, n))
end
function api.bit.band(m, n)
	return api.bit.norm(bit.band(m, n))
end
function api.bit.bnot(n)
	return api.bit.norm(bit.bnot(n))
end

function api.init() -- Called after this file is loaded! Important. Else api.x is not defined
	api.comp = {
		cursorX = 1,
		cursorY = 1,
		bg = 32768,
		fg = 1,
		blink = false,
		label = nil,
	}
	api.env = {
		_VERSION = "Luaj-jse 2.0.3",
		tostring = tostring,
		tonumber = tonumber,
		unpack = unpack,
		getfenv = getfenv,
		setfenv = setfenv,
		rawequal = rawequal,
		rawset = rawset,
		rawget = rawget,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		next = next,
		type = type,
		select = select,
		assert = assert,
		error = error,
		ipairs = ipairs,
		pairs = pairs,
		pcall = pcall,
		loadstring = api.loadstring,
		math = tablecopy(math),
		string = tablecopy(string),
		table = tablecopy(table),
		coroutine = tablecopy(coroutine),

		-- CC apis (BIOS completes api.)
		term = {
			native = {
				clear = api.term.clear,
				clearLine = api.term.clearLine,
				getSize = api.term.getSize,
				getCursorPos = api.term.getCursorPos,
				setCursorPos = api.term.setCursorPos,
				setTextColor = api.term.setTextColor,
				setTextColour = api.term.setTextColor,
				setBackgroundColor = api.term.setBackgroundColor,
				setBackgroundColour = api.term.setBackgroundColor,
				setCursorBlink = api.term.setCursorBlink,
				scroll = api.term.scroll,
				write = api.term.write,
				isColor = api.term.isColor,
				isColour = api.term.isColor,
			},
			clear = api.term.clear,
			clearLine = api.term.clearLine,
			getSize = api.term.getSize,
			getCursorPos = api.term.getCursorPos,
			setCursorPos = api.term.setCursorPos,
			setTextColor = api.term.setTextColor,
			setTextColour = api.term.setTextColor,
			setBackgroundColor = api.term.setBackgroundColor,
			setBackgroundColour = api.term.setBackgroundColor,
			setCursorBlink = api.term.setCursorBlink,
			scroll = api.term.scroll,
			write = api.term.write,
			isColor = api.term.isColor,
			isColour = api.term.isColor,
		},
		fs = {
			open = api.fs.open,
			list = api.fs.list,
			exists = api.fs.exists,
			isDir = api.fs.isDir,
			isReadOnly = api.fs.isReadOnly,
			getName = api.fs.getName,
			getDrive = function(path) return nil end, -- Dummy function
			getSize = api.fs.getSize,
			getFreeSpace = api.fs.getFreeSpace,
			makeDir = api.fs.makeDir,
			move = api.fs.move,
			copy = api.fs.copy,
			delete = api.fs.delete,
			combine = api.fs.combine,
		},
		os = {
			clock = api.os.clock,
			getComputerID = function() return 0 end,
			computerID = function() return 0 end,
			setComputerLabel = api.os.setComputerLabel,
			getComputerLabel = api.os.getComputerLabel,
			computerLabel = api.os.getComputerLabel,
			queueEvent = api.os.queueEvent,
			startTimer = api.os.startTimer,
			setAlarm = api.os.setAlarm,
			time = api.os.time,
			day = api.os.day,
			shutdown = api.os.shutdown,
			reboot = api.os.reboot,
		},
		peripheral = {
			isPresent = api.peripheral.isPresent,
			getType = api.peripheral.getType,
			getMethods = api.peripheral.getMethods,
			call = api.peripheral.call,
			getNames = api.peripheral.getNames,
		},
		redstone = {
			getSides = function() return {"top","bottom","left","right","front","back"} end,
			getInput = function() end,
			getOutput = function() end,
			getBundledInput = function() end,
			getBundledOutput = function() end,
			getAnalogInput = function() end,
			getAnalogOutput = function() end,
			setOutput = function() end,
			setBundledOutput = function() end,
			setAnalogOutput = function() end,
			testBundledInput = function() end,
		},
		bit = {
			blshift = api.bit.blshift,
			brshift = api.bit.brshift,
			blogic_rshift = api.bit.blogic_rshift,
			bxor = api.bit.bxor,
			bor = api.bit.bor,
			band = api.bit.band,
			bnot = api.bit.bnot,
		},
	}
	if _conf.enableAPI_http == true then
		api.env.http = {
			request = api.http.request,
		}
	end
	if _conf.enableAPI_cclite == true then
		api.env.cclite = {
			peripheralAttach = api.cclite.peripheralAttach,
			peripheralDetach = api.cclite.peripheralDetach,
			call = api.cclite.call,
			log = print,
			traceback = debug.traceback,
		}
	end
	api.env.redstone.getAnalogueInput = api.env.redstone.getAnalogInput
	api.env.redstone.getAnalogueOutput = api.env.redstone.getAnalogOutput
	api.env.redstone.setAnalogueOutput = api.env.redstone.setAnalogOutput
	api.env.rs = api.env.redstone
	api.env.math.mod = nil
	api.env.string.gfind = nil
	api.env._G = api.env
end