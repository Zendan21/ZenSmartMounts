local _, ns = ...
local UI = ns.UI

function UI:CreateStatusBar(parent,width,height)
    local bar=CreateFrame("StatusBar",nil,parent or UIParent)
    bar:SetWidth(width or 220); bar:SetHeight(height or 16)
    bar:SetStatusBarTexture(self.Media.textures.white)
    bar:SetMinMaxValues(0,100)
    bar:SetValue(68)
    local bg=bar:CreateTexture(nil,"BACKGROUND")
    bg:SetTexture(0,0,0,0.45)
    bg:SetAllPoints(bar)
    self:BindStyle(bar,function(widget)
        local r,g,b=UI:Accent()
        widget:SetStatusBarColor(r,g,b,0.95)
    end)
    return bar
end
