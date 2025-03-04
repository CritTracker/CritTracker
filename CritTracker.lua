-- CritTracker
-- Tracks your highest critical hits per specific spell/ability

CritTracker = {
    highestCrits = {
        spells = {},    -- Key: spellName, Value: {value = number, timestamp = time}
        abilities = {}, -- Key: abilityName, Value: {value = number, timestamp = time}
        melee = {value = 0, timestamp = 0},  -- Single record for melee
        wand = {value = 0, timestamp = 0},   -- Single record for wand
        heals = {}      -- Key: spellName, Value: {value = number, timestamp = time}
    },
    settings = {
        enabled = true,
        announceParty = true,
        announceRaid = true,
        playSoundOnRecord = true,
        recordSound = "TAUREN" -- Default sound
    }
}

local CT = CritTracker

CT.sounds = {
    -- Sound options for dropdown with corrected IDs
    { text = "Raid Warning", value = "RAID_WARNING", soundID = 8959 },
    { text = "Level Up", value = "LEVELUP", soundID = 888 },
    { text = "Ready Check", value = "READY_CHECK", soundID = 8960 },
    { text = "PVP Flag Taken", value = "PVP_FLAG", soundID = 8212 },
    { text = "Treasure Pickup", value = "MONEY", soundID = 891 },
	{ text = "Murloc Aggro", value = "MURLOC", soundID = 416 },
    { text = "Tauren Proud", value = "TAUREN", soundID = 6366 },
	{ text = "Succubus", value = "SUCCUBUS", soundID = 7096 },
}

-- Main addon frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

-- Print to chat
function CT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CritTracker|r: " .. msg)
end

-- Clean spell name (used in multiple places)
function CT:CleanSpellName(spellName)
    if not spellName then return spellName end
    spellName = string.gsub(spellName, "%s+%(Rank%s+%d+%)", "")
    return string.gsub(spellName, "%s+%[Rank%s+%d+%]", "")
end

-- Initialize
function CT:Init(addonName)
    if addonName ~= "CritTracker" then return end
    
    -- Load saved variables
    if CritTrackerDB then
        -- Copy saved settings
        if CritTrackerDB.settings then
            for k, v in pairs(CritTrackerDB.settings) do
                if self.settings[k] ~= nil then
                    self.settings[k] = v
                end
            end
        end
        
        -- Copy saved highest crits
        if CritTrackerDB.highestCrits then
            for category, data in pairs(CritTrackerDB.highestCrits) do
                if self.highestCrits[category] then
                    self.highestCrits[category] = CopyTable(data)
                end
            end
        end
    end
    
    -- Register slash commands
    SLASH_CRITTRACKER1 = "/ct"
    SLASH_CRITTRACKER2 = "/crittracker"
    SlashCmdList["CRITTRACKER"] = function(msg) self:HandleCommand(msg) end
    
    -- Set up tooltip hooks
    self:SetupTooltips()
    
    -- Initial welcome message (shown only on first load, not reload)
    self.initialized = true
end

-- Update the player login message
function CT:ShowWelcomeMessage()
    self:Print("loaded successfully! Type /ct to open settings or /ct help for commands.")
end

-- Deep copy a table
function CopyTable(src)
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Helper to create UI elements - reduces code duplication
function CT:CreateCheckButton(parent, x, y, settingName, labelText)
    local checkBtn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkBtn:SetPoint("TOPLEFT", 20, y)
    checkBtn:SetChecked(self.settings[settingName])
    checkBtn:SetScript("OnClick", function(self)
        CT.settings[settingName] = self:GetChecked()
        CT:Print(labelText .. " " .. (CT.settings[settingName] and "enabled" or "disabled"))
    end)
    
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", checkBtn, "RIGHT", 5, 0)
    text:SetText(labelText)
    
    return checkBtn, y - 25 -- Return button and new y position
end

-- Helper function to create dropdown menu
function CT:CreateDropdown(parent, y, width, settingName, labelText, options)
    -- Create label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 25, y)
    label:SetText(labelText)
    
    -- Create dropdown frame
    local dropdown = CreateFrame("Frame", "CritTracker_"..settingName.."Dropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 20, y - 20)
    UIDropDownMenu_SetWidth(dropdown, width)
    
    -- Initialize dropdown
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(options) do
            info.text = option.text
            info.value = option.value
            info.func = function(self)
                CT.settings[settingName] = self.value
                UIDropDownMenu_SetSelectedValue(dropdown, self.value)
                CT:Print(labelText .. " set to " .. info.text)
            end
            info.checked = (CT.settings[settingName] == option.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    -- Set initial value
    UIDropDownMenu_SetSelectedValue(dropdown, self.settings[settingName])
    
    return dropdown, y - 50 -- Return dropdown and new y position for next element
end

-- Create a standalone configuration frame
function CT:CreateConfigPanel()
    -- Clean up any existing frames with the same name
    if _G["CritTrackerConfigFrame"] then
        _G["CritTrackerConfigFrame"]:Hide()
        _G["CritTrackerConfigFrame"] = nil
    end
    
    -- Create the main frame with a unique name using time to avoid conflicts
    local frameName = "CritTrackerConfigFrame"
    local frame = CreateFrame("Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 450)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    
    -- Setup frame title
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("CritTracker Options")
    
    -- Settings
    local y = -40  -- Starting vertical position
    
    -- Use helper function to create checkboxes with less code
    local _, newY = self:CreateCheckButton(frame, 20, y, "enabled", "Enable Tracking")
    _, newY = self:CreateCheckButton(frame, 20, newY, "announceParty", "Announce Records to Party")
    _, newY = self:CreateCheckButton(frame, 20, newY, "announceRaid", "Announce Records to Raid")
    _, newY = self:CreateCheckButton(frame, 20, newY, "playSoundOnRecord", "Play Sound on New Records")
    
    -- Add sound dropdown with more space
    newY = newY - 10 -- Add extra space before the dropdown
    _, newY = self:CreateDropdown(frame, newY, 180, "recordSound", "Record Sound", self.sounds)
    
    -- Add Test Sound button
    local testSoundButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testSoundButton:SetSize(100, 22)
    testSoundButton:SetPoint("TOPLEFT", 30, newY - 15) -- Moved down by adjusting the Y coordinate
    testSoundButton:SetText("Test Sound")
    testSoundButton:SetScript("OnClick", function()
        local selectedSound = CT.settings.recordSound
        local soundID = 6227 -- Default fallback
        
        for _, sound in ipairs(CT.sounds) do
            if sound.value == selectedSound then
                soundID = sound.soundID
                break
            end
        end
        
        PlaySound(soundID)
        CT:Print("Testing sound: " .. selectedSound)
    end)
    
    newY = newY - 40 -- Add space after the button
    
    -- Add Reset All Records button at bottom
    local resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetButton:SetPoint("BOTTOM", 0, 40)
    resetButton:SetSize(150, 22)
    resetButton:SetText("Reset All Records")
    resetButton:SetScript("OnClick", function()
        StaticPopup_Show("CRITTRACKER_RESET_CONFIRM")
    end)
    
    -- Reset confirmation dialog
    StaticPopupDialogs["CRITTRACKER_RESET_CONFIRM"] = {
        text = "Are you sure you want to reset all critical hit records?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            CT:ResetRecords("all")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    -- Save frame reference
    self.configFrame = frame
    self.configFrame:Hide()  -- Hide by default
    
    -- Make sure the close button actually works
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    return frame
end

-- Set up tooltip functionality
function CT:SetupTooltips()
    GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
        if not CT.settings.enabled then return end
        
        local spellName, spellRank = tooltip:GetSpell()
        if not spellName then return end
        
        -- Use the helper function to clean spell name 
        spellName = self:CleanSpellName(spellName)
        
        local found = false
        
        -- Special handling for "Shoot" ability (wand)
        if spellName == "Shoot" then
            if CT.highestCrits.wand.value > 0 then
                tooltip:AddLine(" ")
                tooltip:AddLine("|cffff8800CritTracker:|r")
                found = true
                
                local record = CT.highestCrits.wand
                local timeAgo = CT:FormatTimeAgo(record.timestamp)
                tooltip:AddLine("Highest Wand crit: |cffff0000" .. record.value .. "|r " .. timeAgo)
            end
        else
            -- Check regular spell categories
            local categories = {
                {name = "spells", label = "Spell"},
                {name = "abilities", label = "Ability"},
                {name = "heals", label = "Heal"}
            }
            
            for _, category in ipairs(categories) do
                -- Make the lookup case-insensitive to catch more potential matches
                for storedSpellName, data in pairs(CT.highestCrits[category.name]) do
                    if string.lower(storedSpellName) == string.lower(spellName) and data.value > 0 then
                        if not found then
                            tooltip:AddLine(" ")
                            tooltip:AddLine("|cffff8800CritTracker:|r")
                            found = true
                        end
                        
                        local timeAgo = CT:FormatTimeAgo(data.timestamp)
                        tooltip:AddLine("Highest " .. category.label .. " crit: |cffff0000" .. data.value .. "|r " .. timeAgo)
                    end
                end
            end
        end
        
        if found then
            tooltip:Show()
        end
    end)
end

-- Format time ago
function CT:FormatTimeAgo(timestamp)
    if timestamp == 0 then return "" end
    
    local now = time()
    local diff = now - timestamp
    
    if diff < 60 then
        return "(just now)"
    elseif diff < 3600 then
        return string.format("(%d min ago)", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("(%d hours ago)", math.floor(diff / 3600))
    else
        return string.format("(%d days ago)", math.floor(diff / 86400))
    end
end

-- Toggle a setting on/off with feedback
function CT:ToggleSetting(settingName, displayName, value)
    if value ~= nil then 
        self.settings[settingName] = (value == "on")
    end
    
    local status = self.settings[settingName] and "ON" or "OFF"
    local action = self.settings[settingName] and "enabled" or "disabled"
    
    if value ~= nil then
        self:Print(displayName .. " " .. action .. ".")
    else
        self:Print("Current " .. string.lower(displayName) .. " setting: " .. status)
        self:Print("Use '/ct " .. settingName .. " on' or '/ct " .. settingName .. " off' to change.")
    end
end

-- Handle slash commands - simplified version
function CT:HandleCommand(msg)
    local args = {}
    for arg in string.gmatch(string.lower(msg or ""), "%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1] or "config"
    
    if command == "help" then
        self:Print("Commands:")
        self:Print("/ct - Open configuration panel")
        self:Print("/ct help - Show this help")
        self:Print("/ct toggle - Quickly enable/disable tracking")
        self:Print("/ct report [all/spell/ability/heal/melee/wand] - Show highest crits")
        self:Print("/ct reset - Reset all records (with confirmation)")
    elseif command == "toggle" then
        self.settings.enabled = not self.settings.enabled
        self:Print("Tracking " .. (self.settings.enabled and "enabled" or "disabled") .. ".")
    elseif command == "report" then
        local category = args[2] or "all"
        self:ShowHighestCrits(category)
    elseif command == "reset" then
        -- Always show confirmation dialog
        StaticPopup_Show("CRITTRACKER_RESET_CONFIRM")
    else
        -- Default action: open config panel (if no command or unknown command)
        -- Create the config panel if it doesn't exist
        if not self.configFrame then
            self:CreateConfigPanel()
        end
        
        -- Show panel if not visible
        if not self.configFrame:IsVisible() then
            -- Hide any other instances that might exist
            if CritTrackerConfigFrame and CritTrackerConfigFrame ~= self.configFrame then
                CritTrackerConfigFrame:Hide()
            end
            self.configFrame:Show()
        else
            self.configFrame:Hide()
            self:Print("Configuration window closed.")
        end
    end
end

-- Reset records
function CT:ResetRecords(category)
    if category == "all" then
        -- Reset all categories
        self.highestCrits = {
            spells = {},
            abilities = {},
            melee = {value = 0, timestamp = 0},
            wand = {value = 0, timestamp = 0},
            heals = {}
        }
        self:Print("All critical hit records have been reset.")
    elseif category == "spell" then
        self.highestCrits.spells = {}
        self:Print("All spell critical hit records have been reset.")
    elseif category == "ability" then
        self.highestCrits.abilities = {}
        self:Print("All ability critical hit records have been reset.")
    elseif category == "heal" then
        self.highestCrits.heals = {}
        self:Print("All healing critical hit records have been reset.")
    elseif category == "melee" then
        self.highestCrits.melee = {value = 0, timestamp = 0}
        self:Print("Melee critical hit record has been reset.")
    elseif category == "wand" then
        self.highestCrits.wand = {value = 0, timestamp = 0}
        self:Print("Wand critical hit record has been reset.")
    else
        self:Print("Unknown category. Use spell, ability, heal, melee, wand, or all.")
    end
end

-- Helper function for ShowHighestCrits
function CT:DisplayCritList(items, label)
    self:Print("|cffff8800Highest " .. label .. " Critical Hits:|r")
    
    if #items == 0 then
        self:Print("  None recorded")
        return
    end
    
    -- Sort by value, highest first
    table.sort(items, function(a, b) return a.value > b.value end)
    
    -- Display top items
    for i, item in ipairs(items) do
        if i <= 10 then -- Show top 10
            local timeAgo = self:FormatTimeAgo(item.timestamp)
            self:Print("  " .. item.name .. ": " .. item.value .. " " .. timeAgo)
        end
    end
    
    if #items > 10 then
        self:Print("  ... and " .. (#items - 10) .. " more " .. label:lower() .. "s")
    end
end

-- Helper function for sound selections
function CT:GetSoundByValue(value)
    for _, sound in ipairs(self.sounds) do
        if sound.value == value then
            return sound
        end
    end
    return self.sounds[1]  -- Return default if not found
end

-- Show highest crits - with helper function to reduce duplicate code
function CT:ShowHighestCrits(category)
    -- For list display categories (spells, abilities, heals)
    if category == "all" or category == "spell" then
        local spells = {}
        for spellName, data in pairs(self.highestCrits.spells) do
            table.insert(spells, {name = spellName, value = data.value, timestamp = data.timestamp})
        end
        self:DisplayCritList(spells, "Spell")
    end
    
    if category == "all" or category == "ability" then
        local abilities = {}
        for abilityName, data in pairs(self.highestCrits.abilities) do
            table.insert(abilities, {name = abilityName, value = data.value, timestamp = data.timestamp})
        end
        self:DisplayCritList(abilities, "Ability")
    end
    
    if category == "all" or category == "heal" then
        local heals = {}
        for healName, data in pairs(self.highestCrits.heals) do
            table.insert(heals, {name = healName, value = data.value, timestamp = data.timestamp})
        end
        self:DisplayCritList(heals, "Healing")
    end
    
    -- For single record categories (melee, wand)
    if category == "all" or category == "melee" then
        self:Print("|cffff8800Highest Melee Critical Hit:|r")
        if self.highestCrits.melee.value > 0 then
            local timeAgo = self:FormatTimeAgo(self.highestCrits.melee.timestamp)
            self:Print("  Melee Attack: " .. self.highestCrits.melee.value .. " " .. timeAgo)
        else
            self:Print("  None recorded")
        end
    end
    
    if category == "all" or category == "wand" then
        self:Print("|cffff8800Highest Wand Critical Hit:|r")
        if self.highestCrits.wand.value > 0 then
            local timeAgo = self:FormatTimeAgo(self.highestCrits.wand.timestamp)
            self:Print("  Wand Shot: " .. self.highestCrits.wand.value .. " " .. timeAgo)
        else
            self:Print("  None recorded")
        end
    end
end

-- Process combat log
function CT:ProcessCombatLog()
    if not self.settings.enabled then return end
    
    -- Get combat log info using CombatLogGetCurrentEventInfo() for Classic
    local timestamp, event, _, sourceGUID = CombatLogGetCurrentEventInfo()
    
    -- Only track player's actions
    if sourceGUID ~= UnitGUID("player") then return end
    
    -- Handle different event types
    if event == "SWING_DAMAGE" then
        local amount, overkill, school, resisted, blocked, absorbed, critical = select(12, CombatLogGetCurrentEventInfo())
        
        if critical then
            self:RecordCrit("melee", "Melee Attack", amount)
        end
    elseif event == "RANGE_DAMAGE" then
        local spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical = select(12, CombatLogGetCurrentEventInfo())
        
        if critical then
            self:RecordCrit("wand", spellName or "Wand Shot", amount)
        end
    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" then
        local spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical = select(12, CombatLogGetCurrentEventInfo())
        
        if critical and spellName then
            -- Use helper function to clean spell name
            spellName = self:CleanSpellName(spellName)
            
            -- In Classic, physical abilities have spellSchool = 1
            local category = (spellSchool == 1) and "abilities" or "spells"
            self:RecordCrit(category, spellName, amount)
        end
    elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(12, CombatLogGetCurrentEventInfo())
        
        if critical and spellName then
            -- Use helper function to clean spell name
            spellName = self:CleanSpellName(spellName)
            
            self:RecordCrit("heals", spellName, amount)
        end
    end
end

-- Record critical hit
function CT:RecordCrit(category, name, amount)
    local record = nil
    local isNewRecord = false
    local oldValue = 0
    
    -- Handle special cases for melee and wand which are single records
    if category == "melee" or category == "wand" then
        record = self.highestCrits[category]
    else
        -- For spells, abilities, and heals
        -- Initialize if this spell hasn't been recorded before
        if not self.highestCrits[category][name] then
            self.highestCrits[category][name] = {value = 0, timestamp = 0}
        end
        record = self.highestCrits[category][name]
    end
    
    -- Check for new record
    if amount > record.value then
        oldValue = record.value
        record.value = amount
        record.timestamp = time()
        isNewRecord = true
    end
    
    -- Notify player of new record
    if isNewRecord then
        local categoryLabel = category
        if category == "spells" then categoryLabel = "SPELL"
        elseif category == "abilities" then categoryLabel = "ABILITY"
        elseif category == "heals" then categoryLabel = "HEAL"
        elseif category == "melee" then categoryLabel = "MELEE"
        elseif category == "wand" then categoryLabel = "WAND"
        end
        
        -- Format message
        local message
        if oldValue == 0 then
            message = string.format("New %s crit record: %s hit for %d", categoryLabel, name, amount)
        else
            message = string.format("New %s crit record: %s hit for %d (prev: %d)", categoryLabel, name, amount, oldValue)
        end
        
        -- Show message to player
        self:Print(message)
        
        -- Announce to party/raid if appropriate
        if IsInRaid() and self.settings.announceRaid then
            SendChatMessage(message, "RAID")
        elseif IsInGroup() and not IsInRaid() and self.settings.announceParty then
            SendChatMessage(message, "PARTY")
        end
        
        -- Play sound if enabled
        if self.settings.playSoundOnRecord then
            local soundID = 6227 -- Default fallback
            for _, sound in ipairs(self.sounds) do
                if sound.value == self.settings.recordSound then
                    soundID = sound.soundID
                    break
                end
            end
            PlaySound(soundID)
        end
    end
end

-- Save data between sessions
function CT:SaveData()
    CritTrackerDB = {
        settings = self.settings,
        highestCrits = self.highestCrits
    }
end

-- Consolidated event handler
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        CT:Init(addonName)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        CT:ProcessCombatLog()
    elseif event == "PLAYER_LOGIN" then
        -- Welcome message when entering world or after /reload
        CT:ShowWelcomeMessage()
    elseif event == "PLAYER_LOGOUT" then
        CT:SaveData()
    end
end)
