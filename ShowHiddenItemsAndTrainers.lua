local map_to_event = require("mapToEvent/map_to_event")

local config = {
    -- event files directory
    eventDataPath = "eventFiles",
    
    -- Display settings
    itemColor = "yellow",   -- Color for hidden items
    trainerColor = "red",   -- Color for trainers
    
    -- Memory domains
    armDomain = "ARM9 System Bus",


    ratioX = 1,
    ratioY = 1,
    -- Screen offset and scale
    screenXOffset = 705, --Should be the center of the game screen
    screenYOffset = 230, --Should be the center of the game screen
    screenScaleX = 39, --depending on the game size screen
    screenScaleY = 27, --depending on the game size screen
   
    -- Max distance to show items and trainers
    maxDistanceShow = 8,
    showOffscreenItems = true,
    showOffscreenTrainers = true,
}

-- Memory addresses (updated with discovered map ID method)
local addresses = {
    -- Map ID discovery (ARM9 System Bus method)
    mapPointerAddress = 0x21118A0,  -- Pointer location in ARM9 System Bus -- US: 0x2111880
    mapIdOffset = 0x1244,          -- Offset to add to the pointer value
    
    
    -- Player coordinates (ARM9 System Bus method - same pointer as map ID)
    playerXOffset = 0x124C,    
    playerYOffset = 0x1250, 

    flagBaseAddress = 0x021118A0, -- US: 0x02111880
    flagOffset = 0x10D4,

    inFightAddress = 0x02246F48 -- US: 0x02246F28
}

-- Current game state
local gameState = {
    currentMapId = 0,
    currentEventId = 0,
    playerX = 0,
    playerY = 0,
    mapData = nil,
    hiddenItems = {},
    trainers = {},
    -- Caching variables
    lastMapId = -1,
    lastPlayerX = -1,
    lastPlayerY = -1,
    -- Cached screen positions for items and trainers
    cachedItemPositions = {},
    cachedTrainerPositions = {},
    needsRecalculate = false
}

-- DSPRE Event File Structure Constants
local DSPRE_CONSTANTS = {
    -- Event categories in event files (in order)
    -- 1. Spawnables (includes hidden items)
    -- 2. Overworlds (NPCs, trainers, etc.)
    -- 3. Warps
    -- 4. Triggers
    
    -- Event sizes (in bytes) - from EventFile.cs
    SPAWNABLE_SIZE = 0x14,    -- 20 bytes - includes hidden items
    OVERWORLD_SIZE = 0x20,    -- 32 bytes - NPCs, trainers  
    WARP_SIZE = 0xC,          -- 12 bytes
    TRIGGER_SIZE = 0x10,      -- 16 bytes
    
    -- Spawnable types
    SPAWNABLE_TYPE_MISC = 0,
    SPAWNABLE_TYPE_BOARD = 1,
    SPAWNABLE_TYPE_HIDDENITEM = 2,
    
    -- Overworld types
    OVERWORLD_TYPE_NORMAL = 0,
    OVERWORLD_TYPE_TRAINER = 1,
    OVERWORLD_TYPE_ITEM = 3,
    
    -- Map size constant
    MAP_SIZE = 32,           -- mapSize constant used in coordinate calculations
}


function save_settings(settings, filename)
    local file = io.open(filename, "w")
    if file then
        file:write("return " .. string.format("{ ratioX = %f, ratioY = %f }", config.ratioX, config.ratioY))
        file:close()
        return true
    else
        print("Warning: Could not save GUI settings to " .. filename)
        return false
    end
end

function load_settings(filename)
    local ok, settings = pcall(dofile, filename)

    if not ok or settings == nil then
        print("Warning: Failed to load settings, using default values.")
        settings = {ratioX = 1, ratioY = 1}
    end
    
    return settings
end

local function readMapId()
    local mapPointer = memory.read_u32_le(addresses.mapPointerAddress, config.armDomain)
    
    local mapIdAddress = mapPointer + addresses.mapIdOffset
    gameState.currentMapId = memory.read_u16_le(mapIdAddress, config.armDomain)
    
    gameState.currentEventId = map_to_event[gameState.currentMapId] or 0
end

local function readPlayerPosition()
    local basePointer = memory.read_u32_le(addresses.mapPointerAddress, config.armDomain)
    
    local playerXAddress = basePointer + addresses.playerXOffset
    gameState.playerX = memory.read_u16_le(playerXAddress, config.armDomain)
    
    local playerYAddress = basePointer + addresses.playerYOffset
    gameState.playerY = memory.read_u16_le(playerYAddress, config.armDomain)

end

local function readU16LE(data, offset)
    if offset + 1 >= #data then return 0 end
    return data[offset] + (data[offset + 1] * 256)
end

local function readU32LE(data, offset)
    if offset + 3 >= #data then return 0 end
    return data[offset] + (data[offset + 1] * 256) + (data[offset + 2] * 65536) + (data[offset + 3] * 16777216)
end

local function readBinaryFile(filename)
    local file = io.open(filename, "rb")
    if not file then
        return nil
    end
    
    local data = {}
    local byte = file:read(1)
    local index = 0
    
    while byte do
        data[index] = string.byte(byte)
        index = index + 1
        byte = file:read(1)
    end
    
    file:close()
    return data
end

-- Parse event file and extract both hidden items and trainers
local function parseDSPREEventFile(data)
    if not data or #data < 8 then
        return {}, {}
    end
    
    -- Read spawnable count (32-bit)
    local spawnableCount = readU32LE(data, 0)
    
    -- Validate spawnable count makes sense
    local expectedMinSize = 4 + (spawnableCount * DSPRE_CONSTANTS.SPAWNABLE_SIZE)
    if spawnableCount > 1000 or expectedMinSize > #data then
        return {}, {}
    end
    
    local hiddenItems = {}
    local offset = 4 -- Start after the spawnable count (32-bit)
    
    -- Parse Spawnables (focus only on hidden items)
    for i = 0, spawnableCount - 1 do
        if offset + DSPRE_CONSTANTS.SPAWNABLE_SIZE <= #data then
            local scriptNumber = readU16LE(data, offset + 0)
            local spawnableType = readU16LE(data, offset + 2)
            local xPosition = readU16LE(data, offset + 4)
            local unknown2 = readU16LE(data, offset + 6)
            local yPosition = readU16LE(data, offset + 8)
            local zPosition = readU32LE(data, offset + 10)
            local unknown4 = readU16LE(data, offset + 14)
            local dir = readU16LE(data, offset + 16)
            local unknown5 = readU16LE(data, offset + 18)
            
            -- Only process hidden items (type 2)
            if spawnableType == DSPRE_CONSTANTS.SPAWNABLE_TYPE_HIDDENITEM then
                local xMapPosition = xPosition % DSPRE_CONSTANTS.MAP_SIZE
                local xMatrixPosition = math.floor(xPosition / DSPRE_CONSTANTS.MAP_SIZE)
                local yMapPosition = yPosition % DSPRE_CONSTANTS.MAP_SIZE
                local yMatrixPosition = math.floor(yPosition / DSPRE_CONSTANTS.MAP_SIZE)
                
                table.insert(hiddenItems, {
                    x = xPosition,
                    y = yPosition,
                    xMap = xMapPosition,
                    yMap = yMapPosition,
                    xMatrix = xMatrixPosition,
                    yMatrix = yMatrixPosition,
                    scriptNumber = scriptNumber,
                    zPosition = zPosition,
                    dir = dir,
                    itemName = string.format("Script %d", scriptNumber)
                })
            end
        else
            break
        end
        offset = offset + DSPRE_CONSTANTS.SPAWNABLE_SIZE
    end
    
    -- Now parse overworlds for trainers
    local overworldOffset = 4 + (spawnableCount * DSPRE_CONSTANTS.SPAWNABLE_SIZE)
    
    -- Check if we have enough data for overworld count
    if overworldOffset + 4 > #data then
        return hiddenItems, {}
    end
    
    -- Read overworld count
    local overworldCount = readU32LE(data, overworldOffset)
    overworldOffset = overworldOffset + 4
    
    -- Validate overworld count
    local expectedOverworldSize = overworldOffset + (overworldCount * DSPRE_CONSTANTS.OVERWORLD_SIZE)
    if overworldCount > 1000 or expectedOverworldSize > #data then
        return hiddenItems, {}
    end
    
    local trainers = {}
    
    -- Parse Overworlds (look for trainers only)
    for i = 0, overworldCount - 1 do
        if overworldOffset + DSPRE_CONSTANTS.OVERWORLD_SIZE <= #data then
            local owID = readU16LE(data, overworldOffset + 0)
            local overlayTableEntry = readU16LE(data, overworldOffset + 2)
            local movement = readU16LE(data, overworldOffset + 4)
            local overworldType = readU16LE(data, overworldOffset + 6)
            local flag = readU16LE(data, overworldOffset + 8)
            local scriptNumber = readU16LE(data, overworldOffset + 10)
            local orientation = readU16LE(data, overworldOffset + 12)
            local sightRange = readU16LE(data, overworldOffset + 14)
            local unknown1 = readU16LE(data, overworldOffset + 16)
            local unknown2 = readU16LE(data, overworldOffset + 18)
            local xRange = readU16LE(data, overworldOffset + 20)
            local yRange = readU16LE(data, overworldOffset + 22)
            local xPosition = readU16LE(data, overworldOffset + 24)
            local yPosition = readU16LE(data, overworldOffset + 26)
            local zPosition = readU32LE(data, overworldOffset + 28)
            
            -- Only process trainers (type 1)
            if overworldType == DSPRE_CONSTANTS.OVERWORLD_TYPE_TRAINER then
                local xMapPosition = xPosition % DSPRE_CONSTANTS.MAP_SIZE
                local xMatrixPosition = math.floor(xPosition / DSPRE_CONSTANTS.MAP_SIZE)
                local yMapPosition = yPosition % DSPRE_CONSTANTS.MAP_SIZE
                local yMatrixPosition = math.floor(yPosition / DSPRE_CONSTANTS.MAP_SIZE)
                
                table.insert(trainers, {
                    x = xPosition,
                    y = yPosition,
                    xMap = xMapPosition,
                    yMap = yMapPosition,
                    xMatrix = xMatrixPosition,
                    yMatrix = yMatrixPosition,
                    owID = owID,
                    overlayTableEntry = overlayTableEntry,
                    movement = movement,
                    flag = flag,
                    scriptNumber = scriptNumber,
                    orientation = orientation,
                    sightRange = sightRange,
                    zPosition = zPosition,
                    trainerInfo = string.format("Trainer ID %d", owID)
                })
            end
        else
            break
        end
        overworldOffset = overworldOffset + DSPRE_CONSTANTS.OVERWORLD_SIZE
    end
    
    return hiddenItems, trainers
end

local function loadMapData(mapId)
    local eventId = map_to_event[mapId] or 0
    
    if eventId == 0 then
        return {
            hiddenItems = {},
            trainers = {},
            eventId = 0,
            eventFilePath = "No events"
        }
    end
    
    local eventFileName = string.format("%04d", eventId)
    local eventFilePath = config.eventDataPath .. "/" .. eventFileName
    
    local eventData = readBinaryFile(eventFilePath)
    if eventData then
        local hiddenItems, trainers = parseDSPREEventFile(eventData)
        return {
            hiddenItems = hiddenItems,
            trainers = trainers,
            eventId = eventId,
            eventFilePath = eventFileName
        }
    else
        return {
            hiddenItems = {},
            trainers = {},
            eventId = eventId,
            eventFilePath = "File not found: " .. eventFileName
        }
    end
end


local function checkFlag(flagNumber)
    local flagByteOffset = math.floor(flagNumber / 8)
    local flagBitPosition = flagNumber % 8
    local flagAddress = memory.read_u32_le(addresses.flagBaseAddress, config.armDomain) + addresses.flagOffset + flagByteOffset
    local flagByte = memory.read_u8(flagAddress, config.armDomain)
    local flag = (flagByte >> flagBitPosition) & 1
    return flag == 1
end

local function isHiddenItemCollected(itemScript)
    local itemId = itemScript - 8000
    local flagNumber = 800 + itemId
    return checkFlag(flagNumber)
end

local function isTrainerDefeated(trainerScript)
    local trainerId = trainerScript - 3000 + 1
    local flagNumber = 0x550 + trainerId
    return checkFlag(flagNumber)
end
    
-- Calculate screen positions for items and trainers (only when player moves)
local function calculatePositions()
    gameState.cachedItemPositions = {}
    gameState.cachedTrainerPositions = {}
    
    if gameState.hiddenItems then
        for i, item in ipairs(gameState.hiddenItems) do

            local deltaX = item.x - gameState.playerX
            local deltaY = item.y - gameState.playerY
            
            if not config.showOffscreenItems and (math.abs(deltaX) > config.maxDistanceShow or math.abs(deltaY) > config.maxDistanceShow) then
                --skip this item
            else

                if math.abs(deltaX) > config.maxDistanceShow then
                    deltaX = config.maxDistanceShow * deltaX / math.abs(deltaX)
                end
                if math.abs(deltaY) > config.maxDistanceShow then
                    deltaY = config.maxDistanceShow * deltaY / math.abs(deltaY)
                end

                local screenX = config.screenXOffset + (deltaX * config.screenScaleX)  -- Scale up for visibility
                local screenY = config.screenYOffset + (deltaY * config.screenScaleY) -- Scale up for visibility
                
                if(screenY < 0) then
                    screenY = screenY+10
                end

                table.insert(gameState.cachedItemPositions, {
                    screenX = screenX,
                    screenY = screenY,
                    item = item            
                })
            end
        end
    end
    
    if gameState.trainers then
    for i, trainer in ipairs(gameState.trainers) do

            local deltaX = trainer.x - gameState.playerX
            local deltaY = trainer.y - gameState.playerY
            
            if not config.showOffscreenTrainers and (math.abs(deltaX) > config.maxDistanceShow or math.abs(deltaY) > config.maxDistanceShow) then
                --skip this trainer
            else

                if math.abs(deltaX) > config.maxDistanceShow then
                    deltaX = config.maxDistanceShow * deltaX / math.abs(deltaX)
                end
                if math.abs(deltaY) > config.maxDistanceShow then
                    deltaY = config.maxDistanceShow * deltaY / math.abs(deltaY)
                end
                local screenX = config.screenXOffset + (deltaX * config.screenScaleX)  -- Scale up for visibility
                local screenY = config.screenYOffset + (deltaY * config.screenScaleY)   -- Scale up for visibility
                
                if(screenY < 0) then
                    screenY = screenY+10
                end

                table.insert(gameState.cachedTrainerPositions, {
                    screenX = screenX,
                    screenY = screenY,
                    trainer = trainer            
                })
            end
        end
    end
end

local function updateMapData()
    -- Only load map data if map ID changed
    if gameState.currentMapId ~= gameState.lastMapId then
        gameState.mapData = loadMapData(gameState.currentMapId)
        if gameState.mapData then
            gameState.mapData.mapId = gameState.currentMapId
            gameState.hiddenItems = gameState.mapData.hiddenItems or {}
            gameState.trainers = gameState.mapData.trainers or {}
        end
        gameState.lastMapId = gameState.currentMapId
        calculatePositions()
    end
end

local function drawHiddenItems()
    if not gameState.cachedItemPositions then 
        return 
    end
    
    for _, cachedItem in ipairs(gameState.cachedItemPositions) do
        if not isHiddenItemCollected(cachedItem.item.scriptNumber) then
            gui.text(cachedItem.screenX, cachedItem.screenY, "o", config.itemColor)
        end
    end
end

local function drawTrainers()
    if not gameState.cachedTrainerPositions then 
        return 
    end
    
    for _, cachedTrainer in ipairs(gameState.cachedTrainerPositions) do
        if not checkFlag(cachedTrainer.trainer.flag) and not isTrainerDefeated(cachedTrainer.trainer.scriptNumber) then
            gui.text(cachedTrainer.screenX, cachedTrainer.screenY, "o", config.trainerColor)
        end
    end
end


local function isInFight()

    local inFight = memory.read_u16_le(addresses.inFightAddress, config.armDomain)
    return inFight == 0x2100 or inFight == 0x2101 or inFight == 0xF7F3
end

local function update()

    if isInFight() then
        return
    end

    local mapSuccess, mapError = pcall(readMapId)
    if not mapSuccess then
        gui.text(10, 10, "Error reading map ID: " .. tostring(mapError), "red")
        return
    end
    
    local posSuccess, posError = pcall(readPlayerPosition)
    if not posSuccess then
        gui.text(10, 25, "Error reading position: " .. tostring(posError), "orange")
    end
    
    if gameState.needsRecalculate or gameState.playerX ~= gameState.lastPlayerX or gameState.playerY ~= gameState.lastPlayerY then
        gameState.lastPlayerX = gameState.playerX
        gameState.lastPlayerY = gameState.playerY
        calculatePositions()
        gameState.needsRecalculate = false
    end
    
    updateMapData()
    
    drawHiddenItems()  
    drawTrainers()    

end


local function calculateScreenOffsets()
    local centerTransformed = client.transformPoint(client.bufferwidth()/2, -client.bufferheight()/2)

    local bottomRightTransformed = client.transformPoint(client.bufferwidth(), 0)
    config.screenScaleX = math.abs(bottomRightTransformed.x - centerTransformed.x)/8 * config.ratioX
    config.screenScaleY = math.abs(bottomRightTransformed.y - centerTransformed.y)/16 * config.ratioY

    local topLeftTransformed = client.transformPoint(0, -client.bufferheight())
    config.screenXOffset = (centerTransformed.x -6) *config.ratioX 

    config.screenYOffset = (centerTransformed.y + client.borderheight() -30)*config.ratioY/2
    gameState.needsRecalculate = true
end

local recalculateOffsets = true
local calibrateMode = false
local save_message = ""
local save_message_timer = 0
local function calibrate()
    gui.text(10, 75, "Calibrage :", "red")
    gui.text(10, 100, "Utiliser les fleches directionnelles pour deplacer le point vert au milieu de l'ecran (sur le personnage principal)", "red")
    gui.text(10, 125, "Entree pour sauvegarder", "red")
    gui.text(config.screenXOffset, config.screenYOffset, "o", "green")
    local inputs = input.get()
    if inputs.Down then
        config.ratioY = config.ratioY + 0.001
        recalculateOffsets = true
    end
    if inputs.Up then
        config.ratioY = config.ratioY - 0.001
        recalculateOffsets = true
    end

    if inputs.Left then
        config.ratioX = config.ratioX - 0.001
        recalculateOffsets = true
    end
    if inputs.Right then
        config.ratioX = config.ratioX + 0.001
        recalculateOffsets = true
    end

    if inputs.Enter then 
        if save_settings(config, "configs/show_hidden_item_settings.cfg") then
            save_message = "Settings saved!"
            save_message_timer = 60  -- Show message for 60 frames
        else
            save_message = "Failed to save settings"
            save_message_timer = 60
        end
    end

    if save_message_timer > 0 then
        gui.text(10, 10, save_message, "yellow")
        save_message_timer = save_message_timer - 1
    end
    
end

local settings = load_settings("configs/show_hidden_item_settings.cfg")
config.ratioX = settings.ratioX
config.ratioY = settings.ratioY

local previousScreenWidth = client.screenwidth()
local previousScreenHeight = client.screenheight()
local previousScreenBorderHeight = client.borderheight()
local previousScreenBorderWidth = client.borderwidth()
local lastInputFrame = 0
while true do
    local currentRom = gameinfo.getromhash()

    if currentRom ~= "" then
        local inputs = input.get()
        if inputs.R and lastInputFrame <= 0 then
            lastInputFrame = 10 --wait 10 frames before accepting another input
            calibrateMode = not calibrateMode
        else
            lastInputFrame = lastInputFrame - 1
        end

        if calibrateMode then
            calibrate()
        end

        if recalculateOffsets then
            calculateScreenOffsets()
            recalculateOffsets = false
        end

        local currentScreenWidth = client.screenwidth()
        local currentScreenHeight = client.screenheight()
        local currentScreenBorderHeight = client.borderheight()
        local currentScreenBorderWidth = client.borderwidth()
        if currentScreenWidth ~= previousScreenWidth or currentScreenHeight ~= previousScreenHeight or currentScreenBorderHeight ~= previousScreenBorderHeight or currentScreenBorderWidth ~= previousScreenBorderWidth then
            calculateScreenOffsets()
            previousScreenWidth = currentScreenWidth
            previousScreenHeight = currentScreenHeight
            previousScreenBorderHeight = currentScreenBorderHeight
            previousScreenBorderWidth = currentScreenBorderWidth
            recalculateOffsets = true  --delay the recalculation to next frame, otherwise it doesn't work
        end

        update()
    end
    emu.frameadvance()
end