local addonName, ns = ...
local UI = ns.UI

local ADDON_VERSION = "1.4.0"
local PREFIX = "|cff58c6ffZenSmartMounts:|r "
local DEFAULT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local SUMMON_MACRO_NAME = "Zen Smart Mount"
local LEGACY_MACRO_NAME = "EH Smart Mount"
local LEGACY_MACRO_BODY = "/click EbonholdSmartMountsButton"
local SUMMON_MACRO_BODY = "/click ZenSmartMountsButton"
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

BINDING_HEADER_ZENSMARTMOUNTS = "ZenSmartMounts"
BINDING_NAME_ZENSMARTMOUNTS_SUMMON = "Summon smart random mount"

local eventFrame = CreateFrame("Frame")
local panel
local appearancePanel
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
local selectionPoolCache = {}
local preparedMounts = {}
local lastMountKey = {}
local macroUpdatePending
local macroAutoAttempted
local secureActionUpdatePending
local companionCollectionReady
local refreshSequenceFrame
local uiReady
local scanDetails = {}
local RefreshPanel
local RefreshRows
local BuildPoolSignature
local PrepareSecureSummonAction

local function InvalidateSelectionCache()
    selectionPoolCache = {}
    shuffleBags = {}
    preparedMounts = {}
    if PrepareSecureSummonAction then
        PrepareSecureSummonAction()
    end
end

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
    -- When the old SavedVariables file has been copied to ZenSmartMounts.lua,
    -- its legacy global can be imported automatically without discarding pools.
    if type(ZenSmartMountsDB) ~= "table" then
        if type(EbonholdSmartMountsDB) == "table" then
            ZenSmartMountsDB = EbonholdSmartMountsDB
            EbonholdSmartMountsDB = nil
        else
            ZenSmartMountsDB = {}
        end
    end

    local db = ZenSmartMountsDB
    db.assignments = type(db.assignments) == "table" and db.assignments or {}
    db.assignmentOverrides = type(db.assignmentOverrides) == "table" and db.assignmentOverrides or {}
    db.weights = type(db.weights) == "table" and db.weights or {}
    db.zoneOverrides = type(db.zoneOverrides) == "table" and db.zoneOverrides or {}
    db.managedMacros = type(db.managedMacros) == "table" and db.managedMacros or {}
    db.button = type(db.button) == "table" and db.button or {}
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.appearance = type(db.appearance) == "table" and db.appearance or UI.DefaultAppearance()

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
    local assignment = ZenSmartMountsDB.assignments[key]

    if type(assignment) ~= "table" then
        local legacySpellID = string.match(key, "^spell:(.+)$")
        if legacySpellID and type(ZenSmartMountsDB.assignments[legacySpellID]) == "table" then
            assignment = ZenSmartMountsDB.assignments[legacySpellID]
            ZenSmartMountsDB.assignments[key] = assignment
            ZenSmartMountsDB.assignments[legacySpellID] = nil
        end
    end

    if create and type(assignment) ~= "table" then
        assignment = {}
        ZenSmartMountsDB.assignments[key] = assignment
    end
    return assignment, key
end

local function SetAssignment(mountKey, poolKey, enabled, manual)
    local assignment, key = GetAssignment(mountKey, true)
    assignment[poolKey] = enabled and true or nil

    if manual then
        ZenSmartMountsDB.assignmentOverrides[key] =
            type(ZenSmartMountsDB.assignmentOverrides[key]) == "table"
                and ZenSmartMountsDB.assignmentOverrides[key]
                or {}
        ZenSmartMountsDB.assignmentOverrides[key][poolKey] = enabled and true or false
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
        ZenSmartMountsDB.assignments[key] = nil
    end
    InvalidateSelectionCache()
end

local function GetWeight(mountKey)
    local weight = ZenSmartMountsDB.weights[tostring(mountKey)]
    if not WEIGHTS[weight] then
        return "normal"
    end
    return weight
end

local function SetWeight(mountKey, weight)
    if weight == "normal" then
        ZenSmartMountsDB.weights[tostring(mountKey)] = nil
    else
        ZenSmartMountsDB.weights[tostring(mountKey)] = weight
    end
    InvalidateSelectionCache()
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

    -- C_MountJournal returns MountType.db2 IDs, not bit flags. Ebonhold's
    -- regular ground and flying mounts use 230 and 248 respectively. The
    -- Companion API used by older 3.3.5 clients may instead return the
    -- legacy 0-3 flags, so retain the bit check only for that small range.
    if mountType == 248 then return true end
    if mountType == 230 then return false end
    if mountType >= 0 and mountType <= 3 then
        return math.floor(mountType / 2) % 2 == 1
    end
    return false
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
        return false
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

local function ScanEbonCompletionistCache(knownMountKeys)
    local cache = type(EbonCompletionistDB) == "table"
        and type(EbonCompletionistDB.account) == "table"
        and EbonCompletionistDB.account.mounts
    if type(cache) ~= "table" then return end

    local _, info
    for _, info in pairs(cache) do
        if type(info) == "table" and info.name then
            local key = BuildMountKey(info.spellID, info.creatureID, info.name)
            scanDetails.cacheCount = scanDetails.cacheCount + 1
            if not knownMountKeys[key] then
                table.insert(mounts, {
                    key = key,
                    source = "account cache",
                    availableNow = false,
                    name = info.name,
                    spellID = info.spellID,
                    creatureID = info.creatureID,
                    icon = info.icon or DEFAULT_ICON,
                })
                knownMountKeys[key] = true
            end
        end
    end
end

local function ScanMounts()
    mounts = {}
    ResetScanDetails()
    if not ScanMountJournal() or scanDetails.liveCount == 0 then
        ScanCompanions()
    end

    local knownMountKeys = {}
    local _, liveMount
    for _, liveMount in ipairs(mounts) do
        knownMountKeys[liveMount.key] = true
    end
    ScanEbonCompletionistCache(knownMountKeys)

    local _, mount
    for _, mount in ipairs(mounts) do
        mount.sortName = Lower(mount.name)
        mount.category = GetMountCategory(mount)
        mount.excludedAQ = IsAQMount(mount)
        local assignment = GetAssignment(mount.key, false)
        if mount.excludedAQ then
            ZenSmartMountsDB.assignments[mount.key] = nil
        elseif assignment then
            -- A row only belongs to its detected physical mount type. Clean
            -- up selections made by older versions that exposed both boxes.
            -- Preserve selections whose category changes after correcting the
            -- Mount Journal type-ID handling in 1.3.
            if mount.category == "ground" then
                if assignment.flying and not assignment.ground then
                    assignment.ground = true
                end
                assignment.flying = nil
            else
                if assignment.ground and not assignment.flying then
                    assignment.flying = true
                end
                assignment.ground = nil
            end
        end
    end
    table.sort(mounts, function(left, right)
        return left.sortName < right.sortName
    end)
    InvalidateSelectionCache()

    return mounts
end

local function MarkCompanionCollectionReady()
    -- Once login has exposed the collection, COMPANION_UPDATE only needs to
    -- refresh the already prepared secure action. Learned/unlearned events
    -- remain responsible for the comparatively expensive catalog rescan.
    if scanDetails.liveCount > 0 then
        companionCollectionReady = true
    end
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
        local subOverride = ZenSmartMountsDB.zoneOverrides["subzone:" .. zone .. "|" .. subZone]
        if subOverride == "ground" or subOverride == "flying" then
            return subOverride, "sub-zone override"
        end
    end
    local zoneOverride = ZenSmartMountsDB.zoneOverrides["zone:" .. zone]
    if zoneOverride == "ground" or zoneOverride == "flying" then
        return zoneOverride, "zone override"
    end
    return nil
end

local function GetAutomaticMode(ignoreModifiers)
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

    if not ignoreModifiers then
        if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
            canFly = true
            reason = "Control override"
        elseif type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            canFly = false
            reason = "Shift override"
        end
    end

    return canFly and "flying" or "ground", reason
end

local function HasAssignment(mount, poolKey)
    local assignment = GetAssignment(mount.key, false)
    return assignment and assignment[poolKey] and true or false
end

local function BuildPool(poolKey)
    local cached = selectionPoolCache[poolKey]
    if cached then return cached.mounts, cached.signature end

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
    local selected = #ready > 0 and ready or all
    local signature = BuildPoolSignature and BuildPoolSignature(selected) or nil
    selectionPoolCache[poolKey] = { mounts = selected, signature = signature }
    return selected, signature
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

BuildPoolSignature = function(pool)
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

local function PickShuffleMount(pool, poolKey, signature)
    if #pool == 0 then return nil end
    signature = signature or BuildPoolSignature(pool)
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
    local pool, signature = BuildPool(poolKey)

    if #pool == 0 then
        return nil, poolKey, reason
    end
    return PickShuffleMount(pool, poolKey, signature), poolKey, reason
end

local function UpdateSummonButtonIcon(icon)
    if summonButton and summonButton.icon then
        summonButton.icon:SetTexture(icon or DEFAULT_ICON)
    end
end

local function GetSecureClickPool()
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
        return "flying", "Control override"
    elseif type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        return "ground", "Shift override"
    end
    return GetAutomaticMode(true)
end

local function GetPreparedMount(poolKey)
    local prepared = preparedMounts[poolKey]
    if prepared then return prepared end

    local pool, signature = BuildPool(poolKey)
    prepared = PickShuffleMount(pool, poolKey, signature)
    preparedMounts[poolKey] = prepared
    return prepared
end

local function MountMacroText(mount)
    if not mount then return "" end
    return "/cast " .. string.gsub(mount.name, "[\r\n]", " ")
end

local function SetSecureMacroText(attribute, value)
    value = value or ""
    if summonButton:GetAttribute(attribute) ~= value then
        summonButton:SetAttribute(attribute, value)
    end
end

PrepareSecureSummonAction = function()
    if not summonButton then return false end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        secureActionUpdatePending = true
        return false
    end
    secureActionUpdatePending = nil

    if type(IsMounted) == "function" and IsMounted() then
        local dismount = "/dismount"
        SetSecureMacroText("macrotext1", dismount)
        SetSecureMacroText("shift-macrotext1", dismount)
        SetSecureMacroText("ctrl-macrotext1", dismount)
        SetSecureMacroText("ctrl-shift-macrotext1", dismount)
        SetSecureMacroText("alt-macrotext1", dismount)
        SetSecureMacroText("alt-shift-macrotext1", dismount)
        SetSecureMacroText("alt-ctrl-macrotext1", dismount)
        SetSecureMacroText("alt-ctrl-shift-macrotext1", dismount)
        summonButton.preparedAction = "dismount"
        return true
    end

    local groundMount = GetPreparedMount("ground")
    local flyingMount = GetPreparedMount("flying")
    local groundMacro = MountMacroText(groundMount)
    local flyingMacro = MountMacroText(flyingMount)
    local automaticPool = GetAutomaticMode(true)
    local automaticMount = automaticPool == "flying" and flyingMount or groundMount
    local automaticMacro = automaticPool == "flying" and flyingMacro or groundMacro

    -- These are prepared outside the protected click. Modifier-specific
    -- attributes keep Shift/Control overrides without mutating the action in
    -- PreClick, which can otherwise leave the previous macro one click behind.
    SetSecureMacroText("macrotext1", automaticMacro)
    SetSecureMacroText("shift-macrotext1", groundMacro)
    SetSecureMacroText("ctrl-macrotext1", flyingMacro)
    SetSecureMacroText("ctrl-shift-macrotext1", flyingMacro)
    SetSecureMacroText("alt-macrotext1", automaticMacro)
    SetSecureMacroText("alt-shift-macrotext1", groundMacro)
    SetSecureMacroText("alt-ctrl-macrotext1", flyingMacro)
    SetSecureMacroText("alt-ctrl-shift-macrotext1", flyingMacro)
    summonButton.preparedAction = "mount"
    UpdateSummonButtonIcon(automaticMount and automaticMount.icon or DEFAULT_ICON)
    return true
end

local function SummonSmartMount(requestedPool)
    if type(IsMounted) == "function" and IsMounted() then
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
    elseif ZenSmartMountsDB.debug then
        Print("Selected " .. mount.name .. " from " .. poolKey .. " (" .. reason .. ").")
    end
end

function ZenSmartMounts_Summon()
    SummonSmartMount()
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


local function MigrateLegacyMacro(announce)
    if type(GetMacroIndexByName) ~= "function" or type(GetMacroInfo) ~= "function"
        or type(EditMacro) ~= "function" then return false end
    if (GetMacroIndexByName(SUMMON_MACRO_NAME) or 0) > 0 then return false end
    local index = GetMacroIndexByName(LEGACY_MACRO_NAME) or 0
    if index <= 0 then return false end
    local _, _, body = GetMacroInfo(index)
    if body ~= LEGACY_MACRO_BODY and body ~= "/ehmsummon" then return false end
    local ok = pcall(EditMacro, index, SUMMON_MACRO_NAME, GetSummonMacroIconIndex(), SUMMON_MACRO_BODY, 1)
    if ok and GetSummonMacroStatus() == "Ready" then
        ZenSmartMountsDB.managedMacros[GetCharacterKey()] = true
        if announce then Print("Updated the old EH Smart Mount macro for ZenSmartMounts.") end
        return true
    end
    return false
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

    MigrateLegacyMacro(announce)
    local status, index = GetSummonMacroStatus()
    local characterKey = GetCharacterKey()
    if status == "Ready" then
        ZenSmartMountsDB.managedMacros[characterKey] = true
        if announce then Print("The " .. SUMMON_MACRO_NAME .. " macro is ready.") end
        return true
    elseif status == "Name conflict" then
        local _, _, existingBody = GetMacroInfo(index)
        local mayRepair = ZenSmartMountsDB.managedMacros[characterKey]
            or existingBody == "/ehmsummon"
        if not mayRepair then
            if announce then Print("A different macro named " .. SUMMON_MACRO_NAME .. " already exists.") end
            return false
        end
        if type(EditMacro) == "function" then
            local ok = pcall(EditMacro, index, SUMMON_MACRO_NAME, GetSummonMacroIconIndex(), SUMMON_MACRO_BODY, 1)
            local newStatus = GetSummonMacroStatus()
            if ok and newStatus == "Ready" then
                ZenSmartMountsDB.managedMacros[characterKey] = true
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
        ZenSmartMountsDB.managedMacros[characterKey] = true
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
        ZenSmartMountsDB.button.left = left
        ZenSmartMountsDB.button.bottom = bottom
    end
end

local function ApplySummonButtonSettings()
    if not summonButton then return end
    summonButton:ClearAllPoints()
    local buttonDB = ZenSmartMountsDB.button
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
    summonButton = CreateFrame("Button", "ZenSmartMountsButton", UIParent, "SecureActionButtonTemplate")
    summonButton:SetWidth(44)
    summonButton:SetHeight(44)
    summonButton:SetClampedToScreen(true)
    summonButton:SetMovable(true)
    summonButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    summonButton:RegisterForDrag("LeftButton")
    summonButton:SetAttribute("type1", "macro")
    summonButton:SetAttribute("macrotext1", "")
    -- Zen visuals only; all secure click attributes remain unchanged.
    UI:StyleSurface(summonButton, "button")

    local icon = summonButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(DEFAULT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    summonButton.icon = icon
    local iconBorder = UI:CreateAccentLine(summonButton, 2)
    iconBorder:SetPoint("BOTTOMLEFT", summonButton, "BOTTOMLEFT", 3, 3)
    iconBorder:SetPoint("BOTTOMRIGHT", summonButton, "BOTTOMRIGHT", -3, 3)

    summonButton:SetScript("OnDragStart", function(self)
        if ZenSmartMountsDB.button.locked then return end
        if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
        self:StartMoving()
    end)
    summonButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSummonButtonPosition()
    end)
    summonButton:SetScript("PreClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        self.wasMountedBeforeClick = type(IsMounted) == "function" and IsMounted() or false
        self.clickBlockedByCombat = type(InCombatLockdown) == "function" and InCombatLockdown() or false
        if self.clickBlockedByCombat then
            Print("You cannot mount while in combat.")
        end
    end)
    summonButton:SetScript("PostClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            TogglePanel()
        elseif mouseButton == "LeftButton" and not self.clickBlockedByCombat then
            if not self.wasMountedBeforeClick then
                local usedPool, reason = GetSecureClickPool()
                local usedMount = preparedMounts[usedPool]
                if usedMount then
                    preparedMounts[usedPool] = nil
                    if ZenSmartMountsDB.debug then
                        Print("Selected " .. usedMount.name .. " from " .. usedPool .. " (" .. reason .. ").")
                    end
                else
                    Print("No " .. usedPool .. " mounts are selected and available.")
                end
            end
            PrepareSecureSummonAction()
        end
    end)
    summonButton:SetScript("OnEnter", function(self)
        local poolKey, reason = GetContextPool(nil)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("ZenSmartMounts", 0.35, 0.78, 1)
        GameTooltip:AddLine("Next pool: " .. poolKey .. " (" .. reason .. ")", 1, 1, 1)
        GameTooltip:AddLine("Left-click: summon or dismount", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Right-click: configure", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Shift: Ground | Control: Flying", 0.75, 0.75, 0.75)
        if not ZenSmartMountsDB.button.locked then
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
            and (query == "" or string.find(mount.sortName, query, 1, true))
        then
            table.insert(filteredMounts, mount)
        end
    end
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
                local c = UI:Theme().text
                row.name:SetTextColor(c[1], c[2], c[3])
                row.status:SetText("|cff66dd66Ready|r")
            else
                local c = UI:Theme().muted
                row.name:SetTextColor(c[1], c[2], c[3])
                row.status:SetText("|cff999999Cached|r")
            end
            local weight = GetWeight(mount.key)
            row.weightButton:SetZenText(WEIGHTS[weight].label)
            row.groundCheck:SetZenChecked(Boolean(HasAssignment(mount, "ground")))
            row.flyingCheck:SetZenChecked(Boolean(HasAssignment(mount, "flying")))
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
    local scope = ZenSmartMountsDB.ui.overrideScope
    local key, label = GetScopeKey(scope)
    local value = ZenSmartMountsDB.zoneOverrides[key] or "auto"
    scopeButton:SetZenText(scope == "subzone" and "Scope: Sub-zone" or "Scope: Zone")
    overrideButton:SetZenText(label .. ": " .. string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2))
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
    showButtonCheck:SetZenChecked(Boolean(ZenSmartMountsDB.button.shown))
    lockButtonCheck:SetZenChecked(Boolean(ZenSmartMountsDB.button.locked))
    UpdateMacroStatus()
    UpdateZoneControls()
    RefreshRows()
end

local function CycleWeight(mount)
    local current = GetWeight(mount.key)
    SetWeight(mount.key, NEXT_WEIGHT[current] or "normal")
end

local function RunRefreshSequence()
    if not refreshSequenceFrame then
        refreshSequenceFrame = CreateFrame("Frame")
    else
        refreshSequenceFrame:SetScript("OnUpdate", nil)
    end
    RefreshPanel(true, true)
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
    local checkbox = UI:CreateCheckbox(row, "", 26, false, function(checked, control)
        if not control.ownerRow.mount then return end
        SetAssignment(control.ownerRow.mount.key, control.poolKey, checked, true)
        RefreshPanel(false, false)
    end)
    checkbox:SetPoint("CENTER", row, "LEFT", xOffset, 0)
    checkbox.ownerRow = row
    checkbox.poolKey = poolKey
    return checkbox
end

local function OpenAppearancePanel()
    if not appearancePanel then
        appearancePanel = UI:CreateAppearancePanel(UIParent)
        -- Keep the editor separate, centred and dismissible via Escape.
        table.insert(UISpecialFrames, "ZenSmartMountsAppearancePanel")
        appearancePanel:Hide()
    end
    if appearancePanel:IsShown() then
        appearancePanel:Hide()
    else
        appearancePanel:Show()
        appearancePanel:Raise()
    end
end

local function CreatePanel()
    panel = UI:CreateWindow(UIParent, "ZenSmartMounts", 680, 630, {
        name = "ZenSmartMountsPanel", strata = "DIALOG",
    })
    panel:EnableMouseWheel(true)

    local version = UI:CreateText(panel, "v" .. ADDON_VERSION .. "  |  ZenStylingPack 1.1.0", 10, true)
    version:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -48, -19)

    local instructions = UI:CreateText(panel,
        "Choose Ground or Flying mounts below. Qiraji mounts are excluded automatically.", 11, true)
    instructions:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -62)

    detectedModeText = UI:CreateText(panel, "", 11)
    detectedModeText:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -90)
    detectedModeText:SetWidth(360)
    detectedModeText:SetJustifyH("LEFT")

    countText = UI:CreateText(panel, "", 11)
    countText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -21, -90)
    countText:SetWidth(285)
    countText:SetJustifyH("RIGHT")

    sourceText = UI:CreateText(panel, "", 10, true)
    sourceText:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -113)
    sourceText:SetWidth(600)
    sourceText:SetJustifyH("LEFT")

    local searchLabel = UI:CreateText(panel, "SEARCH", 10, true)
    searchLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -147)
    searchBox = UI:CreateEditBox(panel, "Filter mounts...", 270, 27, function()
        RefreshPanel(false, true)
    end)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 86, -139)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local refreshButton = UI:CreateButton(panel, "Refresh Mounts", 135, 27, function()
        RunRefreshSequence()
    end)
    refreshButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 370, -139)

    local appearanceButton = UI:CreateButton(panel, "Appearance", 135, 27, function()
        OpenAppearancePanel()
    end)
    appearanceButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -21, -139)

    showButtonCheck = UI:CreateCheckbox(panel, "Show summon button", 179, false, function(checked)
        ZenSmartMountsDB.button.shown = checked
        ApplySummonButtonSettings()
    end)
    showButtonCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -177)

    lockButtonCheck = UI:CreateCheckbox(panel, "Lock position", 155, false, function(checked)
        ZenSmartMountsDB.button.locked = checked
    end)
    lockButtonCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 219, -177)

    local tablePanel = UI:CreatePanel(panel, 638, 276, "section")
    tablePanel:SetPoint("TOPLEFT", panel, "TOPLEFT", 21, -211)

    local function Header(title, x, width)
        local text = UI:CreateText(tablePanel, title, 10, true)
        text:SetPoint("TOPLEFT", tablePanel, "TOPLEFT", x, -13)
        if width then text:SetWidth(width) end
        return text
    end
    Header("MOUNT", 50)
    Header("STATUS", 319)
    Header("WEIGHT", 423)
    Header("GROUND", 516)
    Header("FLYING", 572)

    local rowIndex
    for rowIndex = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, tablePanel)
        row:SetWidth(604)
        row:SetHeight(27)
        row:SetPoint("TOPLEFT", tablePanel, "TOPLEFT", 10, -35 - ((rowIndex - 1) * 29))
        row:SetFrameLevel(tablePanel:GetFrameLevel() + 2)
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        UI:StyleSurface(row, "section")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(23)
        row.icon:SetHeight(23)
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = UI:CreateText(row, "", 11)
        row.name:SetPoint("LEFT", row, "LEFT", 34, 0)
        row.name:SetWidth(252)
        row.name:SetJustifyH("LEFT")
        row.status = UI:CreateText(row, "", 10)
        row.status:SetPoint("LEFT", row, "LEFT", 306, 0)
        row.status:SetWidth(75)
        row.status:SetJustifyH("LEFT")
        row.weightButton = UI:CreateButton(row, "Normal", 77, 22, function(button)
            if button.ownerRow.mount then
                CycleWeight(button.ownerRow.mount)
                RefreshPanel(false, false)
            end
        end)
        row.weightButton:SetPoint("LEFT", row, "LEFT", 401, 0)
        row.weightButton.ownerRow = row
        row.groundCheck = CreateTypeCheckbox(row, "ground", 517)
        row.flyingCheck = CreateTypeCheckbox(row, "flying", 573)
        row:SetScript("OnEnter", function(self)
            if not self.mount then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.mount.name, 1, 1, 1)
            GameTooltip:AddLine("Pools: " .. GetMountPoolSummary(self.mount), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(self.mount.availableNow and
                "Available from the live collection" or "Account cache only", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnMouseWheel", function(_, delta)
            ScrollMountList(-delta * 3)
        end)
        UI:InstallHover(row)
        rows[rowIndex] = row
    end

    local scrollUp = UI:CreateButton(tablePanel, "^", 21, 23, function() ScrollMountList(-3) end)
    scrollUp:SetPoint("TOPRIGHT", tablePanel, "TOPRIGHT", -5, -37)
    scrollBar = CreateFrame("Slider", nil, tablePanel)
    scrollBar:SetWidth(13)
    scrollBar:SetHeight(178)
    scrollBar:SetPoint("TOPRIGHT", tablePanel, "TOPRIGHT", -9, -65)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetValueStep(1)
    scrollBar:EnableMouse(true)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
    track:SetWidth(4)
    scrollBar:SetThumbTexture(UI.Media.textures.white)
    local thumb = scrollBar:GetThumbTexture()
    if thumb then thumb:SetWidth(12); thumb:SetHeight(24) end
    UI:BindStyle(scrollBar, function(slider)
        local c = UI:Theme().border
        track:SetTexture(c[1], c[2], c[3], 1)
        if thumb then
            local r,g,b = UI:Accent()
            thumb:SetVertexColor(r,g,b,1)
        end
    end)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        local _, maximum = scrollBar:GetMinMaxValues()
        local newOffset = maximum - math.floor(value + 0.5)
        if newOffset ~= scrollOffset then
            scrollOffset = newOffset
            RefreshRows()
        end
    end)
    local scrollDown = UI:CreateButton(tablePanel, "v", 21, 23, function() ScrollMountList(3) end)
    scrollDown:SetPoint("BOTTOMRIGHT", tablePanel, "BOTTOMRIGHT", -5, 4)
    tablePanel:EnableMouseWheel(true)
    tablePanel:SetScript("OnMouseWheel", function(_, delta) ScrollMountList(-delta * 3) end)
    panel:SetScript("OnMouseWheel", function(_, delta) ScrollMountList(-delta * 3) end)

    local listNote = UI:CreateText(panel, "Only the compatible mount type can be selected.", 10, true)
    listNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -497)

    local zoneLabel = UI:CreateText(panel, "ZONE OVERRIDE", 10, true)
    zoneLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -532)
    scopeButton = UI:CreateButton(panel, "Scope: Zone", 150, 27, function()
        ZenSmartMountsDB.ui.overrideScope =
            ZenSmartMountsDB.ui.overrideScope == "zone" and "subzone" or "zone"
        UpdateZoneControls()
    end)
    scopeButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 145, -521)
    overrideButton = UI:CreateButton(panel, "Automatic", 320, 27, function()
        local key = GetScopeKey(ZenSmartMountsDB.ui.overrideScope)
        local current = ZenSmartMountsDB.zoneOverrides[key]
        if current == nil then
            ZenSmartMountsDB.zoneOverrides[key] = "ground"
        elseif current == "ground" then
            ZenSmartMountsDB.zoneOverrides[key] = "flying"
        else
            ZenSmartMountsDB.zoneOverrides[key] = nil
        end
        PrepareSecureSummonAction()
        RefreshPanel(false, false)
    end)
    overrideButton:SetPoint("LEFT", scopeButton, "RIGHT", 8, 0)

    macroStatusText = UI:CreateText(panel, "", 11)
    macroStatusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -569)
    macroStatusText:SetWidth(155)
    macroStatusText:SetJustifyH("LEFT")
    local macroButton = UI:CreateButton(panel, "Create/Repair", 138, 27, function()
        EnsureSummonMacro(true)
        UpdateMacroStatus()
    end)
    macroButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 190, -560)
    local pickupButton = UI:CreateButton(panel, "Place on Cursor", 150, 27, function()
        PlaceSummonMacroOnCursor()
        UpdateMacroStatus()
    end)
    pickupButton:SetPoint("LEFT", macroButton, "RIGHT", 9, 0)

    local help = UI:CreateText(panel,
        "/zsm  |  /zsmsummon [ground/flying]  |  Right-click summon button to configure", 10, true)
    help:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    help:SetWidth(630)
    help:SetJustifyH("CENTER")

    UI:OnAppearanceChanged(function()
        if uiReady then RefreshRows() end
    end)
    uiReady = true
    panel:SetScript("OnShow", function() RefreshPanel(false, false) end)
    table.insert(UISpecialFrames, "ZenSmartMountsPanel")
    panel:Hide()
end

local function ShowHelp()
    Print("/zsm - open configuration and /zsm appearance - theme editor")
    Print("/zsmsummon [ground/flying] - summon automatically or force a mount type")
    Print("/zsm macro - create or repair the Zen Smart Mount macro")
    Print("/zsm button - show or hide the on-screen button")
    Print("/zsm lock - lock or unlock the on-screen button")
    Print("/zsm debug - toggle selection messages")
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
    elseif command == "appearance" or command == "style" then
        OpenAppearancePanel()
    elseif command == "macro" then
        EnsureSummonMacro(true)
        UpdateMacroStatus()
    elseif command == "button" then
        ZenSmartMountsDB.button.shown = not ZenSmartMountsDB.button.shown
        ApplySummonButtonSettings()
        Print("Summon button " .. (ZenSmartMountsDB.button.shown and "shown." or "hidden."))
    elseif command == "lock" then
        ZenSmartMountsDB.button.locked = not ZenSmartMountsDB.button.locked
        Print("Summon button " .. (ZenSmartMountsDB.button.locked and "locked." or "unlocked."))
    elseif command == "debug" then
        ZenSmartMountsDB.debug = not ZenSmartMountsDB.debug
        Print("Debug messages " .. (ZenSmartMountsDB.debug and "enabled." or "disabled."))
    else
        ShowHelp()
    end
end

SLASH_ZENSMARTMOUNTS1 = "/zsm"
SLASH_ZENSMARTMOUNTS2 = "/zensmartmounts"
SLASH_ZENSMARTMOUNTS3 = "/ehm"
SLASH_ZENSMARTMOUNTS4 = "/ehmount"
SLASH_ZENSMARTMOUNTS5 = "/smartmount"
SlashCmdList.ZENSMARTMOUNTS = HandleSlashCommand

SLASH_ZENSMARTMOUNTSSUMMON1 = "/zsmsummon"
SLASH_ZENSMARTMOUNTSSUMMON2 = "/ehmsummon"
SlashCmdList.ZENSMARTMOUNTSSUMMON = function(message)
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
        UI:AttachSettings(ZenSmartMountsDB.appearance)
        CreatePanel()
        CreateSummonButton()
        ScanMounts()
        Print("Loaded. Type /zsm to configure or /zsm appearance for themes.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanMounts()
        MarkCompanionCollectionReady()
        PrepareSecureSummonAction()
        if not macroAutoAttempted then
            macroAutoAttempted = true
            EnsureSummonMacro(false)
        end
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if macroUpdatePending then EnsureSummonMacro(false) end
        if secureActionUpdatePending then PrepareSecureSummonAction() end
    elseif event == "COMPANION_UPDATE" then
        -- During initial login the collection may not be populated yet. Once
        -- ready, mount-state updates only refresh the prebuilt secure action.
        if argument == nil or string.upper(tostring(argument)) == "MOUNT" then
            if not companionCollectionReady then
                ScanMounts()
                MarkCompanionCollectionReady()
                if panel and panel:IsShown() then RefreshPanel(false, false) end
            end
            PrepareSecureSummonAction()
        end
    elseif event == "COMPANION_LEARNED" or event == "COMPANION_UNLEARNED" then
        ScanMounts()
        MarkCompanionCollectionReady()
        PrepareSecureSummonAction()
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA"
    then
        PrepareSecureSummonAction()
        if panel and panel:IsShown() then RefreshPanel(false, false) end
    end
end)
