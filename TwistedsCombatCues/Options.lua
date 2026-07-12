-- Twisteds Combat Cues - Options.lua
-- Minimal Blizzard Settings entry: all real options now live in the Cue Manager
-- window (UI.lua). This just gives the AddOns list a launcher.
local addonName, TCC = ...

function TCC.InitOptions()
    if TCC.optionsBuilt then return end
    TCC.optionsBuilt = true

    local panel = CreateFrame("Frame", "TwistedsCombatCuesOptions")
    panel.name = "Twisteds Combat Cues"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Twisteds Combat Cues")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText(
        "|cffffffffCombat-safe audible & visual cues|r for the moments that matter - no target, "
        .. "out of range, pulled aggro, pet down, item ready - plus |cffffffffFocus Tools|r for your "
        .. "marker, keybind, call-outs, and spec-aware interrupt / stun macros.\n\n"
        .. "Everything is configured in the Cue Manager. Open it with |cffffff00/tcc|r or the button "
        .. "below. For the full command list, open the |cffffffffHelp|r page inside the manager.\n\n"
        .. "Why \"combat-safe\"? Patch 12.0 (Midnight) made spell cooldowns, auras, and health / power "
        .. "|cffffffffSecret|r to addons in combat, so this tool sticks to what stays readable: your "
        .. "target, range, threat, pet, and item cooldowns.\n\n"
        .. "Created by |cffffffffTwistedfury-Zul'jin|r (Twisted Modding).  Cue sounds sourced from "
        .. "WeakAuras; icons by Tabler; data from wago.tools; design inspired by "
        .. "EllesmereUI. Full credits are on the |cffffffffAbout & Thanks|r page.")

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(180, 26); btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    btn:SetText("Open Cue Manager")
    btn:SetScript("OnClick", function()
        if HideUIPanel and SettingsPanel then HideUIPanel(SettingsPanel) end
        TCC.OpenManager()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Twisteds Combat Cues")
    category.ID = category.ID or "TwistedsCombatCues"
    Settings.RegisterAddOnCategory(category)
    TCC.category = category
    TCC.categoryID = category:GetID()
end

-- "/tcc options" opens Blizzard's Settings panel to this addon's entry.
function TCC.OpenOptions()
    if TCC.InitOptions then TCC.InitOptions() end
    if Settings and Settings.OpenToCategory and TCC.categoryID then
        Settings.OpenToCategory(TCC.categoryID)
    else
        TCC.OpenManager("global")   -- fallback for older clients
    end
end
