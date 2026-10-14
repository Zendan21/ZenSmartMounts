-- Fonts are native to WoW 3.3.5a; no font redistribution required.
local _, ns = ...
local UI = ns.UI
UI.Media = {
    root = UI.root .. "Media\\",
    textures = {
        white = UI.root .. "Media\\Textures\\White.tga",
        shine = UI.root .. "Media\\Textures\\GlassShine.tga",
        glow = UI.root .. "Media\\Textures\\SoftGlow.tga",
    },
    fonts = {
        Narrow   = "Fonts\\ARIALN.TTF",
        Default  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
        Morpheus = "Fonts\\MORPHEUS.TTF",
        Skurri   = "Fonts\\SKURRI.TTF",
    },
    fontOptions = {
        {key="Narrow", label="Arial Narrow"},
        {key="Default", label="Blizzard Default"},
        {key="Morpheus", label="Morpheus (Fantasy)"},
        {key="Skurri", label="Skurri (Bold)"},
    },
}
