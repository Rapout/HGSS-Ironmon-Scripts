local PokemonReader = {}

-- Monte Carlo configuration
local MONTE_CARLO_TOTAL_ITERATIONS = 10000  -- Total iterations per calculation
local MONTE_CARLO_ITERATIONS_PER_FRAME = 500  -- Iterations per frame to prevent lag

-- Persistence configuration
local savedDataFolder = "savedData"
local MAX_SAVED_POKEMON = 10  -- Maximum number of Pokemon to keep in save file

local GAME_INFO = {
    GEN = 4,
    ENCRYPTED_POKEMON_SIZE = 236
}

local ADDRESSES = {
    GLOBAL_POINTER = 0xBA8,
    VERSION_POINTER_OFFSET = 0x20,
    VERSION_POINTER_OFFSETS = {
        playerBase = 0xA8
    }
}


local domain = "Main RAM"

local CHAR_MAP = {
    [0x0000] = " ",
    [0x0121] = "0", [0x0122] = "1", [0x0123] = "2", [0x0124] = "3", [0x0125] = "4",
    [0x0126] = "5", [0x0127] = "6", [0x0128] = "7", [0x0129] = "8", [0x012A] = "9",
    [0x012B] = "A", [0x012C] = "B", [0x012D] = "C", [0x012E] = "D", [0x012F] = "E",
    [0x0130] = "F", [0x0131] = "G", [0x0132] = "H", [0x0133] = "I", [0x0134] = "J",
    [0x0135] = "K", [0x0136] = "L", [0x0137] = "M", [0x0138] = "N", [0x0139] = "O",
    [0x013A] = "P", [0x013B] = "Q", [0x013C] = "R", [0x013D] = "S", [0x013E] = "T",
    [0x013F] = "U", [0x0140] = "V", [0x0141] = "W", [0x0142] = "X", [0x0143] = "Y",
    [0x0144] = "Z", [0x0145] = "a", [0x0146] = "b", [0x0147] = "c", [0x0148] = "d",
    [0x0149] = "e", [0x014A] = "f", [0x014B] = "g", [0x014C] = "h", [0x014D] = "i",
    [0x014E] = "j", [0x014F] = "k", [0x0150] = "l", [0x0151] = "m", [0x0152] = "n",
    [0x0153] = "o", [0x0154] = "p", [0x0155] = "q", [0x0156] = "r", [0x0157] = "s",
    [0x0158] = "t", [0x0159] = "u", [0x015A] = "v", [0x015B] = "w", [0x015C] = "x",
    [0x015D] = "y", [0x015E] = "z", [0x01DE] = " "
}

local CONSTANTS = {
    GEN = GAME_INFO.GEN,
    POKEMON_DATA_SIZE = GAME_INFO.ENCRYPTED_POKEMON_SIZE,
    BLOCK_TOTAL = 4,
    BLOCK_SIZE = 32,
    BLOCK_SHUFFLE_ORDER = {
        "ABCD", "ABDC", "ACBD", "ACDB", "ADBC", "ADCB",
        "BACD", "BADC", "BCAD", "BCDA", "BDAC", "BDCA",
        "CABD", "CADB", "CBAD", "CBDA", "CDAB", "CDBA",
        "DABC", "DACB", "DBAC", "DBCA", "DCAB", "DCBA"
    },
    IMPORTANT_BLOCK_DATA = {
        A = {
            {0, {"pokemonID"}},
            {2, {"heldItem"}},
            {4, {"trainerID"}},
            {8, {"experience1"}},
            {10, {"experience2"}},
            {12, {"friendship", "ability"}},
            {16, {"HP_EV", "ATK_EV"}},
            {18, {"DEF_EV", "SPE_EV"}},
            {20, {"SPA_EV", "SPD_EV"}}
        },
        B = {
            {0, {"move1"}},
            {2, {"move2"}},
            {4, {"move3"}},
            {6, {"move4"}},
            {8, {"move1PP", "move2PP"}},
            {10, {"move3PP", "move4PP"}},
            {16, {"ivData1"}},
            {18, {"ivData2"}},
            {24, {"alternateForm", "nature"}}
        },
        C = {
            {0, "Nickname"}
        },
        D = {
            {28, {"unused", "encounterType"}}
        }
    },
    BATTLE_STAT_OFFSETS = {
        {0, {"status", "unused"}},
        {4, {"level", "unused"}},
        {6, {"curHP"}},
        {8, {"HP"}},
        {10, {"ATK"}},
        {12, {"DEF"}},
        {14, {"SPE"}},
        {16, {"SPA"}},
        {18, {"SPD"}}
    }
}

local function mult32(a, b)
    return (a * b) % 4294967296
end

local function getBits(value, startBit, numBits)
    local mask = (2^numBits) - 1
    return bit.band(bit.rshift(value, startBit), mask)
end

local function createPokemonReader()
    local decryptedData = {}
    local seed = 0
    local pid = 0
    local currentBase = 0

    local function advanceRNG()
        seed = mult32(seed, 0x41C64E6D) + 0x00006073
    end

    local function advanceRNGByDifference(difference)
        for _ = 1, difference, 2 do
            advanceRNG()
        end
    end

    local function combineBytes(byte1, byte2)
        local combinedBytes = bit.band(byte2, 0x00FF)
        combinedBytes = bit.lshift(combinedBytes, 8)
        combinedBytes = bit.bor(combinedBytes, byte1)
        return combinedBytes
    end

    local function bytesFromWord(encryptedWord)
        local encryptedByte1 = bit.band(encryptedWord, 0xFF)
        local encryptedByte2 = bit.band(bit.rshift(encryptedWord, 8), 0xFF)

        local shift16 = bit.rshift(seed, 16)
        local shift24 = bit.rshift(seed, 24)

        local byte1Data = bit.bxor(encryptedByte1, bit.band(shift16, 0xFF))
        byte1Data = bit.band(byte1Data, 0xFF)

        local byte2Data = bit.bxor(encryptedByte2, bit.band(shift24, 0xFF))
        byte2Data = bit.band(byte2Data, 0xFF)
        
        return {
            byte1 = byte1Data,
            byte2 = byte2Data
        }
    end

    local function decryptWord(offsetData, address)
        local offsetAmount = offsetData[1]
        local dataName = offsetData[2]
        local shouldCombineBytes = (#dataName == 1)
        local encryptedWord = memory.read_u16_le(address + offsetAmount, domain)
        local byteData = bytesFromWord(encryptedWord)
        local byte1Data, byte2Data = byteData.byte1, byteData.byte2
        
        if dataName[1] == "isEgg" then
            decryptedData[dataName[1]] = getBits(byte2Data, 6, 1)
        elseif shouldCombineBytes then
            decryptedData[dataName[1]] = combineBytes(byte1Data, byte2Data)
        else
            decryptedData[dataName[1]] = byte1Data
            if dataName[2] ~= "nature" then
                decryptedData[dataName[2]] = byte2Data
            end
            if dataName[1] == "alternateForm" then
                decryptedData["isFemale"] = getBits(byte1Data, 1, 1)
            else
                decryptedData[dataName[2]] = byte2Data
            end
        end
    end

    local function decryptNickname(nicknameStart)
        local done = false
        local completeName = ""
        for i = 0, 24, 2 do
            if not done then
                local encryptedWord = memory.read_u16_le(nicknameStart + i, domain)
                local byteData = bytesFromWord(encryptedWord)
                local combined = combineBytes(byteData.byte1, byteData.byte2)
                if combined == 0xFFFF then
                    done = true
                else
                    local char = ""
                    if CHAR_MAP[combined] then
                        char = CHAR_MAP[combined]
                    end
                    completeName = completeName .. char
                end
            end
            advanceRNG()
        end
        decryptedData["nickname"] = completeName
        return 26
    end

    local function decryptBlocks(blockReadingStart, blockOrder)
        for i = 0, CONSTANTS.BLOCK_TOTAL - 1, 1 do
            local currentBlockStart = blockReadingStart + (CONSTANTS.BLOCK_SIZE * i)
            local totalBytesAdvanced = 0
            local currentBlockLetter = string.sub(blockOrder, i + 1, i + 1)
            local offsets = CONSTANTS.IMPORTANT_BLOCK_DATA[currentBlockLetter]
            local previousOffset = 0
            
            advanceRNG()
            totalBytesAdvanced = totalBytesAdvanced + 2
            
            if offsets ~= nil then
                for _, offsetData in ipairs(offsets) do
                    local offsetAmount = offsetData[1]
                    local difference = offsetAmount - previousOffset
                    advanceRNGByDifference(difference)
                    totalBytesAdvanced = totalBytesAdvanced + difference
                    
                    if offsetData[2] == "Nickname" then
                        totalBytesAdvanced = totalBytesAdvanced + decryptNickname(currentBlockStart)
                    else
                        decryptWord(offsetData, currentBlockStart)
                    end
                    previousOffset = offsetAmount
                end
            end
            
            local remainder = CONSTANTS.BLOCK_SIZE - totalBytesAdvanced
            for _ = 2, remainder, 2 do
                advanceRNG()
            end
        end
    end

    local function decryptBattleStats(battleStatStart)
        local offsets = CONSTANTS.BATTLE_STAT_OFFSETS
        local previousOffset = 0
        seed = pid
        advanceRNG()
        
        if offsets ~= nil then
            for _, offsetData in ipairs(offsets) do
                local offsetAmount = offsetData[1]
                local difference = offsetAmount - previousOffset
                advanceRNGByDifference(difference)
                decryptWord(offsetData, battleStatStart)
                previousOffset = offsetAmount
            end
        end
    end

    local function formatData()
        decryptedData.moveIDs = {
            decryptedData.move1,
            decryptedData.move2,
            decryptedData.move3,
            decryptedData.move4
        }
        decryptedData.stats = {
            HP = decryptedData.HP,
            ATK = decryptedData.ATK,
            DEF = decryptedData.DEF,
            SPA = decryptedData.SPA,
            SPD = decryptedData.SPD,
            SPE = decryptedData.SPE
        }
        decryptedData.EVs = {
            HP = decryptedData.HP_EV,
            ATK = decryptedData.ATK_EV,
            DEF = decryptedData.DEF_EV,
            SPA = decryptedData.SPA_EV,
            SPD = decryptedData.SPD_EV,
            SPE = decryptedData.SPE_EV
        }
        
        if decryptedData.ivData1 and decryptedData.ivData2 then
            local ivValue = decryptedData.ivData1 + (decryptedData.ivData2 * 65536)
            decryptedData.IVs = {
                HP = getBits(ivValue, 0, 5),
                ATK = getBits(ivValue, 5, 5),
                DEF = getBits(ivValue, 10, 5),
                SPE = getBits(ivValue, 15, 5),
                SPA = getBits(ivValue, 20, 5),
                SPD = getBits(ivValue, 25, 5)
            }
        end
        
    end

    -- Public functions
    local reader = {}


    function reader.getPlayerPokemonAddress()
        local globalPtr = ADDRESSES.GLOBAL_POINTER
        local globalPtrAddr = memory.read_u32_le(globalPtr, domain)
        globalPtrAddr = bit.band(globalPtrAddr, 0xFFFFFF)
        local versionPtr = globalPtrAddr + ADDRESSES.VERSION_POINTER_OFFSET
        local versionPtrAddr = memory.read_u32_le(versionPtr, domain)
        versionPtrAddr = bit.band(versionPtrAddr, 0xFFFFFF)
        return versionPtrAddr + ADDRESSES.VERSION_POINTER_OFFSETS.playerBase
    end

    function reader.decryptPokemonInfo(pokemonBaseAddress)
        decryptedData = {}
        currentBase = pokemonBaseAddress or currentBase
        
        if currentBase == 0 then
            return {}
        end

        pid = memory.read_u32_le(currentBase, domain)
        local checksum = memory.read_u16_le(currentBase + 0x06, domain)
        
        if checksum == 0 then
            return {}
        end

        decryptedData["pid"] = pid
        decryptedData.nature = (pid % 25)
        
        local blockShift = bit.rshift(bit.band(pid, 0x3E000), 0xD) % 24
        local blockOrder = CONSTANTS.BLOCK_SHUFFLE_ORDER[blockShift + 1]
        local blockReadingStart = currentBase + 0x08
        
        seed = checksum
        decryptBlocks(blockReadingStart, blockOrder)
        
        local battleStatStart = currentBase + 0x88
        decryptBattleStats(battleStatStart)
        
        formatData()
        
        if not decryptedData.moveIDs or #decryptedData.moveIDs == 0 then
            return {}
        end

        return decryptedData
    end


    return reader
end

local function getIVColor(averageIV)
    if averageIV < 6 then
        return "red"           
    elseif averageIV < 13 then
        return "orange"        
    elseif averageIV < 20 then
        return "yellow"        
    elseif averageIV < 27 then
        return "lime"          
    else
        return "green"         
    end
end

local function getBSTColor(BST)
    if BST < 400 then
        return "red"           
    elseif BST < 450 then
        return "orange"        
    elseif BST < 500 then
        return "yellow"        
    elseif BST < 550 then
        return "lime"          
    else
        return "green"         
    end
end

local function validPokemonData(pokemonData)
    if pokemonData == nil or next(pokemonData) == nil then
        return false
    end
    
    local STAT_LIMIT = 2000
    local statsToCheck = {}
    
    if pokemonData.curHP then
        table.insert(statsToCheck, pokemonData.curHP)
    end
    
    if pokemonData.stats then
        if pokemonData.stats.HP then table.insert(statsToCheck, pokemonData.stats.HP) end
        if pokemonData.stats.ATK then table.insert(statsToCheck, pokemonData.stats.ATK) end
        if pokemonData.stats.SPE then table.insert(statsToCheck, pokemonData.stats.SPE) end
        if pokemonData.stats.DEF then table.insert(statsToCheck, pokemonData.stats.DEF) end
        if pokemonData.stats.SPD then table.insert(statsToCheck, pokemonData.stats.SPD) end
        if pokemonData.stats.SPA then table.insert(statsToCheck, pokemonData.stats.SPA) end
    end
    
    for _, stat in pairs(statsToCheck) do
        if stat and stat > STAT_LIMIT then
            return false
        end
    end
    
    local id = tonumber(pokemonData.pokemonID)
    if id == nil or id < 0 or id > 493 then
        return false
    end
    
    if pokemonData.level and pokemonData.level > 100 then
        return false
    end
    
    return true
end

local function calculateHiddenPower(pokemonData)
        local a = (pokemonData.IVs.HP   % 4 >= 2) and 1   or 0
        local b = (pokemonData.IVs.ATK  % 4 >= 2) and 2   or 0
        local c = (pokemonData.IVs.DEF  % 4 >= 2) and 4   or 0
        local d = (pokemonData.IVs.SPE  % 4 >= 2) and 8   or 0
        local e = (pokemonData.IVs.SPA % 4 >= 2) and 16 or 0
        local f = (pokemonData.IVs.SPD % 4 >= 2) and 32 or 0
    
        local power_value = math.floor(((a + b + c + d + e + f) * 40) / 63 + 30)
        a = (pokemonData.IVs.HP   % 2 == 1) and 1   or 0
        b = (pokemonData.IVs.ATK  % 2 == 1) and 2   or 0
        c = (pokemonData.IVs.DEF  % 2 == 1) and 4   or 0
        d = (pokemonData.IVs.SPE  % 2 == 1) and 8   or 0
        e = (pokemonData.IVs.SPA % 2 == 1) and 16 or 0
        f = (pokemonData.IVs.SPD % 2 == 1) and 32 or 0
    
        local type_value = math.floor(((a + b + c + d + e + f) * 15) / 63)
    
        local types = {
            "Combat", "Vol", "Poison", "Sol", "Roche",
            "Insecte", "Spectre", "Acier", "Feu", "Eau",
            "Plante", "Electrik", "Psy", "Glace", "Dragon", "Tenebres"
        }

        local type_color = {
            "orange", "lightblue", "purple", "brown", "gray",
            "lightgreen", "darkviolet", "silver", "red", "blue",
            "green", "yellow", "magenta", "cyan", "darkblue", "dimgray"
        }
    
        local type_name = types[type_value + 1] 
    
        return power_value, type_name, type_color[type_value + 1]
end

local function getLoadedRomPath()
	local luaconsole = client.gettool("luaconsole")
	local luaImp = luaconsole and luaconsole.get_LuaImp()
	local filepath = luaImp and luaImp.PathEntries and luaImp.PathEntries.LastRomPath or ""
	if filepath ~= "" then
		return filepath
	end
	return nil
end

local function readLinesFromFile(filePath)
    local lines = {}
    local file = io.open(filePath, "r")
    if file == nil then
        return lines
    end

    for line in file:lines() do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    file:close()
    return lines
end

local function trimWhitespace(input)
    return input:gsub("^%s*(.-)%s*$", "%1")
end


local function split(s, delimiter, doTrimWhitespace)
    local result = {}
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        if doTrimWhitespace then
            match = trimWhitespace(match)
        end
        table.insert(result, match)
    end
    return result
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file ~= nil then
        io.close(file)
        return true
    else
        return false
    end
end

local function ensureDirectoryExists(dirPath)
    os.execute("mkdir \"" .. dirPath .. "\" 2>nul")
end

local function parseAllBSTFromLogFile(logFilePath)
	if not logFilePath or not fileExists(logFilePath) then
		return {}
	end
	
	local lines = readLinesFromFile(logFilePath)
	if not lines or #lines == 0 then
		return {}
	end
	local pokemonSectionStart = nil
	for i, line in pairs(lines) do
		if line == "--Pokemon Base Stats & Types--" then
			pokemonSectionStart = i + 1
			break
		end
	end
	
	if not pokemonSectionStart then
		return {}
	end
	
	local bstLookup = {}
	local currentLineIndex = pokemonSectionStart + 1
	
	while currentLineIndex <= #lines do
		local line = lines[currentLineIndex]
		if not line or line == "" then
			break
		end
		
		local pokemonData = split(line, "|", true)
		local pokemonID = tonumber(pokemonData[1])
		
		if pokemonID then
			local hp = tonumber(pokemonData[4])
			local atk = tonumber(pokemonData[5])
			local def = tonumber(pokemonData[6])
			local spa = tonumber(pokemonData[7])
			local spd = tonumber(pokemonData[8])
			local spe = tonumber(pokemonData[9])
			
			if hp and atk and def and spa and spd and spe then
				bstLookup[pokemonID] = hp + atk + def + spa + spd + spe
			end
		end
		currentLineIndex = currentLineIndex + 1
	end
	
	return bstLookup
end

local pokemon_base_stats

local function InitBST()
	local romName = gameinfo.getromname()
	local safeRomName = romName:gsub(" ", "_")

    local logFilePath = getLoadedRomPath() .. "\\" .. safeRomName .. ".nds.log"
    console.log("Loading BST from log file: " .. logFilePath)
    pokemon_base_stats = parseAllBSTFromLogFile(logFilePath)

    if pokemon_base_stats == nil or pokemon_base_stats == {} or next(pokemon_base_stats) == nil then
        pokemon_base_stats = require("utils/pokemon_base_stats")
        console.log("Failed to load BST from log file, using default BST")
    else
        console.log("Successfully loaded BST from log file")
    end
end

local pokemon_nature = require("utils/pokemon_nature")
local statNames = {"HP","ATK","DEF","SPA","SPD","SPE"}

-- Monte Carlo state for non-blocking calculation
local monteCarloState = {
    active = false,
    pokemonData = nil,
    completedIterations = 0,
    samples = {},
    targetIterations = 0
}

local function generateBaseSpread(estimate, totalBase)
    local perturbed = {}
    local sum = 0
    for _, stat in ipairs(statNames) do
        local v = math.max(1, estimate[stat] + math.random(-3, 3)) -- small wiggle
        perturbed[stat] = v
        sum = sum + v
    end
    local scale = totalBase / sum
    sum = 0
    for _, stat in ipairs(statNames) do
        perturbed[stat] = math.max(1, math.floor(perturbed[stat] * scale + 0.5))
        sum = sum + perturbed[stat]
    end
    while sum < totalBase do
        local s = statNames[math.random(#statNames)]
        perturbed[s] = perturbed[s] + 1
        sum = sum + 1
    end
    while sum > totalBase do
        local s = statNames[math.random(#statNames)]
        if perturbed[s] > 1 then
            perturbed[s] = perturbed[s] - 1
            sum = sum - 1
        end
    end
    return perturbed
end

local function matchingIVs(statName, observed, base, ev, level, nature)
    local valid = {}
    if statName == "HP" then
        for iv = 0, 31 do
            local calc = math.floor(((2 * base + iv + math.floor(ev / 4) + 100) * level) / 100) + 10
            if calc == observed then
                table.insert(valid, iv)
            end
        end
    else
        for iv = 0, 31 do
            local raw = math.floor(((2 * base + iv + math.floor(ev / 4)) * level) / 100) + 5
            raw = math.floor(raw * nature)
            if raw == observed then
                table.insert(valid, iv)
            end
        end
    end
    return valid
end

local function startMonteCarloCalculation(pokemonData)
    monteCarloState.active = true
    monteCarloState.pokemonData = pokemonData
    monteCarloState.completedIterations = 0
    monteCarloState.samples = {}
    monteCarloState.targetIterations = MONTE_CARLO_TOTAL_ITERATIONS
end

local function processMonteCarloFrame()
    if not monteCarloState.active then
        return false
    end
    
    local pokemonData = monteCarloState.pokemonData
    local nature = pokemon_nature[pokemonData.nature]
    local totalBaseStats = pokemon_base_stats[pokemonData.pokemonID]
    local level = pokemonData.level
    local stats = pokemonData.stats
    local evs = pokemonData.EVs

    if not stats or not evs or not level or not nature or not totalBaseStats then
        monteCarloState.active = false
        return true
    end
    local estimate = {}
    estimate.HP = (((stats.HP - 10 - level) * 100) / level - math.floor(evs.HP / 4)) / 2
    for _, statName in ipairs({"ATK", "DEF", "SPA", "SPD", "SPE"}) do
        estimate[statName] = (((stats[statName] / nature[statName] - 5) * 100) / level - math.floor(evs[statName] / 4)) / 2
    end

    local iterationsThisFrame = math.min(MONTE_CARLO_ITERATIONS_PER_FRAME, 
                                        monteCarloState.targetIterations - monteCarloState.completedIterations)
    
    for i = 1, iterationsThisFrame do
        local baseSpread = generateBaseSpread(estimate, totalBaseStats)
        local totalIV = 0
        local valid = true

        for _, statName in ipairs(statNames) do
            local possible = matchingIVs(statName, stats[statName], baseSpread[statName], evs[statName], level, nature[statName])
            if #possible == 0 then
                valid = false
                break
            end
            totalIV = totalIV + possible[math.random(#possible)]
        end

        if valid then
            local avgIV = totalIV / 6
            table.insert(monteCarloState.samples, avgIV)
        end
        
        monteCarloState.completedIterations = monteCarloState.completedIterations + 1
    end

    if monteCarloState.completedIterations >= monteCarloState.targetIterations then
        monteCarloState.active = false
        return true
    end
    
    return false
end

local function getMonteCarloResults()
    local pokemonData = monteCarloState.pokemonData
    local samples = monteCarloState.samples
    
    if #samples == 0 then
        local totalBaseStats = pokemon_base_stats[pokemonData.pokemonID] or 0
        return {BST = totalBaseStats, EstimatedPower = totalBaseStats, EstimatedAverageIVs = 0, MinIV = 0, MaxIV = 31}
    end

    table.sort(samples)
    
    local avgIV = 0
    for _, sample in ipairs(samples) do
        avgIV = avgIV + sample
    end
    avgIV = avgIV / #samples
    
    local minIndex = math.max(1, math.floor(#samples * 0.025))
    local maxIndex = math.min(#samples, math.ceil(#samples * 0.975))
    local minIV = samples[minIndex]
    local maxIV = samples[maxIndex]
    
    local totalBaseStats = pokemon_base_stats[pokemonData.pokemonID] or 0
    
    return {
        BST = totalBaseStats, 
        EstimatedPower = totalBaseStats + avgIV * 3, 
        EstimatedAverageIVs = avgIV,
        MinIV = minIV,
        MaxIV = maxIV
    }
end

PokemonReader = createPokemonReader()

local save_gui_settings = require("utils/save_gui_settings")
local show_iv_settings = save_gui_settings.load_settings("configs/show_iv_settings.cfg")
local settings = save_gui_settings.load_settings("configs/gui_settings.cfg")

local lastValidPokemonData = nil
local showIvs = false
local last_press = false

local averageIV = 0
local estimatedPower = 0
local previousLevel = 0
local previousPID = 0
local BST = 0

local currentIntervalEstimate = nil

local intervalData = {}
local function getIntervalKey(pokemonData)
    return tostring(pokemonData.pid)
end

local function saveIntervalData()
    ensureDirectoryExists(savedDataFolder)
    local saveFilePath = savedDataFolder .. "\\" .. gameinfo.getromname() .. ".dat"
    
    local file = io.open(saveFilePath, "w")
    if file then
        local sortedData = {}
        for pid, data in pairs(intervalData) do
            table.insert(sortedData, {pid = pid, data = data})
        end
        
        table.sort(sortedData, function(a, b)
            return (a.data.lastUpdate or 0) > (b.data.lastUpdate or 0)
        end)
        
        for i = 1, math.min(MAX_SAVED_POKEMON, #sortedData) do
            local entry = sortedData[i]
            file:write(string.format("%s|%.3f|%.3f|%d\n", entry.pid, entry.data.minBound or 0, entry.data.maxBound or 31, entry.data.lastUpdate or 0))
        end
        file:close()
    end
end

local function loadIntervalData()
    local saveFilePath = savedDataFolder .. "\\" .. gameinfo.getromname() .. ".dat"
        
    if not fileExists(saveFilePath) then
        return
    end
    
    local lines = readLinesFromFile(saveFilePath)
    local loadedData = {}
    
    for _, line in ipairs(lines) do
        local parts = split(line, "|", true)
        if #parts >= 3 then
            local pid = parts[1]
            local minBound = tonumber(parts[2])
            local maxBound = tonumber(parts[3])
            local lastUpdate = tonumber(parts[4]) or os.time() 
            
            if pid and minBound and maxBound then
                table.insert(loadedData, {
                    pid = pid,
                    data = {
                        minBound = minBound,
                        maxBound = maxBound,
                        lastUpdate = lastUpdate
                    }
                })
            end
        end
    end
    
    table.sort(loadedData, function(a, b)
        return (a.data.lastUpdate or 0) > (b.data.lastUpdate or 0)
    end)
    
    intervalData = {}
    for i = 1, math.min(MAX_SAVED_POKEMON, #loadedData) do
        local entry = loadedData[i]
        intervalData[entry.pid] = entry.data
    end
end

local function refineIntervalEstimate(pokemonData, newEstimate)
    local key = getIntervalKey(pokemonData)
    
    if not intervalData[key] then
        intervalData[key] = {
            minBound = 0,
            maxBound = 31,
            lastUpdate = os.time()
        }
    end
    
    local stored = intervalData[key]
    local newMinBound = newEstimate.MinIV
    local newMaxBound = newEstimate.MaxIV
    
    local updatedMinBound = math.max(stored.minBound, newMinBound)
    local updatedMaxBound = math.min(stored.maxBound, newMaxBound)
    
    -- Safety check: if bounds got inverted, swap them
    if updatedMinBound > updatedMaxBound then
        updatedMinBound, updatedMaxBound = updatedMaxBound, updatedMinBound
    end
    
    stored.minBound = updatedMinBound
    stored.maxBound = updatedMaxBound
    stored.lastUpdate = os.time() 
    
    local refinedAvgIV = (updatedMinBound + updatedMaxBound) / 2
    
    return {
        BST = newEstimate.BST,
        EstimatedPower = newEstimate.BST + refinedAvgIV * 3,
        EstimatedAverageIVs = refinedAvgIV,
        MinIV = updatedMinBound,
        MaxIV = updatedMaxBound,
    }
end
local function draw_pokemon_stats()

    local inputs = joypad.get()

    if not show_iv_settings.always_show_iv then

		local pressing_select = inputs["Select"] or false
		local pressing_right = inputs["Right"] or false

        if pressing_select and pressing_right and not last_press then
            showIvs = not showIvs
        end
        last_press = pressing_select and pressing_right
    end

    local playerAddress = PokemonReader.getPlayerPokemonAddress()
    local poke_info = PokemonReader.decryptPokemonInfo(playerAddress)
    
    if validPokemonData(poke_info) and poke_info.stats and poke_info.IVs then

        if not show_iv_settings.always_show_iv and showIvs and lastValidPokemonData and lastValidPokemonData.pid ~= poke_info.pid then
            showIvs = false
        end
        lastValidPokemonData = poke_info
    end

    if lastValidPokemonData and lastValidPokemonData.stats and lastValidPokemonData.IVs then
        local evs = lastValidPokemonData.EVs
        local ivs = lastValidPokemonData.IVs
        
        if show_iv_settings.always_show_iv or showIvs then
            local totalIVs = ivs.HP + ivs.ATK + ivs.DEF + ivs.SPE + ivs.SPA + ivs.SPD
            local averageIV = totalIVs / 6
            gui.text(75 + settings.x_offset, 50 + settings.y_offset, "IVs", "white")
            gui.text(155 + settings.x_offset, 50 + settings.y_offset, "EVs", "white")

            gui.text(10 + settings.x_offset, 70 + settings.y_offset, "PV ", "white")
            gui.text(75 + settings.x_offset, 70 + settings.y_offset, string.format("%2d", ivs.HP), getIVColor(ivs.HP))
            gui.text(155 + settings.x_offset, 70 + settings.y_offset, string.format("%2d", evs.HP), "white")
            gui.text(10 + settings.x_offset, 85 + settings.y_offset, "ATQ", "white")
            gui.text(75 + settings.x_offset, 85 + settings.y_offset, string.format("%2d", ivs.ATK), getIVColor(ivs.ATK))
            gui.text(155 + settings.x_offset, 85 + settings.y_offset, string.format("%2d", evs.ATK), "white")
            gui.text(10 + settings.x_offset, 100 + settings.y_offset, "DEF", "white")
            gui.text(75 + settings.x_offset, 100 + settings.y_offset, string.format("%2d", ivs.DEF), getIVColor(ivs.DEF))
            gui.text(155 + settings.x_offset, 100 + settings.y_offset, string.format("%2d", evs.DEF), "white")
            gui.text(10 + settings.x_offset, 115 + settings.y_offset, "A.SP", "white")
            gui.text(75 + settings.x_offset, 115 + settings.y_offset, string.format("%2d", ivs.SPA), getIVColor(ivs.SPA))
            gui.text(155 + settings.x_offset, 115 + settings.y_offset, string.format("%2d", evs.SPA), "white")
            gui.text(10 + settings.x_offset, 130 + settings.y_offset, "D.SP", "white")
            gui.text(75 + settings.x_offset, 130 + settings.y_offset, string.format("%2d", ivs.SPD), getIVColor(ivs.SPD))
            gui.text(155 + settings.x_offset, 130 + settings.y_offset, string.format("%2d", evs.SPD), "white")
            gui.text(10 + settings.x_offset, 145 + settings.y_offset, "VIT", "white")
            gui.text(75 + settings.x_offset, 145 + settings.y_offset, string.format("%2d", ivs.SPE), getIVColor(ivs.SPE))
            gui.text(155 + settings.x_offset, 145 + settings.y_offset, string.format("%2d", evs.SPE), "white")
            gui.text(10 + settings.x_offset, 175 + settings.y_offset, "IV Moyens : " .. string.format("%4.1f", averageIV), getIVColor(averageIV))
            gui.text(10 + settings.x_offset, 190 + settings.y_offset, "Puissance totale : " .. string.format("%.0f", pokemon_base_stats[lastValidPokemonData.pokemonID] + averageIV * 3), getBSTColor(pokemon_base_stats[lastValidPokemonData.pokemonID] + averageIV * 3))


            local power, type_name, type_color = calculateHiddenPower(lastValidPokemonData)
            gui.text(10 + settings.x_offset, 220 + settings.y_offset, "Puis. Cachee : " .. power .. " " .. type_name, type_color)   
        else
            gui.text(155 + settings.x_offset, 50 + settings.y_offset, "EVs", "white")

            gui.text(10 + settings.x_offset, 70 + settings.y_offset, "PV ", "white")
            gui.text(155 + settings.x_offset, 70 + settings.y_offset, string.format("%2d", evs.HP), "white")
            gui.text(10 + settings.x_offset, 85 + settings.y_offset, "ATQ", "white")
            gui.text(155 + settings.x_offset, 85 + settings.y_offset, string.format("%2d", evs.ATK), "white")
            gui.text(10 + settings.x_offset, 100 + settings.y_offset, "DEF", "white")
            gui.text(155 + settings.x_offset, 100 + settings.y_offset, string.format("%2d", evs.DEF), "white")
            gui.text(10 + settings.x_offset, 115 + settings.y_offset, "A.SP", "white")
            gui.text(155 + settings.x_offset, 115 + settings.y_offset, string.format("%2d", evs.SPA), "white")
            gui.text(10 + settings.x_offset, 130 + settings.y_offset, "D.SP", "white")
            gui.text(155 + settings.x_offset, 130 + settings.y_offset, string.format("%2d", evs.SPD), "white")
            gui.text(10 + settings.x_offset, 145 + settings.y_offset, "VIT", "white")
            gui.text(155 + settings.x_offset, 145 + settings.y_offset, string.format("%2d", evs.SPE), "white")
           
            if lastValidPokemonData.level ~= previousLevel or lastValidPokemonData.pid ~= previousPID then
                startMonteCarloCalculation(lastValidPokemonData)
                
                previousLevel = lastValidPokemonData.level
                previousPID = lastValidPokemonData.pid
            end
            
            if monteCarloState.active then
                local finished = processMonteCarloFrame()
                if finished then
                    local newEstimate = getMonteCarloResults()
                    currentIntervalEstimate = refineIntervalEstimate(lastValidPokemonData, newEstimate)
                    
                    saveIntervalData()
                    
                    if currentIntervalEstimate then
                        averageIV = currentIntervalEstimate.EstimatedAverageIVs or 0
                        estimatedPower = currentIntervalEstimate.EstimatedPower or 0
                        BST = currentIntervalEstimate.BST or 0
                    end
                end
            end

            if monteCarloState.active then
                local progress = math.floor((monteCarloState.completedIterations / monteCarloState.targetIterations) * 100)
                gui.text(10 + settings.x_offset, 175 + settings.y_offset, "Calcul en cours... " .. progress .. "%", "yellow")
                if currentIntervalEstimate then
                    gui.text(10 + settings.x_offset, 190 + settings.y_offset, "Puissance totale : " .. BST .. " -> " .. string.format("%.0f", estimatedPower), getBSTColor(estimatedPower))
                end
            elseif currentIntervalEstimate then
                local minIV = currentIntervalEstimate.MinIV
                local maxIV = currentIntervalEstimate.MaxIV
                
                gui.text(10 + settings.x_offset, 175 + settings.y_offset, "IV Moyens : " .. string.format("%.1f", averageIV) .. " [" .. string.format("%.1f", minIV) .. "-" .. string.format("%.1f", maxIV) .. "]", getIVColor(averageIV))
                gui.text(10 + settings.x_offset, 190 + settings.y_offset, "Puissance totale : " .. BST .. " -> " .. string.format("%.0f", estimatedPower), getBSTColor(estimatedPower))
            else
                gui.text(10 + settings.x_offset, 175 + settings.y_offset, "IV Moyens (Estimation) : " .. string.format("%4.1f", averageIV), getIVColor(averageIV))
                gui.text(10 + settings.x_offset, 190 + settings.y_offset, "Puissance totale (Estimation) : " .. BST .. " -> " .. string.format("%.0f", estimatedPower), getBSTColor(estimatedPower))
            end
        end

        if not show_iv_settings.always_show_iv then
            if showIvs then
                gui.text(10 + settings.x_offset, 250 + settings.y_offset, "Select + Droite : Masquer les IVs", "yellow")
            else
                gui.text(10 + settings.x_offset, 250 + settings.y_offset, "Select + Droite : Afficher les IVs", "yellow")
            end
        end
    end
end

local current_rom 
local dataLoaded = false

while true do

    if(gameinfo.getromhash() ~= nil and gameinfo.getromhash() ~= "" and gameinfo.getromhash() ~= current_rom) then
        current_rom = gameinfo.getromhash()
        InitBST()
        
        if not dataLoaded then
            loadIntervalData()
            dataLoaded = true
        end
    end
    if current_rom ~= "" then
        draw_pokemon_stats()
    end
    emu.frameadvance()
end