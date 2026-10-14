local _, ns = ...
local UI = ns.UI

function UI:CreateCheckbox(parent, title, width, checked, onChanged)
    local check = CreateFrame("CheckButton", nil, parent or UIParent)
    check:SetWidth(width or 240)
    check:SetHeight(25)
    local box = self:CreatePanel(check,18,18,"input")
    box:SetPoint("LEFT",check,"LEFT",1,0)
    check.box = box
    local mark = box:CreateFontString(nil,"OVERLAY","GameFontNormal")
    mark:SetText("X")
    mark:SetPoint("CENTER",box,"CENTER",0,0)
    self:BindStyle(mark,function(text)
        local r,g,b=UI:Accent()
        text:SetFont(UI:FontPath(),13)
        text:SetTextColor(r,g,b)
    end)
    check.mark=mark
    check.text = self:CreateText(check, title or "Checkbox", 11)
    check.text:SetPoint("LEFT",box,"RIGHT",10,0)
    check:SetChecked(checked and true or false)
    function check:RefreshCheck()
        if self:GetChecked() then
            mark:Show()
            local r,g,b=UI:Accent()
            mark:SetTextColor(r,g,b)
        else mark:Hide() end
    end
    function check:SetZenChecked(v)
        self:SetChecked(v and true or false)
        self:RefreshCheck()
    end
    check:SetScript("OnClick",function(self)
        self:RefreshCheck()
        if type(onChanged)=="function" then onChanged(self:GetChecked() and true or false,self) end
    end)
    self:BindStyle(check,function(widget) widget:RefreshCheck() end)
    return check
end

function UI:CreateEditBox(parent, placeholder, width, height, onChanged)
    local edit = CreateFrame("EditBox",nil,parent or UIParent)
    edit:SetWidth(width or 220)
    edit:SetHeight(height or 28)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(9,9,0,0)
    self:StyleSurface(edit,"input")
    edit.placeholder = self:CreateText(edit,placeholder or "",10,true)
    edit.placeholder:SetPoint("LEFT",edit,"LEFT",9,0)
    edit:SetScript("OnEditFocusGained",function(self) self.placeholder:Hide() end)
    edit:SetScript("OnEditFocusLost",function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end)
    edit:SetScript("OnTextChanged",function(self,userInput)
        if self:GetText()=="" and not self:HasFocus() then self.placeholder:Show()
        else self.placeholder:Hide() end
        if type(onChanged)=="function" then onChanged(self:GetText(),userInput,self) end
    end)
    edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    self:BindStyle(edit,function(box)
        box:SetFont(UI:FontPath(),12)
        local c=UI:Theme().text
        box:SetTextColor(c[1],c[2],c[3])
        UI:RefreshSurface(box)
    end)
    return edit
end

function UI:CreateSlider(parent, title, minValue, maxValue, value, width, step, onChanged)
    local wrap = CreateFrame("Frame",nil,parent or UIParent)
    wrap:SetWidth(width or 240)
    wrap:SetHeight(51)
    wrap.label = self:CreateText(wrap,title or "Value",11)
    wrap.label:SetPoint("TOPLEFT",wrap,"TOPLEFT",0,0)
    wrap.valueText = self:CreateText(wrap,"",10,true)
    wrap.valueText:SetPoint("TOPRIGHT",wrap,"TOPRIGHT",0,0)
    local slider=CreateFrame("Slider",nil,wrap)
    slider:SetOrientation("HORIZONTAL")
    slider:SetWidth((width or 240)-12)
    slider:SetHeight(18)
    slider:SetPoint("BOTTOM",wrap,"BOTTOM",0,1)
    slider:SetMinMaxValues(minValue or 0,maxValue or 1)
    slider:SetValueStep(step or 0.05)
    slider:SetThumbTexture(self.Media.textures.white)
    slider.thumb=slider:GetThumbTexture()
    if slider.thumb then slider.thumb:SetWidth(12); slider.thumb:SetHeight(19) end
    local track=slider:CreateTexture(nil,"BACKGROUND")
    track:SetTexture(self.Media.textures.white)
    track:SetPoint("LEFT",slider,"LEFT",0,0)
    track:SetPoint("RIGHT",slider,"RIGHT",0,0)
    track:SetHeight(5)
    wrap.slider=slider
    local function Display(v)
        wrap.valueText:SetText(string.format("%.2f",tonumber(v) or 0))
    end
    slider:SetScript("OnValueChanged",function(self,v)
        Display(v)
        if not wrap._zenSilent and type(onChanged)=="function" then onChanged(v,wrap) end
    end)
    slider:SetValue(value or minValue or 0)
    Display(slider:GetValue())
    self:BindStyle(slider,function(control)
        local c=UI:Theme().border
        track:SetVertexColor(c[1],c[2],c[3],1)
        local r,g,b=UI:Accent()
        if control.thumb then control.thumb:SetVertexColor(r,g,b,1) end
    end)
    function wrap:SetValue(v, silent)
        self._zenSilent = silent and true or false
        self.slider:SetValue(v)
        self._zenSilent = false
    end
    function wrap:GetValue() return self.slider:GetValue() end
    return wrap
end

function UI:CreateDropdown(parent, options, selected, width, onChanged)
    options=options or {}
    local dropdown = self:CreateButton(parent,"Select...",width or 195,28)
    dropdown.options=options
    dropdown.selected=nil
    local popup=self:CreatePanel(UIParent,width or 195,math.max(1,#options)*28+8,"section")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetPoint("TOPLEFT",dropdown,"BOTTOMLEFT",0,-4)
    popup:EnableMouse(true)
    popup:Hide()
    dropdown.popup=popup
    dropdown.items={}
    for i=1,#options do
        local opt=options[i]
        local entry=self:CreateButton(popup,opt.label or opt.key,(width or 195)-8,26,function()
            dropdown:SetSelection(opt.key)
            popup:Hide()
        end)
        entry:SetPoint("TOPLEFT",popup,"TOPLEFT",4,-4-(i-1)*28)
        dropdown.items[i]=entry
    end
    function dropdown:SetSelection(key,silent)
        for i=1,#self.options do
            local option=self.options[i]
            if option.key==key then
                self.selected=key
                self:SetZenText(option.label)
                if not silent and type(onChanged)=="function" then onChanged(key,self) end
                return true
            end
        end
        return false
    end
    dropdown:SetSelection(selected or (options[1] and options[1].key),true)
    dropdown:SetScript("OnClick",function()
        if UI._activePopup and UI._activePopup ~= popup then UI._activePopup:Hide() end
        if popup:IsShown() then popup:Hide() else popup:Show() end
        UI._activePopup=popup:IsShown() and popup or nil
    end)
    dropdown:HookScript("OnHide",function() popup:Hide() end)
    return dropdown
end

function UI:CreateColorSwatch(parent, rgb, size, onClick)
    local swatch=self:CreateButton(parent,"",size or 23,size or 23,function() if onClick then onClick() end end)
    swatch.rgb=rgb
    local color=swatch:CreateTexture(nil,"ARTWORK")
    color:SetPoint("TOPLEFT",swatch,"TOPLEFT",3,-3)
    color:SetPoint("BOTTOMRIGHT",swatch,"BOTTOMRIGHT",-3,3)
    color:SetTexture(rgb[1],rgb[2],rgb[3],1)
    return swatch
end
