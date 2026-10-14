-- Optional complete appearance editor for embedded ZenStylingPack 1.1.0.
local _, ns = ...
local UI = ns.UI

function UI:CreateAppearancePanel(parent)
    local win = self:CreateWindow(parent or UIParent, "ZenSmartMounts  |  Appearance", 560, 610, {name = "ZenSmartMountsAppearancePanel"})
    local sub = self:CreateText(win, "DESIGN SYSTEM", 10, true)
    sub:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -61)

    local modeLabel = self:CreateText(win, "Theme settings", 12)
    modeLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -92)
    local modeSelector
    modeSelector = self:CreateDropdown(win, {
        {key="GLOBAL", label="Global (EbonAPI)"},
        {key="LOCAL", label="This addon only"},
    }, self:GetAppearanceMode(), 218, function(key)
        if not UI:SetAppearanceMode(key) then
            -- Keep selector accurate if EbonAPI isn't installed.
            modeSelector:SetSelection(UI:GetAppearanceMode(), true)
        end
    end)
    modeSelector:SetPoint("TOPLEFT", win, "TOPLEFT", 152, -87)
    local syncStatus = self:CreateText(win, "", 10, true)
    syncStatus:SetPoint("TOPLEFT", win, "TOPLEFT", 153, -121)

    local styleLabel = self:CreateText(win, "Visual style", 12)
    styleLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -159)
    local styleSelector = self:CreateDropdown(win, self:ThemeOptions(), self:StyleKey(), 218, function(key)
        UI:SetStyle(key)
    end)
    styleSelector:SetPoint("TOPLEFT", win, "TOPLEFT", 152, -154)

    local accentTitle = self:CreateText(win, "Accent colour", 12)
    accentTitle:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -210)
    local accentRow = CreateFrame("Frame", nil, win)
    accentRow:SetWidth(330); accentRow:SetHeight(31)
    accentRow:SetPoint("TOPLEFT", win, "TOPLEFT", 152, -205)
    local swatches = {}
    for i = 1, #self.AccentPresets do
        local preset = self.AccentPresets[i]
        local swatch = self:CreateColorSwatch(accentRow, preset.rgb, 29, function()
            UI:SetAccent(preset.rgb[1], preset.rgb[2], preset.rgb[3])
        end)
        swatch:SetPoint("LEFT", accentRow, "LEFT", (i-1)*40, 0)
        swatches[i] = swatch
    end

    local opacity = self:CreateSlider(win, "Panel opacity", 0.30, 1.00,
        self:GetSettings().panelAlpha, 243, 0.05, function(value)
            UI:SetPanelAlpha(value)
        end)
    opacity:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -270)
    local scale = self:CreateSlider(win, "Window scale", 0.70, 1.40,
        self:GetSettings().scale, 243, 0.05, function(value)
            UI:SetScale(value)
        end)
    scale:SetPoint("TOPRIGHT", win, "TOPRIGHT", -19, -270)

    local fontLabel = self:CreateText(win, "Type style", 12)
    fontLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -359)
    local fontSelector = self:CreateDropdown(win, self.Media.fontOptions,
        self:GetSettings().font, 218, function(key)
            UI:SetFont(key)
        end)
    fontSelector:SetPoint("TOPLEFT", win, "TOPLEFT", 152, -355)

    local preview = self:CreateSection(win, "Live widget preview", 522, 127)
    preview:SetPoint("TOPLEFT", win, "TOPLEFT", 19, -421)
    preview.previewBar = self:CreateStatusBar(preview, 296, 15)
    preview.previewBar:SetPoint("TOPLEFT", preview, "TOPLEFT", 13, -46)
    preview.check = self:CreateCheckbox(preview, "Show recipe highlights", 234, true)
    preview.check:SetPoint("TOPLEFT", preview, "TOPLEFT", 12, -77)
    preview.action = self:CreateButton(preview, "Craft All", 139, 31, function()
        preview.previewBar:SetValue((preview.previewBar:GetValue() + 17) % 101)
    end)
    preview.action:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -13, -58)

    local footer = self:CreateText(win, "Changes are saved by your addon or EbonAPI.", 10, true)
    footer:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -566)

    -- Sync all controls when a different embedded addon broadcasts global changes.
    -- Silent slider updates are critical: otherwise an incoming event can re-emit.
    local function SyncSelectors()
        local settings = UI:GetSettings()
        modeSelector:SetSelection(UI:GetAppearanceMode(), true)
        styleSelector:SetSelection(UI:StyleKey(), true)
        fontSelector:SetSelection(settings.font, true)
        opacity:SetValue(settings.panelAlpha, true)
        scale:SetValue(settings.scale, true)
        if not UI:IsGlobalAvailable() then
            syncStatus:SetText("EbonAPI unavailable  -  using local settings")
        elseif UI:GetAppearanceMode() == "GLOBAL" then
            syncStatus:SetText("Shared across Zen addons via EbonAPI")
        else
            syncStatus:SetText("Local override  -  affects only this addon")
        end
        local r, g, b = UI:Accent()
        for i = 1, #swatches do
            local swatch = swatches[i]
            local rgb = swatch.rgb
            if math.abs(rgb[1]-r) < 0.001 and math.abs(rgb[2]-g) < 0.001 and
               math.abs(rgb[3]-b) < 0.001 then
                UI:ColorBorder(swatch, 1, 1, 1, 1)
            else
                UI:RefreshSurface(swatch)
            end
        end
    end
    self:OnAppearanceChanged(SyncSelectors)
    SyncSelectors()
    win.modeSelector = modeSelector
    win.styleSelector = styleSelector
    win.fontSelector = fontSelector
    win.opacitySlider = opacity
    win.scaleSlider = scale
    win.syncStatus = syncStatus
    win.preview = preview
    return win
end
