-- CritTracker
-- Tracks your highest critical hits per specific spell/ability

CritTracker = {
    -- Constants for category names to avoid string literals
    CATEGORIES = {
        SPELLS = "spells",
        ABILITIES = "abilities",
        MELEE = "melee",
        WAND = "wand",
        HEALS = "heals"
    },
    
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
        recordSound = "MONEY" -- Default sound
    },
    -- Cache player GUID to avoid repeated calls
    playerGUID = nil
}

local CT = CritTracker

CT.sounds = {
    -- Sound options for dropdown
    { text = "Raid Warning", value = "RAID_WARNING", soundID = 8959 },
    { text = "Level Up", value = "LEVELUP", soundID = 888 },
    { text = "Ready Check", value = "READY_CHECK", soundID = 8960 },
    { text = "PVP Flag Taken", value = "PVP_FLAG", soundID = 8212 },
    { text = "Cash Money", value = "MONEY", soundID = 891 },
    { text = "Murloc Aggro", value = "MURLOC", soundID = 416 },
    { text = "Cheering Crowd", value = "CHEERS", soundID = 8571 },
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
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Deep copy a table
function CT:CopyTable(src)
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = self:CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Clean spell name 
function CT:CleanSpellName(spellName)
    if not spellName then return spellName end
    spellName = string.gsub(spellName, "%s+%(Rank%s+%d+%)", "")
    return string.gsub(spellName, "%s+%[Rank%s+%d+%]", "")
end

-- Initialize
function CT:Init(addonName)
    if addonName ~= "CritTracker" then return end
    
    -- Cache player GUID for performance
    self.playerGUID = UnitGUID("player")
    
	-- Initialize lookup table for tooltips
    self.spellLookup = {}
	
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
                    self.highestCrits[category] = self:CopyTable(data)
                end
            end
        end
    end
    
	-- Build the spell lookup table after loading data
    self:RebuildSpellLookup()
	
    -- Register slash commands
    SLASH_CRITTRACKER1 = "/ct"
    SLASH_CRITTRACKER2 = "/crittracker"
    SlashCmdList["CRITTRACKER"] = function(msg) self:HandleCommand(msg) end
    
    -- Set up tooltip hooks
    self:SetupTooltips()
    
    -- Initial welcome message (shown only on first load, not reload)
    self.initialized = true
end

-- Build the tooltip lookup table
function CT:RebuildSpellLookup()
    wipe(self.spellLookup or {})
    self.spellLookup = {}
    
    -- Add spells
    for spellName, data in pairs(self.highestCrits.spells) do
        if data.value > 0 then
            self.spellLookup[string.lower(spellName)] = {
                category = self.CATEGORIES.SPELLS,
                data = data,
                name = spellName
            }
        end
    end
    
    -- Add abilities
    for abilityName, data in pairs(self.highestCrits.abilities) do
        if data.value > 0 then
            self.spellLookup[string.lower(abilityName)] = {
                category = self.CATEGORIES.ABILITIES,
                data = data, 
                name = abilityName
            }
        end
    end
    
    -- Add heals
    for healName, data in pairs(self.highestCrits.heals) do
        if data.value > 0 then
            self.spellLookup[string.lower(healName)] = {
                category = self.CATEGORIES.HEALS,
                data = data,
                name = healName
            }
        end
    end
    
    -- Add wand special case
    if self.highestCrits.wand.value > 0 then
        self.spellLookup["shoot"] = {
            category = "wand",
            data = self.highestCrits.wand,
            name = "Wand Shot"
        }
    end
end

-- Update the player login message
function CT:ShowWelcomeMessage()
    self:Print("|cffff8800[CritTracker]|r Loaded. Type /ct to open settings or /ct help for commands.")
end

-- Helper to create UI elements - consolidated function
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

-- Helper function to create dropdown menu - avoids taint issues with unique name
function CT:CreateDropdown(parent, y, width, settingName, labelText, options)
    -- Create label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 25, y)
    label:SetText(labelText)
    
    -- Create dropdown frame with unique name to avoid taint
    local dropdownName = "CritTracker_"..settingName.."Dropdown_"..tostring(GetTime()):gsub("%.", "")
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
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
    
    -- Close frame when Escape key is pressed
    table.insert(UISpecialFrames, frameName)
    
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
    
    -- Use helper function to create checkboxes
    local _, newY = self:CreateCheckButton(frame, 20, y, "enabled", "Enable Tracking")
    _, newY = self:CreateCheckButton(frame, 20, newY, "announceParty", "Announce Records to Party")
    _, newY = self:CreateCheckButton(frame, 20, newY, "announceRaid", "Announce Records to Raid")
    _, newY = self:CreateCheckButton(frame, 20, newY, "playSoundOnRecord", "Play Sound on New Records")
    
    -- Add sound dropdown
    newY = newY - 10
    _, newY = self:CreateDropdown(frame, newY, 180, "recordSound", "Record Sound", self.sounds)
    
    -- Add Test Sound button
    local testSoundButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testSoundButton:SetSize(100, 22)
    testSoundButton:SetPoint("TOPLEFT", 30, newY - 15)
    testSoundButton:SetText("Test Sound")
    testSoundButton:SetScript("OnClick", function()
        -- Improved sound selection with proper fallback
        local selectedSound = CT.settings.recordSound
        local soundID = CT.sounds[1].soundID -- Default to first sound as fallback
        
        for _, sound in ipairs(CT.sounds) do
            if sound.value == selectedSound then
                soundID = sound.soundID
                break
            end
        end
        
        PlaySound(soundID)
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

-- Set up tooltip functionality - improved with error checking and case management
function CT:SetupTooltips()
    GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
        if not CT.settings.enabled then return end
        
        local spellName, spellRank = tooltip:GetSpell()
        if not spellName then return end
        
        -- Use the helper function to clean spell name 
        spellName = self:CleanSpellName(spellName)
        
               -- Use the lookup table instead of multiple loops
        local recordInfo = self.spellLookup[string.lower(spellName)]
        
        if recordInfo then
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffff8800[CritTracker]|r ")
            
            local timeAgo = CT:FormatTimeAgo(recordInfo.data.timestamp)
            tooltip:AddLine("Highest crit: |cffff0000" .. recordInfo.data.value .. "|r " .. timeAgo)
            
            tooltip:Show()
        end
    end)
end

-- Format time ago - more readable
function CT:FormatTimeAgo(timestamp)
    if not timestamp or timestamp == 0 then return "" end
    
    local now = time()
    local diff = now - timestamp
    
    if diff < 60 then
        return "(just now)"
    elseif diff < 3600 then
        return string.format("(%d min ago)", math.floor(diff / 60))
    elseif diff < 7200 then
        return "(1 hour ago)"
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

-- Handle slash commands - update for report panel
function CT:HandleCommand(msg)
    local args = {}
    for arg in string.gmatch(string.lower(msg or ""), "%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1] or "config"
    
    -- Command dispatch table for cleaner code
    local commandHandlers = {
        help = function()
            self:Print("|cffff8800[CritTracker]|r Commands:")
            self:Print("/ct - Open configuration panel")
            self:Print("/ct help - Show this help")
            self:Print("/ct toggle - Quickly enable/disable tracking")
            self:Print("/ct report [all/spell/ability/heal/physical] - Show highest crits")
            self:Print("/ct reset - Reset all records (with confirmation)")
        end,
        
        toggle = function()
            self.settings.enabled = not self.settings.enabled
            self:Print("Tracking " .. (self.settings.enabled and "enabled" or "disabled") .. ".")
        end,
        
        report = function()
            local category = args[2] or "all"
            
            -- Validate the category
            local validCategories = {
                ["all"] = true,
                ["spell"] = true,
                ["ability"] = true,
                ["heal"] = true,
                ["physical"] = true,
                ["melee"] = "physical", -- Map melee to physical category
                ["wand"] = "physical"   -- Map wand to physical category
            }
            
            -- Check if category is valid, otherwise default to "all"
            if not validCategories[category] then
                self:Print("Invalid category: '" .. category .. "'. Using 'all' instead.")
                category = "all"
            elseif type(validCategories[category]) == "string" then
                -- If the category maps to another one, use that
                category = validCategories[category]
            end
            
            -- Create and show the report panel
            if not self.reportFrame then
                self:CreateReportPanel(category)
            else
                -- If already created, just update and show it
                if not self.reportFrame:IsShown() then
                    self.reportFrame:Show()
                end
                
                -- Update content and highlight the proper category button
                self:UpdateReportPanelContent(self.reportFrame.scrollContent, category)
                
                -- Highlight the selected category button
                for _, button in ipairs(self.reportFrame.categoryButtons) do
                    if button.value == category then
                        button:LockHighlight()
                    else
                        button:UnlockHighlight()
                    end
                end
            end
        end,
        
        reset = function()
            StaticPopup_Show("CRITTRACKER_RESET_CONFIRM")
        end,
        
        -- Default action opens config panel
        config = function()
            if not self.configFrame then
                self:CreateConfigPanel()
            end
            
            if not self.configFrame:IsVisible() then
                -- Hide any other instances that might exist
                if CritTrackerConfigFrame and CritTrackerConfigFrame ~= self.configFrame then
                    CritTrackerConfigFrame:Hide()
                end
                self.configFrame:Show()
            else
                self.configFrame:Hide()
            end
        end
    }
    
    -- Execute the appropriate handler or default to config
    local handler = commandHandlers[command] or commandHandlers.config
    handler()
end

-- Reset records - with proper error checking
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
        self:Print("|cffff8800[CritTracker]|r All critical hit records have been reset.")
    elseif category == "spell" then
        self.highestCrits.spells = {}
        self:Print("|cffff8800[CritTracker]|r All spell critical hit records have been reset.")
    elseif category == "ability" then
        self.highestCrits.abilities = {}
        self:Print("|cffff8800[CritTracker]|r All ability critical hit records have been reset.")
    elseif category == "heal" then
        self.highestCrits.heals = {}
        self:Print("|cffff8800[CritTracker]|r All healing critical hit records have been reset.")
    elseif category == "melee" then
        self.highestCrits.melee = {value = 0, timestamp = 0}
        self:Print("|cffff8800[CritTracker]|r Melee critical hit record has been reset.")
    elseif category == "wand" then
        self.highestCrits.wand = {value = 0, timestamp = 0}
        self:Print("|cffff8800[CritTracker]|r Wand critical hit record has been reset.")
    else
        self:Print("|cffff8800[CritTracker]|r Unknown category. Use spell, ability, heal, melee, wand, or all.")
    end
end

-- Helper function for ShowHighestCrits - optimized for top-N selection
function CT:DisplayCritList(items, label, displayCount)
    displayCount = displayCount or 10 -- Default to top 10
    
    self:Print("|cffff8800[CritTracker]|r Highest " .. label .. " Critical Hits:|r")
    
    if #items == 0 then
        self:Print("  None recorded")
        return
    end
    
    -- Sort by value, highest first - only once
    table.sort(items, function(a, b) return a.value > b.value end)
    
    -- Display top items
    local displayedCount = math.min(displayCount, #items)
    for i = 1, displayedCount do
        local item = items[i]
        local timeAgo = self:FormatTimeAgo(item.timestamp)
        self:Print("  " .. item.name .. ": " .. item.value .. " " .. timeAgo)
    end
    
    if #items > displayCount then
        self:Print("  ... and " .. (#items - displayCount) .. " more " .. label:lower() .. "s")
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

-- Show highest crits - optimized with error checking
function CT:ShowHighestCrits(category)
    -- For list display categories (spells, abilities, heals)
    if category == "all" or category == "spell" then
        local spells = {}
        if self.highestCrits.spells then
            for spellName, data in pairs(self.highestCrits.spells) do
                table.insert(spells, {name = spellName, value = data.value, timestamp = data.timestamp})
            end
        end
        self:DisplayCritList(spells, "Spell")
    end
    
    if category == "all" or category == "ability" then
        local abilities = {}
        if self.highestCrits.abilities then
            for abilityName, data in pairs(self.highestCrits.abilities) do
                table.insert(abilities, {name = abilityName, value = data.value, timestamp = data.timestamp})
            end
        end
        self:DisplayCritList(abilities, "Ability")
    end
    
    if category == "all" or category == "heal" then
        local heals = {}
        if self.highestCrits.heals then
            for healName, data in pairs(self.highestCrits.heals) do
                table.insert(heals, {name = healName, value = data.value, timestamp = data.timestamp})
            end
        end
        self:DisplayCritList(heals, "Healing")
    end
    
    -- For single record categories (melee, wand)
    if category == "all" or category == "melee" then
        self:Print("|cffff8800[CritTracker]|r Highest Melee Critical Hit:")
        if self.highestCrits.melee and self.highestCrits.melee.value > 0 then
            local timeAgo = self:FormatTimeAgo(self.highestCrits.melee.timestamp)
            self:Print("  Melee Attack: " .. self.highestCrits.melee.value .. " " .. timeAgo)
        else
            self:Print("  None recorded")
        end
    end
    
    if category == "all" or category == "wand" then
        self:Print("|cffff8800[CritTracker]|r Highest Wand Critical Hit:")
        if self.highestCrits.wand and self.highestCrits.wand.value > 0 then
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
    
    -- Get all combat log info once and store in a local table
    local timestamp, event, _, sourceGUID, _, _, _, 
          destGUID, destName, _, _, 
          param1, param2, param3, param4, param5, param6, 
          param7, param8, param9, param10, param11, param12 = CombatLogGetCurrentEventInfo()
    
    -- Only track player's actions - use cached GUID for performance
    if sourceGUID ~= self.playerGUID then return end
    
    -- Handle specific events
    if event == "SWING_DAMAGE" then
        local amount, _, _, _, _, _, critical = param1, param2, param3, param4, param5, param6, param7
        if critical then
            self:RecordCrit(self.CATEGORIES.MELEE, "Melee Attack", amount)
        end
        
    elseif event == "RANGE_DAMAGE" then
        local spellId, spellName, spellSchool = param1, param2, param3
        local amount, _, _, _, _, _, critical = param4, param5, param6, param7, param8, param9, param10
        
        if critical then
            self:RecordCrit(self.CATEGORIES.WAND, spellName or "Wand Shot", amount)
        end
        
    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" then
        local spellId, spellName, spellSchool = param1, param2, param3
        local amount, _, _, _, _, _, critical = param4, param5, param6, param7, param8, param9, param10
        
        if critical and spellName then
            -- Use helper function to clean spell name
            spellName = self:CleanSpellName(spellName)
            
            -- In Classic, physical abilities have spellSchool = 1
            local category = (event == "SPELL_DAMAGE" and spellSchool == 1) 
                and self.CATEGORIES.ABILITIES 
                or self.CATEGORIES.SPELLS
                
            self:RecordCrit(category, spellName, amount)
        end
        
    elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool = param1, param2, param3
        local amount, _, _, critical = param4, param5, param6, param7
        
        if critical and spellName then
            spellName = self:CleanSpellName(spellName)
            self:RecordCrit(self.CATEGORIES.HEALS, spellName, amount)
        end
    end
end

-- Record critical hit - with better error handling and organization
function CT:RecordCrit(category, name, amount)
    local record = nil
    local isNewRecord = false
    local oldValue = 0
    
    -- Handle special cases for melee and wand which are single records
    if category == self.CATEGORIES.MELEE or category == self.CATEGORIES.WAND then
        record = self.highestCrits[category]
    else
        -- For spells, abilities, and heals
        -- Initialize if this spell hasn't been recorded before
        if not self.highestCrits[category] then
            self.highestCrits[category] = {}
        end
        
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
		-- Rebuild the lookup table when records change
        self:RebuildSpellLookup()
    end
    
    -- Notify player of new record
    if isNewRecord then
        local categoryLabel = category
        if category == self.CATEGORIES.SPELLS then categoryLabel = "SPELL"
        elseif category == self.CATEGORIES.ABILITIES then categoryLabel = "ABILITY"
        elseif category == self.CATEGORIES.HEALS then categoryLabel = "HEAL"
        elseif category == self.CATEGORIES.MELEE then categoryLabel = "MELEE"
        elseif category == self.CATEGORIES.WAND then categoryLabel = "WAND"
        end
        
        -- Format local message
        local message
        if oldValue == 0 then
            message = string.format("|cffff8800[CritTracker]|r New |cFF00CCFF%s|r crit record: |cffA335EE%s|r hit for: |cffff0000%d|r", categoryLabel, name, amount)
        else
            message = string.format("|cffff8800[CritTracker]|r New |cFF00CCFF%s|r crit record: |cffA335EE%s|r hit for: |cffff0000%d|r (prev: %d)", categoryLabel, name, amount, oldValue)
        end
        
        -- Show message to player
        self:Print(message)
        
        -- Set up message with no colors for party/raid announce
        local socialMessage
        -- Format socialMessage
        if oldValue == 0 then
            socialMessage = string.format("[CritTracker] New %s crit record! %s hit for: %d", categoryLabel, name, amount)
        else
            socialMessage = string.format("[CritTracker] New %s crit record! %s hit for: %d (prev: %d)", categoryLabel, name, amount, oldValue)
        end
        
        -- Announce to party/raid if appropriate - with rate limiting
        local currentTime = GetTime()
        if not self.lastAnnounceTime or (currentTime - self.lastAnnounceTime) > 1 then
            if IsInRaid() and self.settings.announceRaid then
                SendChatMessage(socialMessage, "RAID")
                self.lastAnnounceTime = currentTime
            elseif IsInGroup() and not IsInRaid() and self.settings.announceParty then
                SendChatMessage(socialMessage, "PARTY")
                self.lastAnnounceTime = currentTime
            end
        end
        
        -- Play sound if enabled - with better error handling
        if self.settings.playSoundOnRecord then
            local sound = self:GetSoundByValue(self.settings.recordSound)
            PlaySound(sound.soundID)
        end
    end
end

-- Create a report panel for displaying crit records
function CT:CreateReportPanel(category)
    -- Clean up any existing frames with the same name
    if _G["CritTrackerReportFrame"] then
        _G["CritTrackerReportFrame"]:Hide()
        _G["CritTrackerReportFrame"] = nil
    end
    
    -- Create the main frame
    local frameName = "CritTrackerReportFrame"
    local frame = CreateFrame("Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    
    -- Close frame when Escape key is pressed
    table.insert(UISpecialFrames, frameName)
    
    frame:SetSize(400, 500)
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
    frame.title:SetText("CritTracker Records")
    
    -- Create category buttons at the top
    local buttonWidth = 70
    local buttonSpacing = 5
    local totalWidth = (buttonWidth * 5) + (buttonSpacing * 4)
    local startX = (frame:GetWidth() - totalWidth) / 2
    
    local categories = {
        {text = "All", value = "all"},
        {text = "Spells", value = "spell"},
        {text = "Abilities", value = "ability"},
        {text = "Healing", value = "heal"},
        {text = "Physical", value = "physical"} -- Combines melee and wand
    }
    
    frame.categoryButtons = {}
    
    for i, cat in ipairs(categories) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(buttonWidth, 22)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + ((i-1) * (buttonWidth + buttonSpacing)), -30)
        button:SetText(cat.text)
        button.value = cat.value
        
        button:SetScript("OnClick", function()
            -- Highlight the selected button and unhighlight others
            for _, btn in ipairs(frame.categoryButtons) do
                if btn == button then
                    btn:LockHighlight()
                else
                    btn:UnlockHighlight()
                end
            end
            
            -- Update the displayed data
            self:UpdateReportPanelContent(frame.scrollContent, cat.value)
        end)
        
        table.insert(frame.categoryButtons, button)
    end
    
    -- Highlight the default/selected category
    for _, button in ipairs(frame.categoryButtons) do
        if button.value == (category or "all") then
            button:LockHighlight()
        end
    end
    
    -- Create a scrolling content frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1) -- Height will be set dynamically
    scrollFrame:SetScrollChild(content)
    
    -- Store references
    frame.scrollFrame = scrollFrame
    frame.scrollContent = content
    
    -- Display crit information in the panel
    self:UpdateReportPanelContent(content, category or "all")
    
    -- Make sure the close button actually works
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Save frame reference and return
    self.reportFrame = frame
    return frame
end

-- Display crit information in the report panel
function CT:UpdateReportPanelContent(contentFrame, category)
    -- Clear existing content
    for _, child in pairs({contentFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in pairs({contentFrame:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    local y = 5
    local lineHeight = 20
    
    -- Helper function to add a text line
    local function AddHeader(text)
        local header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 5, -y)
        header:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -5, -y)
        header:SetJustifyH("LEFT")
        header:SetText("|cffff8800" .. text .. "|r")
        y = y + lineHeight + 5
        return header
    end
    
    local function AddNoneRecorded(indent)
        local line = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", indent or 15, -y)
        line:SetText("None recorded")
        y = y + lineHeight
        return line
    end
    
	local function CreateRecordLine(parent, recordName, recordValue, recordTime)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetSize(parent:GetWidth() - 20, lineHeight)
		frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -y)
		
		-- Name text - reduce width to give more space to other elements
		local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
		nameText:SetPoint("LEFT", frame, "LEFT", 0, 0)
		nameText:SetWidth(180) -- Reduced from 240
		nameText:SetJustifyH("LEFT")
		nameText:SetText(recordName)
		
		-- Value text - position closer to the name
		local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		valueText:SetPoint("LEFT", nameText, "RIGHT", 5, 0)
		valueText:SetWidth(60) -- Adjusted width
		valueText:SetJustifyH("RIGHT")
		valueText:SetText("|cffFF4500" .. recordValue .. "|r")
		
		-- Time text - position relative to value
		local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		timeText:SetPoint("LEFT", valueText, "RIGHT", 5, 0)
		timeText:SetWidth(80)
		timeText:SetJustifyH("LEFT") -- Changed from RIGHT to LEFT
		timeText:SetText("|cff888888" .. recordTime .. "|r")
		
		y = y + lineHeight
		return frame
	end
    
    -- Helper to display a category of crits
    local function DisplayCategory(catName, records, label)
        AddHeader(label)
        
        if not records or #records == 0 then
            AddNoneRecorded()
            y = y + 10
            return
        end
        
        -- Sort by value, highest first
        table.sort(records, function(a, b) return a.value > b.value end)
        
        -- Display top items
        local displayCount = math.min(25, #records)
        for i = 1, displayCount do
            local record = records[i]
            local timeAgo = self:FormatTimeAgo(record.timestamp)
            CreateRecordLine(contentFrame, record.name, record.value, timeAgo)
        end
        
        if #records > displayCount then
            local moreText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            moreText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, -y)
            moreText:SetText("|cff888888... and " .. (#records - displayCount) .. " more " .. catName:lower() .. "s|r")
            y = y + lineHeight
        end
        
        y = y + 15
    end
    
    -- Process each category based on selection
    if category == "all" or category == "spell" then
        local spells = {}
        if self.highestCrits.spells then
            for spellName, data in pairs(self.highestCrits.spells) do
                if data.value > 0 then -- Only include records with values
                    table.insert(spells, {name = spellName, value = data.value, timestamp = data.timestamp})
                end
            end
        end
        DisplayCategory("Spell", spells, "Spell Critical Hits")
    end
    
    if category == "all" or category == "ability" then
        local abilities = {}
        if self.highestCrits.abilities then
            for abilityName, data in pairs(self.highestCrits.abilities) do
                if data.value > 0 then -- Only include records with values
                    table.insert(abilities, {name = abilityName, value = data.value, timestamp = data.timestamp})
                end
            end
        end
        DisplayCategory("Ability", abilities, "Ability Critical Hits")
    end
    
    if category == "all" or category == "heal" then
        local heals = {}
        if self.highestCrits.heals then
            for healName, data in pairs(self.highestCrits.heals) do
                if data.value > 0 then -- Only include records with values
                    table.insert(heals, {name = healName, value = data.value, timestamp = data.timestamp})
                end
            end
        end
        DisplayCategory("Healing", heals, "Healing Critical Hits")
    end
    
    if category == "all" or category == "physical" then
        AddHeader("Physical Critical Hits")
        
        -- Display melee crit if available
        if self.highestCrits.melee and self.highestCrits.melee.value > 0 then
            local timeAgo = self:FormatTimeAgo(self.highestCrits.melee.timestamp)
            CreateRecordLine(contentFrame, "Melee Attack", self.highestCrits.melee.value, timeAgo)
        else
            -- No melee records
            local noMeleeText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noMeleeText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, -y)
            noMeleeText:SetText("No melee crits recorded")
            y = y + lineHeight
        end
        
        -- Display wand crit if available
        if self.highestCrits.wand and self.highestCrits.wand.value > 0 then
            local timeAgo = self:FormatTimeAgo(self.highestCrits.wand.timestamp)
            CreateRecordLine(contentFrame, "Wand Shot", self.highestCrits.wand.value, timeAgo)
        else
            -- No wand records
            local noWandText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noWandText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, -y)
            noWandText:SetText("No wand crits recorded")
            y = y + lineHeight
        end
        
        y = y + 15
    end
    
    -- Set content height
    contentFrame:SetHeight(y + 20)
end

-- Save data between sessions
function CT:SaveData()
    CritTrackerDB = {
        settings = self.settings,
        highestCrits = self.highestCrits
    }
end

-- Event handlers table for cleaner organization
local eventHandlers = {
    ADDON_LOADED = function(addonName)
        CT:Init(addonName)
    end,
    
    COMBAT_LOG_EVENT_UNFILTERED = function()
        CT:ProcessCombatLog()
    end,
    
    PLAYER_LOGIN = function()
        CT:ShowWelcomeMessage()
    end,
    
    PLAYER_LOGOUT = function()
        CT:SaveData()
    end
}

-- Consolidated event handler with dispatcher
frame:SetScript("OnEvent", function(self, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(...)
    end
end)
