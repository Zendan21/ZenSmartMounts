-- Backdrop method adapted from the original ZenUI, extended for six surfaces.
-- Only 3.3.5-era Frame/Texture/FontString methods; no Retail APIs.
local _, ns = ...
local UI = ns.UI

local function Color(region, c, alpha)
    region:SetTexture(c[1], c[2], c[3], alpha or 1)
end
UI.SetSolidColor = Color

local function MakeTex(frame, layer, texturePath)
    local region = frame:CreateTexture(nil, layer)
    if texturePath then region:SetTexture(texturePath) end
    return region
end

function UI:CreateText(parent, message, size, muted)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(message or "")
    fs._zenSize = size or 11
    fs._zenMuted = muted
    return self:BindStyle(fs, function(text)
        local palette = UI:Theme()
        local color = text._zenMuted and palette.muted or palette.text
        text:SetFont(UI:FontPath(), text._zenSize)
        text:SetTextColor(color[1],color[2],color[3],1)
        if UI:StyleKey() == "BRUTAL" then
            text:SetShadowColor(0,0,0,0.9)
            text:SetShadowOffset(1,-1)
        else
            text:SetShadowColor(0,0,0,0.50)
            text:SetShadowOffset(1,-1)
        end
    end)
end

-- 'surface' is one of "panel", "button", "input", "section".
function UI:StyleSurface(frame, surface)
    surface = surface or "panel"
    if not frame._zenSurface then
        -- The shadow is drawn first so it sits behind the background.
        local shadow = MakeTex(frame, "BACKGROUND")
        local background = MakeTex(frame, "BACKGROUND")
        background:SetAllPoints(frame)
        local borders = {}
        for _, side in ipairs({"top","bottom","left","right"}) do
            borders[side] = MakeTex(frame, "BORDER")
        end
        borders.top:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
        borders.top:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
        borders.bottom:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0)
        borders.bottom:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
        borders.left:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
        borders.left:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0)
        borders.right:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0)
        borders.right:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)

        local gloss = MakeTex(frame, "ARTWORK", self.Media.textures.shine)
        gloss:SetPoint("TOPLEFT",frame,"TOPLEFT",3,-3)
        gloss:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-3,-3)
        gloss:SetHeight(58)
        local glowL = MakeTex(frame, "OVERLAY", self.Media.textures.glow)
        local glowR = MakeTex(frame, "OVERLAY", self.Media.textures.glow)
        glowL:SetBlendMode("ADD")
        glowR:SetBlendMode("ADD")
        glowL:SetPoint("TOPLEFT",frame,"TOPLEFT",-22,24)
        glowR:SetPoint("TOPRIGHT",frame,"TOPRIGHT",22,24)
        glowL:SetWidth(92); glowL:SetHeight(64)
        glowR:SetWidth(92); glowR:SetHeight(64)
        local highlight = MakeTex(frame, "ARTWORK")
        highlight:SetAllPoints(frame)
        highlight:Hide()
        frame._zenSurface = {
            kind=surface, bg=background, shadow=shadow, borders=borders,
            gloss=gloss, glowL=glowL, glowR=glowR, highlight=highlight,
        }
        self:BindStyle(frame, function(widget) UI:RefreshSurface(widget) end)
    else
        frame._zenSurface.kind = surface
        self:RefreshSurface(frame)
    end
    return frame
end

function UI:RefreshSurface(frame)
    local s = frame._zenSurface
    if not s then return end
    local theme = self:Theme()
    local width = self:Pixel(frame, theme.borderWidth or 1)
    local bg = s.kind == "panel" and theme.background or theme.surface
    local a = self:PanelAlpha()
    if s.kind == "button" then a = math.min(1, a + 0.02) end
    Color(s.bg, bg, a)
    for _,side in ipairs({"top","bottom","left","right"}) do
        local texture = s.borders[side]
        Color(texture, theme.border, 1)
        if side == "top" or side == "bottom" then texture:SetHeight(width)
        else texture:SetWidth(width) end
    end
    if theme.shadow == "hard" then
        s.shadow:ClearAllPoints()
        s.shadow:SetPoint("TOPLEFT",frame,"TOPLEFT",5,-5)
        s.shadow:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",5,-5)
        Color(s.shadow, {0,0,0}, 0.78)
        s.shadow:Show()
    elseif theme.shadow == "soft" and s.kind == "panel" then
        s.shadow:ClearAllPoints()
        s.shadow:SetPoint("TOPLEFT",frame,"TOPLEFT",3,-3)
        s.shadow:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",3,-3)
        Color(s.shadow, {0,0,0}, 0.26)
        s.shadow:Show()
    else
        s.shadow:Hide()
    end
    if theme.overlay == "shine" and s.kind == "panel" then
        s.gloss:SetVertexColor(1,1,1,0.55)
        s.gloss:Show()
    else s.gloss:Hide() end
    if theme.overlay == "glow" then
        local r,g,b = self:Accent()
        s.glowL:SetVertexColor(r,g,b,0.45)
        s.glowR:SetVertexColor(r,g,b,0.45)
        s.glowL:Show(); s.glowR:Show()
    else s.glowL:Hide(); s.glowR:Hide() end
    if frame._zenHover then
        local r,g,b = self:Accent()
        s.highlight:SetTexture(r,g,b,theme.hoverAlpha or 0.13)
        s.highlight:Show()
    else s.highlight:Hide() end
    if frame._zenBorderAccent then
        self:ColorBorder(frame, self:Accent())
    end
end

function UI:ColorBorder(frame, r, g, b, a)
    local surface = frame._zenSurface
    if not surface then return end
    if type(r)=="table" then r,g,b = r[1],r[2],r[3] end
    for _,side in ipairs({"top","bottom","left","right"}) do
        Color(surface.borders[side], {r or 1, g or 1, b or 1}, a or 1)
    end
end

function UI:CreateAccentLine(parent, height)
    local t = MakeTex(parent, "ARTWORK")
    t:SetHeight(height or 2)
    self:BindStyle(t, function(tex)
        local r,g,b=UI:Accent(); tex:SetTexture(r,g,b,1)
    end)
    return t
end

-- Does not replace existing handlers, unlike the original ZenUI StyleButton.
function UI:InstallHover(button)
    if button._zenHoverInstalled then return end
    button._zenHoverInstalled = true
    button:HookScript("OnEnter", function(self)
        self._zenHover = true
        UI:RefreshSurface(self)
    end)
    button:HookScript("OnLeave", function(self)
        self._zenHover = false
        UI:RefreshSurface(self)
    end)
end
