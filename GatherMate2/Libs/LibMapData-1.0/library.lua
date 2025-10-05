--[[
	Library contains a dataset for Map file names and floors giving the raw map data
	it also has a few functions to help determine distance and directions.
--]]
local MAJOR, MINOR = "LibMapData-1.0", tonumber("61") or 999
assert(LibStub, MAJOR.." requires LibStub")

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

local watchFrame = CreateFrame("Frame")
local lastMap, lastFloor = nil,0
local mapData = {}
local mapToLocal = {}
local localToMap = {}
local idToMap = {}
local GetPlayerFacing, GetPlayerMapPosition,SetMapToCurrentZone = GetPlayerFacing, GetPlayerMapPosition, SetMapToCurrentZone
local atan2 = math.atan2
local PI2 = math.pi*2
local floor = math.floor
local type,assert = type,assert
--- Constants
lib.MAP_NORMAL = 0
lib.MAP_INSTANCE = 1
lib.MAP_RAID = 2
lib.MAP_BG = 3
 -- estimated world map size
local worldMapWidth = 47714.278579261
local worlMapHeight = 31809.64857610083

local contOffsets = {
	[1] = {-8590.40725049343,5628.692856102324},
	[2] = {18542.31220836664, 3585.574573158966},
	[3] = {0,0},
	[4] = {16020.94044398222,454.2451915717977},
}

local transforms_x = {
	[1] = 10133.3330078125,
	[2] = -2400.0
}
local transforms_y = {
	[1] = 17600.0,
	[2] = 2400.0
}

do
	-- Format: 
	-- floors = number of floors
	-- area_id = in game area id
	-- floor_index = width,height, ulX,ulY, lrXx,lrY, mapid
	local emptyMaps = { 
		['floors'] = 0,['name'] = WORLD_MAP, ['continent'] = 0, ['phase'] = 0, ['map_type'] = 0, ['link'] = 0,
		[1] = {0,0,0,0,0,0,0}
	}
	setmetatable(mapData, { __index = function(t, k) if k and k ~= 0 then DEFAULT_CHAT_FRAME:AddMessage("LibMapData-1.0 is missing data for "..k) end; return emptyMaps end })
	setmetatable(idToMap, { __index = function(t, k) if k then DEFAULT_CHAT_FRAME:AddMessage("LibMapData-1.0 is missing data for area id "..k) end; return k end})
	setmetatable(mapToLocal, { __index = function(t,k) if k and k ~= "World Map" then DEFAULT_CHAT_FRAME:AddMessage("LibMapData-1.0 is missing localized data for "..k) end; return k end})
	
	for i=0,9999 do
		if C_WorldMap.GetWorldPosition(i, 0, 0) then
			local x1, y1 = C_WorldMap.GetWorldPosition(i, 0, 0)
			local x2, y2 = C_WorldMap.GetWorldPosition(i, 1, 1)
			mapData[i] = {
				['floors'] = 0, ['name'] = C_WorldMap.GetMapFileByAreaID(i), ['rzti'] = 0, ['map_type'] = 0, ['continent'] = C_WorldMap.GetMapIDByAreaID(i), ['link'] = 0,['transform'] = 0,
				[1] = {abs(x1-x2), abs(y1-y2), x1, y1, x2, y2},
			}
		end
	end

	-- Create Reverse map
	for k,v in pairs(mapData) do
		idToMap[v['name']] = k
	end

	-- Build the localized name list.
	local continentList = {GetMapContinents()}
	for cID = 1, #continentList do
		for zID, zname in ipairs({GetMapZones(cID)}) do
			SetMapZoom(cID, zID)
			local mapfile = GetMapInfo()
			mapToLocal[mapfile] = zname
			localToMap[zname] = mapfile
			mapData[idToMap[mapfile]].continent = cID
		end
	end
	for k,v in pairs(mapData) do
		local rName = rawget(mapToLocal,v.name)
		if rName == nil and v.rzti then
			mapToLocal[v.name] = GetRealZoneText(v.rzti)
		end
		SetMapByID(k)
		local _,l,t,r,b = GetCurrentMapZone()
		if l and l ~= 0 and t and t ~= 0 and r and r ~= 0 and b and b ~= 0 and v.floors == 0 then
			v[1][3] = -l
			v[1][4] = t
			v[1][5] = -r
			v[1][6] = b
		end
	end
end

--- API to encode a location in game
-- @param x
-- @param y
-- @param mapLevel
-- @return encoded location number
function lib:EncodeLoc(x,y,level)
	local level = level or 0
	if x > 0.9999 then
		x = 0.9999
	end
	if y > 0.9999 then
		y = 0.9999
	end
	return floor( x * 10000 + 0.5 ) * 1000000 + floor( y * 10000  + 0.5 ) * 100 + level
end

--- API to decode a location num
-- @param location id
-- @return x,y,level
function lib:DecodeLoc(id)
	return floor(id/1000000)/10000, floor(id % 1000000 / 100)/10000, id % 100
end

--- API to list all zones
-- @param (optional) table to store results in
-- @return a table of zones
function lib:GetAllMapIDs(storage)
	local t = storage or {}
	local i = 1
	for k,v in pairs(mapData) do
		t[i] = k
		i= i + 1
	end
	return t
end

--- API to list raids
-- @param (optional) table to store results in
-- @return a table containing the raid area ids
function lib:GetRaids(storage)
	local t = storage or {}
	local i = 1
	for k,v in pairs(mapData) do
		if v.map_type == 2 then
			t[i] = k
			i = i + 1
		end
	end
	return t
end

--- API to list dungeons
-- @param (optional) table to store results in
-- @return a table containing the dungeon area ids
function lib:GetDungeons(storage)
	local t = storage or {}
	local i = 1
	for k,v in pairs(mapData) do
		if v.map_type == 1 then
			t[i] = k
			i = i + 1
		end
	end
	return t
end

--- API to list zones by continent
-- @param Continent index
-- @param (optional) table to store results in
-- @return a table containing the zone area ids
function lib:GetZonesForContinent(continent, storage)
	local t = storage or {}
	if continent < 1 then
		return t
	end
	local i = 1
	for k,v in pairs(mapData) do
		if v.continent == continent then
			t[i] = k
			i = i + 1
		end
	end
	return t
end
--- API to determine is a map is a continent
-- @param mapfile or area id to check
-- @return true if a continent
function lib:IsContinentMap(mapfile)
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return true end
	if mapfile == 466 or mapfile == 485 or mapfile == 13 or mapfile == 14 then
		return true
	end
	return false
end

--[[
	The upper lft, lower right coords are the position within the continent map
	so to figure out location on a given continent, we need to upscale the x,y to the continent
--]]

--- API to get distance and direction to a target in the same map
-- @param mapfile to use
-- @param targetX coords
-- @param targetY coords
-- @return distance,angle where distance is yards and angle is radians
function lib:DistanceAndDirection(mapfile,floor,targetX, targetY)
	local srcX,srcY = GetPlayerMapPosition("player")
	local distance,xd,yd = self:Distance(mapfile,floor,srcX,srcY,targetX,targetY)
	local radians =  atan2(xd,-yd)
	if radians > 0 then
		radians = PI2 - radians
	else
		radians = -radians
	end
	return distance,radians
end

--- API to calc the distance between 2 locations within the same mapfile
-- @param mapfile or area_id
-- @param floor to use
-- @param srcX starting x
-- @param srcY starting y
-- @param dstX destination x
-- @param dstY destination y
-- @return distance, xdelta, ydelta where distance is the total distance, xdelta is the delta of the x values and ydelta is the detla of y values all in yards
function lib:Distance(mapfile,floor, srcX,srcY,dstX,dstY)
	assert(floor == nil or (type(floor) == "number" and floor))
	local width = 0
	local height = 0
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0,0 end
	local data = mapData[mapfile]
	local fl = data[floor]
	if floor and floor <= data['floors'] and floor > 0 then
		width, height  = fl[1],fl[2] 
	else
		fl = data[1]
		width,height = fl[1], fl[2]
	end
	local x = (dstX - srcX) * width
	local y = (dstY - srcY) * height
	return (x*x + y*y)^0.5,x,y
end

--- API to convert an x,y (yards) in a given zone up to the world map
-- @param mapfile
-- @param x in yards
-- @param y in yards
-- @return the x,y point in world map yards
function lib:ConvertToWorldPoint(mapfile,x,y)
   	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0 end
	local fl = mapData[mapfile]
	-- Convert to continet data
	local x1,y1 = self:ConvertToContinent(mapfile,0,x,y)
	return x1 + contOffsets[fl.continent], y1 + contOffsets[fl.continent]
end

--- API to convert from the world poistion in yars to the world map scale
-- @param x the world map x point in yards
-- @param y in the world map yard point
-- @return x,y in world map frame scale
function lib:ConvertFromWorldPoint(x,y)
	return x/worldMapWidth, y/worldMapHeight
end

-- API to convert from continent x,y (in yards) to zone x,y
-- @param map the map to use
-- @param floor the floor to use
-- @param x in yards
-- @param y in yards
-- @return x,y in zone scale
function lib:ConvertFromContinent(map,floor,x,y)
	local zx1,zy1 = self:GetMapUpperLeft(map,floor)
	local zx2,zy2 = self:GetMapLowerRight(map,floor)
	local x,y = (x-zx1)/(zx1-zx2), (y-zy1)/(zy2-zy1)
	if mapData[map].transform == 1 then
		x = x - transforms_x[mapData[mapfile].continent]
		y = y - transforms_y[mapData[mapfile].continent]
	end
	return x,y
end

-- API to convert to continent x,y (in yards) from zone x,y
-- @param map the map to use
-- @param floor the floor to use
-- @param x in yards
-- @param y in yards
-- @return x,y in continent scale
function lib:ConvertToContinent(map,floor, x,y)
	local zx1,zy1 = self:GetMapUpperLeft(map,floor)
	local zx2,zy2 = self:GetMapLowerRight(map,floor)
	local x,y =  zx1 + (zx2-zx1)*x,zy1 + (zy2-zy1)*y
	if mapData[map].transform == 1 then
		x = x + transforms_x[mapData[mapfile].continent]
		y = y + transforms_y[mapData[mapfile].continent]
	end
	return x,y
end

--- API to calc the distance between 2 locations across map files
-- @param srcMap or area_id
-- @param srcFloor to use
-- @param srcX starting x
-- @param srcY starting y
-- @param dstMap destination map file
-- @param dstFloor destination floor
-- @param dstX destination x
-- @param dstY destination y
-- @return distance, xdelta, ydelta where distance is the total distance, xdelta is the delta of the x values and ydelta is the detla of y values all in yards
function lib:DistanceWithinContinent(srcMap,srcFloor, srcX, srcY, dstMap, dstFloor, dstX, dstY)
	assert(srcFloor == nil or (type(srcFloor) == "number" and srcFloor))
	assert(dstFloor == nil or (type(dstFloor) == "number" and dstFloor))
	if type(dstMap) == "string" then
		dstMap = idToMap[dstMap]
	end
	if type(srcMap) == "string" then
		srcMap = idToMap[srcMap]
	end
	if mapData[srcMap].continent ~= mapData[dstMap].continent then
		return 0,0,0
	end
	local startX, startY = self:ConvertToContinent(srcMap,srcFloor, srcX, srcY)
	local endX, endY = self:ConvertToContinent(dstMap,dstFloor, dstX, dstY)
	local x = (endX - startX)
	local y = (endY - startY)
	return (x*x+y*y)^0.5,x,y
end

--- API to convert coords to yards
-- @param mapfile or area_id
-- @param floor
-- @param x coord
-- @param y coord
-- @return x,y as yards
function lib:PointToYards(mapfile,floor, x, y)
	assert(floor == nil or (type(floor) == "number" and floor))
	local width = 0
	local height = 0
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0 end
	local data = mapData[mapfile]
	local fl = data[floor]
	if floor and floor <= data['floors'] and floor > 0 then
		width, height  = fl[1],fl[2] 
	else
		fl = data[1]
		width,height = fl[1], fl[2]
	end
	return x * width, y * height
end

--- API to convert from yards to a point
-- @param mapfile or area_id
-- @param floor
-- @param x coord in yards
-- @param y coord in yards
-- @return x,y as a fractional point
function lib:YardsToPoint(mapfile,floor,x,y)
	assert(floor == nil or (type(floor) == "number" and floor))
	local width = 0
	local height = 0
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0 end
	local data = mapData[mapfile]
	local fl = data[floor]
	if floor and floor <= data['floors'] and floor > 0 then
		width, height  = fl[1],fl[2] 
	else
		local fl = data[1]
		width,height = fl[1], fl[2]
	end
	return x/width, y/height
end


--- API to get the number of floors of a given map
-- @param mapfile the mapfile you wish to check or area id from GetCurrentMapAreaID()
-- @return number of floors or 0 if no floors exist
-- @usage floors = lib:MapFloors(GetMapInfo())
function lib:MapFloors(mapfile)
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0 end
	local fl = mapData[mapfile]['floors']
	if fl == 1 then
		fl = 0
	end
	return fl
end

--- API to get area id for a given map file
-- @param mapfile to check
-- @return area_id or 0 if the map doesnt exist
-- @usage aid = lib:MapAreaId(GetMapInfo())
function lib:MapAreaId(mapfile)
	assert(mapfile and type(mapfile) == "string")
	return idToMap[mapfile]
end

--- API to get localized name of a given map file
-- @param mapfile or area id to check, note area id is more accurate 
-- @return the localized map name or nil
-- @usage lname = lib:MapLocalized(GetMapInfo())
function lib:MapLocalize(mapfile)
	if type(mapfile) == "number" then
		mapfile = mapData[mapfile]['name']
	end
	if mapfile == -1 then return WORLD_MAP end
	return mapToLocal[mapfile]
end

--- API to get the width,height of a given map
-- @param mapfile you wish to interrogate or area id from GetCurrentMapAreaID()
-- @param floor optional floor you wish to examine
-- @return width,height in yards or 0,0 if no data exists. Will add a message to the DEFAULT_CHAT_FRAME
-- @usage local w,h = lib:MapArea(GetMapInfo(),GetCurrentMapDungeonLevel())
function lib:MapArea(mapfile,floor)
	assert(floor == nil or (type(floor) == "number" and floor))
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0 end
	local data = mapData[mapfile]
	local fl = data[floor]
	if floor and floor <= data['floors'] and floor > 0 then
		return fl[1],fl[2] 
	else
		if floor and floor > 0 then
			return 0,0
		end
		fl = data[1]
		return fl[1], fl[2]
	end
end


--- API to get the upper left x,y of a given map
-- @param mapfile you wish to interrogate or area id from GetCurrentMapAreaID()
-- @param floor optional floor you wish to examine
-- @return x,y or the upper left corner or 0,0 if no data exists. Will add a message to the DEFAULT_CHAT_FRAME
-- @usage local x,y = lib:MapUpperLeft(GetMapInfo(),GetCurrentMapDungeonLevel())
function lib:GetMapUpperLeft(mapfile, floor)
	assert(floor == nil or (floor and floor >= 0))
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0 end
	local data = mapData[mapfile]
	local fl = data[floor + 1]
	if floor and floor <= data['floors'] then
		return fl[3],fl[4]
	else
		if floor and floor > 0 then
			return 0,0
		end
		fl = data[1]
		return fl[3],fl[4]
	end
end

--- API to get the lower right x,y of a given map
-- @param mapfile you wish to interrogate or area id from GetCurrentMapAreaID()
-- @param floor optional floor you wish to examine
-- @return x,y or the lower right corner or 0,0 if no data exists. Will add a message to the DEFAULT_CHAT_FRAME
-- @usage local x,y = lib:MapLowerRight(GetMapInfo(),GetCurrentMapDungeonLevel())
function lib:GetMapLowerRight(mapfile, floor)
	assert(floor == nil or (floor and floor >= 0))
	if type(mapfile) == "string" then
		mapfile = idToMap[mapfile]
	end
	if mapfile == -1 then return 0,0 end
	local data = mapData[mapfile]
	local fl = data[floor + 1]
	if floor and floor <= data['floors'] then
		return fl[5],fl[6]
	else
		if floor and floor > 0 then
			return 0,0
		end
		fl = data[1]
		return fl[5],fl[6]
	end
end

--- API to force a zone change check
-- calling this method will fire a callback
-- @param force, optional if you want to force a check even if data hasnt changed
-- @return void
function lib:ZoneChanged(force)
	if WorldMapFrame:IsVisible() then return end
	SetMapToCurrentZone()
	local x,y = GetPlayerMapPosition("player")
	-- if the player is in an instance without a map then dont fire anything
	if x == 0 and y == 0 then
		return
	end
	local map = GetMapInfo()
	if map == nil then
		return
	end
	local floor = GetCurrentMapDungeonLevel()
	if map ~= lastMap or floor ~= lastFloor or force then
		local w,h = self:MapArea(map,floor)
		self.callbacks:Fire("MapChanged",map,floor,w,h)
		lastMap = map
		lastFloor = floor
	end
end

-- Turn on events on someone registers for them
function lib.callbacks:OnUsed()
	watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	watchFrame:RegisterEvent("ZONE_CHANGED")
	watchFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	watchFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
	lib:ZoneChanged(true)
end

-- turn off events once we no longer have listeners
function lib.callbacks:OnUnused()
	watchFrame:UnregisterAllEvents()	
end
watchFrame:SetScript("OnEvent", function(frame,event,...) 
	lib:ZoneChanged(false) 
end)

--@alpha@
function lib:Test()
-- Validate map files are all present.
for continent in pairs({GetMapContinents()}) do
	local zones = { GetMapZones(continent) }
	print("Continent "..continent)
	for zone, name in pairs(zones) do
		SetMapZoom(continent, zone)
		local mapFile = GetMapInfo()
		local area_id = GetCurrentMapAreaID()
		local w,h = self:MapArea(mapFile)
		local aid = self:MapAreaId(mapFile)
		if w == 0 and h == 0 then
			error("Failed to find map "..mapFile)
		end
		if area_id ~= aid then
			error(mapFile.." area id mismatch")
		end
	end
end
print("All Tests passed")
end