local addonName = ...

local ADDON_VERSION = "1.2.1"
local PREFIX = "|cff58c6ffEbonhold Smart Mounts:|r "
local DEFAULT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local SUMMON_MACRO_NAME = "EH Smart Mount"
local SUMMON_MACRO_BODY = "/click EbonholdSmartMountsButton"
local VISIBLE_ROWS = 8

local POOLS = {
    { key = "ground", label = "Ground" },
    { key = "flying", label = "Flying" },
}

local WEIGHTS = {
    rare = { label = "Rare", tickets = 1 },
    normal = { label = "Normal", tickets = 2 },
    frequent = { label = "Frequent", tickets = 4 },
}
local NEXT_WEIGHT = {
    rare = "normal",
    normal = "frequent",
    frequent = "rare",
}

local POOL_LOOKUP = {}
local _, definition
for _, definition in ipairs(POOLS) do
    POOL_LOOKUP[definition.key] = definition
end

BINDING_HEADER_EBONHOLDSMARTMOUNTS = "Ebonhold Smart Mounts"
BINDING_NAME_EBONHOLDSMARTMOUNTS_SUMMON = "Summon smart random mount"

local eventFrame = CreateFrame("Frame")
local panel
local summonButton
local searchBox
local detectedModeText
local sourceText
local countText
local showButtonCheck
local lockButtonCheck
local scrollBar
local macroStatusText
local scopeButton
local overrideButton
local rows = {}
local mounts = {}
local filteredMounts = {}
local scrollOffset = 0
local shuffleBags = {}
local lastMountKey = {}
local macroUpdatePending
local macroAutoAttempted
local refreshSequenceFrame
local uiReady
local scanDetails = {}
local RefreshPanel
local RefreshRows

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message))
end

local function Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function Lower(value)
    return string.lower(value or "")
end

local function Boolean(value)
    return value and true or false
end

local function GetCharacterKey()
    local characterName = type(UnitName) == "function" and UnitName("player") or "Unknown"
    local realmName = type(GetRealmName) == "function" and GetRealmName() or "Realm"
    return tostring(characterName) .. "-" .. tostring(realmName)
end

local function InitializeDatabase()
    if type(EbonholdSmartMountsDB) ~= "table" then
        EbonholdSmartMountsDB = {}
    end

    local db = EbonholdSmartMountsDB
    db.assignments = type(db.assignments) == "table" and db.assignments or {}
    db.assignmentOverrides = type(db.assignmentOverrides) == "table" and db.assignmentOverrides or {}
    db.weights = type(db.weights) == "table" and db.weights or {}
    db.zoneOverrides = type(db.zoneOverrides) == "table" and db.zoneOverrides or {}
    db.managedMacros = type(db.managedMacros) == "table" and db.managedMacros or {}
    db.button = type(db.button) == "table" and db.button or {}
    db.ui = type(db.ui) == "table" and db.ui or {}

    if db.button.shown == nil then db.button.shown = true end
    if db.button.locked == nil then db.button.locked = false end
    if db.ui.overrideScope ~= "subzone" then db.ui.overrideScope = "zone" end
end

local function BuildMountKey(spellID, secondaryID, name)
    if spellID then
        return "spell:" .. tostring(spellID)
    elseif secondaryID then
        return "mount:" .. tostring(secondaryID)
    end
    return "name:" .. Lower(name)
end

local function GetAssignment(mountKey, create)
    local key = tostring(mountKey)
    local assignment = EbonholdSmartMountsDB.assignments[key]

    if type(assignment) ~= "table" then
        local legacySpellID = string.match(key, "^spell:(.+)$")
        if legacySpellID and type(EbonholdSmartMountsDB.assignments[legacySpellID]) == "table" then
            assignment = EbonholdSmartMountsDB.assignments[legacySpellID]
            EbonholdSmartMountsDB.assignments[key] = assignment
            EbonholdSmartMountsDB.assignments[legacySpellID] = nil
        end
    end

    if create and type(assignment) ~= "table" then
        assignment = {}
        EbonholdSmartMountsDB.assignments[key] = assignment
    end
    return assignment, key
end

local function SetAssignment(mountKey, poolKey, enabled, manual)
    local assignment, key = GetAssignment(mountKey, true)
    assignment[poolKey] = enabled and true or nil

    if manual then
        EbonholdSmartMountsDB.assignmentOverrides[key] =
            type(EbonholdSmartMountsDB.assignmentOverrides[key]) == "table"
                and EbonholdSmartMountsDB.assignmentOverrides[key]
                or {}
        EbonholdSmartMountsDB.assignmentOverrides[key][poolKey] = enabled and true or false
    end

    local hasAssignment = false
    local _, pool
    for _, pool in ipairs(POOLS) do
        if assignment[pool.key] then
            hasAssignment = true
            break
        end
    end
    if not hasAssignment then
        EbonholdSmartMountsDB.assignments[key] = nil
    end
    shuffleBags = {}
end

local function GetWeight(mountKey)
    local weight = EbonholdSmartMountsDB.weights[tostring(mountKey)]
    if not WEIGHTS[weight] then
        return "normal"
    end
    return weight
end

local function SetWeight(mountKey, weight)
    if weight == "normal" then
        EbonholdSmartMountsDB.weights[tostring(mountKey)] = nil
    else
        EbonholdSmartMountsDB.weights[tostring(mountKey)] = weight
    end
    shuffleBags = {}
end

local FLYING_WORDS = {
    "gryphon", "wind rider", "drake", "proto-drake", "hippogryph",
    "dragonhawk", "nether ray", "flying carpet", "frostwyrm", "phoenix",
    "flying machine", "rocket", "broom", "invincible", "mimiron's head",
    "celestial steed", "ashes of al'ar", "winged steed", "frostbrood",
    "headless horseman's mount",
}
local AQ_WORDS = { "qiraji battle tank", "qiraji resonating crystal" }

local function ContainsAny(value, words)
    local lowered = Lower(value)
    local _, word
    for _, word in ipairs(words) do
        if string.find(lowered, word, 1, true) then return true end
    end
    return false
end

local function MountTypeCanFly(mountType)
    if type(mountType) ~= "number" then return false end
    return math.floor(mountType / 2) % 2 == 1
end

local function GetMountCategory(mount)
    if MountTypeCanFly(mount.mountType) or ContainsAny(mount.name, FLYING_WORDS) then
        return "flying"
    end
    return "ground"
end

local function IsAQMount(mount)
    return ContainsAny(mount.name, AQ_WORDS)
end

local function ResetScanDetails()
    scanDetails = {
        source = "not scanned",
        upperCount = 0,
        lowerCount = 0,
        journalCount = 0,
        cacheCount = 0,
        liveCount = 0,
        skippedCount = 0,
    }
end

local function MountKeyExists(mountKey)
    local _, mount
    for _, mount in ipairs(mounts) do
        if mount.key == mountKey then
            return true
        end
    end
    return false
end

local function SafeCompanionCount(companionType)
    if type(GetNumCompanions) ~= "function" then return 0 end
    local ok, count = pcall(GetNumCompanions, companionType)
    return ok and type(count) == "number" and count or 0
end

local function GetJournalMountType(mountID)
    if type(C_MountJournal) ~= "table"
        or type(C_MountJournal.GetMountInfoExtraByID) ~= "function"
    then
        return nil
    end
    local ok, _, _, _, _, mountType = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
    return ok and mountType or nil
end

local function ScanMountJournal()
    if type(C_MountJournal) ~= "table"
        or type(C_MountJournal.GetMountIDs) ~= "function"
        or type(C_MountJournal.GetMountInfoByID) ~= "function"
    then
        return false
    end

    local ok, mountIDs = pcall(C_MountJournal.GetMountIDs)
    if not ok or type(mountIDs) ~= "table" then
        scanDetails.source = "Mount Journal unavailable"
        return true
    end

    scanDetails.source = "Mount Journal"
    scanDetails.journalCount = #mountIDs

    local _, mountID
    for _, mountID in ipairs(mountIDs) do
        local infoOK, name, spellID, icon, isActive, isUsable, sourceType,
            isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected =
            pcall(C_MountJournal.GetMountInfoByID, mountID)

        if infoOK and name and isCollected and not shouldHideOnChar then
            table.insert(mounts, {
                key = BuildMountKey(spellID, mountID, name),
                source = "journal",
                availableNow = true,
                mountID = mountID,
                name = name,
                spellID = spellID,
                icon = icon or DEFAULT_ICON,
                isSummoned = isActive,
                isUsable = isUsable,
                mountType = GetJournalMountType(mountID),
                sourceType = sourceType,
                isFavorite = isFavorite,
                isFactionSpecific = isFactionSpecific,
                faction = faction,
            })
            scanDetails.liveCount = scanDetails.liveCount + 1
        else
            scanDetails.skippedCount = scanDetails.skippedCount + 1
        end
    end
    return true
end

local function ScanCompanions()
    if type(GetNumCompanions) ~= "function" or type(GetCompanionInfo) ~= "function" then
        scanDetails.source = "Companion API unavailable"
        return
    end

    scanDetails.upperCount = SafeCompanionCount("MOUNT")
    scanDetails.lowerCount = SafeCompanionCount("mount")
    local companionType = "MOUNT"
    local count = scanDetails.upperCount
    if count == 0 and scanDetails.lowerCount > 0 then
        companionType = "mount"
        count = scanDetails.lowerCount
    end
    scanDetails.source = "Companion API (" .. companionType .. ")"

    local index
    for index = 1, count do
        local ok, creatureID, name, spellID, icon, isSummoned, mountType =
            pcall(GetCompanionInfo, companionType, index)
        if ok and name then
            table.insert(mounts, {
                key = BuildMountKey(spellID, creatureID, name),
                source = "companion",
                availableNow = true,
                companionType = companionType,
                index = index,
                creatureID = creatureID,
                name = name,
                spellID = spellID,
                icon = icon or DEFAULT_ICON,
                isSummoned = isSummoned,
                mountType = mountType,
            })
            scanDetails.liveCount = scanDetails.liveCount + 1
        else
            scanDetails.skippedCount = scanDetails.skippedCount + 1
        end
    end
end

local function ScanEbonCompletionistCache()
    local cache = type(EbonCompletionistDB) == "table"
        and type(EbonCompletionistDB.account) == "table"
        and EbonCompletionistDB.account.mounts
    if type(cache) ~= "table" then return end

    local _, info
    for _, info in pairs(cache) do
        if type(info) == "table" and info.name then
            local key = BuildMountKey(info.spellID, info.creatureID, info.name)
            scanDetails.cacheCount = scanDetails.cacheCount + 1
            if not MountKeyExists(key) then
                table.insert(mounts, {
                    key = key,
                    source = "account cache",
                    availableNow = false,
                    name = info.name,
                    spellID = info.spellID,
                    creatureID = info.creatureID,
                    icon = info.icon or DEFAULT_ICON,
                })
            end
        end
    end
end

local function ScanMounts()
    mounts = {}
    ResetScanDetails()
    if not ScanMountJournal() then
        ScanCompanions()
    end
    ScanEbonCompletionistCache()

    local _, mount
    for _, mount in ipairs(mounts) do
        mount.category = GetMountCategory(mount)
        mount.excludedAQ = IsAQMount(mount)
        local assignment = GetAssignment(mount.key, false)
        if mount.excludedAQ then
            EbonholdSmartMountsDB.assignments[mount.key] = nil
        elseif assignment then
            -- A row only belongs to its detected physical mount type. Clean
            -- up selections made by older versions that exposed both boxes.
            if mount.category == "ground" then
                assignment.flying = nil
            else
                assignment.ground = nil
            end
        end
    end
    table.sort(mounts, function(left, right)
        return Lower(left.name) < Lower(right.name)
    end)
    return mounts
end

local function GetCurrentLocation()
    local zone = type(GetRealZoneText) == "function" and GetRealZoneText()
        or (type(GetZoneText) == "function" and GetZoneText())
        or "Unknown"
    local subZone = type(GetSubZoneText) == "function" and GetSubZoneText() or ""
    return zone, subZone
end

local function GetScopeKey(scope)
    local zone, subZone = GetCurrentLocation()
    if scope == "subzone" and subZone ~= "" then
        return "subzone:" .. zone .. "|" .. subZone, subZone
    end
    return "zone:" .. zone, zone
end

local function GetSavedZoneOverride()
    local zone, subZone = GetCurrentLocation()
    if subZone ~= "" then
        local subOverride = EbonholdSmartMountsDB.zoneOverrides["subzone:" .. zone .. "|" .. subZone]
        if subOverride == "ground" or subOverride == "flying" then
            return subOverride, "sub-zone override"
        end
    end
    local zoneOverride = EbonholdSmartMountsDB.zoneOverrides["zone:" .. zone]
    if zoneOverride == "ground" or zoneOverride == "flying" then
        return zoneOverride, "zone override"
    end
    return nil
end

local function GetAutomaticMode()
    local canFly = type(IsFlyableArea) == "function" and IsFlyableArea() or false
    local reason = canFly and "area is flyable" or "area is not flyable"

    if type(IsInInstance) == "function" and IsInInstance() then
        canFly = false
        reason = "inside an instance"
    end

    local zone, subZone = GetCurrentLocation()
    if zone == "Dalaran" and subZone ~= "Krasus' Landing" then
        canFly = false
        reason = "Dalaran ground area"
    end
    if zone == "Wintergrasp"
        and type(GetWintergraspWaitTime) == "function"
        and GetWintergraspWaitTime() == nil
    then
        canFly = false
        reason = "Wintergrasp battle"
    end

    local savedOverride, overrideReason = GetSavedZoneOverride()
    if savedOverride then
        canFly = savedOverride == "flying"
        reason = overrideReason
    end

    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
        canFly = true
        reason = "Control override"
    elseif type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        canFly = false
        reason = "Shift override"
    end

    return canFly and "flying" or "ground", reason
end

local function HasAssignment(mount, poolKey)
    local assignment = GetAssignment(mount.key, false)
    return assignment and assignment[poolKey] and true or false
end

local function BuildPool(poolKey)
    ScanMounts()
    local all = {}
    local ready = {}
    local _, mount
    for _, mount in ipairs(mounts) do
        if not mount.excludedAQ and mount.category == poolKey and HasAssignment(mount, poolKey) then
            table.insert(all, mount)
            if mount.availableNow then
                table.insert(ready, mount)
            end
        end
    end
    -- Prefer mounts confirmed by the live client. Cached mounts remain a
    -- fallback for Ebonhold characters whose account collection loads late.
    return #ready > 0 and ready or all
end

local function GetContextPool(requestedPool)
    if requestedPool and POOL_LOOKUP[requestedPool] then
        return requestedPool, "requested pool"
    end

    return GetAutomaticMode()
end

local function Shuffle(list)
    local index
    for index = #list, 2, -1 do
        local other = math.random(index)
        list[index], list[other] = list[other], list[index]
    end
end

local function BuildPoolSignature(pool)
    local parts = {}
    local _, mount
    for _, mount in ipairs(pool) do
        table.insert(parts, mount.key .. ":" .. GetWeight(mount.key))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function RebuildShuffleBag(pool, poolKey, signature)
    local primary = {}
    local bonus = {}
    local _, mount
    for _, mount in ipairs(pool) do
        table.insert(primary, mount)
        local tickets = WEIGHTS[GetWeight(mount.key)].tickets
        local extra
        for extra = 2, tickets do
            table.insert(bonus, mount)
        end
    end
    Shuffle(primary)
    Shuffle(bonus)
    shuffleBags[poolKey] = { signature = signature, primary = primary, bonus = bonus }
    return shuffleBags[poolKey]
end

local function PopAvoidingImmediateRepeat(list, poolKey)
    if #list == 0 then return nil end
    if #list > 1 and list[#list].key == lastMountKey[poolKey] then
        local index
        for index = #list - 1, 1, -1 do
            if list[index].key ~= lastMountKey[poolKey] then
                list[index], list[#list] = list[#list], list[index]
                break
            end
        end
    end
    return table.remove(list)
end

local function PickShuffleMount(pool, poolKey)
    if #pool == 0 then return nil end
    local signature = BuildPoolSignature(pool)
    local state = shuffleBags[poolKey]
    if not state or state.signature ~= signature
        or (#state.primary == 0 and #state.bonus == 0)
    then
        state = RebuildShuffleBag(pool, poolKey, signature)
    end

    local mount
    if #state.primary > 0 then
        mount = PopAvoidingImmediateRepeat(state.primary, poolKey)
    else
        mount = PopAvoidingImmediateRepeat(state.bonus, poolKey)
    end
    lastMountKey[poolKey] = mount and mount.key or nil
    return mount
end

local function ChooseMount(requestedPool)
    local poolKey, reason = GetContextPool(requestedPool)
    local pool = BuildPool(poolKey)

    if #pool == 0 then
        return nil, poolKey, reason
    end
    return PickShuffleMount(pool, poolKey), poolKey, reason
end

local function UpdateSummonButtonIcon(icon)
    if summonButton and summonButton.icon then
        summonButton.icon:SetTexture(icon or DEFAULT_ICON)
    end
end

local function SummonSmartMount(requestedPool)
    if type(IsMounted) == "function" and IsMounted() then
        if type(IsFlying) == "function" and IsFlying()
            and not (type(IsAltKeyDown) == "function" and IsAltKeyDown())
        then
            Print("Already flying. Hold Alt while pressing the button to dismount in the air.")
            return
        end
        if type(Dismount) == "function" then Dismount() end
        return
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Print("You cannot mount while in combat.")
        return
    end

    local mount, poolKey, reason = ChooseMount(requestedPool)
    if not mount then
        Print("No " .. poolKey .. " mounts are selected and available.")
        return
    end
    UpdateSummonButtonIcon(mount.icon)

    local ok, errorMessage
    if mount.source == "journal" and type(C_MountJournal.SummonByID) == "function" then
        ok, errorMessage = pcall(C_MountJournal.SummonByID, mount.mountID)
    elseif mount.source == "companion" and type(CallCompanion) == "function" then
        ok, errorMessage = pcall(CallCompanion, mount.companionType or "MOUNT", mount.index)
    elseif type(CastSpellByName) == "function" then
        ok, errorMessage = pcall(CastSpellByName, mount.name)
    else
        ok = false
        errorMessage = "no supported summon API"
    end

    if not ok then
        Print("Could not summon " .. mount.name .. ": " .. tostring(errorMessage))
    elseif EbonholdSmartMountsDB.debug then
        Print("Selected " .. mount.name .. " from " .. poolKey .. " (" .. reason .. ").")
    end
end

function EbonholdSmartMounts_Summon()
    SummonSmartMount()
end

local function PrepareSecureSummon(self, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Print("You cannot mount while in combat.")
        return
    end

    if type(IsMounted) == "function" and IsMounted() then
        if type(IsFlying) == "function" and IsFlying()
            and not (type(IsAltKeyDown) == "function" and IsAltKeyDown())
        then
            self:SetAttribute("macrotext1", "")
            Print("Already flying. Hold Alt while pressing the button to dismount in the air.")
            return
        end
        self:SetAttribute("macrotext1", "/dismount")
        return
    end

    local mount, poolKey, reason = ChooseMount(nil)
    if not mount then
        self:SetAttribute("macrotext1", "")
        Print("No " .. poolKey .. " mounts are selected and available.")
        return
    end

    UpdateSummonButtonIcon(mount.icon)
    local safeName = string.gsub(mount.name, "[\r\n]", " ")
    self:SetAttribute("macrotext1", "/cast " .. safeName)
    if EbonholdSmartMountsDB.debug then
        Print("Prepared " .. mount.name .. " from " .. poolKey .. " (" .. reason .. ").")
    end
end

local function GetSummonMacroIconIndex()
    if type(GetMacroIcons) ~= "function" then return 1 end
    local icons = GetMacroIcons()
    if type(icons) ~= "table" then return 1 end
    local index, iconName
    for index, iconName in ipairs(icons) do
        if iconName and Lower(iconName) == "ability_mount_ridinghorse" then
            return index
        end
    end
    return 1
end

local function GetSummonMacroStatus()
    if type(GetMacroIndexByName) ~= "function" or type(GetMacroInfo) ~= "function" then
        return "Unavailable", 0, "unavailable"
    end
    local index = GetMacroIndexByName(SUMMON_MACRO_NAME) or 0
    if index <= 0 then return "Missing", 0, "missing" end
    local _, _, body = GetMacroInfo(index)
    if body == SUMMON_MACRO_BODY then return "Ready", index, "ready" end
    return "Name conflict", index, "conflict"
end

local function EnsureSummonMacro(announce)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        macroUpdatePending = true
        if announce then Print("The summon macro will be created after combat.") end
        return false
    end
    macroUpdatePending = nil

    if type(CreateMacro) ~= "function" or type(GetMacroIndexByName) ~= "function"
        or type(GetMacroInfo) ~= "function"
    then
        if announce then Print("This client does not provide the macro-management API.") end
        return false
    end

    local status, index = GetSummonMacroStatus()
    local characterKey = GetCharacterKey()
    if status == "Ready" then
        EbonholdSmartMountsDB.managedMacros[characterKey] = true
        if announce then Print("The " .. SUMMON_MACRO_NAME .. " macro is ready.") end
        return true
    elseif status == "Name conflict" then
        local _, _, existingBody = GetMacroInfo(index)
        local mayRepair = EbonholdSmartMountsDB.managedMacros[characterKey]
            or existingBody == "/ehmsummon"
        if not mayRepair then
            if announce then Print("A different macro named " .. SUMMON_MACRO_NAME .. " already exists.") end
            return false
        end
        if type(EditMacro) == "function" then
            local ok = pcall(EditMacro, index, SUMMON_MACRO_NAME, GetSummonMacroIconIndex(), SUMMON_MACRO_BODY, 1)
            local newStatus = GetSummonMacroStatus()
            if ok and newStatus == "Ready" then
                EbonholdSmartMountsDB.managedMacros[characterKey] = true
                if announce then Print("Repaired the " .. SUMMON_MACRO_NAME .. " macro.") end
                return true
            end
        end
        if announce then Print("The existing summon macro could not be repaired.") end
        return false
    end

    if type(GetNumMacros) == "function" then
        local _, characterCount = GetNumMacros()
        if type(characterCount) == "number" and characterCount >= (MAX_CHARACTER_MACROS or 18) then
            if announce then Print("No character macro slots are available.") end
            return false
        end
    end

    local ok, newIndex = pcall(
        CreateMacro,
        SUMMON_MACRO_NAME,
        GetSummonMacroIconIndex(),
        SUMMON_MACRO_BODY,
        1
    )
    if ok and type(newIndex) == "number" and newIndex > 0 then
        EbonholdSmartMountsDB.managedMacros[characterKey] = true
        Print("Created the " .. SUMMON_MACRO_NAME .. " macro. Drag it from /macro to an action bar.")
        return true
    end
    if announce then
        Print("The summon macro could not be created: "
            .. (not ok and tostring(newIndex) or "the client returned no macro index") .. ".")
    end
    return false
end

local function PlaceSummonMacroOnCursor()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Print("The macro cannot be picked up during combat.")
        return
    end
    local status, index = GetSummonMacroStatus()
    if status ~= "Ready" then
        if not EnsureSummonMacro(true) then return end
        status, index = GetSummonMacroStatus()
    end
    if status == "Ready" and type(PickupMacro) == "function" then
        PickupMacro(index)
        Print("The macro is on your cursor. Click an action-bar slot to place it.")
    end
end

local function SaveSummonButtonPosition()
    if not summonButton then return end
    local left, bottom = summonButton:GetLeft(), summonButton:GetBottom()
    if left and bottom then
        EbonholdSmartMountsDB.button.left = left
        EbonholdSmartMountsDB.button.bottom = bottom
    end
end

local function ApplySummonButtonSettings()
    if not summonButton then return end
    summonButton:ClearAllPoints()
    local buttonDB = EbonholdSmartMountsDB.button
    if buttonDB.left and buttonDB.bottom then
        summonButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", buttonDB.left, buttonDB.bottom)
    else
        summonButton:SetPoint("CENTER", UIParent, "CENTER", 220, -80)
    end
    if buttonDB.shown then summonButton:Show() else summonButton:Hide() end
end

local function TogglePanel()
    if not panel then return end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

local function CreateSummonButton()
    summonButton = CreateFrame("Button", "EbonholdSmartMountsButton", UIParent, "SecureActionButtonTemplate")
    summonButton:SetWidth(44)
    summonButton:SetHeight(44)
    summonButton:SetClampedToScreen(true)
    summonButton:SetMovable(true)
    summonButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    summonButton:RegisterForDrag("LeftButton")
    summonButton:SetAttribute("type1", "macro")
    summonButton:SetAttribute("macrotext1", "")
    summonButton:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    summonButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    summonButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local icon = summonButton:CreateTexture(nil, "BACKGROUND")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(DEFAULT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    summonButton.icon = icon

    summonButton:SetScript("OnDragStart", function(self)
        if EbonholdSmartMountsDB.button.locked then return end
        if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
        self:StartMoving()
    end)
    summonButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSummonButtonPosition()
    end)
    summonButton:SetScript("PreClick", PrepareSecureSummon)
    summonButton:SetScript("PostClick", function(_, mouseButton)
        if mouseButton == "RightButton" then TogglePanel() end
    end)
    summonButton:SetScript("OnEnter", function(self)
        local poolKey, reason = GetContextPool(nil)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Ebonhold Smart Mounts", 0.35, 0.78, 1)
        GameTooltip:AddLine("Next pool: " .. poolKey .. " (" .. reason .. ")", 1, 1, 1)
        GameTooltip:AddLine("Left-click: summon or dismount", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Right-click: configure", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Shift: Ground | Control: Flying", 0.75, 0.75, 0.75)
        if not EbonholdSmartMountsDB.button.locked then
            GameTooltip:AddLine("Drag to move", 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    summonButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ApplySummonButtonSettings()
end

local function BuildFilteredMounts()
    filteredMounts = {}
    local query = searchBox and Lower(Trim(searchBox:GetText())) or ""
    local _, mount
    for _, mount in ipairs(mounts) do
        if not mount.excludedAQ
            and (query == "" or string.find(Lower(mount.name), query, 1, true))
        then
            table.insert(filteredMounts, mount)
        end
    end
    table.sort(filteredMounts, function(left, right)
        return Lower(left.name) < Lower(right.name)
    end)
end

local function UpdateScrollBar()
    if not scrollBar then return end
    local maximum = math.max(0, #filteredMounts - VISIBLE_ROWS)
    if scrollOffset > maximum then scrollOffset = maximum end
    scrollBar:SetMinMaxValues(0, maximum)
    -- Vertical sliders place their minimum at the bottom. Invert the value
    -- so offset zero correctly displays the thumb at the top of the list.
    scrollBar:SetValue(maximum - scrollOffset)
    if maximum == 0 then scrollBar:Hide() else scrollBar:Show() end
end

local function ScrollMountList(amount)
    if not scrollBar then return end
    local _, maximum = scrollBar:GetMinMaxValues()
    scrollOffset = math.max(0, math.min(maximum, scrollOffset + amount))
    scrollBar:SetValue(maximum - scrollOffset)
    RefreshRows()
end

local function GetMountPoolSummary(mount)
    local labels = {}
    local _, pool
    for _, pool in ipairs(POOLS) do
        if HasAssignment(mount, pool.key) then table.insert(labels, pool.label) end
    end
    return #labels > 0 and table.concat(labels, ", ") or "None"
end

RefreshRows = function()
    local rowIndex
    for rowIndex = 1, VISIBLE_ROWS do
        local row = rows[rowIndex]
        local mount = filteredMounts[scrollOffset + rowIndex]
        if mount then
            row.mount = mount
            row.icon:SetTexture(mount.icon)
            row.name:SetText(mount.name)
            if mount.availableNow then
                row.name:SetTextColor(1, 1, 1)
                row.status:SetText("|cff66dd66Ready|r")
            else
                row.name:SetTextColor(0.55, 0.55, 0.55)
                row.status:SetText("|cff999999Cached|r")
            end
            local weight = GetWeight(mount.key)
            row.weightButton:SetText(WEIGHTS[weight].label)
            row.groundCheck:SetChecked(Boolean(HasAssignment(mount, "ground")))
            row.flyingCheck:SetChecked(Boolean(HasAssignment(mount, "flying")))
            if mount.category == "ground" then
                row.groundCheck:Show()
                row.flyingCheck:Hide()
            else
                row.groundCheck:Hide()
                row.flyingCheck:Show()
            end
            row:Show()
        else
            row.mount = nil
            row:Hide()
        end
    end
end

local function CountPool(poolKey)
    local count = 0
    local _, mount
    for _, mount in ipairs(mounts) do
        if not mount.excludedAQ and mount.category == poolKey and HasAssignment(mount, poolKey) then
            count = count + 1
        end
    end
    return count
end

local function CountEligibleMounts()
    local count = 0
    local _, mount
    for _, mount in ipairs(mounts) do
        if not mount.excludedAQ then count = count + 1 end
    end
    return count
end

local function UpdateMacroStatus()
    if not macroStatusText then return end
    local status, _, statusKey = GetSummonMacroStatus()
    local color = statusKey == "ready" and "|cff66dd66"
        or (statusKey == "conflict" and "|cffff6666" or "|cffffcc44")
    macroStatusText:SetText("Macro: " .. color .. status .. "|r")
end

local function UpdateZoneControls()
    if not scopeButton or not overrideButton then return end
    local scope = EbonholdSmartMountsDB.ui.overrideScope
    local key, label = GetScopeKey(scope)
    local value = EbonholdSmartMountsDB.zoneOverrides[key] or "auto"
    scopeButton:SetText(scope == "subzone" and "Scope: Sub-zone" or "Scope: Zone")
    overrideButton:SetText(label .. ": " .. string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2))
end

RefreshPanel = function(rescan, resetScroll)
    if not panel or not uiReady then return end
    if rescan then ScanMounts() end
    if resetScroll then scrollOffset = 0 end
    BuildFilteredMounts()
    UpdateScrollBar()

    local mode, reason = GetAutomaticMode()
    detectedModeText:SetText("Area: |cffffffff" .. mode .. "|r |cff888888- " .. reason .. "|r")
    sourceText:SetText("|cff888888Source: " .. scanDetails.source
        .. " + " .. tostring(scanDetails.cacheCount) .. " cached; "
        .. tostring(#filteredMounts) .. " shown|r")
    countText:SetText(
        tostring(CountEligibleMounts()) .. " mounts | " .. tostring(CountPool("ground"))
            .. " Ground | " .. tostring(CountPool("flying")) .. " Flying"
    )
    showButtonCheck:SetChecked(Boolean(EbonholdSmartMountsDB.button.shown))
    lockButtonCheck:SetChecked(Boolean(EbonholdSmartMountsDB.button.locked))
    UpdateMacroStatus()
    UpdateZoneControls()
    RefreshRows()
end

local function CycleWeight(mount)
    local current = GetWeight(mount.key)
    SetWeight(mount.key, NEXT_WEIGHT[current] or "normal")
end

local function RunRefreshSequence()
    if refreshSequenceFrame then
        refreshSequenceFrame:SetScript("OnUpdate", nil)
    end
    RefreshPanel(true, true)
    refreshSequenceFrame = CreateFrame("Frame")
    local elapsed, nextPass = 0, 1
    local passTimes = { 0.5, 1.5, 3.0 }
    refreshSequenceFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if nextPass <= #passTimes and elapsed >= passTimes[nextPass] then
            RefreshPanel(true, false)
            nextPass = nextPass + 1
        end
        if nextPass > #passTimes then
            self:SetScript("OnUpdate", nil)
            Print("Refresh complete: " .. tostring(#mounts) .. " learned mounts found.")
        end
    end)
end

local function CreateTypeCheckbox(row, poolKey, xOffset)
    local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    checkbox:SetWidth(26)
    checkbox:SetHeight(26)
    checkbox:SetPoint("CENTER", row, "LEFT", xOffset, 0)
    checkbox.ownerRow = row
    checkbox.poolKey = poolKey
    checkbox:SetScript("OnClick", function(self)
        if not self.ownerRow.mount then return end
        SetAssignment(self.ownerRow.mount.key, self.poolKey, self:GetChecked(), true)
        RefreshPanel(false, false)
    end)
    return checkbox
end

local function CreatePanel()
    panel = CreateFrame("Frame", "EbonholdSmartMountsPanel", UIParent)
    panel:SetWidth(640)
    panel:SetHeight(560)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Ebonhold Smart Mounts")
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("TOPRIGHT", -38, -21)
    version:SetText("v" .. ADDON_VERSION)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instructions:SetPoint("TOPLEFT", 24, -45)
    instructions:SetPoint("TOPRIGHT", -24, -45)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Choose Ground or Flying mounts below. AQ mounts are hidden automatically.")

    detectedModeText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detectedModeText:SetPoint("TOPLEFT", 24, -72)
    detectedModeText:SetWidth(330)
    detectedModeText:SetJustifyH("LEFT")
    sourceText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sourceText:SetPoint("TOPLEFT", 24, -87)
    sourceText:SetWidth(330)
    sourceText:SetJustifyH("LEFT")
    countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", -24, -72)
    countText:SetWidth(235)
    countText:SetJustifyH("RIGHT")

    local searchLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 24, -99)
    searchLabel:SetText("Search:")
    searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetWidth(240)
    searchBox:SetHeight(24)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function() RefreshPanel(false, true) end)
    local refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshButton:SetWidth(120)
    refreshButton:SetHeight(23)
    refreshButton:SetPoint("TOPRIGHT", -24, -91)
    refreshButton:SetText("Refresh Mounts")
    refreshButton:SetScript("OnClick", RunRefreshSequence)

    showButtonCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showButtonCheck:SetWidth(24)
    showButtonCheck:SetHeight(24)
    showButtonCheck:SetPoint("TOPLEFT", 24, -127)
    showButtonCheck:SetScript("OnClick", function(self)
        EbonholdSmartMountsDB.button.shown = self:GetChecked() and true or false
        ApplySummonButtonSettings()
    end)
    local showLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showLabel:SetPoint("LEFT", showButtonCheck, "RIGHT", 0, 0)
    showLabel:SetText("Button")

    lockButtonCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    lockButtonCheck:SetWidth(24)
    lockButtonCheck:SetHeight(24)
    lockButtonCheck:SetPoint("LEFT", showLabel, "RIGHT", 7, 0)
    lockButtonCheck:SetScript("OnClick", function(self)
        EbonholdSmartMountsDB.button.locked = self:GetChecked() and true or false
    end)
    local lockLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lockLabel:SetPoint("LEFT", lockButtonCheck, "RIGHT", 0, 0)
    lockLabel:SetText("Lock")

    local nameHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHeader:SetPoint("TOPLEFT", 63, -162)
    nameHeader:SetText("Learned mount")
    local statusHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHeader:SetPoint("TOPLEFT", 354, -162)
    statusHeader:SetText("Availability")
    local weightHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weightHeader:SetPoint("TOPLEFT", 448, -162)
    weightHeader:SetText("Weight")
    local groundHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groundHeader:SetPoint("TOPLEFT", 520, -162)
    groundHeader:SetText("Ground")
    local flyingHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flyingHeader:SetPoint("TOPLEFT", 575, -162)
    flyingHeader:SetText("Flying")

    local rowIndex
    for rowIndex = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetWidth(584)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", 24, -175 - ((rowIndex - 1) * 32))
        row:SetFrameLevel(panel:GetFrameLevel() + 2)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        if rowIndex % 2 == 0 then
            local shade = row:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints(row)
            shade:SetTexture(1, 1, 1, 0.035)
        end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(27)
        row.icon:SetHeight(27)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 38, 0)
        row.name:SetWidth(280)
        row.name:SetJustifyH("LEFT")
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", 330, 0)
        row.status:SetWidth(68)
        row.status:SetJustifyH("LEFT")
        row.weightButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.weightButton:SetWidth(75)
        row.weightButton:SetHeight(21)
        row.weightButton:SetPoint("LEFT", 410, 0)
        row.weightButton.ownerRow = row
        row.weightButton:SetScript("OnClick", function(self)
            if self.ownerRow.mount then
                CycleWeight(self.ownerRow.mount)
                RefreshPanel(false, false)
            end
        end)
        row.groundCheck = CreateTypeCheckbox(row, "ground", 510)
        row.flyingCheck = CreateTypeCheckbox(row, "flying", 562)
        row:SetScript("OnEnter", function(self)
            if not self.mount then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.mount.name, 1, 1, 1)
            GameTooltip:AddLine("Pools: " .. GetMountPoolSummary(self.mount), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(self.mount.availableNow and "Available from the live collection" or "Account cache only", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnMouseWheel", function(_, delta)
            ScrollMountList(-delta * 3)
        end)
        rows[rowIndex] = row
    end

    local scrollUpButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scrollUpButton:SetWidth(20)
    scrollUpButton:SetHeight(19)
    scrollUpButton:SetPoint("TOPRIGHT", -10, -172)
    scrollUpButton:SetText("^")
    scrollUpButton:SetScript("OnClick", function() ScrollMountList(-3) end)

    scrollBar = CreateFrame("Slider", nil, panel)
    scrollBar:SetWidth(14)
    scrollBar:SetHeight(208)
    scrollBar:SetPoint("TOPRIGHT", -13, -195)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetValueStep(1)
    scrollBar:EnableMouse(true)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollBar)
    track:SetTexture(0, 0, 0, 0.4)
    scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = scrollBar:GetThumbTexture()
    if thumb then thumb:SetWidth(18); thumb:SetHeight(24) end
    scrollBar:SetScript("OnValueChanged", function(_, value)
        local _, maximum = scrollBar:GetMinMaxValues()
        local newOffset = maximum - math.floor(value + 0.5)
        if newOffset ~= scrollOffset then
            scrollOffset = newOffset
            RefreshRows()
        end
    end)

    local scrollDownButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scrollDownButton:SetWidth(20)
    scrollDownButton:SetHeight(19)
    scrollDownButton:SetPoint("TOPRIGHT", -10, -406)
    scrollDownButton:SetText("v")
    scrollDownButton:SetScript("OnClick", function() ScrollMountList(3) end)

    panel:SetScript("OnMouseWheel", function(_, delta)
        ScrollMountList(-delta * 3)
    end)

    local listNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listNote:SetPoint("BOTTOMLEFT", 24, 104)
    listNote:SetWidth(590)
    listNote:SetJustifyH("LEFT")
    listNote:SetText("Only the checkbox valid for each mount type is shown.")

    scopeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scopeButton:SetWidth(115)
    scopeButton:SetHeight(23)
    scopeButton:SetPoint("BOTTOMLEFT", 24, 72)
    scopeButton:SetScript("OnClick", function()
        EbonholdSmartMountsDB.ui.overrideScope =
            EbonholdSmartMountsDB.ui.overrideScope == "zone" and "subzone" or "zone"
        UpdateZoneControls()
    end)
    overrideButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    overrideButton:SetWidth(237)
    overrideButton:SetHeight(23)
    overrideButton:SetPoint("LEFT", scopeButton, "RIGHT", 7, 0)
    overrideButton:SetScript("OnClick", function()
        local key = GetScopeKey(EbonholdSmartMountsDB.ui.overrideScope)
        local current = EbonholdSmartMountsDB.zoneOverrides[key]
        if current == nil then
            EbonholdSmartMountsDB.zoneOverrides[key] = "ground"
        elseif current == "ground" then
            EbonholdSmartMountsDB.zoneOverrides[key] = "flying"
        else
            EbonholdSmartMountsDB.zoneOverrides[key] = nil
        end
        RefreshPanel(false, false)
    end)

    macroStatusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    macroStatusText:SetPoint("BOTTOMLEFT", 24, 48)
    macroStatusText:SetWidth(160)
    macroStatusText:SetJustifyH("LEFT")
    local macroButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    macroButton:SetWidth(105)
    macroButton:SetHeight(23)
    macroButton:SetPoint("BOTTOMLEFT", 190, 40)
    macroButton:SetText("Create/Repair")
    macroButton:SetScript("OnClick", function()
        EnsureSummonMacro(true)
        UpdateMacroStatus()
    end)
    local pickupButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pickupButton:SetWidth(105)
    pickupButton:SetHeight(23)
    pickupButton:SetPoint("LEFT", macroButton, "RIGHT", 7, 0)
    pickupButton:SetText("Place on Cursor")
    pickupButton:SetScript("OnClick", function()
        PlaceSummonMacroOnCursor()
        UpdateMacroStatus()
    end)

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOM", 0, 17)
    help:SetWidth(590)
    help:SetJustifyH("CENTER")
    help:SetText("/ehm | /ehmsummon [ground/flying] | Right-click the mount button to configure")

    uiReady = true
    panel:SetScript("OnShow", function() RefreshPanel(true, false) end)
    table.insert(UISpecialFrames, "EbonholdSmartMountsPanel")
    panel:Hide()
end

local function ShowHelp()
    Print("/ehm - open configuration")
    Print("/ehmsummon [ground/flying] - summon automatically or force a mount type")
    Print("/ehm macro - create or repair the EH Smart Mount macro")
    Print("/ehm button - show or hide the on-screen button")
    Print("/ehm lock - lock or unlock the on-screen button")
    Print("/ehm debug - toggle selection messages")
end

local function NormalizeRequestedPool(value)
    value = Lower(Trim(value))
    return POOL_LOOKUP[value] and value or nil
end

local function HandleSlashCommand(message)
    local command, remainder = string.match(Lower(Trim(message)), "^(%S+)%s*(.-)$")
    command = command or ""
    if command == "" or command == "config" then
        TogglePanel()
    elseif command == "summon" or command == "mount" then
        SummonSmartMount(NormalizeRequestedPool(remainder))
    elseif POOL_LOOKUP[command] then
        SummonSmartMount(command)
    elseif command == "macro" then
        EnsureSummonMacro(true)
        UpdateMacroStatus()
    elseif command == "button" then
        EbonholdSmartMountsDB.button.shown = not EbonholdSmartMountsDB.button.shown
        ApplySummonButtonSettings()
        Print("Summon button " .. (EbonholdSmartMountsDB.button.shown and "shown." or "hidden."))
    elseif command == "lock" then
        EbonholdSmartMountsDB.button.locked = not EbonholdSmartMountsDB.button.locked
        Print("Summon button " .. (EbonholdSmartMountsDB.button.locked and "locked." or "unlocked."))
    elseif command == "debug" then
        EbonholdSmartMountsDB.debug = not EbonholdSmartMountsDB.debug
        Print("Debug messages " .. (EbonholdSmartMountsDB.debug and "enabled." or "disabled."))
    else
        ShowHelp()
    end
end

SLASH_EBONHOLDSMARTMOUNTS1 = "/ehm"
SLASH_EBONHOLDSMARTMOUNTS2 = "/ehmount"
SLASH_EBONHOLDSMARTMOUNTS3 = "/smartmount"
SlashCmdList.EBONHOLDSMARTMOUNTS = HandleSlashCommand

SLASH_EBONHOLDSMARTMOUNTSSUMMON1 = "/ehmsummon"
SlashCmdList.EBONHOLDSMARTMOUNTSSUMMON = function(message)
    SummonSmartMount(NormalizeRequestedPool(message))
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("COMPANION_UPDATE")
eventFrame:RegisterEvent("COMPANION_LEARNED")
eventFrame:RegisterEvent("COMPANION_UNLEARNED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" and argument == addonName then
        InitializeDatabase()
        CreatePanel()
        CreateSummonButton()
        ScanMounts()
        Print("Loaded. Type /ehm to configure smart mount pools.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanMounts()
        if not macroAutoAttempted then
            macroAutoAttempted = true
            EnsureSummonMacro(false)
        end
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if macroUpdatePending then EnsureSummonMacro(false) end
    elseif event == "COMPANION_UPDATE" or event == "COMPANION_LEARNED"
        or event == "COMPANION_UNLEARNED"
    then
        ScanMounts()
        shuffleBags = {}
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA"
    then
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    end
end)
