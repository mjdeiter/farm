-- NPC Farm Script for MacroQuest (E3/Project Lazarus version)
-- Enhanced with GUI and additional features

local mq = require('mq')
local ImGui = require('ImGui')

-- Configuration structure
local config = {
    targetNPCs = {"orc pawn", "orc centurion", "decaying skeleton"},
    partialMatches = {"orc", "skeleton"},
    usePartialMatching = true,
    searchRadius = 100,
    restHPPct = 60,
    restManaPct = 40,
    useAbilities = true,
    lootCorpses = true,
    minDistance = 10,
    maxZDiff = 20,
    lootDelay = 3000,
    showGUI = true,
    addNPC = "",
    addPartial = ""
}

-- State variables
local state = {
    isRunning = false,
    currentTarget = nil,
    status = "Idle",
    lastAction = "None"
}

-- Class ability configuration
local classAbilities = {
    Warrior = {"Kick", "Bash", "Taunt"},
    Rogue = {"Backstab", "Hide", "Sneak"},
    Wizard = {"Ethereal Incandescence", "Ice Comet", "Burning Affliction"},
    Cleric = {"Hammer of Wrath", "Stun"},
    -- Add more classes as needed
}

-- Load configuration from INI file
local function loadConfig()
    local iniFile = "farm_config.ini"
    local section = "Config"
    
    -- Helper function to read INI value
    local function readIni(key, default)
        local value = mq.TLO.Ini(iniFile, section, key)
        if value() then
            return value()
        else
            return default
        end
    end
    
    -- Load numeric values
    local sr = readIni("searchRadius", tostring(config.searchRadius))
    if sr and tonumber(sr) then
        config.searchRadius = tonumber(sr)
    end
    
    local md = readIni("minDistance", tostring(config.minDistance))
    if md and tonumber(md) then
        config.minDistance = tonumber(md)
    end
    
    local mzd = readIni("maxZDiff", tostring(config.maxZDiff))
    if mzd and tonumber(mzd) then
        config.maxZDiff = tonumber(mzd)
    end
    
    local rhp = readIni("restHPPct", tostring(config.restHPPct))
    if rhp and tonumber(rhp) then
        config.restHPPct = tonumber(rhp)
    end
    
    local rmp = readIni("restManaPct", tostring(config.restManaPct))
    if rmp and tonumber(rmp) then
        config.restManaPct = tonumber(rmp)
    end
    
    local ld = readIni("lootDelay", tostring(config.lootDelay))
    if ld and tonumber(ld) then
        config.lootDelay = tonumber(ld)
    end
    
    -- Load boolean values
    config.usePartialMatching = readIni("usePartialMatching", config.usePartialMatching and "1" or "0") == "1"
    config.useAbilities = readIni("useAbilities", config.useAbilities and "1" or "0") == "1"
    config.lootCorpses = readIni("lootCorpses", config.lootCorpses and "1" or "0") == "1"
    
    -- Load targetNPCs
    local tnCount = tonumber(readIni("targetNPCCount", "0"))
    config.targetNPCs = {}
    for i = 1, tnCount do
        local npc = readIni("targetNPC" .. i, "")
        if npc ~= "" then
            table.insert(config.targetNPCs, npc)
        end
    end
    
    -- Load partialMatches
    local pmCount = tonumber(readIni("partialMatchCount", "0"))
    config.partialMatches = {}
    for i = 1, pmCount do
        local pattern = readIni("partialMatch" .. i, "")
        if pattern ~= "" then
            table.insert(config.partialMatches, pattern)
        end
    end
end

-- Save configuration to INI file
local function saveConfig()
    local iniFile = "farm_config.ini"
    local section = "Config"
    
    -- Save numeric values
    mq.cmdf('/ini "%s" "%s" "searchRadius" "%d"', iniFile, section, config.searchRadius)
    mq.cmdf('/ini "%s" "%s" "minDistance" "%d"', iniFile, section, config.minDistance)
    mq.cmdf('/ini "%s" "%s" "maxZDiff" "%d"', iniFile, section, config.maxZDiff)
    mq.cmdf('/ini "%s" "%s" "restHPPct" "%d"', iniFile, section, config.restHPPct)
    mq.cmdf('/ini "%s" "%s" "restManaPct" "%d"', iniFile, section, config.restManaPct)
    mq.cmdf('/ini "%s" "%s" "lootDelay" "%d"', iniFile, section, config.lootDelay)
    
    -- Save boolean values
    mq.cmdf('/ini "%s" "%s" "usePartialMatching" "%d"', iniFile, section, config.usePartialMatching and 1 or 0)
    mq.cmdf('/ini "%s" "%s" "useAbilities" "%d"', iniFile, section, config.useAbilities and 1 or 0)
    mq.cmdf('/ini "%s" "%s" "lootCorpses" "%d"', iniFile, section, config.lootCorpses and 1 or 0)
    
    -- Save targetNPCs
    mq.cmdf('/ini "%s" "%s" "targetNPCCount" "%d"', iniFile, section, #config.targetNPCs)
    for i, npc in ipairs(config.targetNPCs) do
        mq.cmdf('/ini "%s" "%s" "targetNPC%d" "%s"', iniFile, section, i, npc)
    end
    
    -- Save partialMatches
    mq.cmdf('/ini "%s" "%s" "partialMatchCount" "%d"', iniFile, section, #config.partialMatches)
    for i, pattern in ipairs(config.partialMatches) do
        mq.cmdf('/ini "%s" "%s" "partialMatch%d" "%s"', iniFile, section, i, pattern)
    end
end

-- Load the configuration
loadConfig()

-- Helper functions
local function contains(table, val)
    for i = 1, #table do
        if string.lower(table[i]) == string.lower(val) then
            return true
        end
    end
    return false
end

local function containsPartial(name)
    if not config.usePartialMatching then return false end
    local lowerName = string.lower(name)
    for _, pattern in ipairs(config.partialMatches) do
        if string.find(lowerName, string.lower(pattern)) then
            return true
        end
    end
    return false
end

local function needsRest()
    local hp = mq.TLO.Me.PctHPs()
    local mana = mq.TLO.Me.PctMana()
    local isCaster = (mq.TLO.Me.Class.CanCast() == true)
    
    if hp < config.restHPPct then return true end
    if isCaster and mana < config.restManaPct then return true end
    
    return false
end

-- Find a suitable NPC target within the search radius
-- Returns the ID of the target if found, nil otherwise
local function findTarget()
    state.lastAction = "Scanning for targets"
    print("\ayScanning for targets within " .. config.searchRadius .. " radius...")
    
    local count = mq.TLO.SpawnCount("npc radius " .. config.searchRadius)()
    
    for i = 1, count do
        local spawn = mq.TLO.NearestSpawn(i, "npc radius " .. config.searchRadius)
        
        if spawn() then
            local name = spawn.Name()
            local zDiff = math.abs(spawn.Z() - mq.TLO.Me.Z())
            local distance = spawn.Distance()
            
            if (contains(config.targetNPCs, name) or containsPartial(name)) and zDiff <= config.maxZDiff and spawn.LineOfSight() then
                print("\agTarget found: " .. name .. " (Distance: " .. string.format("%.1f", distance) .. ")")
                return spawn.ID()
            end
        end
    end
    
    print("\arNo valid targets found within range.")
    return nil
end

-- Rest the character until HP and mana are above thresholds
local function rest()
    state.status = "Resting"
    state.lastAction = "Resting"
    print("\ayResting to recover...")
    mq.cmd("/sit")
    
    local isCaster = (mq.TLO.Me.Class.CanCast() == true)
    
    mq.delay(30000, function()
        local hpOK = mq.TLO.Me.PctHPs() > 90
        local manaOK = not isCaster or mq.TLO.Me.PctMana() > 80
        return hpOK and manaOK
    end)
    
    mq.cmd("/stand")
    print("\agRest complete, resuming hunt...")
end

-- Engage in combat with the specified target ID
-- Returns true if the target was defeated, false otherwise
local function engageCombat(targetID)
    if not targetID then return false end
    
    mq.cmdf("/target id %d", targetID)
    mq.delay(500)
    
    if not mq.TLO.Target.ID() then
        print("\arFailed to target NPC.")
        return false
    end
    
    local targetName = mq.TLO.Target.Name()
    state.lastAction = "Engaging " .. targetName
    print("\ayEngaging " .. targetName)
    
    if mq.TLO.Target.Distance() > config.minDistance + 5 then
        print("\ayMoving closer to target...")
        mq.cmd("/face")
        mq.cmd("/stick 15")
        mq.delay(1000, function() return mq.TLO.Me.Distance() <= config.minDistance + 5 end)
        mq.cmd("/stick off")
    end
    
    mq.cmd("/attack on")
    
    while mq.TLO.Target.ID() == targetID and mq.TLO.Target.Type() == "NPC" and mq.TLO.Target.PctHPs() > 0 do
        if needsRest() then
            print("\ayNeed to rest! Disengaging...")
            mq.cmd("/attack off")
            return false
        end
        
        if config.useAbilities then
            local myClass = mq.TLO.Me.Class.Name()
            if classAbilities[myClass] then
                for _, ability in ipairs(classAbilities[myClass]) do
                    if mq.TLO.Me.CombatAbilityReady(ability)() then
                        mq.cmdf("/doability %s", ability)
                        state.lastAction = "Used: " .. ability
                        mq.delay(500)
                    end
                end
            end
        end
        
        mq.delay(500)
    end
    
    if mq.TLO.Target.ID() == targetID and mq.TLO.Target.Type() == "NPC" and mq.TLO.Target.PctHPs() == 0 then
        print("\agTarget defeated: " .. targetName)
        mq.cmd("/attack off")
        
        if config.lootCorpses then
            mq.delay(1000)
            print("\ayLooting corpse...")
            mq.cmd("/loot")
            mq.delay(config.lootDelay, function() return not mq.TLO.Window("LootWnd").Open() end)
        end
        
        return true
    end
    
    mq.cmd("/attack off")
    return false
end

-- Render the GUI for configuration and control
local function DrawGUI()
    if config.showGUI then
        ImGui.Begin("NPC Farm Controller", config.showGUI)
        
        ImGui.TextColored(0, 255, 0, 255, "Status: " .. state.status)
        ImGui.Text("Last Action: " .. state.lastAction)
        ImGui.Separator()
        
        if ImGui.CollapsingHeader("Main Settings") then
            config.searchRadius = ImGui.SliderInt("Search Radius", config.searchRadius, 10, 500)
            config.minDistance = ImGui.SliderInt("Min Distance", config.minDistance, 5, 100)
            config.maxZDiff = ImGui.SliderInt("Max Z Difference", config.maxZDiff, 5, 50)
            config.restHPPct = ImGui.SliderInt("Rest HP%", config.restHPPct, 10, 90)
            config.restManaPct = ImGui.SliderInt("Rest Mana%", config.restManaPct, 10, 90)
            config.lootDelay = ImGui.SliderInt("Loot Delay (ms)", config.lootDelay, 1000, 10000)
        end

        if ImGui.CollapsingHeader("NPC Selection") then
            ImGui.Checkbox("Use Partial Matching", config.usePartialMatching)
            
            ImGui.Text("Target NPCs:")
            for i, npc in ipairs(config.targetNPCs) do
                ImGui.Text(tostring(i) .. ". " .. npc)
                if ImGui.Button("Remove##npc"..i) then
                    table.remove(config.targetNPCs, i)
                end
                ImGui.SameLine()
            end
            ImGui.InputText("Add NPC", config.addNPC, 256)
            if ImGui.Button("Add Target NPC") and #config.addNPC > 0 then
                table.insert(config.targetNPCs, config.addNPC)
                config.addNPC = ""
            end

            ImGui.Text("Partial Matches:")
            for i, pattern in ipairs(config.partialMatches) do
                ImGui.Text(tostring(i) .. ". " .. pattern)
                if ImGui.Button("Remove##partial"..i) then
                    table.remove(config.partialMatches, i)
                end
                ImGui.SameLine()
            end
            ImGui.InputText("Add Partial", config.addPartial, 256)
            if ImGui.Button("Add Partial Match") and #config.addPartial > 0 then
                table.insert(config.partialMatches, config.addPartial)
                config.addPartial = ""
            end
        end

        if ImGui.CollapsingHeader("Combat Settings") then
            ImGui.Checkbox("Use Abilities", config.useAbilities)
            ImGui.Checkbox("Loot Corpses", config.lootCorpses)
            
            if config.useAbilities then
                local myClass = mq.TLO.Me.Class.Name()
                if classAbilities[myClass] then
                    ImGui.Text("Class Abilities (" .. myClass .. "):")
                    for _, ability in ipairs(classAbilities[myClass]) do
                        ImGui.BulletText(ability)
                    end
                end
            end
        end

        ImGui.Separator()
        if ImGui.Button(state.isRunning and "Stop Script" or "Start Script") then
            state.isRunning = not state.isRunning
            if state.isRunning then
                farmNPCs()
            end
        end
        
        if ImGui.Button("Save Config") then
            saveConfig()
        end
        
        ImGui.End()
    end
end

-- Main loop for farming NPCs
local function farmNPCs()
    state.isRunning = true
    state.status = "Running"
    
    while state.isRunning do
        mq.doevents()
        DrawGUI()
        
        if needsRest() then
            state.status = "Resting"
            rest()
        end
        
        local targetID = findTarget()
        if targetID then
            state.status = "Engaging Target"
            if not engageCombat(targetID) then
                mq.delay(5000)
            end
        else
            state.status = "Searching"
            mq.delay(5000)
        end
    end
    
    state.status = "Idle"
end

-- Command handler for /farm
function farm(...)
    local args = {...}
    
    if #args == 0 then
        config.showGUI = not config.showGUI
    elseif args[1] == "start" then
        if not state.isRunning then
            state.isRunning = true
            farmNPCs()
        else
            print("\ayScript is already running.")
        end
    elseif args[1] == "stop" then
        if state.isRunning then
            state.isRunning = false
            print("\ayStopping script...")
        else
            print("\ayScript is not running.")
        end
    elseif args[1] == "gui" then
        config.showGUI = not config.showGUI
    elseif args[1] == "help" then
        print("\ay===== NPC Farm Script Help =====")
        print("\aw/farm         - Toggle GUI on/off")
        print("\aw/farm start   - Start the farming script")
        print("\aw/farm stop    - Stop the farming script")
        print("\aw/farm help    - Show this help menu")
        print("\aw/farm gui     - Toggle the GUI interface")
        print("\aw/farm targets - Show current target list")
        print("\aw/farm partial - Show partial match list")
        print("\aw/farm add <name> - Add NPC to target list")
        print("\aw/farm remove <name> - Remove NPC from target list")
        print("\aw/farm addp <part> - Add partial match string")
        print("\aw/farm removep <part> - Remove partial match string")
        print("\aw/farm radius <number> - Set search radius")
        print("\aw/farm toggle - Toggle partial matching on/off")
    elseif args[1] == "targets" then
        print("\ay===== Current Target NPCs =====")
        for i, name in ipairs(config.targetNPCs) do
            print("\aw" .. i .. ". " .. name)
        end
    elseif args[1] == "partial" then
        print("\ay===== Current Partial Matches =====")
        print("\awPartial matching is " .. (config.usePartialMatching and "\agON" or "\arOFF"))
        for i, pattern in ipairs(config.partialMatches) do
            print("\aw" .. i .. ". " .. pattern)
        end
    elseif args[1] == "add" and args[2] then
        table.insert(config.targetNPCs, args[2])
        print("\agAdded '" .. args[2] .. "' to target list")
    elseif args[1] == "remove" and args[2] then
        for i, name in ipairs(config.targetNPCs) do
            if string.lower(name) == string.lower(args[2]) then
                table.remove(config.targetNPCs, i)
                print("\arRemoved '" .. args[2] .. "' from target list")
                return
            end
        end
        print("\arCould not find '" .. args[2] .. "' in target list")
    elseif args[1] == "addp" and args[2] then
        table.insert(config.partialMatches, args[2])
        print("\agAdded '" .. args[2] .. "' to partial match list")
    elseif args[1] == "removep" and args[2] then
        for i, pattern in ipairs(config.partialMatches) do
            if string.lower(pattern) == string.lower(args[2]) then
                table.remove(config.partialMatches, i)
                print("\arRemoved '" .. args[2] .. "' from partial match list")
                return
            end
        end
        print("\arCould not find '" .. args[2] .. "' in partial match list")
    elseif args[1] == "radius" and tonumber(args[2]) then
        config.searchRadius = tonumber(args[2])
        print("\agSearch radius set to " .. config.searchRadius)
    elseif args[1] == "toggle" then
        config.usePartialMatching = not config.usePartialMatching
        print("\ayPartial matching is now " .. (config.usePartialMatching and "\agON" or "\arOFF"))
    end
end

-- Initialize
mq.bind("/farm", farm)
print("\ag===== Enhanced NPC Farm Script Loaded by Alektra <Lederhosen> =====")
print("\ayType /farm gui to toggle the interface")
print("\ayType /farm help for command list")