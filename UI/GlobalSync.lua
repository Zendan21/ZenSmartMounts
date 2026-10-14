-- Optional EbonAPI 2.1.2 integration for shared Zen styling preferences.
-- No EbonAPI global database is written to unless EbonAPI is present and valid.
-- EbonAPI:On/Emit is a local Lua event bus (NOT a WoW RegisterEvent).
local _, ns = ...
local UI = ns.UI

local EVENT = "ZENSTYLINGPACK_APPEARANCE_CHANGED_V1"
local sharedKey = "ZenStylingPack"

local function Ebon()
    local api = _G.EbonAPI
    if type(api) ~= "table" or type(api.DB) ~= "table" or
       type(api.DB.shared) ~= "function" or
       type(api.On) ~= "function" or type(api.Emit) ~= "function" then
        return nil
    end
    return api
end

function UI:ConnectGlobalAppearance()
    local api = Ebon()
    if not api then
        self._sharedAppearance = nil
        self:ResolveAppearance()
        return false
    end
    -- DB.shared() returns an EbonAPI store; account is persisted in EbonAPIDB.
    local ok, store = pcall(api.DB.shared)
    if not ok or type(store) ~= "table" or type(store.account) ~= "table" then
        self._sharedAppearance = nil
        self:ResolveAppearance()
        return false
    end
    local account = store.account
    if type(account[sharedKey]) ~= "table" then account[sharedKey] = {} end
    local bucket = account[sharedKey]
    if type(bucket.appearance) ~= "table" then
        bucket.appearance = self.DefaultAppearance()
    end
    self:NormalizeAppearance(bucket.appearance)
    self._sharedAppearance = bucket.appearance

    if self._ebonSubscribed ~= api then
        if self._ebonSubscribed and self._ebonListener then
            self._ebonSubscribed:Off(EVENT, self._ebonListener)
        end
        self._ebonListener = function(_, sourceAddon)
            if sourceAddon == UI.host then return end
            -- Resynchronise from the authoritative store. This does NOT emit.
            UI:ConnectGlobalAppearance()
            UI:ResolveAppearance()
            if UI:GetAppearanceMode() == "GLOBAL" then UI:RefreshAll() end
        end
        api:On(EVENT, self._ebonListener)
        self._ebonSubscribed = api
    end
    self:ResolveAppearance()
    return true
end

function UI:PublishGlobalAppearance()
    if self:GetAppearanceMode() ~= "GLOBAL" then return end
    local api = Ebon()
    if not api then return end
    -- Mutations are already stored directly in EbonAPI.DB.shared().account.
    api:Emit(EVENT, self.host)
end
