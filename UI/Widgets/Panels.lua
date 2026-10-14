local _, ns = ...
local UI = ns.UI

function UI:CreatePanel(parent, width, height, kind, name)
    local panel = CreateFrame("Frame", name, parent or UIParent)
    panel:SetWidth(width or 300)
    panel:SetHeight(height or 180)
    self:StyleSurface(panel, kind or "panel")
    return panel
end

function UI:CreateWindow(parent, title, width, height, options)
    options = options or {}
    local win = self:CreatePanel(parent or UIParent, width or 460, height or 350, "panel", options.name)
    win:SetFrameStrata(options.strata or "DIALOG")
    win:SetPoint(options.point or "CENTER", parent or UIParent, options.relativePoint or "CENTER",
        options.x or 0, options.y or 0)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    if options.drag ~= false then
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", function(self) self:StartMoving() end)
        win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    end
    win.title = self:CreateText(win, title or "Zen Window", 15)
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -15)
    win.accentLine = self:CreateAccentLine(win, 2)
    win.accentLine:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -45)
    win.accentLine:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -45)
    self:BindStyle(win.title, function(label)
        local palette = UI:Theme()
        local c = palette.text
        label:SetFont(UI:FontPath(), 15)
        label:SetTextColor(c[1],c[2],c[3])
        label:SetShadowColor(0,0,0,0.8)
        label:SetShadowOffset(1,-1)
    end)
    win.close = self:CreateButton(win, "X", 27, 24, function() win:Hide() end)
    win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -9)
    self:BindStyle(win, function(w)
        w:SetScale(UI:GetSettings().scale or 1)
        UI:RefreshSurface(w)
    end)
    return win
end

function UI:CreateSection(parent, title, width, height)
    local frame = self:CreatePanel(parent, width or 250, height or 120, "section")
    frame.title = self:CreateText(frame, title or "Section", 12)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    return frame
end
