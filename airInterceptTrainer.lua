---
---
--- Script to spawn and manage groups configured in specific formations and multi-group presentations
--- As currently implemented, spawn zones are calculated as offsets from the Roosevelt
--- The characteristics of a given presentation are stored in an array of format: {presentationName, num aircraft, minimum range between spawned groups, max range, {bearings from first group}}
--- Presentations will be spawned in a selected zone and on a heading within +-10 degrees of that specified
--- Each group spawned, as well as each menu item generated are stored in tables
--- Inspiration for this script drawn from AIC classes formerly run by DCS Academy
--- Charles T. Wild (Walrus) 2023
---

    -- Vec3 function coalition.getMainRefPoint(enum coalition.side coalition) function call returning bullseye as a Vec3

    BASE:TraceOnOff(true)
    BASE:TraceLevel(1)
    BASE:TraceClass("SPAWN")
    BASE:TraceClass("GROUP")

    --MESSAGE:New(gAircraftTypeTable[1][1]):ToAll()

    local airInterceptTrainer = {}

    --- helper functions

    -- converts value passed in from nm to metres
    local function nmToMetres(nauticalMiles)
        return nauticalMiles * 1852
    end

    -- converts value passed in from feet to metres
    local function ftToMetres(feet)
        return feet * 0.3048
    end

    -- returns a random altitude from the range passed as min and max arguments
    local function randomAltitude(min, max)
        if min == nil then
            BASE:E(tostring(gMinAltitude) .. " " .. tostring(gMaxAltitude))
            return math.random(gMinAltitude, gMaxAltitude)

        else
            BASE:E(tostring(min) .. " " .. tostring(max))
            return math.random(min, max)
        end
    end

    -- generates a random bearing from 001 to 360
    local function randomBearing()
        return math.random(1, 360)
    end

    -- returns range randomly from either optional min/max arguments or globals if no values are passed
    local function randomRange(min, max) -- called by randomDeltaX & Y to find range from centre at which group will be spawned
        if min and max ~= nil then
            return math.random(min, max) -- if arguments are passed in, range is determined between these
        else
            BASE:E("calculating deltaY from min")
            return math.random(gMinSpawnRange, gMaxSpawnRange) -- otherwise uses globals for calculation
        end
    end

    -- calculates delta x (i.e. Northing) from origin either randomly from bearing and minimum and maximum range arguments or at a fixed range if only min is passed
    local function randomDeltaX(bearing, min, max)
        if max ~= nil then
            return randomRange(min, max) * math.cos(math.rad(bearing))
        else
            BASE:E("calculating deltaX from min " .. tostring(min))
            return min * math.cos(math.rad(bearing))
        end
    end

    -- calculates delta z (i.e. Easting) from origin either randomly from bearing and minimum and maximum range arguments or at a fixed range if only min is passed
    local function randomDeltaZ(bearing, min, max)
        if max ~= nil then
            return randomRange(min, max) * math.sin(math.rad(bearing))
        else
            BASE:E("calculating deltaZ from min " .. tostring(min))
            return min * math.sin(math.rad(bearing))
        end
    end

    -- calculates the relative position of one object possessing a position from another i.e. the parameters bearingFromOrigin and separation represent the hypotenuse of the triangle /n
    -- having as its centre the object passed as origin. Returns new position as a POINT_VEC3
    function calculateOffsetPos(bearingFromOrigin, origin, separation)
        MESSAGE:New("origin.z: " .. tostring(origin.z)):ToAll()
        local z = origin.z + (separation * math.sin(math.rad(bearingFromOrigin)))
        MESSAGE:New("output z: " .. tostring(z)):ToAll()
        local y = randomAltitude()
        local x = origin.x + (separation * math.cos(math.rad(bearingFromOrigin)))
        local locationObj = POINT_VEC3:New(x, y, z)
        return locationObj
    end

    -- unused; calculates offset between two bearings; if 180 is passed as either argument, will calculate reciprocal
    local function bearingFrom(presentationBearing, heading)
        if presentationBearing + heading == 360 then
            return 360
        else
            return ((presentationBearing + heading) % 360)
        end
    end

    -- return location of USS Theodore Roosevelt
    function getRooseveltLocation()
        return POINT_VEC3:NewFromVec3(GROUP:FindByName("USS Theodore Roosevelt"):GetVec3())
    end

--- globals
    BASE:E("above gCentre")
    gCentre = POINT_VEC2:New(36199, 268314) -- centre from which spawn locations will be derived. Defined arbitrarily and does not couple script to a particular map. Current value corresponds roughly to centre of the Syria map
    gRoosevelt = UNIT:FindByName("USS Theodore Roosevelt")
    BASE:E("below gCentre")
    gBomberSpawn = ZONE:FindByName("BomberSpawn")
    gMaxGroupSize = 4
    gMinGroupSize = 1
    gMaxSpawnRange = nmToMetres(200) -- max range from gCentre at which groups can be spawned
    gMinSpawnRange = nmToMetres(100) -- min range ditto above
    gMaxAltitude = ftToMetres(32000) -- max altitude at which a group can be spawned
    gMinAltitude = ftToMetres(25000) -- min altitude ditto above
    gSpawnedCounter = 1 -- used to set index for new instances of GROUP in gPresentationTypeTable

    --- presentation, aircraft and spawned groups tables
    --- each element contains: [1] presentation name [2] number of aircraft, [3] min separation, [4] max separation, [5] table of bearings from lead to trail groups
    gPresentationTypeTable	= {{"Azimuth", 2, nmToMetres(7), nmToMetres(17), {270}},
                                 {"Range", 2, nmToMetres(10), nmToMetres(20), {180}},
                                 {"Vic", 3, nmToMetres(6), nmToMetres(12), {135, 225}},
                                 {"Ladder", 3, nmToMetres(7), nmToMetres(12), {180, 360}},
                                 {"Wall", 3, nmToMetres(7), nmToMetres(15), {90, 270}},
                                 {"Single Group", 1, 0, 0, {}},
                                 {"Echelon", 2, nmToMetres(7), nmToMetres(17), {200}},
                                 {"Champagne", 4, nmToMetres(7), nmToMetres(17), {45, 180, 315}},
                                 --[[{"2Stack"}, {"3Stack"}, {"Box"}--]]}

    -- elements are initialised by initSpawnZones(), into which data from table is passed and which replaces each element with a ZONE_UNIT iteratively
    gSpawnZoneTable = {{"Spawn Zone East", gRoosevelt, nmToMetres(5), 90, nmToMetres(225)},
                       {"Spawn Zone South", gRoosevelt, nmToMetres(5), 180, nmToMetres(225)},
                       {"Spawn Zone South-Southwest", gRoosevelt, nmToMetres(5), 202.5, nmToMetres(225)},
                       {"Spawn Zone Southwest", gRoosevelt, nmToMetres(5), 225, nmToMetres(225)},
                       {"Spawn Zone West", gRoosevelt, nmToMetres(5), 270, nmToMetres(225)},
                       {"Spawn Zone North", gRoosevelt, nmToMetres(5), 360, nmToMetres(225)}}

    gAircraftTypeTable = {--[[{"F-4", "fighter", "blue"}, {"F-5", "fighter", "blue"}, {"F-14", "fighter", "blue"},
                          {"F-15", "fighter", "blue"}, {"F-16", "fighter", "blue"}, {"F-18", "fighter", "blue"},--]]
                          {"Fagot", "fighter", "red"}, {"Farmer", "fighter", "red"}, {"Fishbed", "fighter", "red"},
                          {"Flogger", "fighter", "red"}, {"Foxbat", "fighter", "red"}, {"Fulcrum", "fighter", "red"},
                          {"Flanker", "fighter", "red"}, {"Foxhound", "fighter", "red"}, {"Bear", "bomber", "red"},
                          {"Backfire", "fighter", "red"}}
    gSpawnHeadingTable = {360, 45, 90, 135, 180, 270, 315}
    gROETable = {{"WEAPONS FREE", 0}, {"RETURN FIRE", 3}, {"WEAPON HOLD", 4}}
    gROTTable = {{"NO REACTION", 0}, {"PASSIVE DEFENCE", 1}, {"EVADE FIRE", 2}, {"BYPASS AND ESCAPE", 3}, {"ALLOW ABORT MISSION", 4}}
    gECMTable = {{"NEVER USE", 0}, {"USE ONLY IF LOCKED BY RADAR", 1}, {"USE ONLY IF RADAR LOCK DETECTED", 2}, {"ALWAYS ON", 3}}
    gSpawnedTable = {}  -- will be filled with instances of GROUP objects as they are instantiated by spawnGroup function
    gSpawnMenuItems = {}
    gTypeMenuItems = {}
    gZoneMenuItems = {}
    gBearingMenuItems = {}
    gMenuForGroupItems = {} -- will contain menu instances to control all alive groups

    --- further helper functions requiring access to global variables
    -- Called from gSpawnZoneTable. Instantiates ZONE_UNIT object from arguments passed from elements of table
    --[[function initSpawnZoneLocation(zoneName, zoneUnit, zoneRadius, zoneOffsetAngle, zoneOffsetRange)
        local tempOffset = calculateOffsetPos(zoneOffsetAngle, getRooseveltLocation, zoneOffsetRange)

        return ZONE_UNIT:New(zoneName, zoneUnit, zoneRadius, {tempOffset.x, tempOffset.z})
    end]]--

    function initSpawnZones()
        for i = 1, #gSpawnZoneTable do
            local tempZone = ZONE_UNIT:New(gSpawnZoneTable[i][1], gSpawnZoneTable[i][2], gSpawnZoneTable[i][3],
                    {rho = nmToMetres(200), theta = gSpawnZoneTable[i][4], relative_to_unit = false})
            gSpawnZoneTable[i] = tempZone
            gSpawnZoneTable[i]:DrawZone(-1, {1, 0, 0}, 1, {1, 0, 0}, 0.15, 1, true)
        end
    end

    -- randomly returns a string containing a group name (these MUST conform with group names in ME)
    local function randomAircraft()
        local selection = math.random(#gAircraftTypeTable)
        for i = 1, selection do
            if i == selection then
                return gAircraftTypeTable[i][1]
            end
        end
    end

    -- calculates random location and returns it as a POINT_VEC3 from origin, min and max range and bearing from origin arguments
    local function getRandomLocation(centre, min, max, bearing)
        local x = centre.x + randomDeltaX(bearing, min, max)
        local y = randomAltitude()
        local z = centre.y + randomDeltaZ(bearing, min, max)
        local locationObj = POINT_VEC3:New(x, y, z)
        return locationObj
    end

    local function selectLocationInZone(zone)
        local spawnLocation = zone:GetRandomPointVec3()
        spawnLocation.y = (10000)
        return spawnLocation
    end

    local function selectType(type)
        BASE:E("selectType")
        if type == nil then
            return randomAircraft()
        else
            for i = 1, #gAircraftTypeTable do
                if type == gAircraftTypeTable[i][1] then
                    return type
                end
            end
        end
    end

    local function setHeading(baseHeading)
        return (baseHeading + math.random(-10, 10))
    end

    -- unused test function
    local function checkAlive(group)
        if group:IsAlive() == true then
            return true
        else
            return false
        end
    end

    -- unused test function
    function spawnSingleGroupAtRandomLocation()
        BASE:E("spawnRandom")
        MESSAGE:New("spawnRandom", 40):ToAll()
        local spawnPoint = getRandomLocation()
        spawnGroup(spawnPoint, 250, "F-15")
    end

    --- functions to calculate spawn parameters for new groups

    -- helper function for spawnPresentation() - checks if a location has been passed and randomly generates one if not
    local function checkLocation(location)
        if location == nil then
            return getRandomLocation(gCentre, gMinSpawnRange, gMaxSpawnRange, randomBearing())
        else
            return location
        end
    end

    -- helper function for spawnPresentation() - checks if a heading has been passed and randomly generates one if not
    local function checkHeading(heading)
        if heading == nil then
            return randomBearing
        else
            return heading
        end
    end

    --- functions for deleting groups
    -- iteratively deletes all spawned groups and associated menus
    function removeAll()
        for i = 1, #gSpawnedTable do
            if gSpawnedTable[i] ~= nil then
                removeGroup(gSpawnedTable[i], gMenuForGroupItems[i][1])
            end
            gSpawnedCounter = gSpawnedCounter - 1
        end
    end

    -- deletes group passed in and removes menu for that group
    function removeGroup(thisGroup, deleteMenu, optionsMenu)
        thisGroup:Destroy(false, 1)
        thisMenu:Remove()
        thisMenu:Refresh()
    end

    function setROE(thisGroup, ROEVal)
        thisGroup:OptionROE(ROEVal)
    end

    function setROT(thisGroup, ROTVal)
        thisGroup:OptionROT(thisGroup, ROTVal)
    end

    function setECMUse(thisGroup, ECMVal)
        if ECMVal == 3 then
            thisGroup:OptionECM_AlwaysOn()
        elseif ECMVal == 2 then
            thisGroup:OptionECM_DetectedLockByRadar()
        elseif ECMVal == 1 then
            thisGroup:OptionECM_OnlyLockByRadar()
        else
            thisGroup:OptionECM_Never()
        end
    end

    -- helper function using calculateOffsetPos() to set a waypoint for group argument on the passed bearing
    function setWaypoint(group, bearing, origin, range, speed)
        BASE:E("setWaypoint")
        local newWaypoint = calculateOffsetPos(bearing, origin, 250000)
        group:RouteAirTo(newWaypoint:GetCoordinate(), POINT_VEC3.RoutePointAltType.BARO, POINT_VEC3.RoutePointType.TurningPoint, POINT_VEC3.RoutePointAction.TurningPoint, 800, 1)
        BASE:E("waypoint set")
    end

    function spawnGroup(location, heading, type)
        local newGroup = SPAWN:NewWithAlias(type, "AIC Group " .. type .. " " .. tostring(gSpawnedCounter))
        newGroup:InitGroupHeading(heading)         -- if table is not empty, reference will be created at element corresponding to current value of gSpawnedCounter
        BASE:E("table not empty")
        gSpawnedTable[gSpawnedCounter] = newGroup:SpawnFromPointVec3(location)
        gMenuForGroupItems[gSpawnedCounter] = buildGroupMenu(gSpawnedTable[gSpawnedCounter])
        setWaypoint(gSpawnedTable[gSpawnedCounter], heading, location)
        gSpawnedCounter = gSpawnedCounter + 1
        --BASE:E(gSpawnedTable[gSpawnedCounter]:GetPositionVec3())
    end

    -- spawns first group in a presentation (via spawnGroup()) and iteratively spawns remaining groups in presentation
    function spawnPresentation(type, selectedPresentation, origin, groupHeadingArg)
        BASE:E("spawnPresentation")
        local leadPosition = checkLocation(origin)
        local groupHeading = checkHeading(groupHeadingArg)
        local separation = randomRange(selectedPresentation[3], selectedPresentation[4])
        spawnGroup(leadPosition, groupHeading, type)
        for i = 1, #selectedPresentation[5] do
            local angleOff = selectedPresentation[5][i] + groupHeading
            spawnGroup(calculateOffsetPos(angleOff, leadPosition, separation), groupHeading, type)
        end
        MESSAGE:New(selectedPresentation[2] .. "-group " .. selectedPresentation[1] .. " presentation spawned"):ToAll()
    end

    function spawnHelper(type, presentation, zone, heading)
        spawnPresentation(selectType(type), presentation, selectLocationInZone(zone), setHeading(heading))
    end

    --- Build F10 Menu
    function buildPresentationMenu()
        menuAIC = MENU_COALITION:New(coalition.side.BLUE, "Manage Groups and Presentations") -- top level menu (under F10)
        spawnMenu = MENU_COALITION:New(coalition.side.BLUE, "Spawn a New Presentation")
        local menuItemPresentation
        local menuItemType
        local menuItemZone
        local menuItemHeading
        for i = 1, #gPresentationTypeTable do
            menuItemPresentation = MENU_COALITION:New(coalition.side.BLUE, "Spawn " .. tostring(gPresentationTypeTable[i][2]) .. "-Group " .. gPresentationTypeTable[i][1], spawnMenu)
            gSpawnMenuItems[i] = menuItemPresentation
            for j = 1, #gAircraftTypeTable do
                menuItemType = MENU_COALITION:New(coalition.side.BLUE, gAircraftTypeTable[j][1], menuItemPresentation)
                gTypeMenuItems[j] = menuItemType
                for k = 1, #gSpawnZoneTable do
                    menuItemZone = MENU_COALITION:New(coalition.side.BLUE, "Spawn in " .. gSpawnZoneTable[k]:GetName(), menuItemType)
                    gZoneMenuItems[k] = menuItemZone
                    for l = 1, #gSpawnHeadingTable do
                        menuItemHeading = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set Spawn Heading " .. tostring(gSpawnHeadingTable[l]), menuItemZone,
                                spawnHelper, gAircraftTypeTable[j][1], gPresentationTypeTable[i],  gSpawnZoneTable[k], gSpawnHeadingTable[l])
                        gBearingMenuItems[l] = menuItemHeading
                    end
                end
            end
        end
        deleteMenu = MENU_COALITION:New(coalition.side.BLUE, "Delete Groups", menuAIC)
        deleteAllMenu = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Delete All Groups", deleteMenu, removeAll)
        deleteSingleMenu = MENU_COALITION:New(coalition.side.BLUE, "Delete a Group", deleteMenu)
        groupOptionsMenu = MENU_COALITION:New(coalition.side.BLUE, "Set Group Options", menuAIC)
    end

    -- add menu items to delete group, change ROE, ROT and ECM use
    function buildGroupMenu(thisGroup)
        local tempGroupMenu = MENU_COALITION:New(coalition.side.BLUE, "Manage " .. thisGroup:GetName(), groupOptionsMenu)
        local tempROEMenu = MENU_COALITION:New(coalition.side.BLUE, "Set ROE", tempGroupMenu)
        local tempROTMenu = MENU_COALITION:New(coalition.side.BLUE, "Set ROT", tempGroupMenu)
        local tempECMMenu = MENU_COALITION:New(coalition.side.BLUE, "Set ECM Use", tempGroupMenu)
        local tempDeleteMenu = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Delete " .. thisGroup:GetName(), deleteSingleMenu, removeGroup, thisGroup, tempDeleteMenu)
        local menuSet = {tempGroupMenu, tempROEMenu, tempROTMenu, tempECMMenu, tempDeleteMenu}
        for i = 1, #gROETable do
            menuSet[#menuSet + i] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set ROE " .. gROETable[i][1], menuSet[2], setROE, thisGroup, gROETable[i][2])
        end
        for j = 1, #gROTTable do
            menuSet[#menuSet + j] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set ROT " .. gROTTable[j][1], menuSet[3], setROT, thisGroup, gROTTable[j][2])
        end
        for k = 1, #gECMTable do
            menuSet[#menuSet + k] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set ECM Use " .. gECMTable[k][1], menuSet[4], setECMUse, thisGroup, gECMTable[k][2])
        end
        return menuSet
    end

    function buildMenu()

    end

    function buildInterceptTargetMenu()

    end

    function main()
        initSpawnZones()
        buildPresentationMenu()
        return 0
    end

    main()