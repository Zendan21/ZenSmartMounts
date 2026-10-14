local _, ns = ...
local UI = ns.UI

function UI:CreateButton(parent, title, width, height, onClick)
    local button = CreateFrame("Button", nil, parent or UIParent)
    button:SetWidth(width or 120)
    button:SetHeight(height or 28)
    self:StyleSurface(button, "button")
    button.label = self:CreateText(button, title or "Button", 11)
    button.label:SetPoint("CENTER",button,"CENTER",0,0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWidth(math.max(20,(width or 120)-12))
    if type(onClick)=="function" then
        button:SetScript("OnClick", function(self,...) onClick(self,...) end)
    end
    self:InstallHover(button)
    function button:SetZenText(text) self.label:SetText(text or "") end
    return button
end

function UI:CreateTabBar(parent, labels, tabWidth, onSelected)
    local bar = CreateFrame("Frame", nil, parent)
    tabWidth = tabWidth or 90
    bar:SetWidth(tabWidth * #labels + 4 * math.max(0,#labels-1))
    bar:SetHeight(28)
    bar.buttons = {}
    bar.selected = 1
    for i=1,#labels do
        local index = i
        local tab = self:CreateButton(bar, labels[i], tabWidth, 27, function()
            bar:SetSelected(index)
        end)
        if i==1 then tab:SetPoint("TOPLEFT",bar,"TOPLEFT",0,0)
        else tab:SetPoint("LEFT",bar.buttons[i-1],"RIGHT",4,0) end
        bar.buttons[i]=tab
        self:BindStyle(tab, function(widget)
            if bar.selected == index then
                local r,g,b=UI:Accent()
                UI:ColorBorder(widget,r,g,b,1)
            else
                UI:RefreshSurface(widget)
            end
        end)
    end
    function bar:SetSelected(index, silent)
        if not self.buttons[index] then return end
        self.selected = index
        for i=1,#self.buttons do
            UI:RefreshSurface(self.buttons[i])
            if i==index then
                local r,g,b=UI:Accent()
                UI:ColorBorder(self.buttons[i],r,g,b,1)
            end
        end
        if not silent and type(onSelected)=="function" then onSelected(index, labels[index]) end
    end
    bar:SetSelected(1,true)
    return bar
end
