--[[
A trimmed down version of LibMapData-1.0 including only the parts that Gathermate2 uses
]]

local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")

GatherMate.mapData = {}

local nametoid = {}
local idtodxdy = {}
local mapToLocal = {}

-- Build the localized name list.
local continentList = {GetMapContinents()}
for cID = 1, #continentList do
	for zID, zname in ipairs({GetMapZones(cID)}) do
		SetMapZoom(cID, zID)
		local mapfile = GetMapInfo()
		mapToLocal[mapfile] = zname
	end
end

-- Don't know a better way
-- Build list of areaIDs
for i=0,9999 do
	if C_WorldMap.GetWorldPosition(i, 0, 0) then -- and mapToLocal[C_WorldMap.GetMapFileByAreaID(i)] then
		local x1, y1 = C_WorldMap.GetWorldPosition(i, 0, 0)
		local x2, y2 = C_WorldMap.GetWorldPosition(i, 1, 1)
        local mapfile = C_WorldMap.GetMapFileByAreaID(i)
		nametoid[mapfile] = i
        -- if map isn't in overworld then save mapfile name.  Prevents issue with MapLocalize
        if not mapToLocal[mapfile] then
            mapToLocal[mapfile] = mapfile
        end
		idtodxdy[i] = { [1] = abs(x1-x2), [2] = abs(y1-y2) }
	end
end

function GatherMate.mapData:MapLocalize(mapfile)
	local t = mapfile
	if type(mapfile) == "number" then
		mapfile = C_WorldMap.GetMapFileByAreaID(mapfile)
	end
	if mapfile == WORLDMAP_COSMIC_ID then return WORLD_MAP end
    return mapToLocal[mapfile]
end

function GatherMate.mapData:EncodeLoc(x,y,level)
	local level = level or 0
	if x > 0.9999 then
		x = 0.9999
	end
	if y > 0.9999 then
		y = 0.9999
	end
	return floor( x * 10000 + 0.5 ) * 1000000 + floor( y * 10000  + 0.5 ) * 100 + level
end

function GatherMate.mapData:DecodeLoc(id)
	return floor(id/1000000)/10000, floor(id % 1000000 / 100)/10000, id % 100
end

function GatherMate.mapData:GetAllMapIDs(id)
	return nametoid
end

function GatherMate.mapData:MapArea(id)
	if type(id) == "string" then
		mapfile = nametoid[id]
	end
    if idtodxdy[id] then
    	return idtodxdy[id][1], idtodxdy[id][2]
    else
        return 0, 0
    end
end
