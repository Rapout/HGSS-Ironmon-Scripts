local save_gui_settings = require("utils/save_gui_settings")
local settings = save_gui_settings.load_settings("configs/gui_settings.cfg")

local config = {
    -- Memory domains
    armDomain = "ARM9 System Bus",
    
    flagBaseAddress = 0x021118A0, -- US: 0x02111880
    flagOffset = 0x10D4,

    -- Inventory addresses
    inventoryPointerAddress = 0x21118A0,  -- Base pointer address in ARM9 System Bus
    inventoryOffsetItems = 0x654,      -- Offset to add to the pointer value to get inventory items start
    --inventoryOffsetMedicine = 0xB74,      -- Offset to add to the pointer value to get inventory medecine start
    --inventoryOffsetPokeballs = 0xD14,      -- Offset to add to the pointer value to get inventory pokeballs start

    flagRopeAlpha = 0x21B,
    flagFalkner = 0x73,
}

-- Item name dictionary mapping item IDs to French names
local itemNames = {
    [78] = "Corde sortie R.Alpha dispo",
    [80] = "Pierresoleil",
    [81] = "Pierre Lune",
    [82] = "Pierre Feu",
    [83] = "Pierrefoudre",
    [84] = "Pierre Eau",
    [85] = "Pierreplante",
    [107] = "Pierre Eclat",
    [108] = "Pierre Nuit",
    [109] = "Pierre Aube",
    [110] = "Pierre Ovale",
    [221] = "Roche Royale",
    [226] = "Dent Ocean",
    [227] = "Ecailleocean",
    [233] = "Peau Metal",
    [235] = "Ecaille Dragon",
    [252] = "Ameliorator",
    [321] = "Protecteur",
    [322] = "Electiriseur",
    [323] = "Magmariseur",
    [324] = "CD Douteux",
    [325] = "Tissu Fauche",
    [326] = "Croc Rasoir",
    [327] = "Grif. Rasoir",
}

-- Evolution items that should be displayed when Falkner flag is not set
local evolutionItems = {80, 81, 82, 83, 84, 85, 107, 108, 109, 110, 221, 226, 227, 233, 235, 252, 321, 322, 323, 324, 325, 326, 327}

-- Shard item IDs (tessons)
local shardItems = {72, 73, 74, 75}

local function checkFlag(flagNumber)
    local flagByteOffset = math.floor(flagNumber / 8)
    local flagBitPosition = flagNumber % 8
    local flagAddress = memory.read_u32_le(config.flagBaseAddress, config.armDomain) + config.flagOffset + flagByteOffset
    local flagByte = memory.read_u8(flagAddress, config.armDomain)
    local flag = (flagByte >> flagBitPosition) & 1
    return flag == 1
end

-- Helper function to display GUI text with consistent positioning
local function displayText(text, yOffset)
    gui.text(10 + settings.x_offset, yOffset + settings.y_offset, text)
end

function readInventory()
    -- Read the pointer from the ARM9 System Bus
    local basePointer = memory.read_u32_le(config.inventoryPointerAddress, config.armDomain)
    if basePointer == 0 or basePointer == nil then
        return
    end
    
    -- Calculate the actual inventory address
    local currentAddress = basePointer + config.inventoryOffsetItems
    local shardCount = 0
    local foundEvolutionItems = {}
    local itemCount = 0
    
    -- Read items until we hit item ID 0
    while true do
        -- Read item ID (2 bytes, little endian)
        local itemId = memory.read_u16_le(currentAddress, config.armDomain)
        
        -- If item ID is 0, we've reached the end
        if itemId == 0 then
            break
        end
  
        -- Read quantity (2 bytes, little endian)
        local quantity = memory.read_u16_le(currentAddress + 2, config.armDomain)
        
        -- Check for special rope item when flag is not set
        if not checkFlag(config.flagRopeAlpha) and itemId == 78 then
            displayText(itemNames[itemId], 280 + 15)
        end

        -- Count shards
        for _, shardId in ipairs(shardItems) do
            if itemId == shardId then
                shardCount = shardCount + quantity
                break
            end
        end

        -- Collect evolution items when Falkner flag is not set
        if not checkFlag(config.flagFalkner) then
            for _, evoItemId in ipairs(evolutionItems) do
                if itemId == evoItemId and itemNames[itemId] then
                    table.insert(foundEvolutionItems, itemNames[itemId])
                    break
                end
            end
        end
        
        itemCount = itemCount + 1
       
        -- Move to next item (4 bytes per item: 2 for ID, 2 for quantity)
        currentAddress = currentAddress + 4
        
        -- Safety check to prevent infinite loops
        if itemCount >= 999 then
            break
        end
    end
    
    -- Display results
    if shardCount > 0 then
        displayText("Tessons : " .. shardCount, 280)
    end
    
    if #foundEvolutionItems > 0 then
        displayText("Items Evolutions : ", 325)
        for i, itemName in ipairs(foundEvolutionItems) do
            displayText(itemName, 340 + (i - 1) * 15)
        end
    end
end

while true do

    local currentRom = gameinfo.getromhash()

    if currentRom ~= "" then
        readInventory()
    end

	emu.frameadvance()
end

