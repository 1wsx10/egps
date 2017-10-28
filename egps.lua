-- This library provide high level turtle movement functions.
--
-- Before being able to use them, you should start the GPS with egps.startGPS()
--		then get your current location with egps.setLocationFromGPS().
-- egps.forward(), egps.back(), egps.up(), egps.down(), egps.turnLeft(), egps.turnRight()
--		replace the standard turtle functions.
-- If you need to use the standard functions, you
--		should call egps.setLocationFromGPS() again before using any egps functions.

-- Gist at: https://gist.github.com/SquidLord/4741746

-- The MIT License (MIT)

-- Copyright (c) 2012 Alexander Williams

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-------------------MODIFIED BY 1wsx10---------------------------
-- instructions:
-- 1. install it as an api
-- 2. look at comments above each function to see what they do
-- 3. write code
-- 4. complain about shit instructions
--
--
--
--
--
-- recently added: support for LAMA
-- exclusion zone file - turtle wont pathfind through an excluded block.
-- exclusions are similar to waypoints but instead of name it has index "x:y:z" and does not store direction
-- a_star has boolean "priority" - will ignore exclusion zone
----------------------------------------------------------------

-- Cache of the current turtle position and direction
local cachedX, cachedY, cachedZ, cachedDir

-- Directions
North, West, South, East, Up, Down = 0, 1, 2, 3, 4, 5
shortNames = {[North] = "N", [West] = "W", [South] = "S",
[East] = "E", [Up] = "U", [Down] = "D" }
deltas = {[North] = {0, 0, -1}, [West] = {-1, 0, 0}, [South] = {0, 0, 1},
[East] = {1, 0, 0}, [Up] = {0, 1, 0}, [Down] = {0, -1, 0}}
--north = -Z
--south = +Z
--west = -X
--east = +X


-- cache world geometry
cachedWorld = {}
-- cached wrld with block names
cachedWorldDetail = {}

-- waypoint locations
waypoints = {}

-- exclusion locations (will not pathfind through area)
exclusions = {}

dataDir = "/.egpsData"

-- A* parameters
local stopAt, nilCost = 1500, 1000

-- compatibility with LAMA
local isLama = false
if fs.isDir("/.lama") then
	isLama = true
	lama.overwrite() --replaces turtle.forward() etc. with lama.forward()
	print("lama detected, using lama movement...")
end


----------------------------------------
-- formatCoord
--
-- function: formats the coordinate to be used as a key for the tables
-- return: the coordinate string
-- return: nil if the coordinates are bad
--
-- format:
-- 		table["x:y:z"].time.day = integer
-- 		table["x:y:z"].time.time = float
--
function fmtCoord(x, y, z)
	if not x then return nil end
	if not y then return nil end
	if not z then return nil end
	return string.format("%d:%d:%d", x, y, z)
end

----------------------------------------
-- mergeTables
--
-- function: merges 2 tables based on the "time" value
-- return: the merged table, if there are conflicting blocks, the latest one is chosen
-- return: nil if the tables are the wrong format
--
-- format:
-- 		table["x:y:z"].time.day = integer
-- 		table["x:y:z"].time.time = float
--
function mergeTables(tableA, tableB)
	local newtable = tableB
	for k, v in pairs(tableA) do
		--wrong format
		if not v.time then return nil end
		if not newtable[k] then
			--newtable doesn't have a value, insert the value
			newtable[k] = v
		else
			if newtable[k].time.day > v.time.day then
				--newtable is later, do nothing
			elseif newtable[k].time.day < v.time.day then
				--tableA is later, replace the value
				newtable[k] = v
			else
				--the day is the same, check time
				if newtable[k].time.time > v.time.time then
					--newtable is later, do nothing
				else
					--tableA is later, replace the value
					newtable[k] = v
				end
			end
		end
	end
	return newtable
end

----------------------------------------
-- getBlock
--
-- function: tests to see if there is a block or space.
-- return: bool (true if there is a block)
-- return: nil if there is no information on the block
--

function getBlock(bX, bY, bZ)
	local idx_block = fmtCoord(bX, bY, bZ)
	return cachedWorld[idx_block]
end

----------------------------------------
-- getBlockDetail
--
-- function: tests to see if there is a block or space.
-- return: cachedWorldDetail on the block {turtle.inspect(), {os.time, os.day}}
-- return: nil if there is no information on the block
--

function getBlockDetail(bX, bY, bZ)
	local idx_block = fmtCoord(bX, bY, bZ)
	return cachedWorldDetail[idx_block]
end

----------------------------------------
-- drawMap()
--
-- function: draws a map of the current coordinates
-- input x, y, z
-- input optional: characters to replace the ones it uses to draw
--

function drawMap(ox, oy, oz, block, empty, floor, none)
	resx, resy = term.getSize()
	ox = ox - math.floor(resx/2)--west = negx
	oz = oz - math.floor(resy/2)--north = negz
	block = block or "@"
	empty = empty or " "
	floor = floor or "#"
	none = none or "'"
	--term.clear()
	for i=1, resy do
		for j=1, resx do
			term.setCursorPos(j, i)
			if getBlock(ox+j, oy, oz+i) == nil then
				--draw empty
				term.write(none)
			elseif getBlock(ox+j, oy, oz+i) then
				--draw block
				term.write(block)
			elseif getBlock(ox+j, oy-1, oz+i) == true then
				--draw floor
				term.write(floor)
			else
				term.write(empty)
			end
		end
	end
	drawTurtleOnMap(ox, oy, oz, cachedX, cachedY, cachedZ, cachedDir)
end

----------------------------------------
-- drawTurtleOnMap
--
-- function: for use with drawMap, draws a turtle on the map
-- input ox, oy, oz - x, y, z values used to draw the map
-- input x, y, z, d - location and direction of turtle
--

function drawTurtleOnMap(ox, oy, oz, x, y, z, d)
	local resx, resy = term.getSize()
	term.setCursorPos(math.floor(resx/2) + (x - ox), math.floor(resy/2) + (z - oz))
	if(d == 0) then
		term.write("^")--north
	elseif(d == 1) then
		term.write("<")--west
	elseif(d == 2) then
		term.write("v")--south
	elseif(d == 3) then
		term.write(">")
	else
		term.write("#")
	end
end

----------------------------------------
-- printWorld
--
-- function: for debugging, prints raw world data to screen
--

function printWorld()
	print(textutils.serialize(cachedWorld))
end

----------------------------------------
-- getCachedWorld
--
-- return: cached world as table
--

function getCachedWorld()
	return cachedWorld
end


----------------------------------------
-- worldSize
--
-- return: size of the world map (number of blocks)
--

function worldSize()--TODO: this does not work.. fix it
	local count = 0
	for k in pairs(cachedWorld) do
		count = count + 1
	end
	return count
end

----------------------------------------
-- delCache
--
-- function: remove ALL data from cache
-- input: boolean are you sure?
-- return: boolean "success"
--

function delCache(sure)
	if sure then
		cachedX, cachedY, cachedZ, cachedDir = nil, nil, nil, nil
		cachedWorld, waypoints, exclusions = {}, {}, {}
		print("all data deleted from cache")
		return true
	else
		return false
	end
end

----------------------------------------
--
--
--
--
--
--

function getFile(name)
	if fs.exists(dataDir.."/"..name) then
		local file = fs.open(dataDir.."/"..name,"r")
		local data = file.readAll()
		file.close()
		return data
	else
		print("file not found: "..name)
		return ""
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
----
---- textutils.serialize from the built-in APIs.. i just fixed a bug mentioned here: http://www.computercraft.info/forums2/index.php?/topic/11453-a-small-bug-with-textutilsserialize/
----

local g_tLuaKeywords = {
	[ "and" ] = true,
	[ "break" ] = true,
	[ "do" ] = true,
	[ "else" ] = true,
	[ "elseif" ] = true,
	[ "end" ] = true,
	[ "false" ] = true,
	[ "for" ] = true,
	[ "function" ] = true,
	[ "if" ] = true,
	[ "in" ] = true,
	[ "local" ] = true,
	[ "nil" ] = true,
	[ "not" ] = true,
	[ "or" ] = true,
	[ "repeat" ] = true,
	[ "return" ] = true,
	[ "then" ] = true,
	[ "true" ] = true,
	[ "until" ] = true,
	[ "while" ] = true,
}

local function serializeImpl( t, tTracking, sIndent )
	local sType = type(t)
	if sType == "table" then
		if tTracking[t] ~= nil then
			error( "Cannot serialize table with recursive entries", 0 )
		end
		tTracking[t] = true

		if next(t) == nil then
			-- Empty tables are simple
			return "{}"
		else
			-- Other tables take more work
			local sResult = "{\n"
			local sSubIndent = sIndent .. "	"
			local tSeen = {}
			for k,v in ipairs(t) do
				tSeen[k] = true
				sResult = sResult .. sSubIndent .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
			end
			for k,v in pairs(t) do
				if not tSeen[k] then
					local sEntry
					if type(k) == "string" and not g_tLuaKeywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
						sEntry = k .. " = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
					else
						sEntry = "[ " .. serializeImpl( k, tTracking, sSubIndent ) .. " ] = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
					end
					sResult = sResult .. sSubIndent .. sEntry
				end
			end
			sResult = sResult .. sIndent .. "}"
			tTracking[t] = nil
			return sResult
		end

	elseif sType == "string" then
		return string.format( "%q", t )

	elseif sType == "number" or sType == "boolean" or sType == "nil" then
		return tostring(t)

	else
		error( "Cannot serialize type "..sType, 0 )

	end
end

function serialize( t )
	local tTracking = {}
	return serializeImpl( t, tTracking, "" )
end
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

----------------------------------------
--
--
--
--
--
--

function setFile(name, data)
	if fs.isDir(dataDir.."") then
		local file = fs.open(dataDir.."/"..name,"w")
		file.write(serialize(data))
		file.close()
		return true
	else
		print("creating "..name.." file...")
		fs.makeDir(dataDir.."")
		return setFile(name, data)
	end
	print("a black hole happened")
	return false
end

function loadAll()
	load()
	loadDetail()
	loadWaypoints()
	loadExclusions()
end

function saveAll()
	save()
	saveDetail()
	saveWaypoints()
	saveExclusions()
end

----------------------------------------
-- load
--
-- function: load cachedWorld from a file
-- return: boolean "success"
--

function load()
	local data = getFile("blockData")
	if data ~= "" then
		cachedWorld = textutils.unserialize(data)
		if cachedWorld ~= nil then
			return true
		else
			-- print("could not read blockData file: \n"..data)
			cachedWorld = {}
			return false
		end
	else
		print("no world data")
		return false
	end
end

function loadFile(name)
	local data = getFile(name)
	if data ~= "" then
		return textutils.unserialize(data)
	else
		print("no data or file doesn't exist")
		return false
	end
end

----------------------------------------
-- save
--
-- function: save cachedWorld to a file
-- return: boolean "success"
--

function save()
	detectAll()
	setFile("blockData", cachedWorld)
end

----------------------------------------
-- loadDetail
--
-- function: load cachedWorlddetail from a file
-- return: boolean "success"
--

function loadDetail()
	local data = getFile("blockDataDetail")
	if data ~= {} then
		cachedWorldDetail = textutils.unserialize(data)
		if cachedWorldDetail ~= nil then
			return true
		else
			-- print("could not read blockDataDetail file: \n"..data)
			cachedWorldDetail = {}
			return false
		end
	else
		print("no detailed world data")
		saveDetail()
		return false
	end
end

----------------------------------------
-- saveDetail
--
-- function: save cachedWorldDetail to a file
-- return: boolean "success"
--

function saveDetail(name)
	name = name or "blockDataDetail"
	setFile(name, cachedWorldDetail)
end

----------------------------------------
-- loadWaypoints
--
-- function: load waypoints from the file
-- return: boolean "success"
--

function loadWaypoints()
	local data = getFile("waypoints")
	if data ~= {} then
		waypoints = textutils.unserialize(data)
		if waypoints ~= nil then
			return true
		else
			-- print("could not read waypoints file: \n"..data)
			waypoints = {}
			return false
		end
	else
		print("no waypoint data")
		return false
	end
end

----------------------------------------
-- saveWaypoints
--
-- function: save waypoints to a file
-- return: boolean "success"
--

function saveWaypoints()
	setFile("waypoints", waypoints)
end

----------------------------------------
-- setWaypoint
--
-- function: save a waypoint to cache
-- input: name of waypoint, coordinates
-- returns: boolean "success"
--

function setWaypoint(name, x, y, z, d)
	d = d or 0
	x = x or nil
	y = y or nil
	z = z or nil
	if x == nil and y == nil and z == nil then
		waypoints[name] = nil
		print("waypoint deleted")
		return true
	end
	waypoints[name] = {x, y, z, d}
	if waypoints[name] ~= nil then
		return true
	else
		return false
	end
end

----------------------------------------
-- getWaypoint
--
-- function: get a waypoint from cache
-- input: name of waypoint
-- returns: waypoint coordinates and direction
-- returns: false if its not found
--

function getWaypoint(name)
	local x, y, z, d
	if waypoints[name] ~= nil then
		x = waypoints[name][1]
		y = waypoints[name][2]
		z = waypoints[name][3]
		d = waypoints[name][4]
		return x, y, z, d
	else
		print("waypoint "..name.." not found")
		return nil, nil, nil, nil
	end
end

----------------------------------------
-- loadExclusions
--
-- function: load exclusions from the file
-- return: boolean "success"
--

function loadExclusions()
	local data = getFile("exclusions")
	if data ~= {} then
		exclusions = textutils.unserialize(data)
		if exclusions ~= nil then
			return true
		else
			print("could not read exclusions file: \n"..data)
			exclusions = {}
			return false
		end
	else
		print("no exclusion data")
		return false
	end
end

----------------------------------------
-- saveExclusions
--
-- function: save exclusions to a file
-- return: boolean "success"
--

function saveExclusions()
	setFile("exclusions", exclusions)
end

----------------------------------------
-- setExclusion
--
-- function: save an exclusion to cache
-- input: exclusions coordinates
-- returns: boolean "success"
--

function setExclusion(idx, y, z)
	if y == nil and z == nil then
		local x = tonumber(string.match(idx, "(.*):"))
		y = tonumber(string.match(idx, ":(.*):"))
		z = tonumber(string.match(idx, ":(.*)"))
	else
		local x = idx
		idx = fmtCoord(x, y, z)
	end
	d = d or 0
	exclusions[idx] = {x, y, z}
	if exclusions[idx] ~= nil then
		return true
	else
		return false
	end
end

----------------------------------------
-- excludeZone
--
-- function: exclude a cuboid
-- input: 2 opposite corners (x, y, z, x2, y2, z2)
-- option: boolean to include the zone
--

function excludeZone(x, y, z, x2, y2, z2, include)
	local temp, temp2
	temp, temp2 = x, x2
	x = math.min(temp, temp2)
	x2 = math.max(temp, temp2)
	temp, temp2 = y, y2
	y = math.min(temp, temp2)
	y2 = math.max(temp, temp2)
	temp, temp2 = z, z2
	z = math.min(temp, temp2)
	z2 = math.max(temp, temp2)

	for i = x, x2 do
		for j = y, y2 do
			for k = z, z2 do
				if include then
					delExclusion(i, j, k)
				else
					setExclusion(i, j, k)
				end
			end
		end
	end
end

----------------------------------------
-- getExclusion
--
-- function: get an exclusion from cache
-- input: index of exclusion: "x:y:z"
-- returns: exclusion coordinates (or nil, nil, nil)
--

function getExclusion(idx, y, z)
	if y == nil and z == nil then
		local x = tonumber(string.match(idx, "(.*):"))
		y = tonumber(string.match(idx, ":(.*):"))
		z = tonumber(string.match(idx, ":(.*)"))
	else
		local x = idx
		idx = fmtCoord(x, y, z)
	end
	if exclusions[idx] ~= nil then
		x = exclusions[idx][1]
		y = exclusions[idx][2]
		z = exclusions[idx][3]
		return x, y, z
	else
		print("exclusion "..idx.." not found")
		return nil, nil, nil
	end
end

----------------------------------------
-- delExclusion
--
-- function: remove an exclusion from cache
-- input: index of exclusion: "x:y:z" OR x, y, z
-- returns: boolean "success"
--

function delExclusion(idx, y, z)
	if y == nil and z == nil then
		local x = tonumber(string.match(idx, "(.*):"))
		y = tonumber(string.match(idx, ":(.*):"))
		z = tonumber(string.match(idx, ":(.*)"))
	else
		local x = idx
		idx = fmtCoord(x, y, z)
	end
	exclusions[idx] = nil
	print("exclusion deleted")
	return true
end

----------------------------------------
-- empty
--
-- funtion: test if the cachedWorld is empty
-- return: boolean cachedWorld is empty
--

function empty(table)
	table = table or cachedWorld
	for _, value in pairs(table) do
		if value ~= nil then
			return false
		end
	end
	return true
end

----------------------------------------
-- detectAll
--
-- function: Detect up, forward, down and writes it to cachedWorld
--

function detectAll()
	local F, U, D = deltas[cachedDir], deltas[Up], deltas[Down]
	local block

	local time = {}
	time.day = os.day()
	time.time = os.time()

	cachedWorld[fmtCoord(cachedX, cachedY, cachedZ)] = 0
	if not cachedWorldDetail[fmtCoord(cachedX, cachedY, cachedZ)] then cachedWorldDetail[fmtCoord(cachedX, cachedY, cachedZ)] = {} end
	cachedWorldDetail[fmtCoord(cachedX, cachedY, cachedZ)].block = {false, "no block to inspect"}
	cachedWorldDetail[fmtCoord(cachedX, cachedY, cachedZ)].time = {time}

	block = 0
	if turtle.detect()			then block = 1 end
	cachedWorld[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))] = block
	if not cachedWorldDetail[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))] then cachedWorldDetail[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))] = {} end
	cachedWorldDetail[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))].block = {turtle.inspect()}
	cachedWorldDetail[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))].time = {time}

	block = 0
	if turtle.detectUp()		then block = 1 end
	cachedWorld[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))] = block
	if not cachedWorldDetail[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))] then cachedWorldDetail[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))] = {} end
	cachedWorldDetail[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))].block = {turtle.inspectUp()}
	cachedWorldDetail[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))].time = {time}

	block = 0
	if turtle.detectDown()	then block = 1 end
	cachedWorld[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))] = block
	if not cachedWorldDetail[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))] then cachedWorldDetail[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))] = {} end
	cachedWorldDetail[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))].block = {turtle.inspectDown()}
	cachedWorldDetail[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))].time = {time}
end

-- Legacy detectAll --------------only writes 0... fucking weird
--[[
function detectAll()
local F, U, D = deltas[cachedDir], deltas[Up], deltas[Down]

cachedWorld[fmtCoord(cachedX, cachedY, cachedZ)] = 0
if not turtle.detect()		 then cachedWorld[fmtCoord((cachedX + F[1]), (cachedY + F[2]), (cachedZ + F[3]))] = 0 end
if not turtle.detectUp()	 then cachedWorld[fmtCoord((cachedX + U[1]), (cachedY + U[2]), (cachedZ + U[3]))] = 0 end
if not turtle.detectDown() then cachedWorld[fmtCoord((cachedX + D[1]), (cachedY + D[2]), (cachedZ + D[3]))] = 0 end
end--]]

----------------------------------------
-- forward
--
-- function: Move the turtle forward if possible and put the result in cache
-- return: boolean "success"
--

function forward()
	if not cachedX then
		return turtle.forward()
	end
	local D = deltas[cachedDir]--if north, D = {0, 0, -1}
	local x, y, z = cachedX + D[1], cachedY + D[2], cachedZ + D[3]--adds corisponding delta to direction
	local idx_pos = fmtCoord(x, y, z)

	if turtle.forward() then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		cachedWorld[idx_pos] = (turtle.detect() and 1 or 0.5)
		return false
	end
end

----------------------------------------
-- ghost_forward
--
-- function: Pretend to move the turtle forward if possible and put the result in cache, do not actually move the turtle
-- return: boolean "success"
--

function ghost_forward()
	if not cachedX then
		return false
	end
	local D = deltas[cachedDir]--if north, D = {0, 0, -1}
	local x, y, z = cachedX + D[1], cachedY + D[2], cachedZ + D[3]--adds corisponding delta to direction
	local idx_pos = fmtCoord(x, y, z)

	if true then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		cachedWorld[idx_pos] = (turtle.detect() and 1 or 0.5)
		return false
	end
end

----------------------------------------
-- back
--
-- function: Move the turtle backward if possible and put the result in cache
-- return: boolean "success"
--

function back()
	if not cachedX then
		return turtle.back()
	end
	local D = deltas[cachedDir]
	local x, y, z = cachedX - D[1], cachedY - D[2], cachedZ - D[3]
	local idx_pos = fmtCoord(x, y, z)

	if turtle.back() then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		cachedWorld[idx_pos] = 0.5
		return false
	end
end

----------------------------------------
-- ghost_back
--
-- function: Pretend to move the turtle backward if possible and put the result in cache, do not actually move the turtle
-- return: boolean "success"
--

function ghost_back()
	if not cachedX then
		return false
	end
	local D = deltas[cachedDir]
	local x, y, z = cachedX - D[1], cachedY - D[2], cachedZ - D[3]
	local idx_pos = fmtCoord(x, y, z)

	if true then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		cachedWorld[idx_pos] = 0.5
		return false
	end
end

----------------------------------------
-- up
--
-- function: Move the turtle up if possible and put the result in cache
-- return: boolean "success"
--

function up()
	if not cachedX then
		return turtle.up()
	end
	local D = deltas[Up]
	local x, y, z = cachedX + D[1], cachedY + D[2], cachedZ + D[3]
	local idx_pos = fmtCoord(x, y, z)

	if turtle.up() then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		cachedWorld[idx_pos] = (turtle.detectUp() and 1 or 0.5)
		return false
	end
end

----------------------------------------
-- down
--
-- function: Move the turtle down if possible and put the result in cache
-- return: boolean "success"
--

function down()
	if not cachedX then
		return turtle.down()
	end
	local D = deltas[Down]
	local x, y, z = cachedX + D[1], cachedY + D[2], cachedZ + D[3]
	local idx_pos = fmtCoord(x, y, z)

	if turtle.down() then
		cachedX, cachedY, cachedZ = x, y, z
		detectAll()
		return true
	else
		detectAll()
		cachedWorld[idx_pos] = (turtle.detectDown() and 1 or 0.5)
		return false
	end
end

----------------------------------------
-- turnLeft
--
-- function: Turn the turtle to the left and put the result in cache
-- return: boolean "success"
--

function turnLeft()
	if not cachedX then
		return turtle.turnLeft()
	end
	cachedDir = (cachedDir + 1) % 4
	turtle.turnLeft()
	detectAll()
	return true
end

----------------------------------------
-- turnRight
--
-- function: Turn the turtle to the right and put the result in cache
-- return: boolean "success"
--

function turnRight()
	if not cachedX then
		return turtle.turnRight()
	end
	cachedDir = (cachedDir + 3) % 4
	turtle.turnRight()
	detectAll()
	return true
end

----------------------------------------
-- turnTo
--
-- function: Turn the turtle to the choosen direction and put the result in cache
-- input: number _targetDir
-- return: boolean "success"
--

function turnTo(_targetDir)
	if not cachedX then
		return false
	end
	--print(string.format("target dir: {0}\ncachedDir: {1}", _targetDir, cachedDir))
	if _targetDir == cachedDir then
		return true
	elseif ((_targetDir - cachedDir + 4) % 4) == 1 then--moveTo caused exception
		turnLeft()
	elseif ((cachedDir - _targetDir + 4) % 4) == 1 then
		turnRight()
	else
		turnLeft()
		turnLeft()
	end
	return true
end

----------------------------------------
-- clearWorld
--
-- function: Clear the world cache
--

function clearWorld()
	cachedWorld = {}
	detectAll()
end

----------------------------------------
-- compare_path_values
--
-- comparison function, used for sorting with the create_path method
--
-- function: return weather a should occur before b
--

local compare_path_values_order = {}
local compare_path_values_startpos = {}
local function compare_path_values(a, b)
	local first = compare_path_values_order[1].n
	local second = compare_path_values_order[2].n
	local third = compare_path_values_order[3].n

	local is_positive = compare_path_values_order[1].p
	local curr = first
	local nxt = second

	while a[curr] == b[curr] do
		if curr == first then
			is_positive = compare_path_values_order[2].p
			curr = second
			nxt = third
		elseif curr == second then
			is_positive = compare_path_values_order[3].p
			curr = third
			nxt = -1
		elseif curr == third then
			--they are the same coordinate, this should not happen but return anyway
			return true
		end
	end

	if curr == first then
		--print("comparing First! ".. curr .. " " .. a[curr] .. " " .. b[curr])
	elseif curr == second then
		--print("comparing Second! ".. curr .. " " .. a[curr] .. " " .. b[curr])
	elseif curr == third then
		--print("comparing Third! ".. curr .. " " .. a[curr] .. " " .. b[curr])
	else
		error("comparing broke")
	end

	return a[curr] < b[curr]
--[[
	if is_positive then
		if nxt == -1 or (a[nxt] - compare_path_values_startpos[nxt]) % 2 == 0 then
			return a[curr] < b[curr]
		else
			return a[curr] >= b[curr]
		end
	else
		if nxt == -1 or (a[nxt] - compare_path_values_startpos[nxt]) % 2 == 0 then
			return a[curr] >= b[curr]
		else
			return a[curr] < b[curr]
		end
	end]]--
end

----------------------------------------
-- createZone
--
-- function: create a cuboid
-- input: 2 opposite corners (x, y, z, x2, y2, z2)
-- option: boolean to include the zone
--

function createZone(x, y, z, x2, y2, z2)
	local temp, temp2

	temp, temp2 = x, x2
	x = math.min(temp, temp2)
	x2 = math.max(temp, temp2)
	temp, temp2 = y, y2
	y = math.min(temp, temp2)
	y2 = math.max(temp, temp2)
	temp, temp2 = z, z2
	z = math.min(temp, temp2)
	z2 = math.max(temp, temp2)

	local ret = {}
	ret[1] = {}
	ret[2] = {}

	ret[1].x = x
	ret[1].y = y
	ret[1].z = z
	ret[2].x = x2
	ret[2].y = y2
	ret[2].z = z2

	return ret
end

----------------------------------------
-- create_path
--
-- function: create a path to zig-zag through the area
-- zones: table of zones
--		-make a zone with createZone(x,y,z,x2,y2,z2)
-- order: the order with which to execute the moves, x,y,z or y,x,-z or z,y,x etc.
-- return: List of coordinates, to be used with egps.moveTo()
--
-- example, dig down in 2 different areas:
--	local zones = {}
--	zones[1] = egps.createZone(0,0,0, 3,5,3)
--	zones[2] = egps.createZone(6,4,9, 6,5,6)
--	local path = egps.create_path(zones, "x,z,-y")
--	for idx, coord in pairs(path) do
--		egps.moveTo(unpack(coord))
--		if v[4] == egps.Down then
--			turtle.digDown()
--		else
--			turtle.dig()
--		end
--	end
--

function create_path(zones, order)

	--setup order for sorting
	local set_order = function(table, pattern)
		local substring = string.match(order, pattern)
		local pos1, pos2 = string.find(substring, "\-")
		table.p = not pos1
		if table.p then
			table.v = substring
			-- print("("..table.v..") not neg, using this")
		else
			table.v = string.sub(substring, pos2+1)
			-- print("("..table.v..") finding substring in '"..substring.."' and getting char at "..pos2+1)
		end
	end

	--setup order
	local coordmap = {}
	compare_path_values_order[1] = {}
	set_order(compare_path_values_order[1], "^(.-),.-,.-$")
	compare_path_values_order[2] = {}
	set_order(compare_path_values_order[2], "^.-,(.-),.-$")
	compare_path_values_order[3] = {}
	set_order(compare_path_values_order[3], "^.-,.-,(.-)$")

	coordmap[compare_path_values_order[1].v] = 1
	coordmap[compare_path_values_order[2].v] = 2
	coordmap[compare_path_values_order[3].v] = 3

	compare_path_values_order[coordmap.x].n = 1
	compare_path_values_order[coordmap.y].n = 2
	compare_path_values_order[coordmap.z].n = 3

	--print("coordmap (x): "..compare_path_values_order[coordmap.x].v)
	--print("coordmap (y): "..compare_path_values_order[coordmap.y].v)
	--print("coordmap (z): "..compare_path_values_order[coordmap.z].v)

	-- print("order(1): "..compare_path_values_order[1].v.." "..compare_path_values_order[1].n)
	-- print("order(2): "..compare_path_values_order[2].v.." "..compare_path_values_order[2].n)
	-- print("order(3): "..compare_path_values_order[3].v.." "..compare_path_values_order[3].n)

	local is_x_positive
	local is_y_positive
	local is_z_positive

	is_x_positive = compare_path_values_order[coordmap.x].p
	is_y_positive = compare_path_values_order[coordmap.y].p
	is_z_positive = compare_path_values_order[coordmap.z].p

	--setup the path to be sorted
	local path = {}

	local count = 0
	for k, v in pairs(zones) do
		--add each coordinate to the path
		-- print(string.format("x:%d %d y:%d %d z:%d %d", v[1].x, v[2].x, v[1].y, v[2].y, v[1].z, v[2].z))
		for i = v[1].x, v[2].x do
			for j = v[1].y, v[2].y do
				for k = v[1].z, v[2].z do
					count = count + 1
					path[count] = {i, j, k, 0}
				end
			end
		end

		--setup startpos
		if k == 1 then
			compare_path_values_startpos[coordmap.x] = v[1].x
			compare_path_values_startpos[coordmap.y] = v[1].y
			compare_path_values_startpos[coordmap.z] = v[1].z
		end
		if is_x_positive then
			compare_path_values_startpos[coordmap.x] = math.min(compare_path_values_startpos[coordmap.x], v[1].x, v[2].x)
		else
			compare_path_values_startpos[coordmap.x] = math.max(compare_path_values_startpos[coordmap.x], v[1].x, v[2].x)
		end
		if is_y_positive then
			compare_path_values_startpos[coordmap.y] = math.min(compare_path_values_startpos[coordmap.y], v[1].y, v[2].y)
		else
			compare_path_values_startpos[coordmap.y] = math.max(compare_path_values_startpos[coordmap.y], v[1].y, v[2].y)
		end
		if is_z_positive then
			compare_path_values_startpos[coordmap.z] = math.min(compare_path_values_startpos[coordmap.z], v[1].z, v[2].z)
		else
			compare_path_values_startpos[coordmap.z] = math.max(compare_path_values_startpos[coordmap.z], v[1].z, v[2].z)
		end
	end

	-- print("startpos for x: "..compare_path_values_startpos[coordmap.x])
	-- print("startpos for y: "..compare_path_values_startpos[coordmap.y])
	-- print("startpos for z: "..compare_path_values_startpos[coordmap.z])

	--sort, using the table.sort function for lua
	--print("pos "..path[1][1].." "..path[1][2].." "..path[1][3])
	table.sort(path, compare_path_values)
	--print("pos "..path[1][1].." "..path[1][2].." "..path[1][3])

	--set direction TODO

	return path
end

----------------------------------------
-- heuristic_cost_estimate
--
-- function: A* heuristic
-- input: X, Y, Z of the 2 points
-- return: Manhattan distance between the 2 points
--

local function heuristic_cost_estimate(x1, y1, z1, x2, y2, z2)
	return math.abs(x2 - x1) + math.abs(y2 - y1) + math.abs(z2 - z1)
end

----------------------------------------
-- reconstruct_path
--
-- function: A* path reconstruction
-- input: A* visited nodes and goal
-- return: List of movement to be executed
--

local function reconstruct_path(_cameFrom, _currentNode)
	if _cameFrom[_currentNode] ~= nil then
		local dir, nextNode = _cameFrom[_currentNode][1], _cameFrom[_currentNode][2]
		local path = reconstruct_path(_cameFrom, nextNode)
		table.insert(path, dir)
		return path
	else
		return {}
	end
end

----------------------------------------
-- a_star
--
-- function: A* path finding
-- input: start and goal coordinates
-- return: List of movement to be executed
--

local function a_star(x1, y1, z1, x2, y2, z2, discover, priority)
	if not x1 or not y1 or not z1 then
		print(x1)
		print(y1)
		print(z1)
		error("a_star start coordinates nil")
	end
	if not x2 or not y2 or not z2 then
		print(x2)
		print(y2)
		print(z2)
		error("a_star end coordinates nil")
	end
	discover = discover or 1
	local start, idx_start = {x1, y1, z1}, fmtCoord(x1, y1, z1)
	local goal,	idx_goal	= {x2, y2, z2}, fmtCoord(x2, y2, z2)
	priority = priority or false

	if exclusions == nil then
		loadExclusions()
	end

	if exclusions[idx_goal] ~= nil and not priority then
		print("goal is in exclusion zone")
		return {}
	end

	if (cachedWorld[idx_goal] or 0) == 0 then
		local openset, closedset, cameFrom, g_score, f_score, tries = {}, {}, {}, {}, {}, 0

		openset[idx_start] = start
		g_score[idx_start] = 0
		f_score[idx_start] = heuristic_cost_estimate(x1, y1, z1, x2, y2, z2)

		while not empty(openset) do
			local current, idx_current
			local cur_f = 9999999

			for idx_cur, cur in pairs(openset) do --for each entry in openset
				if cur ~= nil and f_score[idx_cur] <= cur_f then
					idx_current, current, cur_f = idx_cur, cur, f_score[idx_cur]
				end
			end
			if idx_current == idx_goal then
				return reconstruct_path(cameFrom, idx_goal)
			end

			-- no more than 500 moves
			if cur_f >= stopAt then
				break
			end

			openset[idx_current] = nil
			closedset[idx_current] = true

			local x3, y3, z3 = current[1], current[2], current[3]

			for dir = 0, 5 do -- for all direction find the neighbor of the current position, put them on the openset
				local D = deltas[dir]
				local x4, y4, z4 = x3 + D[1], y3 + D[2], z3 + D[3]
				local neighbor, idx_neighbor = {x4, y4, z4}, fmtCoord(x4, y4, z4)
				if (exclusions[idx_neighbor] == nil or priority) and (cachedWorld[idx_neighbor] or 0) == 0 then -- if its free or unknow and not on exclusion list
					if closedset[idx_neighbor] == nil then -- if not closed
						local tentative_g_score = g_score[idx_current] + ((cachedWorld[idx_neighbor] == nil) and discover or 1)
						--if block is undiscovered, it adds the discover value. (default 1)
						if openset[idx_neighbor] == nil or tentative_g_score <= g_score[idx_neighbor] then -- tentative_g_score is always at least 1 more than g_score[idx_neighbor] T.T
							--evaluates to if its not on the open list
							cameFrom[idx_neighbor] = {dir, idx_current}
							g_score[idx_neighbor] = tentative_g_score
							f_score[idx_neighbor] = tentative_g_score + heuristic_cost_estimate(x4, y4, z4, x2, y2, z2)
							openset[idx_neighbor] = neighbor
						end
					end
				end
			end
		end
	end
	print("no path found")
	return {}
end

----------------------------------------
-- moveTo
--
-- function: Move the turtle to the choosen coordinates in the world
-- input: X, Y, Z and (optional: direction of the goal)
-- return: boolean "success"
--

function moveTo(_targetX, _targetY, _targetZ, _targetDir, discover)
	local tries = 1
	local max_tries = 20
	while tries < max_tries and (cachedX ~= _targetX or cachedY ~= _targetY or cachedZ ~= _targetZ) do
		local path = a_star(cachedX, cachedY, cachedZ, _targetX, _targetY, _targetZ, discover)
		if #path == 0 then
			return false
		end
		--print(textutils.serialize(table))
		for i, dir in ipairs(path) do
			if dir == Up then
				if not up() then
					break
				end
			elseif dir == Down then
				if not down() then
					break
				end
			else
				turnTo(dir)
				if not forward() then
					break
				end
			end
		end
		tries = tries + 1
	end
	if _targetDir then
		turnTo(_targetDir)
	end
	if tries >= max_tries then
		print("moveTo failed, tries exceded max amount (wall in the way)")
		return false
	end
	return true
end


------------------------------------------
-- progressBar
--
-- function: write a progress bar at cursor position (12 characters)
-- input: %
--

function progressBar(percent)
	term.write("[")
	for i=1, 10 do
		if math.floor(percent/10) >= i then
			term.write("|")
		elseif math.ceil(percent/10) == i then
			term.write(":")
		else
			term.write(" ")
		end
	end
	term.write("]")
end

------------------------------------------
-- explore v2.0
--
-- function: map out an area
-- inputs:
-- int _range: size of the cuboid to check (radius excluding center)
-- bool limitY: if true, height of cuboid is 3
-- bool drawMap: if true, draws a map as it goes along so you can see progress
--

function explore(_range, limitY, drawAMap)--TODO: flag to explore previously explored blocks
	local ox, oy, oz, od = locate()
	local x, y, z, d = 0, 0, 0, 0
	local i = 0
	local total = 0
	local toCheck = {}
	local count = 0
	local maxCount
	local idx
	local dist
	local skip
	local yVal = _range
	drawMap = drawMap or false
	limitY = limitY or false

	if limitY then
		yVal = 1
	end

	for dx = -_range, _range do
		for dy = -yVal, yVal do
			for dz = -_range, _range do
				idx = fmtCoord(ox+dx, oy+dy, oz+dz)
				toCheck[idx] = {ox+dx, oy+dy, oz+dz}--set up the toCheck table
				count = count + 1
			end
		end
	end

	maxCount = count
	while count > 1 do--go through all entries in table
		x, y, z, d = locate()
		term.clear()
		term.setCursorPos(1, 1)
		if drawAMap then
			drawMap(ox, oy, oz)
			drawTurtleOnMap(ox, oy, oz, x, y, z, d)
			term.setCursorPos(1, 1)
		end
		progressBar(100*(maxCount - count)/(maxCount))
		dist = 500
		skip = false

		for k, v in pairs(toCheck) do--find closest block to check
			if v[1] == x and v[2] == y and v[3] == z then--if on the block then remove from list
				toCheck[k] = nil
				skip = true--and run again
				count = count - 1
				maxCount = maxCount - 1
				break
			elseif (math.abs(x - v[1]) + math.abs(y - v[2]) + math.abs(z - v[3])) < dist then
				dist = math.abs(x - v[1]) + math.abs(y - v[2]) + math.abs(z - v[3])--TODO: pathfind to the location and use number of instructions instead of huristic distance
				idx = k
				if dist == 1 then
					break
				end
			end
		end

		if not skip then
			count = count - 1
			moveTo(toCheck[idx][1], toCheck[idx][2], toCheck[idx][3], d, false, nilCost)--still not sure about nilcost
			toCheck[idx] = nil
		end
		sleep(0)--yield... remove this if possible
	end


	term.clear()
	term.setCursorPos(1, 1)
	progressBar(100)
	-- Go back to the starting point
	print(string.format("\nreturning..."))
	moveTo(ox, oy, oz, od, false, nilCost)
end

------------------------------------------
-- discoverWorld - OLD version, use exploe() instead
--
-- function: map out an area
-- input: size of the cuboid to check (radius excluding center)
--

function discoverWorld(_range)
	local x, y, z, d = locate()
	local i = 0
	local total = 0
	for j=1, _range do
		total = total + math.pow(j*2+1, 3)
	end

	-- Try to go to every location in the cuboid
	for r = 1, _range do
		for dx = -r, r do
			for dy = -r, r do
				for dz = -r, r do
					local idx_goal = fmtCoord((x+dx), (y+dy), (z+dz))
					i = i + 1
					term.setCursorPos(1, 1)
					term.clear()--TODO: test this
					--print("completion: "..math.floor(i*100/total).."%")
					progressBar(math.floor(i*100/total))
					if cachedWorld[idx_goal] == nil then
						moveTo(x+dx, y+dy, z+dz, cachedDir, false, nilCost)
						--sleep(0.01)
					end
				end
			end
		end
	end

	-- Go back to the starting point
	moveTo(x, y, z, d)
	term.setCursorPos(0, 0)
	--term.clear()
end

----------------------------------------
-- setLocation
--
-- function: Set the current X, Y, Z and direction of the turtle
-- d can be the direction name or number
--

function setLocation(x, y, z, d)
	cachedX, cachedY, cachedZ = x, y, z
	if d == 0 then
		d = "north"
		cachedDir = North
	elseif string.lower(d) == "north" then
		d = "north"
		cachedDir = North
	elseif d == 1 then
		d = "west"
		cachedDir = West
	elseif string.lower(d) == "west" then
		d = "west"
		cachedDir = West
	elseif d == 2 then
		d = "south"
		cachedDir = South
	elseif string.lower(d) == "south" then
		d = "south"
		cachedDir = South
	elseif d == 3 then
		d = "east"
		cachedDir = East
	elseif string.lower(d) == "east" then
		d = "east"
		cachedDir = East
	else
		print("unknown direction")
		return false
	end
	if isLama then
		lama.setPosition(x, y, z, d)
	end
	return cachedX, cachedY, cachedZ, cachedDir
end

----------------------------------------
-- startGPS
--
-- function: Open the rednet network
-- return: boolean "success"
--

function startGPS()
	local netOpen, modemSide = false, nil

	for _, side in pairs(rs.getSides()) do		-- for all sides
		if peripheral.getType(side) == "modem" then	-- find the modem
			modemSide = side
			if rednet.isOpen(side) then	-- check its status
				netOpen = true
				break
			end
		end
	end

	if not netOpen then	-- if the rednet network is not open
		if modemSide then	-- and we found a modem, open the rednet network
			rednet.open(modemSide)
		else
			print("No modem found")
			return false
		end
	end
	return true
end

-- setLocationFromGPS
--
-- function: Retrieve the turtle GPS position and direction (if possible)
-- return: current X, Y, Z and direction of the turtle (or false if it failed)
--

function setLocationFromGPS()
	if startGPS() then
		-- get the current position
		cachedX, cachedY, cachedZ	= gps.locate(4, false)
		if not cachedX then
			return false
		end
		local d = cachedDir or nil
		cachedDir = nil

		-- determine the current direction
		for tries = 0, 3 do	-- try to move in one direction
			if turtle.forward() then
				local newX, _, newZ = gps.locate(4, false) -- get the new position
				if not turtle.back() then-- and go back
					ghost_forward()--couldn't move backward... need to shuffle the map so we don't screw it up
				end

				-- deduce the curent direction
				if newZ < cachedZ then--north = -Z
					cachedDir = North
					d = "north"
				elseif newZ > cachedZ then--south = +Z
					cachedDir = South
					d = "south"
				elseif newX < cachedX then--west = -X
					cachedDir = West
					d = "west"
				elseif newX > cachedX then--east = +X
					cachedDir = East
					d = "east"
				end

				-- Cancel out the tries
				if tries%4 == 3 then
					turtle.turnLeft()
				else
					for i = 1,tries do
						turtle.turnRight()
					end
				end

				-- exit the loop
				break

			else -- try in another direction
				tries = tries + 1
				turtle.turnLeft()
			end
		end

		if cachedDir == nil then
			if isLama then--TODO: test this
				local x, y, z, d = lama.getPosition()
				setDirection_lamaFormat(d)
				print("got direction from lama")
			else
				print("Could not determine direction")
				return false
			end
		end


		-- Return the current turtle position
		if isLama then
			lama.setPosition(cachedX, cachedY, cachedZ, d)
		end
		return cachedX, cachedY, cachedZ, cachedDir
	else
		print("no GPS signal")
		if isLama then
			setLocationFromLAMA()
		else
			return false
		end
	end
end

----------------------------------------
-- setDirection_lamaFormat
--
-- function: Set the turtle direction from the LAMA format
-- return: boolean success
--
function setDirection_lamaFormat(d)
	if d == "north" then
		cachedDir = North
	elseif d == "south" then
		cachedDir = South
	elseif d == "east" then
		cachedDir = East
	elseif d == "west" then
		cachedDir = West
	else
		print("could not get direction from lama")
		return false
	end
	return true
end

----------------------------------------
-- setLocationFromLAMA
--
-- function: Retrieve the turtle position and direction from LAMA
-- return: current X, Y, Z and direction of the turtle (or false if it failed)
--

function setLocationFromLAMA()
	if isLama then
		cachedX, cachedY, cachedZ, d = lama.getPosition() --last resort if gps fails, get direction from Lama
		return setDirection_lamaFormat(d)
	else
		print("no lama")
		return false
	end
end

----------------------------------------
-- locate
--
-- function: Retrieve the cached turtle position and direction
-- return: cached X, Y, Z and direction of the turtle
--

function locate()
	if isLama then
		local x, y, z, f = lama.getPosition()
		local d
		if f == "north" then
			d = North
		elseif f == "west" then
			d = West
		elseif f == "south" then
			d = South
		elseif f == "east" then
			d = East
		else
			return cachedX, cachedY, cachedZ, cachedDir
		end
		cachedX, cachedY, cachedZ, cachedDir = x, y, z, d
		return x, y, z, d
	else
		return cachedX, cachedY, cachedZ, cachedDir
	end
end
