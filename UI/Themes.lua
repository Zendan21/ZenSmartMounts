-- Extended from ZenUI 1.0.24 Core/API.lua appearance presets.
-- Colours = {r, g, b}; surface treatment is independent of layout.
local _, ns = ...
local UI = ns.UI

UI.ThemeOrder = { "CLASSIC", "OBSIDIAN", "GLASS", "FLAT", "BRUTAL", "NEON" }
UI.Themes = {
    CLASSIC = {
        label="Zen Classic", background={0.035,0.037,0.043}, surface={0.070,0.075,0.087},
        border={0.15,0.16,0.18}, text={0.90,0.91,0.93}, muted={0.55,0.57,0.61},
        alphaMultiplier=1, borderWidth=1, hoverAlpha=0.12, shadow="none", overlay="none",
    },
    OBSIDIAN = {
        label="Zen Obsidian", background={0.008,0.009,0.012}, surface={0.035,0.038,0.047},
        border={0.095,0.10,0.12}, text={0.94,0.95,0.97}, muted={0.57,0.59,0.64},
        alphaMultiplier=1, borderWidth=1, hoverAlpha=0.15, shadow="none", overlay="none",
    },
    GLASS = {
        label="Zen Glass", background={0.055,0.064,0.082}, surface={0.09,0.115,0.155},
        border={0.24,0.27,0.33}, text={0.95,0.96,0.98}, muted={0.62,0.66,0.72},
        alphaMultiplier=0.76, borderWidth=1, hoverAlpha=0.20, shadow="soft", overlay="shine",
    },
    FLAT = {
        label="Zen Flat", background={0.085,0.096,0.115}, surface={0.13,0.15,0.18},
        border={0.18,0.20,0.23}, text={0.95,0.96,0.97}, muted={0.67,0.70,0.73},
        alphaMultiplier=1, borderWidth=1, hoverAlpha=0.11, shadow="none", overlay="none",
    },
    BRUTAL = {
        label="Zen Brutal", background={0.10,0.10,0.11}, surface={0.18,0.19,0.20},
        border={0.84,0.85,0.89}, text={1,1,1}, muted={0.77,0.79,0.83},
        alphaMultiplier=1, borderWidth=3, hoverAlpha=0.30, shadow="hard", overlay="none",
    },
    NEON = {
        label="Zen Neon", background={0.018,0.024,0.059}, surface={0.035,0.048,0.090},
        border={0.10,0.34,0.46}, text={0.91,0.97,1}, muted={0.53,0.70,0.80},
        alphaMultiplier=0.97, borderWidth=2, hoverAlpha=0.25, shadow="none", overlay="glow",
    },
}
UI.AccentPresets = {
    -- Six original ZenUI 1.0.24 presets (names and RGB values retained).
    {key="ORANGE", label="Orange", rgb={0.92,0.63,0.40}},
    {key="BLUE", label="Blue", rgb={0.34,0.64,0.98}},
    {key="GREEN", label="Green", rgb={0.30,0.82,0.55}},
    {key="PURPLE", label="Purple", rgb={0.70,0.50,0.96}},
    {key="GOLD", label="Gold", rgb={0.95,0.78,0.32}},
    {key="GRAPHITE", label="Graphite", rgb={0.62,0.68,0.76}},
    -- Optional new accent that fits the Neon visual preset.
    {key="NEON_PINK", label="Neon Pink", rgb={1.00,0.35,0.73}},
}
function UI:ThemeOptions()
    local options = {}
    for i=1,#self.ThemeOrder do
        local key = self.ThemeOrder[i]
        options[i] = {key=key, label=self.Themes[key].label}
    end
    return options
end
