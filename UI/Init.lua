-- ZenStylingPack 1.1.0 - embedded visuals for WoW 3.3.5a.
-- Separate namespace per hosting addon; EbonAPI integration is OPTIONAL.
local addonName, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

UI.version = "1.1.0"
UI.host = addonName
UI.root = "Interface\\AddOns\\" .. addonName .. "\\UI\\"
UI._styled = setmetatable({}, { __mode = "k" })
UI._listeners = {}

local function DefaultAppearance()
    return {
        style = "CLASSIC",
        accent = { 0.92, 0.63, 0.40 },
        panelAlpha = 0.96,
        scale = 1,
        font = "Narrow",
    }
end
UI.DefaultAppearance = DefaultAppearance
UI._localSettings = DefaultAppearance()
UI._settings = UI._localSettings

local function Clamp(value, lo, hi)
    local n = tonumber(value) or lo
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end
UI.Clamp = Clamp

-- Fill/repair only styling-specific fields; never discard host-specific fields.
function UI:NormalizeAppearance(settings)
    if type(settings) ~= "table" then return false end
    if not self.Themes or not self.Themes[settings.style] then settings.style = "CLASSIC" end
    if type(settings.accent) ~= "table" then settings.accent = {0.92, 0.63, 0.40} end
    settings.accent[1] = Clamp(settings.accent[1] or 0.92, 0, 1)
    settings.accent[2] = Clamp(settings.accent[2] or 0.63, 0, 1)
    settings.accent[3] = Clamp(settings.accent[3] or 0.40, 0, 1)
    settings.panelAlpha = Clamp(settings.panelAlpha or 0.96, 0.30, 1)
    settings.scale = Clamp(settings.scale or 1, 0.70, 1.40)
    if not self.Media or not self.Media.fonts[settings.font] then settings.font = "Narrow" end
    return true
end

-- Pass the HOST's SavedVariables subtable (e.g. ZenProfessionsDB.appearance).
-- The mode preference is stored locally, even if global appearance is active.
-- Default is GLOBAL when EbonAPI is installed, otherwise LOCAL fallback.
function UI:AttachSettings(settings)
    if type(settings) ~= "table" then return false end
    self:NormalizeAppearance(settings)
    if settings.mode ~= "LOCAL" and settings.mode ~= "GLOBAL" then
        settings.mode = "GLOBAL"
    end
    self._localSettings = settings
    if self.ConnectGlobalAppearance then self:ConnectGlobalAppearance() end
    self:ResolveAppearance()
    self:RefreshAll()
    return true
end

function UI:ResolveAppearance()
    if self._localSettings and self._localSettings.mode == "GLOBAL" and
       type(self._sharedAppearance) == "table" then
        self._settings = self._sharedAppearance
    else
        self._settings = self._localSettings
    end
end
function UI:GetSettings() return self._settings end
function UI:StyleKey() return self._settings.style or "CLASSIC" end
function UI:Theme() return (self.Themes and self.Themes[self:StyleKey()]) or self.Themes.CLASSIC end
function UI:Accent() local c = self._settings.accent; return c[1], c[2], c[3] end
function UI:FontPath() return self.Media.fonts[self._settings.font] or self.Media.fonts.Narrow end
function UI:PanelAlpha()
    return Clamp((self._settings.panelAlpha or 0.96) * (self:Theme().alphaMultiplier or 1), 0.22, 1)
end
function UI:GetAppearanceMode()
    return (self._localSettings.mode == "GLOBAL" and self._sharedAppearance) and "GLOBAL" or "LOCAL"
end
function UI:IsGlobalAvailable() return type(self._sharedAppearance) == "table" end
function UI:SetAppearanceMode(mode)
    if mode ~= "LOCAL" and mode ~= "GLOBAL" then return false end
    if mode == "GLOBAL" and not self._sharedAppearance then
        if not (self.ConnectGlobalAppearance and self:ConnectGlobalAppearance()) then return false end
    end
    self._localSettings.mode = mode
    self:ResolveAppearance()
    self:RefreshAll()
    return true
end

function UI:BindStyle(frame, refresh)
    self._styled[frame] = refresh
    refresh(frame)
    return frame
end
function UI:OnAppearanceChanged(callback)
    if type(callback) == "function" then table.insert(self._listeners, callback) end
end
function UI:RefreshAll()
    if not self.Themes or not self.Media then return end
    for frame, refresh in pairs(self._styled) do refresh(frame) end
    for i = 1, #self._listeners do self._listeners[i](self) end
end

-- Local changes stay local; global changes notify other embedded copies once.
function UI:AppearanceEdited()
    self:RefreshAll()
    if self:GetAppearanceMode() == "GLOBAL" and self.PublishGlobalAppearance then
        self:PublishGlobalAppearance()
    end
end
function UI:SetStyle(key)
    key = type(key) == "string" and string.upper(key) or ""
    if not self.Themes[key] then return false end
    self._settings.style = key
    self:AppearanceEdited()
    return true
end
function UI:SetAccent(r, g, b)
    self._settings.accent = {Clamp(r,0,1), Clamp(g,0,1), Clamp(b,0,1)}
    self:AppearanceEdited()
end
function UI:SetPanelAlpha(v)
    self._settings.panelAlpha = Clamp(v,0.30,1)
    self:AppearanceEdited()
end
function UI:SetScale(v)
    self._settings.scale = Clamp(v,0.70,1.40)
    self:AppearanceEdited()
end
function UI:SetFont(key)
    if not self.Media.fonts[key] then return false end
    self._settings.font = key
    self:AppearanceEdited()
    return true
end
function UI:Pixel(frame, count)
    local scale = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    return (count or 1) / scale
end
