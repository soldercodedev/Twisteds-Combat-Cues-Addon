-- Twisteds Combat Cues - UI.lua
-- Self-skinned "Cue Manager": left sidebar (rules + Global Options), right editor.
-- Flat dark theme with a mint accent, custom toggles/dropdowns/sliders/inputs.
-- No external textures or libraries (solid-color textures + built-in fonts only).
local addonName, TCC = ...

-- Prefer the bundled Ubuntu font (a cleaner, modern UI look). WoW only indexes font
-- files that existed at launch, so if it isn't loadable yet (e.g. first run after the
-- files were added) SetFont returns false and we fall back to the default font.
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
do
    local UBUNTU = "Interface\\AddOns\\TwistedsCombatCues\\assets\\fonts\\Ubuntu.ttf"
    local probe = UIParent and UIParent:CreateFontString(nil, "OVERLAY")
    if probe then
        local ok = probe:SetFont(UBUNTU, 12)
        if ok then FONT = UBUNTU end
        probe:Hide()
    end
end
local QMARK = "Interface\\ICONS\\INV_Misc_QuestionMark"

-- Palette
local C = {
    bg      = { 0.09, 0.10, 0.12 },
    sidebar = { 0.11, 0.12, 0.15 },
    panel   = { 0.13, 0.14, 0.17 },
    card    = { 0.17, 0.19, 0.23 },
    hover   = { 0.22, 0.25, 0.30 },
    border  = { 0.26, 0.29, 0.35 },
    accent  = { 0.04, 0.34, 0.79 },  -- bootstrap primary, a few shades darker
    text    = { 0.90, 0.92, 0.95 },
    subtext = { 0.56, 0.60, 0.68 },
}

-- Layout
local WIN_W, WIN_H = 920, 600
local HEADER_H     = 44
local FOOTER_H     = 22
local SIDE_W       = 210
local PAD          = 24
local CONTENT_W    = 660
local TYPE_W       = 180
local PARAM_X      = PAD + TYPE_W + 8
local REMOVE_X     = 620
local ROW          = 36
local INDENT       = 18      -- horizontal step per nested group level
local MAX_INDENT   = 2       -- deeper groups still nest logically, just stop indenting
local MAX_GROUP_DEPTH = 4    -- how deep "+ Group" will let you nest (root = 0)

local CHANNELS = {
    { "Master", "Master (recommended)" },
    { "SFX", "Sound Effects" },
    { "Music", "Music" },
    { "Ambience", "Ambience" },
    { "Dialog", "Dialog" },
}

-- Chat output channels for a rule's chat message.
local CHAT_CHANNELS = {
    { "SELF", "Print to me" },
    { "SAY", "Say" },
    { "YELL", "Yell" },
    { "PARTY", "Party" },
    { "RAID", "Raid" },
    { "INSTANCE_CHAT", "Instance" },
    { "GUILD", "Guild" },
    { "OFFICER", "Officer" },
    { "EMOTE", "Emote" },
}

----------------------------------------------------------------------
-- Frames (assigned in EnsureManager; factories capture these upvalues)
----------------------------------------------------------------------
local mgr, sideChild, content, contentScroll, updateScrollbar
local built = false

local function paint(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a or 1) end
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function lighten(c, f) return { clamp01(c[1] + f), clamp01(c[2] + f), clamp01(c[3] + f) } end
local function darken(c, f) return { c[1] * (1 - f), c[2] * (1 - f), c[3] * (1 - f) } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

-- Tooltip helpers: any frame with ._tipTitle set shows help on hover.
-- A brightened accent so the tooltip header stays readable on the dark tooltip bg
-- even when the user's accent is a dark shade.
local function accentHeader()
    local a = C.accent
    return math.min(1, a[1] * 1.3 + 0.30), math.min(1, a[2] * 1.3 + 0.30), math.min(1, a[3] * 1.3 + 0.30)
end
-- Inline accent color code (lightened) for highlighting words. We author highlights as
-- the |cffffffff placeholder and swap it for the live theme accent when rendering text,
-- so key words pop in accent instead of white-on-white. Updated by ApplyAccent.
local ACCENT_CODE = "|cff5c9dff"
local function updateAccentCode()
    local r, g, b = accentHeader()
    ACCENT_CODE = string.format("|cff%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
updateAccentCode()
local function hl(s) if not s then return s end return (s:gsub("|cffffffff", ACCENT_CODE)) end
local function showTip(self)
    if not self._tipTitle then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._tipTitle, accentHeader())  -- accent-colored header on every tooltip
    if self._tipBody then GameTooltip:AddLine(hl(self._tipBody), 0.82, 0.86, 0.92, true) end
    GameTooltip:Show()
end
local function setTip(frame, title, body)
    if frame then frame._tipTitle = title; frame._tipBody = body end
    return frame
end

-- Give a frame a 1px border + fill.
local function stylePanel(f, fill, edge)
    fill, edge = fill or C.panel, edge or C.border
    local b = f._brd or f:CreateTexture(nil, "BACKGROUND", nil, 0)
    b:SetAllPoints(); paint(b, edge); f._brd = b
    local g = f._fill or f:CreateTexture(nil, "BACKGROUND", nil, 1)
    g:SetPoint("TOPLEFT", 1, -1); g:SetPoint("BOTTOMRIGHT", -1, 1); paint(g, fill); f._fill = g
end

-- Readable vertical scroll max for a ScrollFrame. GetVerticalScrollRange() can return a
-- Midnight "secret" number when the scroll content has held secret values -- comparing or
-- doing math on it then throws. The child/viewport heights stay readable, so derive it.
local function scrollMax(sf)
    local child = sf.GetScrollChild and sf:GetScrollChild()
    local ch = child and child:GetHeight()
    local vh = sf:GetHeight()
    if child and TCC.CanRead(ch) and TCC.CanRead(vh) then
        return math.max(0, ch - vh)
    end
    return 0
end

-- Shared mousewheel scroller.
local function scrollWheel(self, delta)
    local cur = self:GetVerticalScroll()
    if not TCC.CanRead(cur) then return end   -- position unreadable (secret) -> can't clamp safely
    self:SetVerticalScroll(math.min(scrollMax(self), math.max(0, cur - delta * 30)))
end

----------------------------------------------------------------------
-- Themed dropdown menu (replaces Blizzard MenuUtil for our dropdowns).
-- items: array of { label = , value = } or { label = , header = true }.
----------------------------------------------------------------------
local function makeMenuItem(parent)
    local b = CreateFrame("Button", nil, parent); b:SetHeight(22)
    b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:Hide()
    b.dot = b:CreateTexture(nil, "ARTWORK"); b.dot:SetSize(6, 6); b.dot:SetPoint("LEFT", 5, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 14, 0); b.icon:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12)
    b.fs:SetPoint("RIGHT", -6, 0); b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) if not self._header then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    function b:Set(it, selected, onClick)
        self._header = it.header
        paint(self.hl, mix(C.card, C.accent, 0.55))
        self.fs:ClearAllPoints(); self.fs:SetPoint("RIGHT", -6, 0)
        if it.header then
            self.fs:SetFont(FONT, 10); self.fs:SetText(it.label); self.fs:SetTextColor(unpack(C.subtext))
            self.fs:SetPoint("LEFT", 8, 0)
            self.dot:Hide(); self.icon:Hide(); self:SetHeight(20); self:EnableMouse(false); self:SetScript("OnClick", nil)
        else
            self.fs:SetFont(FONT, 12); self.fs:SetText(it.label)
            if it.icon then
                self.icon:SetTexture(it.icon)
                if it.coords then self.icon:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
                else self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                self.icon:Show(); self.fs:SetPoint("LEFT", 34, 0)
            else
                self.icon:Hide(); self.fs:SetPoint("LEFT", 16, 0)
            end
            if selected then
                self.fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]); paint(self.dot, C.accent); self.dot:Show()
            else
                self.fs:SetTextColor(C.text[1], C.text[2], C.text[3]); self.dot:Hide()
            end
            self:SetHeight(22); self:EnableMouse(true)
            self:SetScript("OnClick", function() onClick(it.value) end)
        end
    end
    return b
end

local dropMenu
local function ensureDropMenu()
    if dropMenu then return dropMenu end
    local closer = CreateFrame("Button", nil, UIParent)
    closer:SetAllPoints(UIParent); closer:SetFrameStrata("FULLSCREEN_DIALOG"); closer:Hide()
    local m = CreateFrame("Frame", "TwistedsCombatCuesDropMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetToplevel(true); m:SetClampedToScreen(true); m:Hide()
    stylePanel(m, C.panel, C.accent)
    m.scroll = CreateFrame("ScrollFrame", nil, m)
    m.scroll:SetPoint("TOPLEFT", 4, -4); m.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    m.child = CreateFrame("Frame", nil, m.scroll); m.child:SetSize(10, 10); m.scroll:SetScrollChild(m.child)
    m.scroll:EnableMouseWheel(true); m.scroll:SetScript("OnMouseWheel", scrollWheel)
    m.items = {}
    closer:SetScript("OnClick", function() m:Hide() end)
    m:SetScript("OnHide", function() closer:Hide() end)
    m.closer = closer
    dropMenu = m
    return m
end

local function openDropMenu(anchor, items, getSel, onPick)
    local m = ensureDropMenu()
    for _, b in ipairs(m.items) do b:Hide() end
    local width = math.max(anchor:GetWidth() or 150, 150)
    local sel = getSel and getSel() or nil
    local y, n = -2, 0
    for _, it in ipairs(items) do
        n = n + 1
        local b = m.items[n]
        if not b then b = makeMenuItem(m.child); m.items[n] = b end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, y); b:SetWidth(width - 8)
        b:Set(it, (not it.header) and sel == it.value, function(v) onPick(v); m:Hide() end)
        b:Show()
        y = y - (it.header and 20 or 22)
    end
    m.child:SetWidth(width - 8); m.child:SetHeight(math.max(1, -y + 2))
    local h = math.min(-y + 8, 340)
    m:SetSize(width, h)
    m.closer:Show(); m:Show()
    m:SetFrameLevel(m.closer:GetFrameLevel() + 10)
    m:ClearAllPoints()
    if (anchor:GetBottom() or 999) < h + 8 then
        m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)  -- open upward near screen bottom
    else
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    m.scroll:SetVerticalScroll(0)
end

----------------------------------------------------------------------
-- Widget factories (bare frames with a :Configure/:Set method)
----------------------------------------------------------------------
local function makeToggle(parent)
    local f = CreateFrame("Button", nil, parent); f:SetSize(38, 18)
    f.track = f:CreateTexture(nil, "ARTWORK"); f.track:SetAllPoints()
    f.knob = f:CreateTexture(nil, "OVERLAY"); f.knob:SetSize(14, 14)
    function f:_render()
        if self.checked then
            paint(self.track, C.accent)
            self.knob:ClearAllPoints(); self.knob:SetPoint("RIGHT", -2, 0); self.knob:SetColorTexture(0.05, 0.06, 0.08)
        else
            paint(self.track, C.border)
            self.knob:ClearAllPoints(); self.knob:SetPoint("LEFT", 2, 0); paint(self.knob, C.text)
        end
    end
    function f:Configure(checked, cb) self.checked = checked and true or false; self.cb = cb; self:_render() end
    f:SetScript("OnClick", function(self)
        self.checked = not self.checked; self:_render()
        if self.cb then self.cb(self.checked) end
    end)
    f:SetScript("OnEnter", showTip)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

local function makeButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12); b.fs:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self) self._hovered = true; if self._hover then paint(self.bg, self._hover) end; showTip(self) end)
    b:SetScript("OnLeave", function(self) self._hovered = false; if self._normal then paint(self.bg, self._normal) end; GameTooltip_Hide() end)
    -- Recompute colors from the CURRENT accent (accent is mutable via the picker).
    function b:_applyColors()
        if self._kind == "primary" then
            self._normal = { C.accent[1], C.accent[2], C.accent[3] }
            self._hover = lighten(C.accent, 0.14)
            self.fs:SetTextColor(1, 1, 1)
        elseif self._kind == "danger" then
            self._normal, self._hover = { 0.32, 0.14, 0.15 }, { 0.5, 0.22, 0.23 }
            self.fs:SetTextColor(1, 0.72, 0.72)
        else
            self._normal = { C.card[1], C.card[2], C.card[3] }
            self._hover = darken(C.accent, 0.35)  -- a darker shade of the accent
            self.fs:SetTextColor(unpack(C.text))
        end
        paint(self.bg, self._hovered and self._hover or self._normal)
    end
    function b:Configure(text, w, h, kind, cb)
        self._kind = kind; self:SetSize(w, h or 26); self.fs:SetText(text)
        self:_applyColors()
        self:SetScript("OnClick", function(self) if cb then cb(self) end end)  -- pass button (menu anchor)
    end
    function b:Retheme() self:_applyColors() end
    return b
end

local function makeDropdown(parent)
    local b = CreateFrame("Button", nil, parent); stylePanel(b, C.card)
    b.iconTex = b:CreateTexture(nil, "ARTWORK"); b.iconTex:SetSize(16, 16); b.iconTex:SetPoint("LEFT", 6, 0); b.iconTex:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12)
    b.fs:SetPoint("LEFT", 8, 0); b.fs:SetPoint("RIGHT", -20, 0); b.fs:SetJustifyH("LEFT"); b.fs:SetTextColor(unpack(C.text))
    b.caret = b:CreateFontString(nil, "OVERLAY"); b.caret:SetFont(FONT, 10); b.caret:SetPoint("RIGHT", -7, -1)
    b.caret:SetText("v"); b.caret:SetTextColor(unpack(C.accent))
    b:SetScript("OnEnter", function(self) paint(self._fill, C.hover); showTip(self) end)
    b:SetScript("OnLeave", function(self) paint(self._fill, C.card); GameTooltip_Hide() end)
    function b:SetChoices(w, choices, getVal, setVal)
        self:SetSize(w, 26)
        self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)  -- clear any leftover icon from a pooled reuse
        local function label() for _, c in ipairs(choices) do if c[1] == getVal() then return c[2] end end return "?" end
        self.fs:SetText(label())
        self:SetScript("OnClick", function(self)
            local items = {}
            for _, c in ipairs(choices) do items[#items + 1] = { label = c[2], value = c[1] } end
            openDropMenu(self, items, getVal, function(v) setVal(v); self.fs:SetText(label()) end)
        end)
    end
    function b:SetSoundMenu(w, action)
        self:SetSize(w, 26)
        self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)
        self.fs:SetText(TCC.SoundLabel(action.soundKey))
        self:SetScript("OnClick", function(self)
            local items, customStarted = { { label = "Blizzard Sounds", header = true } }, false
            for _, s in ipairs(TCC.SOUNDS) do
                if s.file and not customStarted then
                    items[#items + 1] = { label = "Custom Sounds", header = true }; customStarted = true
                end
                items[#items + 1] = { label = s.label, value = s.key }
            end
            openDropMenu(self, items, function() return action.soundKey end, function(v)
                action.soundKey = v; self.fs:SetText(TCC.SoundLabel(v)); TCC.PlayKey(v, TCC.db.channel)
            end)
        end)
    end
    -- Dropdown where each item has an icon; the button shows the selected icon.
    function b:SetIconChoices(w, items, getVal, setVal)
        self:SetSize(w, 26)
        local function cur() for _, it in ipairs(items) do if it.value == getVal() then return it end end end
        local function refresh()
            local it = cur()
            if it and it.icon then
                self.iconTex:SetTexture(it.icon)
                if it.coords then self.iconTex:SetTexCoord(it.coords[1], it.coords[2], it.coords[3], it.coords[4])
                else self.iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                self.iconTex:Show(); self.fs:SetPoint("LEFT", 28, 0)
            else
                self.iconTex:Hide(); self.fs:SetPoint("LEFT", 8, 0)
            end
            self.fs:SetText(it and it.label or "?")
        end
        refresh()
        self:SetScript("OnClick", function(self)
            openDropMenu(self, items, getVal, function(v) setVal(v); refresh() end)
        end)
    end
    return b
end

local function makeEdit(parent)
    local e = CreateFrame("EditBox", nil, parent); stylePanel(e, C.bg)
    e:SetFont(FONT, 12, ""); e:SetTextColor(unpack(C.text)); e:SetTextInsets(7, 7, 0, 0); e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnter", showTip)
    e:SetScript("OnLeave", GameTooltip_Hide)
    function e:Configure(w, h, value, onCommit)
        self:SetSize(w, h or 24)
        self:SetScript("OnTextChanged", nil)  -- pooled: avoid a stale handler firing on SetText
        self:SetText(value ~= nil and tostring(value) or ""); self:SetCursorPosition(0)
        self:SetScript("OnEnterPressed", function(self) if onCommit then onCommit(self:GetText()) end self:ClearFocus() end)
        self:SetScript("OnEditFocusLost", function(self) if onCommit then onCommit(self:GetText()) end end)
    end
    return e
end

local function makeSlider(parent)
    local s = CreateFrame("Slider", nil, parent); s:SetOrientation("HORIZONTAL")
    s.track = s:CreateTexture(nil, "ARTWORK"); paint(s.track, C.border)
    s.track:SetHeight(3); s.track:SetPoint("LEFT"); s.track:SetPoint("RIGHT")
    s.thumb = s:CreateTexture(nil, "OVERLAY"); paint(s.thumb, C.accent); s.thumb:SetSize(12, 12)
    s:SetThumbTexture(s.thumb)
    s.val = s:CreateFontString(nil, "OVERLAY"); s.val:SetFont(FONT, 11)
    s.val:SetPoint("BOTTOM", s, "TOP", 0, 3); s.val:SetTextColor(unpack(C.subtext))
    s:SetScript("OnEnter", showTip)
    s:SetScript("OnLeave", GameTooltip_Hide)
    function s:Configure(w, minv, maxv, step, getVal, setVal, fmt)
        fmt = fmt or "%.1f"
        paint(self.thumb, C.accent)
        -- Clear any previous setter FIRST: this slider is pooled, and SetValue()
        -- fires OnValueChanged. Without this, reusing a slider (e.g. window-scale
        -- -> font-size) would run the old setter with the new value.
        self:SetScript("OnValueChanged", nil)
        self:SetSize(w, 16); self:SetMinMaxValues(minv, maxv); self:SetValueStep(step); self:SetObeyStepOnDrag(true)
        self:SetValue(getVal()); self.val:SetText(string.format(fmt, getVal()))
        self:SetScript("OnValueChanged", function(_, v) self.val:SetText(string.format(fmt, v)); setVal(v) end)
    end
    return s
end

local function makeIcon(parent)
    local b = CreateFrame("Button", nil, parent); b:SetSize(20, 20)
    stylePanel(b, C.bg)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return b
end

-- Tabler icons (tabler.io/icons, MIT), converted to 64x64 TGA in assets/icons/.
-- Declared up here so the alert editors, the sidebar, and the icon picker all share them.
local ICON_DIR = "Interface\\AddOns\\TwistedsCombatCues\\assets\\icons\\"
local KIND_ICONS = {
    range    = ICON_DIR .. "target-arrow.tga",
    target   = ICON_DIR .. "target.tga",
    threat   = ICON_DIR .. "flame.tga",
    pet      = ICON_DIR .. "paw.tga",
    item     = ICON_DIR .. "flask.tga",
    advanced = ICON_DIR .. "adjustments.tga",
}
local RULE_ICON = ICON_DIR .. "bell.tga"
local PLUS_ICON = "|T" .. ICON_DIR .. "plus.tga:14:14:0:0|t"   -- inline plus glyph for buttons
-- Curated set a user can pick for a per-alert sidebar icon.
-- Must stay in sync with the PICKER list in Tools/convert_icons.py.
local PICKER_ICONS = {
    "bell", "bell-ringing", "alert-triangle", "alert-circle", "alert-octagon",
    "flame", "bolt", "shield", "shield-half", "sword", "swords", "axe",
    "target", "target-arrow", "crosshair", "focus-2", "skull", "ghost",
    "heart", "heartbeat", "activity", "droplet", "flask", "flask-2", "pill",
    "first-aid-kit", "paw", "dog", "cat", "mouse", "spider", "eye", "run",
    "map-pin", "radar", "hourglass", "clock", "star", "diamond", "hexagon",
    "wind", "snowflake",
}

-- Alert categories (shared by the Alerts page + New-alert menu).
local KIND_ORDER = { "range", "target", "threat", "pet", "item", "advanced" }
local KIND_LABEL = { range = "RANGE ALERTS", target = "TARGET ALERTS", threat = "THREAT ALERTS",
                     pet = "PET ALERTS", item = "ITEM ALERTS", advanced = "ADVANCED" }
local function alertKindOf(rule)
    if rule.kind and TCC.GetAlertKind and TCC.GetAlertKind(rule.kind) then return rule.kind end
    return "advanced"
end

-- The icon that represents an alert (list row + editor swatch):
--   item alert with "use item icon" -> the item's own icon,
--   else the chosen icon, else its on-screen icon, else the kind default.
local function alertIconOf(rule)
    if rule.kind == "item" and rule.useItemIcon and rule.trigger and rule.trigger.item then
        local id = tonumber(rule.trigger.item)
        local getIcon = C_Item and C_Item.GetItemIconByID
        if id and getIcon then local ic = getIcon(id); if ic then return ic end end
    end
    if rule.navIcon and rule.navIcon ~= "" then return ICON_DIR .. rule.navIcon end
    if rule.action and rule.action.showIcon and rule.action.icon and rule.action.icon ~= "" then
        return TCC.ResolveIcon(rule.action.icon)
    end
    return KIND_ICONS[alertKindOf(rule)] or RULE_ICON
end
TCC.AlertIcon = alertIconOf   -- exposed so the position mover can label each ghost

local function makeSwatch(parent)
    local b = CreateFrame("Button", nil, parent); b:SetSize(20, 20); stylePanel(b, C.bg)
    b.color = b:CreateTexture(nil, "ARTWORK")
    b.color:SetPoint("TOPLEFT", 2, -2); b.color:SetPoint("BOTTOMRIGHT", -2, 2)
    return b
end

local LOGO_PATH = "Interface\\AddOns\\TwistedsCombatCues\\assets\\TCC_Logo.tga"
-- Logo image inside a 2px accent border on a dark panel (so it never clashes
-- with the background regardless of the logo's own edges).
local function makeLogo(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.brd = f:CreateTexture(nil, "BACKGROUND", nil, 0); f.brd:SetAllPoints(); paint(f.brd, C.accent)
    f.inner = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.inner:SetPoint("TOPLEFT", 2, -2); f.inner:SetPoint("BOTTOMRIGHT", -2, 2); paint(f.inner, C.bg)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 6, -6); f.tex:SetPoint("BOTTOMRIGHT", -6, 6)
    return f
end

-- Live preview box for a rule's visual text + icon (icon is draggable).
local function makePreview(parent)
    local f = CreateFrame("Frame", nil, parent); stylePanel(f, { 0.05, 0.05, 0.06 }, C.border)
    f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetPoint("CENTER")
    local ag = f.fs:CreateAnimationGroup()
    local p1 = ag:CreateAnimation("Alpha"); p1:SetFromAlpha(1); p1:SetToAlpha(0.3); p1:SetDuration(0.5); p1:SetOrder(1)
    local p2 = ag:CreateAnimation("Alpha"); p2:SetFromAlpha(0.3); p2:SetToAlpha(1); p2:SetDuration(0.5); p2:SetOrder(2)
    ag:SetLooping("REPEAT"); f.pulse = ag

    local ib = CreateFrame("Button", nil, f); ib:SetSize(24, 24); ib:EnableMouse(true); ib:RegisterForDrag("LeftButton"); ib:Hide()
    ib.tex = ib:CreateTexture(nil, "ARTWORK"); ib.tex:SetAllPoints(); ib.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Drag to position the icon", accentHeader()); GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", GameTooltip_Hide)
    ib:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local pf = self:GetParent(); local a, ps = pf._action, pf._pscale or 1
            if not a then return end
            local s = pf:GetEffectiveScale(); local cx, cy = GetCursorPosition()
            local fcx, fcy = pf.fs:GetCenter()
            if fcx and s and s > 0 then
                a.iconX = ((cx / s) - fcx) / ps; a.iconY = ((cy / s) - fcy) / ps
                self:ClearAllPoints(); self:SetPoint("CENTER", pf.fs, "CENTER", a.iconX * ps, a.iconY * ps)
            end
        end)
    end)
    ib:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local pf = self:GetParent(); if pf._onMove then pf._onMove() end
    end)
    f.iconBtn = ib
    return f
end

-- Custom color picker: preview + RGB sliders + hex box + preset grid.
local PRESETS = {
    "0D6EFD", "0A58CA", "0B5ED7", "6610F2", "6F42C1", "D63384", "DC3545", "E35D6A",
    "FD7E14", "FFC107", "FFDA6A", "198754", "20C997", "0DCAF0", "3DD5F3", "FFFFFF",
    "CED4DA", "ADB5BD", "6C757D", "343A40", "000000", "FF0000", "00FF00", "00A2FF",
}

local function hexOf(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
local function parseHex(s)
    s = (s or ""):gsub("[^0-9a-fA-F]", "")
    if #s >= 6 then
        return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
    end
end

local function ensureColorPicker()
    local p = TCC._cpick
    if p then return p end
    p = CreateFrame("Frame", "TwistedsCombatCuesColorPicker", UIParent)
    TCC._cpick = p
    p:SetSize(260, 340); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
    stylePanel(p, C.panel, C.border)
    p:EnableMouse(true); p:SetMovable(true)
    tinsert(UISpecialFrames, "TwistedsCombatCuesColorPicker")

    local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(26)
    local hbg = hd:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); paint(hbg, C.card)
    hd:RegisterForDrag("LeftButton")
    hd:SetScript("OnDragStart", function() p:StartMoving() end)
    hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local t = hd:CreateFontString(nil, "OVERLAY"); t:SetFont(FONT, 12); t:SetPoint("LEFT", 10, 0); t:SetText("Choose a color"); t:SetTextColor(unpack(C.text))
    local xb = makeButton(p); xb:Configure("X", 22, 20, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -3, -3); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

    -- Preview + hex
    local prev = CreateFrame("Frame", nil, p); prev:SetSize(46, 46); prev:SetPoint("TOPLEFT", 14, -34); stylePanel(prev, C.bg)
    p.prevTex = prev:CreateTexture(nil, "ARTWORK"); p.prevTex:SetPoint("TOPLEFT", 2, -2); p.prevTex:SetPoint("BOTTOMRIGHT", -2, 2)
    local hexL = p:CreateFontString(nil, "OVERLAY"); hexL:SetFont(FONT, 11); hexL:SetPoint("TOPLEFT", prev, "TOPRIGHT", 12, -2); hexL:SetText("Hex"); hexL:SetTextColor(unpack(C.subtext))
    local hexBox = makeEdit(p); hexBox:Configure(120, 22, "", nil); hexBox:ClearAllPoints(); hexBox:SetPoint("TOPLEFT", prev, "TOPRIGHT", 12, -16)
    p.hex = hexBox

    p.cur = { 1, 1, 1 }
    local function emit(src)
        local r, g, b = p.cur[1], p.cur[2], p.cur[3]
        p.prevTex:SetColorTexture(r, g, b)
        p._sync = true
        if src ~= "hex" then p.hex:SetText(hexOf(r, g, b)) end
        if p.sr and p.sg and p.sb then
            p.sr:SetValue(r * 255); p.sg:SetValue(g * 255); p.sb:SetValue(b * 255)
        end
        p._sync = false
        if p.cb then p.cb(r, g, b) end
    end
    p.emit = emit

    hexBox:SetScript("OnTextChanged", function(self)
        if p._sync then return end
        local r, g, b = parseHex(self:GetText())
        if r then p.cur[1], p.cur[2], p.cur[3] = r, g, b; emit("hex") end
    end)

    -- RGB sliders
    local sy = -92
    local function mkChannel(label, idx)
        local l = p:CreateFontString(nil, "OVERLAY"); l:SetFont(FONT, 11); l:SetPoint("TOPLEFT", 14, sy); l:SetText(label); l:SetTextColor(unpack(C.subtext))
        local s = makeSlider(p); s:ClearAllPoints(); s:SetPoint("TOPLEFT", 40, sy - 2)
        s:Configure(190, 0, 255, 1, function() return p.cur[idx] * 255 end, function(v)
            if p._sync then return end
            p.cur[idx] = v / 255; emit("slider")
        end, "%d")
        sy = sy - 34
        return s
    end
    p.sr = mkChannel("R", 1)
    p.sg = mkChannel("G", 2)
    p.sb = mkChannel("B", 3)

    -- Preset grid
    local gx, gy, col = 14, sy - 6, 0
    for _, hex in ipairs(PRESETS) do
        local sw = CreateFrame("Button", nil, p); sw:SetSize(24, 18)
        sw:SetPoint("TOPLEFT", gx + col * 28, gy)
        stylePanel(sw, C.bg)
        local tx = sw:CreateTexture(nil, "ARTWORK"); tx:SetPoint("TOPLEFT", 1, -1); tx:SetPoint("BOTTOMRIGHT", -1, 1)
        local r, g, b = parseHex(hex); tx:SetColorTexture(r, g, b)
        sw:SetScript("OnClick", function() p.cur[1], p.cur[2], p.cur[3] = r, g, b; emit("preset") end)
        col = col + 1
        if col >= 8 then col = 0; gy = gy - 22 end
    end

    return p
end

-- Opens the custom color picker seeded with r,g,b; callback(r,g,b) live.
local function OpenColorPicker(r, g, b, callback)
    local p = ensureColorPicker()
    p.cb = callback
    p.cur[1], p.cur[2], p.cur[3] = r or 1, g or 1, b or 1
    p:Show()
    p.emit("open")
end

----------------------------------------------------------------------
-- Pools (PC = content widgets, PS = sidebar widgets)
----------------------------------------------------------------------
local PC, PS = {}, {}
local function acq(store, name, factory)
    local p = store[name]; if not p then p = { items = {}, used = 0 }; store[name] = p end
    p.used = p.used + 1
    local w = p.items[p.used]; if not w then w = factory(); p.items[p.used] = w end
    w._tipTitle, w._tipBody = nil, nil  -- start each build without a stale tooltip
    w:Show(); return w
end
local function releaseAll(store)
    for _, p in pairs(store) do
        for i = p.used, 1, -1 do local w = p.items[i]; if w then w:Hide(); w:ClearAllPoints() end end
        p.used = 0
    end
end

-- Content-widget helpers (parented to `content`, positioned from its TOPLEFT).
local function put(w, x, y) w:ClearAllPoints(); w:SetPoint("TOPLEFT", content, "TOPLEFT", x, y); return w end
local function CLabel(text, x, y, color, size)
    local fs = acq(PC, "label", function() return content:CreateFontString(nil, "OVERLAY") end)
    fs:SetFont(FONT, size or 12); fs:SetJustifyH("LEFT"); fs:SetText(hl(text))
    fs:SetTextColor(unpack(color or C.text)); put(fs, x, y); return fs
end
local function CToggle(x, y, checked, cb)
    local w = acq(PC, "toggle", function() return makeToggle(content) end); w:Configure(checked, cb); return put(w, x, y)
end
local function CButton(x, y, w_, text, kind, cb)
    local b = acq(PC, "button", function() return makeButton(content) end); b:Configure(text, w_, 26, kind, cb); return put(b, x, y)
end
local function CDD(x, y)
    local d = acq(PC, "dd", function() return makeDropdown(content) end); return put(d, x, y)
end
local function CEdit(x, y, w_, value, onCommit)
    local e = acq(PC, "edit", function() return makeEdit(content) end); e:Configure(w_, 24, value, onCommit); return put(e, x, y)
end
local function CSlider(x, y)
    local s = acq(PC, "slider", function() return makeSlider(content) end); return put(s, x, y)
end
local function CIcon(x, y)
    local b = acq(PC, "icon", function() return makeIcon(content) end)
    b:SetSize(20, 20)                          -- reset: pooled, a prior caller may have resized it
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- reset the default crop too
    return put(b, x, y)
end
local function CSection(text, x, y, w)
    CLabel(text, x, y, C.accent, 12)
    local d = acq(PC, "divider", function() return content:CreateTexture(nil, "ARTWORK") end)
    d:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8); d:SetHeight(1)
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - 18); d:SetWidth(w or 552); d:Show()
end

-- Lighter sub-header used inside a section (e.g. Sound / Text / Icon under ACTION).
local function CSub(text, x, y)
    CLabel(text, x, y, C.accent, 11)
    local d = acq(PC, "divider", function() return content:CreateTexture(nil, "ARTWORK") end)
    d:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.45); d:SetHeight(1)
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - 15); d:SetWidth(CONTENT_W - 48); d:Show()
end

local function CSwatch(x, y, colorTbl, onChange)
    local s = acq(PC, "swatch", function() return makeSwatch(content) end)
    local col = colorTbl
    s.color:SetColorTexture(col[1] or 1, col[2] or 0.1, col[3] or 0.1)
    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Click to change text color", accentHeader()); GameTooltip:Show()
    end)
    s:SetScript("OnLeave", GameTooltip_Hide)
    s:SetScript("OnClick", function()
        OpenColorPicker(col[1] or 1, col[2] or 0.1, col[3] or 0.1, function(r, g, b)
            col[1], col[2], col[3] = r, g, b
            s.color:SetColorTexture(r, g, b)
            onChange()
        end)
    end)
    return put(s, x, y)
end

local function CLogo(x, y, size)
    local f = acq(PC, "logo", function() return makeLogo(content) end)
    f:SetSize(size, size)
    paint(f.brd, C.accent)   -- track theme accent on rebuild
    f.tex:SetTexture(LOGO_PATH)
    return put(f, x, y)
end

local function CPreview(x, y, w, h)
    local f = acq(PC, "preview", function() return makePreview(content) end)
    f:SetSize(w, h)
    return put(f, x, y)
end

-- Word-wrapped read-only text; returns the fontstring and its rendered height.
local function CWrap(text, x, y, w, color, size)
    local fs = acq(PC, "wrap", function() return content:CreateFontString(nil, "OVERLAY") end)
    fs:SetFont(FONT, size or 11); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    fs:SetWidth(w); fs:SetText(hl(text)); fs:SetTextColor(unpack(color or C.subtext))
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y); fs:Show()
    return fs, (fs:GetStringHeight() or 14)
end

-- Filled rectangle drawn on content's BACKGROUND layer (sits BEHIND widget frames).
-- Deeper groups use a higher sublevel so a nested tint shows over its parent's.
local function CBox(x, yTop, w, h, alpha, sub, col)
    col = col or C.accent
    local t = acq(PC, "box", function() return content:CreateTexture(nil, "BACKGROUND") end)
    t:SetDrawLayer("BACKGROUND", sub or 0)
    t:SetColorTexture(col[1], col[2], col[3], alpha or 0.06)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", content, "TOPLEFT", x, yTop)
    t:SetSize(math.max(1, w), math.max(1, h)); t:Show()
    return t
end

-- Thin vertical rail (group bracket), on ARTWORK so it shows over the box tint.
local function CVRule(x, yTop, yBottom, sub, col)
    col = col or C.accent
    local t = acq(PC, "vrule", function() return content:CreateTexture(nil, "ARTWORK") end)
    t:SetDrawLayer("ARTWORK", sub or 0)
    t:SetColorTexture(col[1], col[2], col[3], 0.85); t:SetWidth(2)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", content, "TOPLEFT", x, yTop)
    t:SetHeight(math.max(2, yTop - yBottom)); t:Show()
    return t
end

local function softApply() TCC.RebuildEngine(); TCC.Evaluate() end
function TCC.RefreshEditorSoon() C_Timer.After(0, function() TCC.RefreshManager() end) end

-- Apply the saved accent color live (mutates C.accent in place so subsequent
-- widget rebuilds pick it up; updates the create-once logo directly).
local function ApplyAccent()
    local a = TCC.db and TCC.db.accentColor
    if a then C.accent[1], C.accent[2], C.accent[3] = a[1], a[2], a[3] end
    updateAccentCode()   -- keep inline highlight color in sync with the theme
    if mgr then
        if mgr.logo then paint(mgr.logo, C.accent) end
        -- Nav rows + content widgets re-follow the accent via navSelect / rebuild in RefreshManager.
    end
end

----------------------------------------------------------------------
-- Export / import text dialog (reused for both directions)
----------------------------------------------------------------------
local textDlg
local function ensureTextDialog()
    if textDlg then return textDlg end
    local d = CreateFrame("Frame", "TwistedsCombatCuesTextDialog", UIParent)
    d:SetSize(470, 300); d:SetPoint("CENTER"); d:SetFrameStrata("FULLSCREEN_DIALOG"); d:SetToplevel(true); d:SetClampedToScreen(true)
    stylePanel(d, C.panel, C.border)
    d:EnableMouse(true); d:SetMovable(true)
    tinsert(UISpecialFrames, "TwistedsCombatCuesTextDialog")

    local hd = CreateFrame("Button", nil, d); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(28)
    local hbg = hd:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); paint(hbg, C.card)
    hd:RegisterForDrag("LeftButton")
    hd:SetScript("OnDragStart", function() d:StartMoving() end)
    hd:SetScript("OnDragStop", function() d:StopMovingOrSizing() end)
    d.title = hd:CreateFontString(nil, "OVERLAY"); d.title:SetFont(FONT, 13); d.title:SetPoint("LEFT", 10, 0); d.title:SetTextColor(unpack(C.text))
    local x = makeButton(d); x:Configure("X", 24, 22, "danger", function() d:Hide() end); x:SetPoint("TOPRIGHT", -4, -4)
    x:SetFrameLevel(hd:GetFrameLevel() + 5)

    local box = CreateFrame("Frame", nil, d); box:SetPoint("TOPLEFT", 12, -38); box:SetPoint("BOTTOMRIGHT", -12, 46); stylePanel(box, C.bg)
    -- A ScrollFrame clips the editbox to the panel so a long string can't overflow.
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", scrollWheel)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFont(FONT, 12, ""); eb:SetTextColor(unpack(C.text))
    eb:SetTextInsets(2, 2, 2, 2); eb:SetWidth(420)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    -- Keep the editbox width matched to the scroll area so text wraps (never spills).
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then eb:SetWidth(w) end end)
    -- Follow the cursor so long content scrolls into view while typing/pasting.
    eb:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        if -cy < top then scroll:SetVerticalScroll(-cy)
        elseif (-cy + ch) > (top + view) then scroll:SetVerticalScroll(-cy + ch - view) end
    end)
    scroll:SetScript("OnMouseDown", function() eb:SetFocus() end)
    scroll:SetScrollChild(eb)
    d.eb = eb

    d.info = d:CreateFontString(nil, "OVERLAY"); d.info:SetFont(FONT, 11); d.info:SetPoint("BOTTOMLEFT", 14, 16); d.info:SetTextColor(unpack(C.subtext))
    d.accept = makeButton(d); d.accept:SetPoint("BOTTOMRIGHT", -12, 12)
    textDlg = d
    return d
end

local function ShowExportDialog(str)
    local d = ensureTextDialog()
    d.title:SetText("Export - copy this string (Ctrl+C)")
    d.eb:SetText(str or ""); d.eb:SetCursorPosition(0); d.eb:HighlightText()
    d.info:SetText("Select all is done for you - press Ctrl+C.")
    d.accept:Hide()
    d:Show(); d.eb:SetFocus()
end

-- Show a URL in the copy dialog (WoW addons can't open a browser, so we let the user
-- copy it out with Ctrl+C).
local function ShowLinkDialog(title, url)
    local d = ensureTextDialog()
    d.title:SetText(title or "Copy this link (Ctrl+C)")
    d.eb:SetText(url or ""); d.eb:SetCursorPosition(0); d.eb:HighlightText()
    d.info:SetText("Selected for you - press Ctrl+C, then paste it into your browser.")
    d.accept:Hide()
    d:Show(); d.eb:SetFocus()
end

local function ShowImportDialog()
    local d = ensureTextDialog()
    d.title:SetText("Import - paste an alert string")
    d.eb:SetText(""); d.info:SetText("Paste an exported string, then click Import.")
    d.accept:Configure("Import", 90, 24, "primary", function()
        local ok, res = TCC.Import(d.eb:GetText())
        if ok then
            d.info:SetText("|cff33ff33Imported " .. res .. " alert(s).|r")
            d:Hide(); TCC.RefreshManager()
        else
            d.info:SetText("|cffff5555" .. tostring(res) .. "|r")
        end
    end)
    d.accept:Show()
    d:Show(); d.eb:SetFocus()
end

----------------------------------------------------------------------
-- Condition row (inside the rule editor)
----------------------------------------------------------------------
-- Spell / item picker field (kind "spell" or "item").
local function spellField(cond, p, x, y)
    local isItem = (p.kind == "item")
    local resolve = isItem and TCC.ResolveItem or TCC.ResolveSpell
    local id, name, icon = resolve(cond[p.key])
    local ib = CIcon(x, y - 1)
    ib.tex:SetTexture(icon or QMARK)
    ib:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if id then
            if isItem then GameTooltip:SetItemByID(id) else GameTooltip:SetSpellByID(id) end
        else
            GameTooltip:SetText(isItem and "Click to search items" or "Click to search spells / buffs", accentHeader())
        end
        GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", GameTooltip_Hide)
    ib:SetScript("OnClick", function()
        TCC.OpenSpellPicker(ib, cond[p.key], function(pid)
            cond[p.key] = tostring(pid); softApply(); TCC.RefreshEditorSoon()
        end, isItem and "item" or "spell")
    end)
    local display = name or (cond[p.key] ~= nil and tostring(cond[p.key])) or ""
    CEdit(x + 24, y, (p.width or 150) - 24, display, function(t)
        if t ~= display then
            -- Store the ID when we can resolve it: name lookups are restricted inside
            -- Mythic+, so IDs keep the condition working there.
            cond[p.key] = (resolve(t)) or t
            softApply(); TCC.RefreshEditorSoon()
        else
            softApply()
        end
    end)
end

-- Renders one condition row at horizontal offset x (indented for nested groups).
-- Removes from group.children on the X button.
local function conditionRow(group, cond, index, x, y)
    local paramX = x + TYPE_W + 8
    local typeChoices = {}
    for _, m in ipairs(TCC.CONDITION_TYPES) do typeChoices[#typeChoices + 1] = { m.type, m.label } end
    setTip(CDD(x, y), "Condition type", "What this condition checks (combat, target, buff, aura gained/lost, spell/item ready, class/spec, etc.)."):SetChoices(
        TYPE_W, typeChoices,
        function() return cond.type end,
        function(v)
            if v ~= cond.type then
                for k in pairs(cond) do cond[k] = nil end
                cond.type = v
                local meta = TCC.GetConditionMeta(v)
                if meta then for _, pp in ipairs(meta.params) do cond[pp.key] = pp.default end end
                if v == "classSpec" then local _, tok = UnitClass("player"); cond.class = tok; cond.spec = "all" end
                softApply(); TCC.RefreshEditorSoon()
            end
        end)

    if cond.type == "classSpec" then
        local classItems = {}
        for _, c in ipairs(TCC.GetClassList()) do
            classItems[#classItems + 1] = { value = c.token, label = c.name, icon = c.icon, coords = c.coords }
        end
        setTip(CDD(paramX, y), "Class", "Only fire on this class (most useful on account-wide profiles)."):SetIconChoices(
            150, classItems, function() return cond.class end, function(v)
                cond.class = v; cond.spec = "all"; softApply(); TCC.RefreshEditorSoon()
            end)
        local specItems = {}
        for _, s in ipairs(TCC.GetSpecList(cond.class)) do
            specItems[#specItems + 1] = { value = s.value, label = s.name, icon = s.icon }
        end
        setTip(CDD(paramX + 158, y), "Specialization", "Match a specific spec, or All Specs."):SetIconChoices(
            150, specItems, function() return cond.spec end, function(v) cond.spec = v; softApply() end)
    else
        local meta = TCC.GetConditionMeta(cond.type)
        if meta then
            local drivers = {}
            for _, pp in ipairs(meta.params) do if pp.showIf then drivers[pp.showIf.key] = true end end
            local px = paramX
            for _, p in ipairs(meta.params) do
                local show = not (p.showIf and cond[p.showIf.key] ~= p.showIf.val)
                if show then
                    if p.kind == "choice" then
                        setTip(CDD(px, y), meta.label, "Option for this condition."):SetChoices(p.width or 110, p.choices,
                            function() return cond[p.key] end,
                            function(v) cond[p.key] = v; softApply(); if drivers[p.key] then TCC.RefreshEditorSoon() end end)
                    elseif p.kind == "number" then
                        setTip(CEdit(px, y, p.width or 50, cond[p.key], function(t) cond[p.key] = tonumber(t) or p.default; softApply() end),
                            meta.label, p.hint and ("Value in " .. p.hint .. ".") or "Enter a number.")
                    elseif p.kind == "spell" or p.kind == "item" then
                        spellField(cond, p, px, y)
                    else
                        setTip(CEdit(px, y, p.width or 120, cond[p.key], function(t) cond[p.key] = t; softApply() end),
                            meta.label, "Enter a value.")
                    end
                    px = px + (p.width or 110) + 8
                end
            end
        end
    end

    setTip(CButton(REMOVE_X, y, 24, "X", "danger", function()
        table.remove(group.children, index); softApply(); TCC.RefreshEditorSoon()
    end), "Remove condition", "Delete this condition from the rule.")
end

-- Recursive rendering of the condition tree (nested AND / OR groups).
local buildNode, buildGroup

buildNode = function(group, node, index, y, depth, cmap)
    if node.children then
        return buildGroup(node, y, depth, group, index, cmap)
    end
    local x = PAD + math.min(depth, MAX_INDENT) * INDENT
    conditionRow(group, node, index, x, y)
    return y - ROW
end

buildGroup = function(g, y, depth, parent, pindex, cmap)
    local isRoot = (parent == nil)
    local col = (not isRoot) and cmap and cmap[g] or nil   -- group's assigned color
    local headerCol = col or C.accent
    local gx = PAD + math.min(depth, MAX_INDENT) * INDENT
    local boxTop = y + 6

    setTip(CLabel("Match", gx, y - 2, isRoot and C.subtext or headerCol),
        "Match mode", "How the conditions inside this group combine.")
    local ddx = gx + 48
    setTip(CDD(ddx, y), "Match mode", "ALL = every entry must be true. ANY = at least one."):SetChoices(
        66, { { "ALL", "All" }, { "ANY", "Any" } },
        function() return g.op or "ALL" end,
        function(v) g.op = v; TCC.RefreshEditorSoon() end)
    CLabel("of these:", ddx + 74, y - 2, C.subtext)
    if not isRoot then
        setTip(CButton(REMOVE_X, y, 24, "X", "danger", function()
            table.remove(parent.children, pindex); softApply(); TCC.RefreshEditorSoon()
        end), "Remove group", "Delete this group and everything inside it.")
    end
    y = y - ROW

    -- Children, with an AND/OR connector chip drawn between every pair of siblings.
    local connOp = (g.op == "ANY") and "OR" or "AND"
    local childX = PAD + math.min(depth + 1, MAX_INDENT) * INDENT
    for i, child in ipairs(g.children) do
        if i > 1 then
            CLabel(connOp, childX + 2, y - 1, headerCol, 11)
            y = y - 17
        end
        y = buildNode(g, child, i, y, depth + 1, cmap)
    end

    setTip(CButton(childX, y, 128, "+ Condition", "default", function()
        table.insert(g.children, TCC.NewCondition("combat")); softApply(); TCC.RefreshEditorSoon()
    end), "Add condition", "Add a condition to this group.")
    -- Only offer nesting until the depth cap, so rules stay readable.
    if depth < MAX_GROUP_DEPTH then
        setTip(CButton(childX + 136, y, 92, "+ Group", "default", function()
            table.insert(g.children, { op = "ALL", children = { TCC.NewCondition("combat") } }); softApply(); TCC.RefreshEditorSoon()
        end), "Add group", "Add a nested AND / OR group for more complex logic.")
    else
        setTip(CLabel("(max nesting reached)", childX + 140, y - 4, C.subtext, 10),
            "Nesting limit", "Groups can nest up to " .. MAX_GROUP_DEPTH .. " levels deep to keep alerts readable.")
    end
    y = y - 40
    local boxBottom = y + 4

    -- Frame nested groups in their assigned color so extent + identity are obvious.
    if not isRoot then
        local boxX = gx - 8
        local sub = math.min(depth, 6)
        CBox(boxX, boxTop, (CONTENT_W - 10) - boxX, boxTop - boxBottom, 0.10, sub, col)
        CVRule(boxX, boxTop, boxBottom, sub, col)
    end
    return y - 8
end

----------------------------------------------------------------------
-- Content: rule editor
----------------------------------------------------------------------
-- Renders just the params of a single condition (no type dropdown / remove button).
local function renderParams(cond, x, y)
    local meta = TCC.GetConditionMeta(cond.type)
    if not meta then return end
    local drivers = {}
    for _, pp in ipairs(meta.params) do if pp.showIf then drivers[pp.showIf.key] = true end end
    local px = x
    for _, p in ipairs(meta.params) do
        local show = not (p.showIf and cond[p.showIf.key] ~= p.showIf.val)
        if show then
            if p.pre then   -- inline lead-in word (e.g. "Spell", "is") for natural phrasing
                CLabel(p.pre, px, y - 2, C.subtext)
                px = px + (#p.pre * 6) + 12
            end
            if p.kind == "choice" then
                setTip(CDD(px, y), meta.label, "Option for this alert."):SetChoices(p.width or 110, p.choices,
                    function() return cond[p.key] end,
                    function(v) cond[p.key] = v; softApply(); if drivers[p.key] then TCC.RefreshEditorSoon() end end)
            elseif p.kind == "number" then
                setTip(CEdit(px, y, p.width or 50, cond[p.key], function(t) cond[p.key] = tonumber(t) or p.default; softApply() end),
                    meta.label, p.hint and ("Value in " .. p.hint .. ".") or "Enter a number.")
            elseif p.kind == "spell" or p.kind == "item" then
                spellField(cond, p, px, y)
            else
                setTip(CEdit(px, y, p.width or 120, cond[p.key], function(t) cond[p.key] = t; softApply() end), meta.label, "Enter a value.")
            end
            px = px + (p.width or 110) + 8
        end
    end
end

-- Grace period (debounce): the trigger must hold this long before the cue fires.
local function renderGrace(a, x, y)
    a.debounce = tonumber(a.debounce) or 0
    CLabel("Grace period", x, y - 2, C.subtext)
    setTip(CSlider(x + 110, y - 2), "Grace period",
        "Hold the trigger true this many seconds before firing (|cffffffff0|r = instant). Avoids flicker on conditions that flap."):Configure(
        200, 0, 5, 0.1, function() return a.debounce or 0 end,
        function(v) a.debounce = v; softApply() end, "%.1fs")
    return y - 40
end

-- ── SOUND ──────────────────────────────────────────────────────────────────
local function renderSound(a, x, y)
    CSection("SOUND", x, y); y = y - 32
    CLabel("Sound", x, y - 2, C.subtext)
    setTip(CDD(x + 60, y), "Cue sound", "The sound to play. Selecting one previews it."):SetSoundMenu(210, a)
    setTip(CButton(x + 282, y, 60, "Test", "default", function() TCC.PlayKey(a.soundKey, TCC.db.channel) end),
        "Test sound", "Play the selected sound now.")
    y = y - 34
    setTip(CToggle(x, y, a.playSound, function(v) a.playSound = v; softApply() end), "Play sound", "Play the sound when this alert fires.")
    CLabel("Play sound", x + 46, y - 2, C.text)
    CLabel("Cooldown", x + 200, y - 2, C.subtext)
    setTip(CEdit(x + 272, y, 46, a.cooldown, function(t) a.cooldown = tonumber(t) or 3; softApply() end),
        "Cooldown", "Minimum |cffffffffseconds|r between repeats of this cue.")
    CLabel("sec", x + 324, y - 2, C.subtext)
    y = y - ROW
    setTip(CToggle(x, y, a.loopSound, function(v) a.loopSound = v; softApply() end), "Loop sound", "Repeat the sound while active.")
    CLabel("Loop sound", x + 46, y - 2, C.text)
    CLabel("Interval", x + 200, y - 2, C.subtext)
    CEdit(x + 272, y, 46, a.loopInterval, function(t) a.loopInterval = tonumber(t) or 1.5; softApply() end)
    CLabel("sec", x + 324, y - 2, C.subtext)
    return y - ROW - 12
end

-- ── VISUALIZATION (on-screen text + icon) ───────────────────────────────────
local function renderVisual(rule, a, x, y)
    a.color = a.color or { 1, 0.1, 0.1 }
    a.font = a.font or "FRIZQT"; a.fontSize = a.fontSize or 48
    a.icon = a.icon or ""; a.iconSize = a.iconSize or 40

    -- Shared preview (text + icon), declared up front so setters can refresh it.
    local preview
    local function refreshPreview()
        if not preview then return end
        -- Proportional size so the preview reacts across the whole 12-96 range.
        local fs = a.fontSize or 48
        local psize = math.floor(12 + (math.max(12, math.min(96, fs)) - 12) * 30 / 84)
        local pscale = psize / fs
        preview.fs:SetFont(TCC.ResolveFont(a.font), psize, "THICKOUTLINE")
        preview.fs:SetText(a.visual and ((a.visualText ~= "" and a.visualText) or "ALERT") or "")
        local c = a.color or { 1, 0.1, 0.1 }; preview.fs:SetTextColor(c[1], c[2], c[3])
        if a.visual and a.pulse then
            if not preview.pulse:IsPlaying() then preview.pulse:Play() end
        else
            preview.pulse:Stop(); preview.fs:SetAlpha(1)
        end
        preview._action = a; preview._pscale = pscale; preview._onMove = function() softApply() end
        local tex = a.showIcon and TCC.ResolveIcon(a.icon)
        if tex then
            local isz = math.max(10, (a.iconSize or 40) * pscale)
            preview.iconBtn:SetSize(isz, isz); preview.iconBtn.tex:SetTexture(tex)
            preview.iconBtn:ClearAllPoints()
            preview.iconBtn:SetPoint("CENTER", preview.fs, "CENTER", (a.iconX or 0) * pscale, (a.iconY or 64) * pscale)
            preview.iconBtn:Show()
        else
            preview.iconBtn:Hide()
        end
    end

    -- ── VISUALIZATION (on-screen text + icon) ─────────────────────────────────
    CSection("VISUALIZATION", x, y); y = y - 32
    setTip(CToggle(x, y, a.visual, function(v) a.visual = v; softApply(); TCC.RefreshEditorSoon() end),
        "Show text", "Display large on-screen text while this alert is active.")
    CLabel("Show text", x + 46, y - 2, C.text)
    y = y - ROW
    if a.visual then
        CLabel("Text", x, y - 2, C.subtext)
        setTip(CEdit(x + 40, y, 200, a.visualText, function(t)
            a.visualText = (t ~= "" and t) or "ALERT"; refreshPreview(); softApply()
        end), "Visual text", "What the on-screen warning says.")
        CLabel("Color", x + 256, y - 2, C.subtext)
        setTip(CSwatch(x + 300, y, a.color, function() refreshPreview(); softApply() end),
            "Text color", "Color of the on-screen text.")
        y = y - ROW
        CLabel("Font", x, y - 2, C.subtext)
        local fontChoices = {}
        for _, fd in ipairs(TCC.FONTS) do fontChoices[#fontChoices + 1] = { fd.key, fd.label } end
        setTip(CDD(x + 40, y), "Font", "Typeface of the on-screen text."):SetChoices(150, fontChoices,
            function() return a.font end, function(v) a.font = v; refreshPreview(); softApply() end)
        CLabel("Size", x + 206, y - 2, C.subtext)
        setTip(CSlider(x + 244, y - 2), "Font size", "Size of the on-screen text (points)."):Configure(150, 12, 96, 1,
            function() return a.fontSize end, function(v) a.fontSize = v; refreshPreview(); softApply() end, "%d")
        y = y - ROW - 4
        setTip(CToggle(x, y, a.pulse, function(v) a.pulse = v; refreshPreview(); softApply() end), "Pulse", "Fade the text in and out while active.")
        CLabel("Pulse", x + 46, y - 2, C.text)
        y = y - ROW
    end

    setTip(CToggle(x, y, a.showIcon, function(v) a.showIcon = v; softApply(); TCC.RefreshEditorSoon() end),
        "Show icon", "Display an icon (with the text) while this alert is active.")
    CLabel("Show icon", x + 46, y - 2, C.text)
    y = y - ROW
    if a.showIcon then
        local ib = CIcon(x, y - 1)
        ib.tex:SetTexture(TCC.ResolveIcon(a.icon) or QMARK)
        setTip(ib, "Pick a game icon",
            "Search |cffffffffspell / ability icons from the game|r. (The |cffffffffBrowse...|r button instead uses this addon's own Tabler icons.)")
        ib:SetScript("OnEnter", showTip)
        ib:SetScript("OnLeave", GameTooltip_Hide)
        ib:SetScript("OnClick", function()
            TCC.OpenSpellPicker(ib, "", function(pid)
                local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(pid)
                a.icon = (si and si.iconID) or pid
                refreshPreview(); softApply(); TCC.RefreshEditorSoon()
            end)
        end)
        setTip(CEdit(x + 26, y, 200, type(a.icon) == "string" and a.icon or "", function(t)
            a.icon = t; refreshPreview(); softApply(); TCC.RefreshEditorSoon()
        end), "Icon name / ID", "An icon file name (e.g. Ability_Hunter_KillCommand) or a numeric fileID.")
        setTip(CButton(x + 234, y, 92, "Browse...", "default", function()
            TCC.OpenIconPicker({
                title = "Choose Alert Icon",
                current = type(a.icon) == "string" and a.icon or nil,
                fullPath = true,
                onPick = function(path) a.icon = path; refreshPreview(); softApply(); TCC.RefreshEditorSoon() end,
            })
        end), "Browse icons", "Pick from the addon's bundled Tabler icons.")
        CLabel("Size", x + 336, y - 2, C.subtext)
        setTip(CSlider(x + 372, y - 2), "Icon size", "On-screen icon size (pixels)."):Configure(120, 16, 96, 2,
            function() return a.iconSize end, function(v) a.iconSize = v; refreshPreview(); softApply() end, "%d")
        y = y - ROW
    end

    setTip(CButton(x, y, 130, "Move on screen", "default", function()
        TCC.HideManager(); TCC.StartRuleMover(rule)
    end), "Move on screen", "Hide this window and drag the text/icon into place; then Save Position.")
    setTip(CButton(x + 140, y, 100, "Test cue", "primary", function()
        TCC.HideManager(); TCC.StartTest(rule)
    end), "Test cue", "Hide the window and show this cue as if active. Click Stop Test to return.")
    y = y - 30
    CLabel("Preview  |cff777777(drag the icon to position it)|r", x, y - 2, C.subtext); y = y - 18
    preview = CPreview(x, y, CONTENT_W - 40, 92)
    refreshPreview()
    return y - 104
end

-- ── CHAT ────────────────────────────────────────────────────────────────────
local function renderChat(a, x, y)
    CSection("CHAT", x, y); y = y - 32
    setTip(CToggle(x, y, a.chatMessage, function(v) a.chatMessage = v; softApply(); TCC.RefreshEditorSoon() end),
        "Chat message", "Send a chat message when this alert fires.")
    CLabel("Chat message", x + 46, y - 2, C.text)
    if a.chatMessage then
        CLabel("To", x + 200, y - 2, C.subtext)
        a.chatChannel = a.chatChannel or "SELF"
        setTip(CDD(x + 226, y), "Chat channel", "Where the message goes. |cffffffffPrint to me|r shows only to you."):SetChoices(
            120, CHAT_CHANNELS, function() return a.chatChannel end, function(v) a.chatChannel = v; softApply() end)
        y = y - ROW
        CLabel("Text", x + 20, y - 2, C.subtext)
        setTip(CEdit(x + 58, y, 300, a.chatText or "", function(t) a.chatText = t; softApply() end),
            "Chat text", "The message to send (blank = the alert's |cffffffffname|r).")
        y = y - ROW
    else
        y = y - ROW
    end
    return y - 8
end

-- Rule-level actions (shown at the bottom of every editor).
local function renderRuleButtons(rule, x, y)
    setTip(CButton(x, y, 110, "Duplicate", "default", function() TCC.DuplicateSelectedRule() end),
        "Duplicate alert", "Create a copy of this alert.")
    setTip(CButton(x + 120, y, 110, "Export Alert", "default", function() ShowExportDialog(TCC.ExportRule(rule)) end),
        "Export alert", "Get a shareable string for this one alert.")
    setTip(CButton(x + 240, y, 110, "Delete Alert", "danger", function()
        StaticPopup_Show("TWISTEDSCOMBATCUES_DELETE", rule.name or "alert")
    end), "Delete alert", "Remove this alert (asks for confirmation).")
    return y - 40
end

-- Shared long-form action editor (grace + sound + visualization + chat + buttons).
-- Used by the Advanced (tree) editor; the typed editor renders these as tabs.
local function buildActionEditor(rule, x, y)
    local a = rule.action
    y = renderGrace(a, x, y)
    y = renderSound(a, x, y)
    y = renderVisual(rule, a, x, y)
    y = renderChat(a, x, y)
    y = renderRuleButtons(rule, x, y)
    return y
end

----------------------------------------------------------------------
-- Type-based alert editor (tabbed: Load / Trigger / Sound / Visualization / Chat)
----------------------------------------------------------------------
local LOAD_COMBAT = { { "any", "Any" }, { "in", "In combat" }, { "out", "Out of combat" } }
local LOAD_GROUP = { { "any", "Any" }, { "solo", "Solo" }, { "party", "In a party" }, { "raid", "In a raid" } }
local LOAD_INSTANCE = {
    { "any", "Anywhere" }, { "none", "Open world" }, { "any_instance", "Any instance" },
    { "party", "Dungeon" }, { "raid", "Raid" }, { "arena", "Arena" }, { "pvp", "Battleground" }, { "scenario", "Scenario" },
}

local function specSummary(ld)
    if not ld.specs or not next(ld.specs) then return "All classes / specs" end
    local n = 0; for _ in pairs(ld.specs) do n = n + 1 end
    return n .. (n == 1 and " spec selected" or " specs selected")
end

-- A small clickable swatch that shows an alert's current sidebar icon and opens
-- the icon picker. Shared by both editors.
local function iconChooser(rule, bx, by)
    local cur = alertIconOf(rule)
    local sw = CIcon(bx, by)
    sw.tex:SetTexCoord(0, 1, 0, 1); sw.tex:SetTexture(cur)
    setTip(sw, "Alert icon", "Click to choose the icon shown for this alert in the |cffffffffAlerts|r list.")
    sw:SetScript("OnEnter", showTip)
    sw:SetScript("OnLeave", GameTooltip_Hide)
    sw:SetScript("OnClick", function()
        if not TCC.OpenIconPicker then return end
        TCC.OpenIconPicker({
            title = "Choose Alert Icon",
            current = rule.navIcon,
            allowDefault = true,
            defaultLabel = "Use default (by alert type)",
            onPick = function(file) rule.navIcon = file; TCC.RefreshManager() end,
        })
    end)
    return sw
end

-- LOAD tab: class/spec + combat/group/zone gates.
local function tabLoad(rule, x, y)
    rule.load = rule.load or { combat = "any", instance = "any", group = "any" }
    local ld = rule.load
    CSection("LOAD  (only active when...)", x, y); y = y - 30
    CLabel("Class / Spec", x, y - 2, C.subtext)
    setTip(CButton(x + 96, y, 190, specSummary(ld), "default", function()
        if TCC.OpenSpecPicker then TCC.OpenSpecPicker(ld, function() TCC.RefreshEditorSoon() end) end
    end), "Class / Spec", "Only load this alert for the chosen classes/specs (|cffffffffnone = all|r).")
    setTip(CButton(x + 296, y, 110, "Copy load...", "default", function(self)
        local items = { { label = "Copy Load from", header = true } }
        for _, r in ipairs(TCC.db.rules) do
            if r.id ~= rule.id and r.load then items[#items + 1] = { label = r.name or "?", value = r.id } end
        end
        if #items == 1 then items[#items + 1] = { label = "(no other alerts to copy from)", header = true } end
        openDropMenu(self, items, function() return nil end, function(rid)
            for _, r in ipairs(TCC.db.rules) do
                if r.id == rid and r.load then
                    local nl = { combat = r.load.combat, instance = r.load.instance, group = r.load.group }
                    if r.load.specs then nl.specs = {}; for k, v in pairs(r.load.specs) do nl.specs[k] = v end end
                    rule.load = nl; softApply(); TCC.RefreshEditorSoon(); break
                end
            end
        end)
    end), "Copy load", "Copy the Load settings from another alert.")
    y = y - 36
    CLabel("Combat", x, y - 2, C.subtext)
    setTip(CDD(x + 66, y), "Combat", "Only active in / out of combat."):SetChoices(120, LOAD_COMBAT,
        function() return ld.combat or "any" end, function(v) ld.combat = v; softApply() end)
    CLabel("Group", x + 208, y - 2, C.subtext)
    setTip(CDD(x + 258, y), "Group", "Only active solo / in a party / in a raid."):SetChoices(120, LOAD_GROUP,
        function() return ld.group or "any" end, function(v) ld.group = v; softApply() end)
    y = y - ROW
    CLabel("Zone", x, y - 2, C.subtext)
    setTip(CDD(x + 66, y), "Zone", "Only active in this kind of zone."):SetChoices(160, LOAD_INSTANCE,
        function() return ld.instance or "any" end, function(v) ld.instance = v; softApply() end)
    return y - ROW - 10
end

-- TRIGGER tab: what fires the alert (+ the grace period).
local function tabTrigger(rule, x, y)
    local meta = TCC.GetAlertKind(rule.kind)
    rule.trigger = rule.trigger or TCC.NewCondition(meta and meta.default or "target")
    CSection("TRIGGER  (fire when...)", x, y); y = y - 30
    if meta and meta.triggers and #meta.triggers > 1 then
        CLabel("Check", x, y - 2, C.subtext)
        local choices = {}
        for _, tt in ipairs(meta.triggers) do local m = TCC.GetConditionMeta(tt); choices[#choices + 1] = { tt, m and m.label or tt } end
        setTip(CDD(x + 50, y), "Trigger", "What this alert checks."):SetChoices(180, choices,
            function() return rule.trigger.type end,
            function(v) if v ~= rule.trigger.type then rule.trigger = TCC.NewCondition(v); softApply(); TCC.RefreshEditorSoon() end end)
        y = y - ROW
    end
    CLabel("Fire when", x, y - 2, C.subtext)
    renderParams(rule.trigger, x + 76, y); y = y - ROW - 12

    -- Item alerts: offer the item's own icon instead of picking one separately.
    if rule.kind == "item" then
        setTip(CToggle(x, y, rule.useItemIcon, function(v) rule.useItemIcon = v; TCC.RefreshManager() end),
            "Use item icon", "Use the selected item's |cffffffffown icon|r as this alert's icon, so you don't pick it twice.")
        CLabel("Use this item's icon for the alert", x + 46, y - 2, C.text)
        y = y - ROW - 6
    end

    y = renderGrace(rule.action, x, y)
    return y
end

local EDITOR_TABS = {
    { key = "load",    label = "Load" },
    { key = "trigger", label = "Trigger" },
    { key = "sound",   label = "Sound" },
    { key = "visual",  label = "Visuals" },
    { key = "chat",    label = "Chat" },
}

local function buildTypedEditor(rule)
    local x, y = PAD, -20

    setTip(CButton(x, y, 120, "< Back to Alerts", "default", function() TCC.uiView = "alerts"; TCC.RefreshManager() end),
        "Back to alerts", "Return to the alert list.")
    y = y - 34
    CLabel("ALERT NAME", x, y, C.subtext, 10)
    CLabel("ALERT ICON", x + 386, y, C.subtext, 10); y = y - 18
    setTip(CEdit(x, y, 360, rule.name, function(t) rule.name = (t ~= "" and t) or "Unnamed"; TCC.RefreshManager() end),
        "Alert name", "A label for this alert (shown in the |cffffffffAlerts|r list).")
    iconChooser(rule, x + 392, y)
    y = y - 42
    setTip(CToggle(x, y, rule.enabled, function(v) rule.enabled = v; softApply(); TCC.RefreshManager() end),
        "Enabled", "Turn this alert on or off without deleting it.")
    CLabel("Enabled", x + 46, y - 2, C.text)
    y = y - 40

    -- Tab bar (Trigger is the default view so the "fire when" options are seen first).
    local tab = TCC._editorTab or "trigger"
    local tx = x
    for _, t in ipairs(EDITOR_TABS) do
        local active = tab == t.key
        setTip(CButton(tx, y, 104, t.label, active and "primary" or "default", function()
            TCC._editorTab = t.key; TCC.RefreshManager()
        end), t.label, nil)
        tx = tx + 108
    end
    y = y - 38

    -- Tab content
    if tab == "trigger" then y = tabTrigger(rule, x, y)
    elseif tab == "sound" then y = renderSound(rule.action, x, y)
    elseif tab == "visual" then y = renderVisual(rule, rule.action, x, y)
    elseif tab == "chat" then y = renderChat(rule.action, x, y)
    else y = tabLoad(rule, x, y) end

    y = y - 10
    y = renderRuleButtons(rule, x, y)
    content:SetHeight(math.max(WIN_H, -y + 20))
end

----------------------------------------------------------------------
-- Advanced (AND/OR tree) alert editor + dispatcher
----------------------------------------------------------------------
local function buildRuleEditor(rule)
    if rule.kind and rule.kind ~= "advanced" then return buildTypedEditor(rule) end
    local x, y = PAD, -20

    setTip(CButton(x, y, 120, "< Back to Alerts", "default", function() TCC.uiView = "alerts"; TCC.RefreshManager() end),
        "Back to alerts", "Return to the alert list.")
    y = y - 34
    CLabel("ALERT NAME", x, y, C.subtext, 10)
    CLabel("ALERT ICON", x + 386, y, C.subtext, 10); y = y - 18
    setTip(CEdit(x, y, 360, rule.name, function(t) rule.name = (t ~= "" and t) or "Unnamed"; TCC.RefreshManager() end),
        "Alert name", "A label for this alert (shown in the sidebar).")
    iconChooser(rule, x + 392, y)
    y = y - 42
    setTip(CToggle(x, y, rule.enabled, function(v) rule.enabled = v; softApply(); TCC.RefreshManager() end),
        "Enabled", "Turn this alert on or off without deleting it.")
    CLabel("Enabled", x + 46, y - 2, C.text)
    y = y - 42

    CSection("CONDITIONS", x, y); y = y - 30
    if TCC.EnsureRuleTree then TCC.EnsureRuleTree(rule) end
    local cmap = TCC.BuildGroupColorMap(rule.root)
    local summary = "Fires when  " .. TCC.DescribeRuleText(rule.root, cmap)
    local fs, h = CWrap(summary, x + 4, y - 6, CONTENT_W - 52, C.text, 11)
    CBox(x - 2, y + 2, CONTENT_W - 26, h + 16, 0.05, 0, C.accent)
    y = y - (h + 22)
    y = buildGroup(rule.root, y, 0, nil, nil, cmap)
    y = y - 4

    y = buildActionEditor(rule, x, y)
    content:SetHeight(math.max(WIN_H, -y + 20))
end

----------------------------------------------------------------------
-- Load: multi class/spec picker popup (5-column, class-colored grid)
----------------------------------------------------------------------
local function classColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.95
end

local function makeSpecCheck(parent)
    local b = CreateFrame("Button", nil, parent); b:SetHeight(22)
    b.brd = b:CreateTexture(nil, "BACKGROUND"); b.brd:SetSize(16, 16); b.brd:SetPoint("LEFT", 2, 0); b.brd:SetColorTexture(0.30, 0.33, 0.40, 1)
    b.box = b:CreateTexture(nil, "ARTWORK"); b.box:SetPoint("TOPLEFT", b.brd, "TOPLEFT", 1, -1); b.box:SetPoint("BOTTOMRIGHT", b.brd, "BOTTOMRIGHT", -1, 1); b.box:SetColorTexture(0.12, 0.14, 0.18, 1)
    b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetPoint("TOPLEFT", b.box, "TOPLEFT", 2, -2); b.check:SetPoint("BOTTOMRIGHT", b.box, "BOTTOMRIGHT", -2, 2); b.check:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12); b.fs:SetPoint("LEFT", b.brd, "RIGHT", 8, 0); b.fs:SetPoint("RIGHT", 0, 0); b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) self.box:SetColorTexture(0.18, 0.21, 0.26, 1) end)
    b:SetScript("OnLeave", function(self) self.box:SetColorTexture(0.12, 0.14, 0.18, 1) end)
    return b
end

function TCC.OpenSpecPicker(load, onChange)
    load.specs = load.specs or {}
    local COLS, COLW = 5, 160
    local p = TCC._specPicker
    if not p then
        p = CreateFrame("Frame", "TwistedsCombatCuesSpecPicker", UIParent)
        TCC._specPicker = p
        p:SetSize(40 + COLS * COLW, 560); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        stylePanel(p, C.panel, C.border); p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, "TwistedsCombatCuesSpecPicker")
        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(34)
        hd:RegisterForDrag("LeftButton"); hd:SetScript("OnDragStart", function() p:StartMoving() end); hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        local title = hd:CreateFontString(nil, "OVERLAY"); title:SetFont(FONT, 15); title:SetPoint("CENTER"); title:SetText("Load On These Specs"); title:SetTextColor(unpack(C.text))
        local xb = makeButton(p); xb:Configure("X", 26, 22, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -4, -4); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

        local function link(label, w) local b = CreateFrame("Button", nil, p); b:SetSize(w, 18)
            b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12); b.fs:SetAllPoints(); b.fs:SetJustifyH("LEFT"); b.fs:SetText(label); b.fs:SetTextColor(unpack(C.accent)); return b end
        local ca = link("Check All", 64); ca:SetPoint("TOPLEFT", 18, -42)
        ca:SetScript("OnClick", function()
            for _, cls in ipairs(TCC.GetClassList()) do for _, sp in ipairs(TCC.GetSpecList(cls.token)) do if sp.value ~= "all" then p._load.specs[sp.value] = true end end end
            p._rebuild(); if p._onChange then p._onChange() end
        end)
        local sep = p:CreateFontString(nil, "OVERLAY"); sep:SetFont(FONT, 12); sep:SetPoint("LEFT", ca, "RIGHT", 2, 0); sep:SetText("|"); sep:SetTextColor(unpack(C.subtext))
        local ua = link("Uncheck All", 76); ua:SetPoint("LEFT", sep, "RIGHT", 4, 0)
        ua:SetScript("OnClick", function() wipe(p._load.specs); p._rebuild(); if p._onChange then p._onChange() end end)
        local hint = p:CreateFontString(nil, "OVERLAY"); hint:SetFont(FONT, 11); hint:SetPoint("LEFT", ua, "RIGHT", 14, 0); hint:SetTextColor(unpack(C.subtext)); hint:SetText("none checked = loads on every spec")

        local body = CreateFrame("Frame", nil, p); body:SetPoint("TOPLEFT", 20, -70); body:SetPoint("BOTTOMRIGHT", -20, 54); p.body = body
        local done = makeButton(p); done:Configure("Done", 190, 30, "primary", function() p:Hide() end); done:SetPoint("BOTTOM", 0, 14)
        p._headers, p._checks = {}, {}
        p._rebuild = function()
            for _, hh in ipairs(p._headers) do hh:Hide() end
            for _, cc in ipairs(p._checks) do cc:Hide() end
            local classes = {}
            for _, cls in ipairs(TCC.GetClassList()) do classes[#classes + 1] = cls end
            table.sort(classes, function(a, b) return a.name < b.name end)
            local cols = {}; for i = 1, COLS do cols[i] = {} end
            for i, cls in ipairs(classes) do table.insert(cols[((i - 1) % COLS) + 1], cls) end
            local nH, nC = 0, 0
            for ci = 1, COLS do
                local colX, yOff = (ci - 1) * COLW, 0
                for _, cls in ipairs(cols[ci]) do
                    nH = nH + 1
                    local hh = p._headers[nH]
                    if not hh then hh = p.body:CreateFontString(nil, "OVERLAY"); hh:SetFont(FONT, 14); hh:SetJustifyH("LEFT"); p._headers[nH] = hh end
                    hh:ClearAllPoints(); hh:SetPoint("TOPLEFT", p.body, "TOPLEFT", colX, -yOff); hh:Show()
                    local r, g, b = classColor(cls.token)
                    hh:SetTextColor(r, g, b); hh:SetText(cls.name)
                    yOff = yOff + 24
                    for _, sp in ipairs(TCC.GetSpecList(cls.token)) do
                        if sp.value ~= "all" then
                            nC = nC + 1
                            local c = p._checks[nC]; if not c then c = makeSpecCheck(p.body); p._checks[nC] = c end
                            c:ClearAllPoints(); c:SetPoint("TOPLEFT", p.body, "TOPLEFT", colX + 2, -yOff); c:SetWidth(COLW - 8); c:Show()
                            c.fs:SetText(sp.name); c.fs:SetTextColor(r, g, b)
                            c.check:SetColorTexture(r, g, b, 1)
                            local sid = sp.value
                            c.check:SetShown(p._load.specs[sid] and true or false)
                            c:SetScript("OnClick", function(self)
                                p._load.specs[sid] = (not p._load.specs[sid]) and true or nil
                                self.check:SetShown(p._load.specs[sid] and true or false)
                                if p._onChange then p._onChange() end
                            end)
                            yOff = yOff + 23
                        end
                    end
                    yOff = yOff + 14
                end
            end
        end
    end
    p._load = load; p._onChange = onChange
    p._rebuild()
    p:Show()
end

-- Grid picker for one of our curated Tabler icons. Generic so it serves both the
-- per-alert sidebar icon and the alert's on-screen visualization icon.
--   opts = {
--     title       = window title,
--     current     = currently selected value (to highlight),
--     fullPath    = if true, values are full texture paths; else bare "slug.tga",
--     allowDefault= show a "use default" button that calls onPick(nil),
--     defaultLabel= label for that button,
--     onPick      = function(value)  -- value is nil for default, else per fullPath
--   }
function TCC.OpenIconPicker(opts)
    opts = opts or {}
    local COLS, CELL = 8, 36
    local p = TCC._iconPicker
    if not p then
        p = CreateFrame("Frame", "TwistedsCombatCuesIconPicker", UIParent)
        TCC._iconPicker = p
        local rows = math.ceil(#PICKER_ICONS / COLS)
        p:SetSize(40 + COLS * CELL, 118 + rows * CELL)
        p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        stylePanel(p, C.panel, C.border); p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, "TwistedsCombatCuesIconPicker")
        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(34)
        hd:RegisterForDrag("LeftButton"); hd:SetScript("OnDragStart", function() p:StartMoving() end); hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        p._title = hd:CreateFontString(nil, "OVERLAY"); p._title:SetFont(FONT, 15); p._title:SetPoint("CENTER"); p._title:SetTextColor(unpack(C.text))
        local xb = makeButton(p); xb:Configure("X", 26, 22, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -4, -4); xb:SetFrameLevel(hd:GetFrameLevel() + 5)
        p._def = makeButton(p); p._def:SetPoint("TOP", 0, -40)

        -- Cells are parented directly to the panel: a zero-size intermediate frame
        -- would stop them rendering (WoW needs a sized parent for child layout).
        local GX, GY = 20, -74   -- grid origin inside the panel
        p._cells = {}
        for i, slug in ipairs(PICKER_ICONS) do
            local cell = CreateFrame("Button", nil, p); cell:SetSize(CELL - 6, CELL - 6)
            local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            cell:SetPoint("TOPLEFT", p, "TOPLEFT", GX + col * CELL, GY - row * CELL)
            stylePanel(cell, C.bg)
            cell.tex = cell:CreateTexture(nil, "ARTWORK"); cell.tex:SetPoint("TOPLEFT", 3, -3); cell.tex:SetPoint("BOTTOMRIGHT", -3, 3)
            cell.tex:SetTexCoord(0, 1, 0, 1); cell.tex:SetTexture(ICON_DIR .. slug .. ".tga")
            cell.sel = cell:CreateTexture(nil, "OVERLAY"); cell.sel:SetAllPoints(); cell.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35); cell.sel:Hide()
            cell._file = slug .. ".tga"
            cell:SetScript("OnEnter", function(self)
                self.tex:SetVertexColor(0.6, 0.85, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(slug, accentHeader()); GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function(self) self.tex:SetVertexColor(1, 1, 1); GameTooltip_Hide() end)
            cell:SetScript("OnClick", function(self)
                local o = p._opts or {}
                local val = o.fullPath and (ICON_DIR .. self._file) or self._file
                p:Hide(); if o.onPick then o.onPick(val) end
            end)
            p._cells[i] = cell
        end
    end
    p._opts = opts
    p._title:SetText(opts.title or "Choose Icon")
    if opts.allowDefault then
        p._def:Configure(opts.defaultLabel or "Use default", 220, 24, "default", function()
            p:Hide(); if p._opts and p._opts.onPick then p._opts.onPick(nil) end
        end)
        p._def:Show()
    else
        p._def:Hide()
    end
    for _, cell in ipairs(p._cells) do
        local val = opts.fullPath and (ICON_DIR .. cell._file) or cell._file
        cell.sel:SetShown(opts.current == val)
    end
    p:Show()
end

-- Modal "New Alert" selector: a card per alert type with icon + description.
local NEW_ALERT_CARDS = {
    { kind = "range",    icon = "target-arrow", title = "Range Alert",    desc = "Fire on how far you are from your target (in / out of range)." },
    { kind = "target",   icon = "target",       title = "Target Alert",   desc = "Fire on your target's state: none, hostile, dead, attackable." },
    { kind = "threat",   icon = "flame",        title = "Threat Alert",   desc = "Fire on your threat vs the target (pulled aggro, safe...)." },
    { kind = "pet",      icon = "paw",          title = "Pet Alert",      desc = "Fire on your pet's state: dead, missing, or alive." },
    { kind = "item",     icon = "flask",        title = "Item Alert",     desc = "Fire when a usable item (trinket, potion) comes off cooldown." },
    { kind = "advanced", icon = "adjustments",  title = "Advanced Alert", desc = "Custom AND / OR logic across multiple conditions." },
}

function TCC.OpenNewAlertModal()
    local COLS, CW, CH, PADX = 2, 288, 82, 20
    local p = TCC._newAlertModal
    if not p then
        p = CreateFrame("Frame", "TwistedsCombatCuesNewAlert", UIParent)
        TCC._newAlertModal = p
        local rows = math.ceil(#NEW_ALERT_CARDS / COLS)
        p:SetSize(PADX * 2 + COLS * CW + (COLS - 1) * 10, 62 + rows * (CH + 10))
        p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        stylePanel(p, C.panel, C.border); p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, "TwistedsCombatCuesNewAlert")
        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(34)
        hd:RegisterForDrag("LeftButton"); hd:SetScript("OnDragStart", function() p:StartMoving() end); hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        local title = hd:CreateFontString(nil, "OVERLAY"); title:SetFont(FONT, 15); title:SetPoint("CENTER"); title:SetText("Choose an Alert Type"); title:SetTextColor(unpack(C.text))
        local xb = makeButton(p); xb:Configure("X", 26, 22, "danger", function() p:Hide() end); xb:SetPoint("TOPRIGHT", -4, -4); xb:SetFrameLevel(hd:GetFrameLevel() + 5)

        for i, card in ipairs(NEW_ALERT_CARDS) do
            local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            local b = CreateFrame("Button", nil, p); b:SetSize(CW, CH)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", PADX + col * (CW + 10), -48 - row * (CH + 10))
            stylePanel(b, C.card, C.border)
            local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(38, 38); ic:SetPoint("LEFT", 16, 0)
            ic:SetTexCoord(0, 1, 0, 1); ic:SetTexture(ICON_DIR .. card.icon .. ".tga")
            local ti = b:CreateFontString(nil, "OVERLAY"); ti:SetFont(FONT, 14)
            ti:SetPoint("TOPLEFT", b, "TOPLEFT", 66, -14); ti:SetTextColor(unpack(C.text)); ti:SetText(card.title)
            local de = b:CreateFontString(nil, "OVERLAY"); de:SetFont(FONT, 11)
            de:SetPoint("TOPLEFT", b, "TOPLEFT", 66, -36); de:SetPoint("RIGHT", b, "RIGHT", -12, 0)
            de:SetJustifyH("LEFT"); de:SetWordWrap(true); de:SetTextColor(unpack(C.subtext)); de:SetText(card.desc)
            b:SetScript("OnEnter", function(self) paint(self._brd, C.accent); paint(self._fill, mix(C.card, C.accent, 0.18)) end)
            b:SetScript("OnLeave", function(self) paint(self._brd, C.border); paint(self._fill, C.card) end)
            b:SetScript("OnClick", function()
                p:Hide(); TCC.uiView = "rule"
                if card.kind == "advanced" then TCC.NewRuleFrom("blank") else TCC.NewTypedAlert(card.kind) end
            end)
        end
    end
    p:Show()
end

----------------------------------------------------------------------
-- Marker keybind capture (binds a key to Blizzard's secure RAIDTARGET action)
----------------------------------------------------------------------
-- GetBindingKey doesn't always reflect a fresh SetBinding immediately, so nudge the
-- Focus Tools page a few times over the next moment (UPDATE_BINDINGS also covers it).
local function refreshMacrosSoon()
    if not (C_Timer and C_Timer.After) then if TCC.RefreshManager then TCC.RefreshManager() end return end
    for _, d in ipairs({ 0, 0.1, 0.3 }) do
        C_Timer.After(d, function()
            if TCC.uiView == "macros" and mgr and mgr:IsShown() and TCC.RefreshManager then TCC.RefreshManager() end
        end)
    end
end

function TCC.CaptureMarkerKey(markIndex, onDone)
    local f = TCC._keyCapture
    if not f then
        f = CreateFrame("Frame", "TwistedsCombatCuesKeyCapture", UIParent)
        TCC._keyCapture = f
        f:SetSize(380, 96); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
        stylePanel(f, C.panel, C.accent)
        f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetFont(FONT, 15); f.fs:SetPoint("CENTER", 0, 8); f.fs:SetTextColor(unpack(C.text))
        f.sub = f:CreateFontString(nil, "OVERLAY"); f.sub:SetFont(FONT, 11); f.sub:SetPoint("CENTER", 0, -20); f.sub:SetTextColor(unpack(C.subtext))
        f.sub:SetText("Press any key  ·  Esc to cancel")
        f:EnableKeyboard(true); f:SetPropagateKeyboardInput(false)
        f:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide(); if self._onDone then self._onDone(nil, true) end; return end
            local ignore = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }
            if ignore[key] then return end
            local combo = key
            if IsAltKeyDown() then combo = "ALT-" .. combo end
            if IsControlKeyDown() then combo = "CTRL-" .. combo end
            if IsShiftKeyDown() then combo = "SHIFT-" .. combo end
            local action = "RAIDTARGET" .. self._mark
            local ok = (SetBinding and SetBinding(combo, action)) and true or false
            -- IMPORTANT: don't verify with GetBindingAction here - that read lags a frame
            -- exactly like GetBindingKey, so it falsely reports failure and the readout
            -- never updates. Trust SetBinding's own return and cache the key ourselves.
            if ok then
                if SaveBindings and GetCurrentBindingSet then pcall(SaveBindings, GetCurrentBindingSet()) end
                if TCC.db and TCC.db.macro then
                    TCC.db.macro.boundKeys = TCC.db.macro.boundKeys or {}
                    TCC.db.macro.boundKeys[self._mark] = combo
                end
            end
            self:Hide()
            if self._onDone then self._onDone(ok and combo or nil) end
            refreshMacrosSoon()
        end)
    end
    f._mark = markIndex; f._onDone = onDone
    local micon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. markIndex .. ":18|t"
    f.fs:SetText("Bind a key to place  " .. micon .. "  on your target")
    f:Show(); f:EnableKeyboard(true)
end

----------------------------------------------------------------------
-- Content: global options
----------------------------------------------------------------------
local function buildGlobal()
    local db, x, y = TCC.db, PAD, -20

    CSection("GENERAL", x, y); y = y - 34
    setTip(CToggle(x, y, db.enabled, function(v) db.enabled = v; TCC.ApplySettings() end),
        "Enable addon", "Master on/off. When off, no cues fire at all.")
    CLabel("Enable addon", x + 46, y - 2, C.text)
    y = y - 42

    CLabel("ALERTS PROFILE (this character uses)", x, y, C.subtext, 10); y = y - 20
    setTip(CDD(x, y), "Alerts profile",
        "Use the shared account-wide alerts, or a private set just for this character.")
        :SetChoices(300, { { "account", "Account-wide (shared)" }, { "char", "This character only" } },
        function() return TCC.useCharacter and "char" or "account" end,
        function(v) TCC.SetScope(v == "char") end)
    y = y - 40

    -- Copy rules between any two profiles (account or any character).
    CLabel("COPY ALERTS BETWEEN PROFILES", x, y, C.subtext, 10); y = y - 20
    local names = TCC.ListProfiles()
    local hasMe = false
    for _, n in ipairs(names) do if n == TCC.CurrentCharKey() then hasMe = true end end
    if not hasMe then names[#names + 1] = TCC.CurrentCharKey() end
    local profChoices = {}
    for _, n in ipairs(names) do profChoices[#profChoices + 1] = { n, TCC.ProfileLabel(n) } end
    TCC._copyFrom = TCC._copyFrom or TCC.AccountKey()
    TCC._copyTo = TCC._copyTo or TCC.CurrentCharKey()
    TCC._copyRule = TCC._copyRule or "__all__"
    CLabel("From", x, y - 2, C.subtext)
    setTip(CDD(x + 46, y), "Source profile", "Copy alerts FROM this profile."):SetChoices(280, profChoices,
        function() return TCC._copyFrom end,
        function(v) TCC._copyFrom = v; TCC._copyRule = "__all__"; TCC.RefreshManager() end)
    y = y - 30
    CLabel("Rule", x, y - 2, C.subtext)
    local ruleItems = { { "__all__", "All alerts" } }
    for _, r in ipairs(TCC.GetProfileRuleList(TCC._copyFrom)) do ruleItems[#ruleItems + 1] = { r.id, r.name } end
    setTip(CDD(x + 46, y), "Alert to copy", "Copy every alert (replaces destination) or one alert (appended)."):SetChoices(
        280, ruleItems, function() return TCC._copyRule end, function(v) TCC._copyRule = v end)
    y = y - 30
    CLabel("To", x, y - 2, C.subtext)
    setTip(CDD(x + 46, y), "Destination profile", "Copy alerts INTO this profile."):SetChoices(280, profChoices,
        function() return TCC._copyTo end, function(v) TCC._copyTo = v end)
    y = y - 32
    setTip(CButton(x, y, 150, "Copy", "primary", function() TCC.CopyProfileRules(TCC._copyFrom, TCC._copyTo, TCC._copyRule) end),
        "Copy", "Copy the selected alert(s) from the source profile to the destination.")
    y = y - 48

    CSection("SOUND & INTERFACE", x, y); y = y - 34
    CLabel("Sound channel", x, y - 2, C.subtext)
    setTip(CDD(x + 120, y), "Sound channel",
        "Which audio channel cues play on. Master stays audible even if Sound Effects volume is low.")
        :SetChoices(220, CHANNELS, function() return db.channel end, function(v) db.channel = v end)
    y = y - 42
    CLabel("Window scale", x, y - 2, C.subtext)
    setTip(CSlider(x + 120, y - 2), "Window scale", "Size of this Cue Manager window."):Configure(220, 0.7, 1.4, 0.05,
        function() return db.windowScale or 1 end,
        function(v) db.windowScale = v; if mgr then mgr:SetScale(v) end end)
    y = y - 40
    CLabel("Check interval", x, y - 2, C.subtext)
    setTip(CSlider(x + 120, y - 2), "Check interval",
        "How often polling conditions (spell ready, item ready, buff time-left) are re-checked. Higher = less CPU, slightly less responsive. Event-driven conditions are unaffected."):Configure(
        220, 0.1, 1.0, 0.05, function() return db.pollInterval or 0.25 end,
        function(v) db.pollInterval = v; TCC.RebuildEngine() end, "%.2f")
    y = y - 40
    CLabel("Theme accent", x, y - 2, C.subtext)
    db.accentColor = db.accentColor or { 0.04, 0.34, 0.79 }
    setTip(CSwatch(x + 120, y, db.accentColor, function() ApplyAccent(); TCC.RefreshManager() end),
        "Theme accent", "Recolor the interface accent. Visual text color and position are set per rule.")
    y = y - 42
    db.minimap = db.minimap or { angle = 214, hide = false }
    setTip(CToggle(x, y, not db.minimap.hide, function(v) TCC.SetMinimapHidden(not v) end),
        "Minimap button", "Show the minimap button (left-click opens the manager, drag to move it).")
    CLabel("Minimap button", x + 46, y - 2, C.text)
    y = y - 48

    CSection("SHARING", x, y); y = y - 34
    setTip(CButton(x, y, 150, "Import Alert(s)", "primary", function() ShowImportDialog() end),
        "Import alerts", "Paste an exported string to add alerts (never overwrites existing ones).")
    setTip(CButton(x + 160, y, 150, "Export All Alerts", "default", function() ShowExportDialog(TCC.ExportAll()) end),
        "Export all", "Get a shareable string containing every alert in this profile.")
    y = y - 48

    CSection("MAINTENANCE", x, y); y = y - 34
    setTip(CButton(x, y, 170, "Reset Active Profile", "danger", function() StaticPopup_Show("TWISTEDSCOMBATCUES_RESET") end),
        "Reset profile", "Clear all alerts and restore defaults for the ACTIVE profile only.")
    y = y - 44

    content:SetHeight(math.max(WIN_H, -y + 20))
end

local function buildCredits()
    local x, y = PAD, -20
    CLogo(x, y, 104)
    CLabel("Twisteds Combat Cues", x + 120, y - 8, C.text, 16)
    CLabel("Version " .. (TCC.VERSION or "1.0.0"), x + 120, y - 32, C.accent, 12)
    CLabel("Created by |cffffffffTwistedfury-Zul'jin|r", x + 120, y - 52, C.subtext, 12)
    CLabel("A lightweight, alert-based cue addon.", x + 120, y - 70, C.subtext, 11)
    y = y - 124

    CSection("THANKS", x, y); y = y - 34
    CLabel("|cffffffffWeakAuras|r", x, y, C.accent, 13); y = y - 22
    local wa = "A huge, heartfelt shoutout to the |cffffffffWeakAuras|r team. For years it gave the WoW "
        .. "community incredible creative freedom, and it is the direct inspiration for this little addon. "
        .. "In all honesty, though, this is |cffffffffnot|r a WeakAuras replacement - it can't do most of what "
        .. "WA could. Blizzard's Midnight API changes took a lot of that off the table for every addon, so "
        .. "please don't expect the same magic here. Consider this a small tribute to the one piece I always "
        .. "loved most: simple |cffffffffaudible cues|r for the moments that matter - the instant my hunter "
        .. "drops its target, or a nudge to push Prayer of Mending on cooldown. Thank you, WeakAuras, "
        .. "for everything.  o7"
    local _, wh = CWrap(wa, x, y, CONTENT_W - 44, C.subtext, 12); y = y - (wh + 24)
    CLabel("|cffffffffEllesmere (EllesmereUI)|r", x, y, C.accent, 13); y = y - 20
    CLabel("Panel design and layout inspiration.", x, y, C.subtext, 12); y = y - 34
    CLabel("|cffffffffTabler Icons|r", x, y, C.accent, 13); y = y - 20
    CLabel("Interface icons, MIT licensed  -  tabler.io/icons.", x, y, C.subtext, 12); y = y - 34
    CLabel("|cffffffffwago.tools|r", x, y, C.accent, 13); y = y - 20
    CLabel("Spell & item database exports used to build the search index.", x, y, C.subtext, 12); y = y - 34
    CLabel("|cffffffffCue sounds|r", x, y, C.accent, 13); y = y - 20
    CLabel("Community-sourced (several by Piffz). See THIRD_PARTY_NOTICES for details.", x, y, C.subtext, 12); y = y - 40

    CLabel("|cff777777No affiliation with or endorsement by the above is implied.|r", x, y, C.subtext, 11)
    y = y - 30

    content:SetHeight(math.max(WIN_H, -y + 20))
end

-- "What's New": renders the bundled CHANGELOG.md (embedded as TCC.CHANGELOG in the
-- generated Changelog.lua) with a light Markdown pass -- "## x" = version header,
-- "- ..." = bullet, **bold** = white.
local function buildWhatsNew()
    local x, y = PAD, -20
    CLabel("What's New", x, y, C.accent, 16); y = y - 24
    CLabel("Version " .. (TCC.VERSION or "1.0.0"), x, y, C.subtext, 12); y = y - 28

    local text = TCC.CHANGELOG
    if not text or text == "" then
        CLabel("No changelog bundled with this build.", x, y, C.subtext, 12)
        content:SetHeight(math.max(WIN_H, -y + 20)); return
    end

    local BULLET = "\226\128\162"   -- UTF-8 for the bullet glyph
    local function flushBullet(buf)
        if buf and buf ~= "" then
            buf = buf:gsub("%*%*(.-)%*%*", "|cffffffff%1|r")
            local _, h = CWrap("|cff8f98a6" .. BULLET .. "|r  " .. buf, x + 8, y, CONTENT_W - 64, C.subtext, 12)
            y = y - (h + 7)
        end
    end

    local cur
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local ver     = line:match("^##%s+(.+)")
        local bullet  = line:match("^%-%s+(.+)")
        local cont    = line:match("^%s+(%S.*)")
        if ver then
            flushBullet(cur); cur = nil
            y = y - 8; CSection(ver, x, y); y = y - 28
        elseif bullet then
            flushBullet(cur); cur = bullet
        elseif cont and cur then
            cur = cur .. " " .. cont          -- continuation of a wrapped bullet
        elseif line == "" or line:match("^%s*$") then
            flushBullet(cur); cur = nil
        end
    end
    flushBullet(cur)

    content:SetHeight(math.max(WIN_H, -y + 20))
end

----------------------------------------------------------------------
-- Content: live debug / diagnostics (/tcc debug)
----------------------------------------------------------------------
local function buildDebug()
    local GREEN = { 0.45, 0.85, 0.5 }
    local AMBER = { 0.85, 0.68, 0.35 }
    local DIM = C.subtext
    local x, y = PAD, -20
    local labelX, valX = x, x + 190
    local fields = {}

    local function addRow(label, fn)
        CLabel(label, labelX, y, C.subtext, 12)
        local v = CLabel("", valX, y, C.text, 12)
        fields[#fields + 1] = { fs = v, fn = fn }
        y = y - 23
    end
    local function section(title) y = y - 8; CSection(title, x, y); y = y - 26 end
    local function stripErr(e) return tostring(e):gsub("^.-:%d+: ", "") end

    CLabel("LIVE DIAGNOSTICS", x, y, C.accent, 13); y = y - 20
    local _, ih = CWrap("What the client actually returns for each condition input, live - use it "
        .. "to spot anything Blizzard has changed or protected. Refreshes a few times a second.",
        x, y, CONTENT_W - 48, C.subtext, 11)
    y = y - (ih + 12)

    ------------------------------------------------------------------ STATE
    section("STATE")
    addRow("Combat", function()
        local c = UnitAffectingCombat("player") and true or false
        return c and "IN COMBAT" or "out of combat", c and GREEN or DIM
    end)
    addRow("Secret restrictions", function()
        local on = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
        if on then return "ACTIVE  (durations/cooldowns protected)", AMBER end
        return "off  (all values readable)", GREEN
    end)
    addRow("Target", function()
        if not UnitExists("target") then return "none", DIM end
        return UnitName("target") or "?", C.text
    end)
    addRow("   hostile & alive", function()
        local h = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target") and true or false
        return h and "yes" or "no", h and GREEN or DIM
    end)
    addRow("   dead", function()
        local d = UnitExists("target") and UnitIsDeadOrGhost("target") and true or false
        return d and "yes" or "no", d and GREEN or DIM
    end)
    addRow("   attackable", function()
        local a = UnitExists("target") and UnitCanAttack("player", "target") and true or false
        return a and "yes" or "no", a and GREEN or DIM
    end)
    addRow("   threat vs target", function()
        if not UnitExists("target") then return "no target", DIM end
        local ok, txt, col = pcall(function()
            local sit = UnitThreatSituation and UnitThreatSituation("player", "target")
            local names = { [0] = "not on threat table", [1] = "have threat (not tanking)",
                            [2] = "TANKING (not highest)", [3] = "TANKING / aggro" }
            local base = (sit ~= nil) and (names[sit] or ("status " .. tostring(sit))) or "none"
            local pct = ""
            if UnitDetailedThreatSituation then
                local _, _, tp = UnitDetailedThreatSituation("player", "target")
                if tp then pct = string.format("   (%.0f%%)", tp) end
            end
            return base .. pct, (sit and sit >= 2) and { 0.98, 0.5, 0.5 } or GREEN
        end)
        if not ok then return "protected/err: " .. stripErr(txt), AMBER end
        return txt, col
    end)
    addRow("Pet", function()
        if not UnitExists("pet") then return "none", DIM end
        local dead = UnitIsDead and UnitIsDead("pet")
        return (UnitName("pet") or "pet") .. (dead and "  (DEAD)" or "  (alive)"),
            dead and { 0.98, 0.5, 0.5 } or GREEN
    end)
    -- "Is a group member of this role within ~40yd" readout. Prefers exact distance
    -- (UnitDistanceSquared -- readable in scenarios/instances where UnitInRange is
    -- secret) and falls back to a guarded UnitInRange when no distance is available.
    local function roleRangeRow(role, noun)
        if not (IsInGroup and IsInGroup()) then return "not in a group", DIM end
        local raid = IsInRaid and IsInRaid()
        local found, inrange, protected, nearest = false, false, false, nil
        for i = 1, (raid and 40 or 4) do
            local u = (raid and "raid" or "party") .. i
            if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
                if not UnitGroupRolesAssigned or UnitGroupRolesAssigned(u) == role then
                    found = true
                    local yd = TCC.UnitDistanceYards(u)
                    if yd then
                        if not nearest or yd < nearest then nearest = yd end
                        if yd <= 40 + TCC.RANGE_REACH_PAD then inrange = true end
                    else
                        local ir, ch = UnitInRange(u)
                        if TCC.CanRead(ir) and TCC.CanRead(ch) then
                            if ch ~= false and ir then inrange = true end
                        else
                            protected = true        -- range is secret here (restricted content)
                        end
                    end
                end
            end
        end
        if not found then return "no " .. noun .. " found (roles unassigned?)", AMBER end
        local dist = nearest and string.format("  (nearest ~%.0fyd)", nearest) or ""
        if inrange then return "in range" .. dist, GREEN end
        if nearest then return "OUT OF RANGE" .. dist, { 0.98, 0.5, 0.5 } end
        if protected then return "range hidden (protected here)", AMBER end
        return "OUT OF RANGE", { 0.98, 0.5, 0.5 }
    end
    addRow("Healer in range", function() return roleRangeRow("HEALER", "healer") end)
    addRow("Tank in range",   function() return roleRangeRow("TANK", "tank") end)
    addRow("  range guard (raw)", function()   -- TEMP DIAGNOSTIC: remove before release
        if not (IsInGroup and IsInGroup()) then return "not in a group", DIM end
        if not issecretvalue then return "no guard fns on this client", AMBER end
        local function d(v)                     -- mark secrets; never compare one
            if issecretvalue(v) then return "|cffff8800SECRET|r" end
            return tostring(v)
        end
        local raid = IsInRaid and IsInRaid()
        local u
        for i = 1, (raid and 40 or 4) do
            local uu = (raid and "raid" or "party") .. i
            if UnitExists(uu) and not (UnitIsUnit and UnitIsUnit(uu, "player")) then u = uu; break end
        end
        if not u then return "no other member", DIM end
        local _, inst = IsInInstance()
        local parts = {
            u, "inst=" .. tostring(inst),
            "InRange=" .. d((UnitInRange(u))),
            "Vis=" .. d(UnitIsVisible and UnitIsVisible(u)),
            "DistSq=" .. d(UnitDistanceSquared and UnitDistanceSquared(u)),
        }
        return table.concat(parts, "  "), DIM
    end)
    addRow("Instance type", function()
        local inI, t = IsInInstance()
        if not inI then return "none  (open world)", DIM end
        return tostring(t), GREEN
    end)
    addRow("Group / raid", function()
        if IsInRaid() then return "in raid", GREEN end
        if IsInGroup() then return "in group", GREEN end
        return "solo", DIM
    end)
    addRow("Class", function()
        local n, token = UnitClass("player")
        return string.format("%s  (%s)", tostring(n), tostring(token)), C.text
    end)
    addRow("Spec", function()
        local i = GetSpecialization and GetSpecialization()
        if not i then return "none", DIM end
        local id, nm = GetSpecializationInfo(i)
        return string.format("%s  (id %s)", tostring(nm), tostring(id)), C.text
    end)

    ------------------------------------------------------------ PERFORMANCE
    -- Sampled at most every 2s: memory footprint + CPU as a % of one core (from the
    -- delta in profiled CPU time over the sample window).
    local function refreshPerf()
        local now = GetTime()
        local st = TCC._perf
        if st and st.at and (now - st.at) < 2 then return end
        st = st or {}; TCC._perf = st
        local mupd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
        local mget = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
        if mget then
            if mupd then pcall(mupd) end
            local m = 0; pcall(function() m = (mget("TwistedsCombatCues") or 0) + (mget("TwistedsCombatCues_DB") or 0) end)
            st.memStr = (m >= 1024) and string.format("%.2f MB", m / 1024) or string.format("%.0f KB", m)
        else st.memStr = "n/a" end
        local getcv = (C_CVar and C_CVar.GetCVar) or GetCVar
        if (getcv and getcv("scriptProfile")) ~= "1" then
            st.cpuStr = "profiling off  -  /console scriptProfile 1  then reload"; st.cpuOff = true
        else
            local cupd = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
            local cget = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
            if cget then
                if cupd then pcall(cupd) end
                local c = 0; pcall(function() c = (cget("TwistedsCombatCues") or 0) + (cget("TwistedsCombatCues_DB") or 0) end)
                if st.cpuPrev and st.at then
                    local dt = now - st.at
                    local pct = (dt > 0) and ((c - st.cpuPrev) / (dt * 1000) * 100) or 0
                    if pct < 0 then pct = 0 end
                    st.cpuStr = string.format("%.2f%%  of one core", pct); st.cpuOff = false
                else
                    st.cpuStr = "measuring..."; st.cpuOff = false
                end
                st.cpuPrev = c
            else st.cpuStr = "n/a"; st.cpuOff = nil end
        end
        st.at = now
    end
    section("PERFORMANCE   (this addon, ~2s refresh)")
    addRow("Memory", function() refreshPerf(); return TCC._perf.memStr or "-", C.text end)
    addRow("CPU", function()
        refreshPerf(); local st = TCC._perf
        return st.cpuStr or "-", st.cpuOff and AMBER or (st.cpuOff == false and GREEN or DIM)
    end)

    ------------------------------------------------------------- ITEM CHECK
    section("ITEM CHECK   (item ready condition)")
    CLabel("Item ID", labelX, y, C.subtext, 12)
    CEdit(valX, y + 2, 210, TCC._dbgItem or "", function(t)
        TCC._dbgItem = t; if TCC._debugUpdate then TCC._debugUpdate() end
    end)
    setTip(CButton(valX + 220, y + 2, 90, "Search...", "default", function(self)
        TCC.OpenSpellPicker(self, "", function(id)
            TCC._dbgItem = tostring(id); TCC.RefreshManager()
        end, "item")
    end), "Find item", "Search usable items by name and fill in the ID.")
    y = y - 30
    addRow("   resolved", function()
        local s = TCC._dbgItem
        if not s or s == "" then return "(type an item ID)", DIM end
        local id, name = TCC.ResolveItem(s)
        if id then return string.format("%s   (id %s)", tostring(name or "?"), tostring(id)), GREEN end
        return "not found (name search needs an ID)", AMBER
    end)
    addRow("   cooldown", function()
        local id = tonumber(TCC._dbgItem or "")
        if not id then return "-", DIM end
        local ok, txt, ready = pcall(function()
            local getCd = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
            if not getCd then return "no API", false end
            local start, duration = getCd(id)
            if start == nil then return "no data (not owned?)", false end
            if duration and duration > 1.5 and start and start > 0 then
                local rem = (start + duration) - GetTime()
                return string.format("on cooldown  (%.1fs left)", rem > 0 and rem or 0), false
            end
            return "READY", true
        end)
        if not ok then return "err: " .. stripErr(txt), AMBER end
        return txt, ready and GREEN or C.text
    end)
    addRow("   usable now", function()
        local id = tonumber(TCC._dbgItem or "")
        if not id then return "-", DIM end
        local ok, res = pcall(function()
            if C_Item and C_Item.IsUsableItem then return C_Item.IsUsableItem(id)
            elseif IsUsableItem then return IsUsableItem(id) end
            return nil
        end)
        if not ok then return "protected/err: " .. stripErr(res), AMBER end
        if res == nil then return "n/a", DIM end
        return res and "usable" or "not usable", res and GREEN or DIM
    end)
    addRow("   in range of target", function()
        local id = tonumber(TCC._dbgItem or "")
        if not id then return "-", DIM end
        if not UnitExists("target") then return "no target", DIM end
        local ok, res = pcall(function()
            if C_Item and C_Item.IsItemInRange then return C_Item.IsItemInRange(id, "target")
            elseif IsItemInRange then return IsItemInRange(id, "target") end
            return nil
        end)
        if not ok then return "protected/err: " .. stripErr(res), AMBER end
        if not TCC.CanRead(res) then return "hidden (protected here)", AMBER end
        if res == nil then return "n/a (item has no range check)", DIM end
        return res and "IN RANGE" or "out of range", res and GREEN or { 0.98, 0.5, 0.5 }
    end)

    TCC._debugUpdate = function()
        for _, f in ipairs(fields) do
            local ok, text, col = pcall(f.fn)
            if ok then
                f.fs:SetText(text or "-")
                if col then f.fs:SetTextColor(col[1], col[2], col[3]) end
            else
                -- Surface the real error (minus the file:line prefix) so it's diagnosable.
                local msg = tostring(text):gsub("^.-:%d+: ", "")
                f.fs:SetText("|cffff5555" .. msg .. "|r")
            end
        end
    end
    TCC._debugUpdate()

    -- One persistent ticker: only acts while the debug view is on screen.
    if not TCC._debugTicker then
        TCC._debugTicker = C_Timer.NewTicker(0.3, function()
            if TCC.uiView == "debug" and mgr and mgr:IsShown() and TCC._debugUpdate then
                TCC._debugUpdate()
            end
        end)
    end

    content:SetHeight(math.max(WIN_H, -y + 20))
end

----------------------------------------------------------------------
-- Content: Macro Factory (/tcc macros)
----------------------------------------------------------------------
-- Raid-target index (1-8) -> name, and a texture tag so the actual marker icon
-- shows in the dropdown. Index order matches SetRaidTarget / UI-RaidTargetingIcon_N.
local MARK_NAMES = { [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
                     [5] = "Moon", [6] = "Square", [7] = "Cross (X)", [8] = "Skull" }
local function markTag(n) return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":16|t" end
local MARK_CHOICES = { { "0", "No marker" } }
for _, n in ipairs({ 8, 7, 6, 5, 4, 3, 2, 1 }) do
    MARK_CHOICES[#MARK_CHOICES + 1] = { tostring(n), markTag(n) .. "  " .. MARK_NAMES[n] }
end
local ANNOUNCE_CHOICES = {
    { "NONE", "Don't announce" }, { "SAY", "Say" }, { "YELL", "Yell" }, { "PARTY", "Party" },
    { "RAID", "Raid" }, { "INSTANCE_CHAT", "Instance" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" }, { "EMOTE", "Emote" },
}
-- Where the announce is allowed to fire (instance-type gate; e.g. M+ but not raids).
local ANNOUNCE_WHERE = {
    { "any", "Anywhere" }, { "none", "Open world" }, { "any_instance", "Any instance" },
    { "party", "Dungeon (M+)" }, { "raid", "Raid" }, { "arena", "Arena" }, { "pvp", "Battleground" }, { "scenario", "Scenario" },
}
-- What the focus macro sets as your focus.
local FOCUS_SOURCE = {
    { "smart", "Mouseover, else target" }, { "target", "Current target" }, { "mouseover", "Mouseover only" },
}

----------------------------------------------------------------------
-- On-screen marker palette: a small movable bar of the 8 raid markers.
-- Each button is SECURE (macrotext = /focus + /tm ~i), so clicking one focuses
-- your target and marks it with that icon - live, even in combat - and sets it as
-- your preferred focus marker. Handy when someone's already using your marker.
----------------------------------------------------------------------
local RAID_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RT_COORDS = {  -- 4x4 atlas; index 1..8 = Star,Circle,Diamond,Triangle,Moon,Square,Cross,Skull
    { 0, 0.25, 0, 0.25 }, { 0.25, 0.5, 0, 0.25 }, { 0.5, 0.75, 0, 0.25 }, { 0.75, 1, 0, 0.25 },
    { 0, 0.25, 0.25, 0.5 }, { 0.25, 0.5, 0.25, 0.5 }, { 0.5, 0.75, 0.25, 0.5 }, { 0.75, 1, 0.25, 0.5 },
}
local markerPalette

function TCC.UpdateMarkerPalette()
    if not markerPalette then return end
    local mk = tonumber(TCC.db and TCC.db.macro and TCC.db.macro.mark) or 0
    for i, b in ipairs(markerPalette.btns) do b.sel:SetShown(i == mk) end
end

local function ensureMarkerPalette()
    if markerPalette then return markerPalette end
    local CELL, GAP, EDGE = 28, 3, 6
    local p = CreateFrame("Frame", "TwistedsCombatCuesMarkerPalette", UIParent)
    p:SetSize(EDGE * 2 + 8 * CELL + 7 * GAP, CELL + EDGE * 2)
    p:SetFrameStrata("MEDIUM"); p:SetClampedToScreen(true); p:SetMovable(true); p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self) if not (TCC.db.macro and TCC.db.macro.paletteLocked) then self:StartMoving() end end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, _, xo, yo = self:GetPoint()
        if TCC.db.macro then TCC.db.macro.palettePos = { pt, xo, yo } end
    end)
    stylePanel(p, C.panel, C.border)
    -- Deliberately NOT in UISpecialFrames: the palette is only toggled via the Focus
    -- Tools checkbox or /tcc togglemarkers, so Escape / stray clicks can't close it and
    -- its shown state always matches the saved setting (which restores cleanly on reload).
    p.btns = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", "TwistedsCombatCuesPaletteBtn" .. i, p, "SecureActionButtonTemplate")
        b:SetSize(CELL, CELL); b:SetPoint("LEFT", EDGE + (i - 1) * (CELL + GAP), 0)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "#showtooltip\n/focus [@mouseover,exists,nodead][]\n/tm [@focus] ~" .. i)
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
        b.tex:SetTexture(RAID_ATLAS); b.tex:SetTexCoord(unpack(RT_COORDS[i]))
        b.sel = b:CreateTexture(nil, "OVERLAY"); b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        b.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55); b.sel:Hide()
        b:SetScript("PostClick", function()   -- insecure state update (fine in combat)
            if TCC.db and TCC.db.macro then TCC.db.macro.mark = i end
            TCC.UpdateMarkerPalette()
            if TCC.UpdateFocusMacro then TCC.UpdateFocusMacro() end
            if built and mgr and mgr:IsShown() and TCC.uiView == "macros" then TCC.RefreshManager() end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(MARK_NAMES[i], accentHeader())
            GameTooltip:AddLine("Focus + mark your target with this icon.", 0.82, 0.86, 0.92, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        p.btns[i] = b
    end
    markerPalette = p
    return p
end

function TCC.SetMarkerPaletteShown(show)
    if not show then if markerPalette then markerPalette:Hide() end return end
    if InCombatLockdown and InCombatLockdown() and not markerPalette then return end  -- can't build secure frames in combat
    local p = ensureMarkerPalette()
    local pos = TCC.db.macro and TCC.db.macro.palettePos
    p:ClearAllPoints()
    if pos and pos[1] then p:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
    else p:SetPoint("CENTER", UIParent, "CENTER", 0, -220) end
    TCC.UpdateMarkerPalette()
    p:Show()
end

-- Flip the marker palette on/off, persist it, and keep the Focus Tools checkbox in sync.
-- The single entry point for the UI toggle and /tcc togglemarkers. Returns the new state.
function TCC.ToggleMarkerPalette()
    if not (TCC.db and TCC.db.macro) then return end
    local v = not TCC.db.macro.paletteShown
    TCC.db.macro.paletteShown = v
    TCC.SetMarkerPaletteShown(v)
    if TCC.RefreshManager then TCC.RefreshManager() end
    return v
end

local function macroBox(text, x, y)
    local _, h = CWrap(text, x + 8, y - 6, CONTENT_W - 64, C.text, 11)
    CBox(x, y + 2, CONTENT_W - 26, h + 14, 0.07, 0, C.accent)
    return y - (h + 20)
end

local function buildMacros()
    local x, y = PAD, -20
    local d = TCC.db
    d.macro = d.macro or {}
    d.macro.mark = tonumber(d.macro.mark) or 8
    d.macro.channel = d.macro.channel or "NONE"
    if d.macro.focusMsg == nil then d.macro.focusMsg = "Focus {rt}" end
    if d.macro.readyMsg == nil then d.macro.readyMsg = "My interrupt target is {rt}" end
    d.macro.announceInstance = d.macro.announceInstance or "any"

    CLabel("FOCUS TOOLS", x, y, C.accent, 13); y = y - 20
    local _, ih = CWrap("Generate ready-made macros. |cffffffffCreate Macro|r saves it to your "
        .. "macro list (out of combat only); |cffffffffCopy text|r opens it so you can paste it into "
        .. "a macro yourself.", x, y, CONTENT_W - 48, C.subtext, 11)
    y = y - (ih + 14)

    -- One macro: /focus your target/mouseover AND /tm mark it - both secure, so it
    -- works in combat. This is the proper "mark + auto-focus in one press".
    CSection("FOCUS + MARK  (one key, works in combat)", x, y); y = y - 30
    CLabel("Marker", x, y - 2, C.subtext)
    setTip(CDD(x + 60, y), "Focus marker",
        "The raid marker the macro places on your focus (also used in the announce call-out below)."):SetChoices(
        160, MARK_CHOICES, function() return tostring(d.macro.mark or 0) end,
        function(v) d.macro.mark = tonumber(v) or 0; TCC.RefreshManager() end)
    CLabel("Focus", x + 246, y - 2, C.subtext)
    d.macro.focusTarget = d.macro.focusTarget or "smart"
    setTip(CDD(x + 296, y), "Focus source",
        "What the macro focuses: your |cffffffffmouseover|r, your |cffffffffcurrent target|r, or mouseover-then-target."):SetChoices(
        200, FOCUS_SOURCE, function() return d.macro.focusTarget or "smart" end,
        function(v) d.macro.focusTarget = v; TCC.RefreshManager() end)
    local mk = tonumber(d.macro.mark) or 0
    y = y - 34

    -- Warn about markers usually reserved for kill order / tank marking.
    if mk == 8 or mk == 7 or mk == 6 then
        local _, wh = CWrap("|cffffcc00Heads up:|r " .. MARK_NAMES[mk] .. " is commonly used for kill order / tank marking - "
            .. "consider Star, Circle, Diamond, Triangle, or Moon for a focus so you don't clash.",
            x, y, CONTENT_W - 48, { 0.85, 0.68, 0.35 }, 11)
        y = y - (wh + 8)
    end

    local _, mh = CWrap("Sets your focus and |cffffffffmarks|r it in a single press. Both commands are secure, so "
        .. "|cffffffffit works in combat|r. After creating it, bind it under |cffffffffKey Bindings > Macros|r or "
        .. "drag it to a bar.", x, y, CONTENT_W - 48, C.subtext, 11)
    y = y - (mh + 8)
    y = macroBox(TCC.BuildFocusMacro(d.macro), x, y)
    setTip(CButton(x, y, 140, "Create Macro", "primary", function()
        local ok, res = TCC.SaveMacro("TCC Focus", "INV_Misc_QuestionMark", TCC.BuildFocusMacro(d.macro), true)
        print(TCC.PREFIX .. (ok and "Saved character macro |cffffff00TCC Focus|r." or ("Not saved: " .. tostring(res))))
    end), "Create macro", "Save this as a per-character macro named 'TCC Focus' and open the macro pane.")
    setTip(CButton(x + 150, y, 110, "Copy text", "default", function() ShowExportDialog(TCC.BuildFocusMacro(d.macro)) end),
        "Copy text", "Open the macro text so you can copy it.")
    y = y - 44

    -- On-screen marker palette (change your marker on the fly).
    setTip(CToggle(x, y, d.macro.paletteShown, function(v)
        d.macro.paletteShown = v
        if TCC.SetMarkerPaletteShown then TCC.SetMarkerPaletteShown(v) end
        TCC.RefreshManager()
    end), "Marker palette", "Show a small movable bar of the 8 raid markers on screen. Click one to |cffffffff focus + mark|r your target with it - live, even in combat - and make it your focus marker. Handy if someone's already using yours.")
    CLabel("Show marker palette on screen", x + 46, y - 2, C.text)
    if d.macro.paletteShown then
        setTip(CToggle(x + 290, y, d.macro.paletteLocked, function(v) d.macro.paletteLocked = v end),
            "Lock palette", "Lock the palette in place so it can't be dragged.")
        CLabel("Lock", x + 336, y - 2, C.subtext)
    end
    y = y - 44

    -- Announce (event-driven: fires however you set focus).
    CSection("ANNOUNCE", x, y); y = y - 30
    CLabel("Announce to", x, y - 2, C.subtext)
    setTip(CDD(x + 96, y), "Announce channel", "Which chat channel your focus call-outs go to (None = off)."):SetChoices(
        150, ANNOUNCE_CHOICES, function() return d.macro.channel or "NONE" end,
        function(v) d.macro.channel = v; TCC.RefreshManager() end)
    CLabel("in", x + 258, y - 2, C.subtext)
    setTip(CDD(x + 282, y), "Announce where",
        "Only send call-outs in this kind of content - e.g. |cffffffffDungeon (M+)|r but not |cffffffffRaid|r."):SetChoices(
        160, ANNOUNCE_WHERE, function() return d.macro.announceInstance or "any" end,
        function(v) d.macro.announceInstance = v; TCC.RefreshManager() end)
    y = y - 36

    local canAnnounce = (d.macro.channel or "NONE") ~= "NONE"
    local txtCol = canAnnounce and C.text or C.subtext

    setTip(CToggle(x, y, d.macro.announceFocus, function(v) d.macro.announceFocus = v; TCC.RefreshManager() end),
        "Announce on focus", "Send this call-out whenever you set your focus target (by any means).")
    CLabel("When I set focus", x + 46, y - 2, txtCol)
    y = y - 26
    setTip(CEdit(x + 46, y, CONTENT_W - 116, d.macro.focusMsg or "", function(t) d.macro.focusMsg = t end),
        "Focus message", "Sent when you set focus.  {rt} = your marker icon.")
    y = y - 34

    setTip(CToggle(x, y, d.macro.announceReady, function(v) d.macro.announceReady = v; TCC.RefreshManager() end),
        "Announce on ready check", "Re-post your focus call-out when a ready check starts.")
    CLabel("When a ready check starts", x + 46, y - 2, txtCol)
    y = y - 26
    setTip(CEdit(x + 46, y, CONTENT_W - 116, d.macro.readyMsg or "", function(t) d.macro.readyMsg = t end),
        "Ready-check message", "Sent when a ready check starts. There's usually no target then, so lead with |cffffffff{rt}|r (your marker).")
    y = y - 30
    local _, hh = CWrap("Wildcard: |cffffffff{rt}|r = the marker icon.",
        x + 46, y, CONTENT_W - 110, C.subtext, 11)
    y = y - (hh + 6)
    if not canAnnounce then
        local _, nh = CWrap("|cffffcc00Pick an announce channel above to turn call-outs on.|r",
            x + 46, y, CONTENT_W - 110, { 0.85, 0.68, 0.35 }, 11)
        y = y - (nh + 6)
    end
    y = y - 8

    -- Interrupt @focus
    CSection("INTERRUPT  @FOCUS  (auto-detected for your spec)", x, y); y = y - 30
    local kickText, intr = TCC.BuildKickMacro()
    if kickText then
        local line = "Detected: |cff33ff33" .. tostring(intr.name or "?") .. "|r"
        if intr.note then line = line .. "   |cffffcc00(" .. intr.note .. ")|r" end
        CLabel(line, x, y - 2, C.text); y = y - 26
        y = macroBox(kickText, x, y)
        setTip(CButton(x, y, 130, "Create Macro", "primary", function()
            local ok, res = TCC.SaveMacro("TCC Kick", intr.icon or "INV_Misc_QuestionMark", (TCC.BuildKickMacro()), true)
            print(TCC.PREFIX .. (ok and "Saved character macro |cffffff00TCC Kick|r." or ("Not saved: " .. tostring(res))))
        end), "Create macro", "Save this as a per-character macro named 'TCC Kick' (spec-specific).")
        setTip(CButton(x + 140, y, 110, "Copy text", "default", function() ShowExportDialog((TCC.BuildKickMacro())) end),
            "Copy text", "Open the macro text so you can copy it.")
        y = y - 48
    else
        local _, nh = CWrap("|cffffcc00No interrupt macro for your spec.|r  " .. tostring(intr),
            x, y - 2, CONTENT_W - 48, C.subtext, 12)
        y = y - (nh + 14)
    end

    -- Stun @focus / @target
    CSection("STUN  @FOCUS / @TARGET  (auto-detected for your talents)", x, y); y = y - 30
    local stunText, stun = TCC.BuildStunMacro()
    if stunText then
        CLabel("Detected: |cff33ff33" .. tostring(stun.name or "?") .. "|r", x, y - 2, C.text); y = y - 26
        y = macroBox(stunText, x, y)
        setTip(CButton(x, y, 130, "Create Macro", "primary", function()
            local ok, res = TCC.SaveMacro("TCC Stun", stun.icon or "INV_Misc_QuestionMark", (TCC.BuildStunMacro()), true)
            print(TCC.PREFIX .. (ok and "Saved character macro |cffffff00TCC Stun|r." or ("Not saved: " .. tostring(res))))
        end), "Create macro", "Save this as a per-character macro named 'TCC Stun'.")
        setTip(CButton(x + 140, y, 110, "Copy text", "default", function() ShowExportDialog((TCC.BuildStunMacro())) end),
            "Copy text", "Open the macro text so you can copy it.")
        y = y - 48
    else
        local _, sh = CWrap("|cffffcc00No stun macro:|r  " .. tostring(stun),
            x, y - 2, CONTENT_W - 48, C.subtext, 12)
        y = y - (sh + 14)
    end

    content:SetHeight(math.max(WIN_H, -y + 20))
end

-- Content: the Alerts page - a list of every alert with enable / edit / delete.
local function buildAlertsPage()
    local x, y = PAD, -20
    CLabel("ALERTS", x, y, C.accent, 13)
    setTip(CButton(x + 468, y - 4, 132, PLUS_ICON .. " New Alert", "primary", function() TCC.OpenNewAlertModal() end),
        "New alert", "Open the |cffffffffalert type|r picker to create a new alert.")
    y = y - 26
    local _, ih = CWrap("Toggle to enable/disable, |cffffffffEdit|r to configure, or |cffffffffDelete|r to remove.",
        x, y, CONTENT_W - 48, C.subtext, 11)
    y = y - (ih + 10)

    local q = TCC._alertSearch or ""
    CLabel("Search", x, y - 2, C.subtext)
    if mgr and mgr.alertSearch then
        local sb = mgr.alertSearch
        sb:ClearAllPoints(); sb:SetPoint("TOPLEFT", content, "TOPLEFT", x + 56, y)
        if sb:GetText() ~= q then sb:SetText(q) end
        if sb._ph then sb._ph:SetShown(q == "") end
        sb:Show()
    end
    if q ~= "" then
        setTip(CButton(x + 306, y, 70, "Clear", "default", function()
            TCC._alertSearch = ""
            if mgr.alertSearch then mgr.alertSearch:SetText("") end
            TCC.RefreshManager()
        end), "Clear", "Show all alerts.")
    end
    y = y - 36

    local ql = q:lower()
    local buckets = {}; for _, k in ipairs(KIND_ORDER) do buckets[k] = {} end
    for _, rule in ipairs(TCC.db.rules) do
        if ql == "" or (rule.name or ""):lower():find(ql, 1, true) then
            table.insert(buckets[alertKindOf(rule)], rule)
        end
    end

    local shown = 0
    for _, k in ipairs(KIND_ORDER) do
        local list = buckets[k]
        if #list > 0 then
            CSection(KIND_LABEL[k], x, y); y = y - 28
            for _, rule in ipairs(list) do
                shown = shown + 1
                local rid = rule.id
                -- Row is 46 tall; everything vertically centered ~y-23.
                local ic = CIcon(x + 2, y - 4); ic:SetSize(38, 38)
                ic.tex:SetTexCoord(0, 1, 0, 1); ic.tex:SetTexture(alertIconOf(rule))
                CLabel(rule.name or "?", x + 50, y - 17, rule.enabled and C.text or C.subtext, 13)
                setTip(CToggle(x + 372, y - 14, rule.enabled, function(v) rule.enabled = v; softApply(); TCC.RefreshManager() end),
                    "Enabled", "Enable or disable this alert.")
                setTip(CButton(x + 420, y - 10, 70, "Edit", "default", function()
                    TCC.uiView = "rule"; TCC.selectedRuleId = rid; TCC.RefreshManager()
                end), "Edit", "Open this alert's editor.")
                setTip(CButton(x + 496, y - 10, 80, "Delete", "danger", function()
                    TCC.selectedRuleId = rid
                    StaticPopup_Show("TWISTEDSCOMBATCUES_DELETE", rule.name or "alert")
                end), "Delete", "Remove this alert.")
                y = y - 46
            end
        end
    end

    if shown == 0 then
        CWrap(q ~= "" and "No alerts match your search."
            or "No alerts yet. Click |cffffffff+ New Alert|r above to create one.",
            x, y - 4, CONTENT_W - 48, C.subtext, 12)
        y = y - 40
    end
    content:SetHeight(math.max(WIN_H, -y + 20))
end

-- Content: a friendly onboarding walkthrough (first thing new users see).
local function buildGettingStarted()
    local x, y = PAD, -18
    CLogo(x, y - 4, 46)
    CLabel("Welcome to Twisteds Combat Cues", x + 60, y - 4, C.accent, 16)
    CLabel("Combat-safe audible & visual cues for the moments that matter.", x + 60, y - 28, C.subtext, 12)
    y = y - 62

    local _, ih = CWrap("This addon watches a few |cffffffffcombat-safe|r signals - your target, range, threat, pet, "
        .. "and item cooldowns - and fires the cues you set up. Here are the three areas you'll use:",
        x, y, CONTENT_W - 44, C.text, 12)
    y = y - (ih + 16)

    local CARD_W = CONTENT_W - 40
    local function card(iconFile, title, desc, btn, view)
        local h = 98
        CBox(x, y, CARD_W, h, 0.06, 0, C.accent)
        local ic = CIcon(x + 16, y - 16); ic:SetSize(40, 40)
        ic.tex:SetTexCoord(0, 1, 0, 1); ic.tex:SetTexture(iconFile)
        CLabel(title, x + 72, y - 16, C.accent, 14)
        CWrap(desc, x + 72, y - 38, CARD_W - 72 - 168, C.subtext, 11)
        setTip(CButton(x + CARD_W - 150, y - 36, 134, btn, "primary", function()
            TCC.uiView = view; TCC.RefreshManager()
        end), btn, "Jump to this page.")
        y = y - (h + 14)
    end

    card(ICON_DIR .. "bell.tga", "1.  Alerts",
        "Click |cffffffff+ New Alert|r and pick a type (Range, Target, Threat, Pet, Item). On the |cffffffffTrigger|r tab "
        .. "choose what fires it; turn on a |cffffffffSound|r, |cffffffffText|r, or |cffffffffIcon|r under the other tabs. "
        .. "The |cffffffffLoad|r tab limits it to a class/spec, combat, group, or zone.",
        "Go to Alerts", "alerts")

    card(ICON_DIR .. "settings.tga", "2.  General Options",
        "Master on/off, the UI |cffffffffaccent color|r and window scale, and |cffffffffprofiles|r - share your alerts "
        .. "account-wide or keep a private set for this character.",
        "Global Options", "global")

    card(ICON_DIR .. "crosshair.tga", "3.  Focus Tools",
        "One |cffffffffmarker|r drives a set-focus keybind, optional |cffffffffauto-focus|r, and chat |cffffffffcall-outs|r. "
        .. "It also auto-detects your spec's |cffffffffinterrupt|r and |cffffffffstun|r and builds @focus macros.",
        "Focus Tools", "macros")
    y = y - 6

    CSection("What is combat-safe?", x, y); y = y - 28
    local _, wh = CWrap("|cffffffffCombat-safe|r means information WoW still lets an addon read while you're actually fighting. "
        .. "In patch 12.0 (Midnight), Blizzard made much of your combat state |cffffffffSecret|r to addons - spell "
        .. "cooldowns, buffs & auras, and health / power can no longer be read reliably while you are "
        .. "|cffffffffin combat|r or inside an instance. They did it to rein in the |cffffffffover-automation|r that told "
        .. "players exactly what to press and when - the same API change that broke much of what "
        .. "|cffffffffWeakAuras|r used to do.", x, y, CONTENT_W - 44, C.text, 12)
    y = y - (wh + 10)
    local _, w2 = CWrap("Rather than fight that, this addon sticks to the signals that are |cffffffffstill readable in combat|r: "
        .. "whether you have a |cfffffffftarget|r, your |cffffffffrange|r to it, your |cffffffffthreat|r, your "
        .. "|cffffffffpet|r, and |cffffffffitem cooldowns|r. No secret values and nothing against the rules - just honest "
        .. "reminders for the things that are easy to miss mid-pull.", x, y, CONTENT_W - 44, C.subtext, 12)
    y = y - (w2 + 20)

    local _, fh = CWrap("Reopen this any time from |cffffffffGetting Started|r at the top of the sidebar. "
        .. "Type |cffffffff/tcc|r to open this window.", x, y - 2, CONTENT_W - 44, C.subtext, 11)
    y = y - (fh + 18)

    TCC.db.seenIntro = true   -- so future launches open straight to Alerts
    content:SetHeight(math.max(WIN_H, -y + 20))
end

-- Content: Help - slash commands + a few tips.
local HELP_COMMANDS = {
    { "/tcc",              "Open or close this window." },
    { "/tcc alerts",       "Jump straight to the Alerts list." },
    { "/tcc macros",       "Open Focus Tools (focus / interrupt / stun)." },
    { "/tcc togglemarkers", "Show / hide the on-screen marker palette." },
    { "/tcc debug",        "Open Live Diagnostics - what the engine sees." },
    { "/tcc options",      "Open the Blizzard interface options panel." },
    { "/tcc on   /   off", "Enable or disable all cues." },
    { "/tcc test",         "Play a test cue." },
    { "/tcc move",         "Reposition all on-screen alerts at once." },
    { "/tcc status",       "Print your alerts and current state to chat." },
    { "/tcc reset",        "Reset the active profile (asks to confirm)." },
}
local HELP_TIPS = {
    "Alerts use spell / item |cffffffffIDs|r internally, so they keep working in Mythic+ where name lookups are blocked.",
    "New alerts start |cffffffffsilent|r - turn on a Sound, Text, or Icon in the editor tabs.",
    "The Focus Tools marker keybind uses Blizzard's |cffffffffsecure|r action, so it works in combat (placing a mark from a macro does not).",
    "Everything here is |cffffffffcombat-safe|r - see Getting Started for what that means.",
}
local function buildHelp()
    local x, y = PAD, -18
    CLabel("Help & Commands", x, y, C.accent, 16); y = y - 24
    local _, ih = CWrap("Everything you can type, plus a few tips. Every command starts with |cffffffff/tcc|r.",
        x, y, CONTENT_W - 44, C.subtext, 12)
    y = y - (ih + 14)

    CSection("SLASH COMMANDS", x, y); y = y - 28
    local rowH, boxW = 26, CONTENT_W - 40
    local boxH = #HELP_COMMANDS * rowH + 12
    CBox(x, y, boxW, boxH, 0.05, 0, C.accent)
    local ry = y - 10
    for i, c in ipairs(HELP_COMMANDS) do
        if i % 2 == 0 then CBox(x + 4, ry + 4, boxW - 8, rowH - 2, 0.05, 1, C.border) end  -- subtle zebra
        CLabel(c[1], x + 16, ry, C.accent, 13)
        CLabel(c[2], x + 210, ry, C.subtext, 12)
        ry = ry - rowH
    end
    y = y - (boxH + 18)

    CSection("TIPS", x, y); y = y - 26
    for _, tip in ipairs(HELP_TIPS) do
        local _, th = CWrap("|cff5c74d0-|r  " .. tip, x + 6, y, CONTENT_W - 50, C.subtext, 12)
        y = y - (th + 9)
    end
    y = y - 10

    content:SetHeight(math.max(WIN_H, -y + 20))
end

local function buildContent()
    releaseAll(PC)
    if mgr and mgr.alertSearch then mgr.alertSearch:Hide() end   -- only the Alerts page shows it
    TCC._debugUpdate = nil   -- released fontstrings; buildDebug reassigns if needed
    -- Reset scroll to the top whenever the view or selected rule changes.
    local key = tostring(TCC.uiView) .. "|" .. tostring(TCC.selectedRuleId)
    if key ~= TCC._lastViewKey then
        TCC._lastViewKey = key
        if contentScroll then contentScroll:SetVerticalScroll(0) end
    end
    local ok, err = pcall(function()
        if TCC.uiView == "getting-started" then
            buildGettingStarted()
        elseif TCC.uiView == "help" then
            buildHelp()
        elseif TCC.uiView == "global" then
            buildGlobal()
        elseif TCC.uiView == "credits" then
            buildCredits()
        elseif TCC.uiView == "whatsnew" then
            buildWhatsNew()
        elseif TCC.uiView == "debug" then
            buildDebug()
        elseif TCC.uiView == "macros" then
            buildMacros()
        elseif TCC.uiView == "rule" then
            local rule = TCC.GetSelectedRule()
            if rule then buildRuleEditor(rule) else buildAlertsPage() end   -- deleted/missing -> back to list
        else
            buildAlertsPage()
        end
    end)
    if not ok then
        print("|cffff5555Twisteds Combat Cues UI error:|r " .. tostring(err))
        content:SetHeight(WIN_H)
    end
    -- Update the scrollbar once the layout (child height) has settled.
    if updateScrollbar then C_Timer.After(0, updateScrollbar) end
end

----------------------------------------------------------------------
-- Sidebar (rule nav items)
----------------------------------------------------------------------
-- A sidebar nav row: left accent bar + selectable bg + icon + label (+ optional toggle).
local function makeNavRow(parent)
    local b = CreateFrame("Button", nil, parent); b:SetSize(SIDE_W - 16, 30)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); paint(b.bg, C.sidebar)
    b.sel = b:CreateTexture(nil, "ARTWORK"); paint(b.sel, C.accent)
    b.sel:SetPoint("TOPLEFT"); b.sel:SetPoint("BOTTOMLEFT"); b.sel:SetWidth(3); b.sel:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 12, 0)   -- Tabler TGAs are full-bleed (no icon border to crop)
    b.tg = makeToggle(b); b.tg:SetPoint("RIGHT", -8, 0); b.tg:Hide()
    b.fs = b:CreateFontString(nil, "OVERLAY"); b.fs:SetFont(FONT, 12)
    b.fs:SetPoint("LEFT", b.icon, "RIGHT", 8, 0); b.fs:SetPoint("RIGHT", -8, 0); b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) if not self._sel then paint(self.bg, mix(C.sidebar, C.accent, 0.28)) end end)
    b:SetScript("OnLeave", function(self) if not self._sel then paint(self.bg, C.sidebar) end end)
    return b
end

-- Apply/clear the "selected" look on a nav row.
local function navSelect(b, sel)
    b._sel = sel
    b.sel:SetShown(sel); paint(b.sel, C.accent)
    paint(b.bg, sel and mix(C.sidebar, C.accent, 0.45) or C.sidebar)
    b.fs:SetTextColor(unpack(sel and { 0.98, 0.99, 1 } or C.text))
end

----------------------------------------------------------------------
-- Public refresh + window construction
----------------------------------------------------------------------
function TCC.RefreshManager()
    if not built then return end
    ApplyAccent()  -- keep C.accent in sync with db (e.g. after reset / profile switch)
    -- Re-assert size/scale so nothing (a stray callback) can leave it oversized.
    local ws = TCC.db.windowScale
    if type(ws) ~= "number" or ws < 0.6 or ws > 1.5 then ws = 1; TCC.db.windowScale = 1 end
    mgr:SetScale(ws); mgr:SetSize(WIN_W, WIN_H)
    if mgr.toolRows then
        -- Editing a rule is a sub-page of Alerts, so keep Alerts highlighted then.
        for _, r in ipairs(mgr.toolRows) do
            local active = TCC.uiView == r._view or (r._view == "alerts" and TCC.uiView == "rule")
            navSelect(r, active)
        end
    end
    buildContent()
end
TCC.RefreshOptions = TCC.RefreshManager

local function EnsureManager()
    if built then return end

    -- Seed the accent from saved settings before any widgets are created.
    local ac = TCC.db.accentColor
    if ac then C.accent[1], C.accent[2], C.accent[3] = ac[1], ac[2], ac[3] end

    mgr = CreateFrame("Frame", "TwistedsCombatCuesManager", UIParent)
    mgr:SetSize(WIN_W, WIN_H); mgr:SetPoint("CENTER")
    mgr:SetFrameStrata("HIGH"); mgr:SetToplevel(true); mgr:SetClampedToScreen(true)
    stylePanel(mgr, C.bg, C.border)
    mgr:SetMovable(true); mgr:EnableMouse(true)
    mgr:Hide()  -- frames are shown by default; start hidden so the first /tcc opens it
    mgr:SetScale(TCC.db.windowScale or 1)
    tinsert(UISpecialFrames, "TwistedsCombatCuesManager")

    -- Header (drag handle)
    local header = CreateFrame("Button", nil, mgr); header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H); local hbg = header:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); paint(hbg, C.panel)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() mgr:StartMoving() end)
    header:SetScript("OnDragStop", function()
        mgr:StopMovingOrSizing()
        local point, _, _, px, py = mgr:GetPoint()
        TCC.db.windowPos = { point = point, x = px, y = py }
    end)
    local logo = header:CreateTexture(nil, "ARTWORK"); paint(logo, C.accent); logo:SetSize(14, 14); logo:SetPoint("LEFT", 16, 0)
    mgr.logo = logo
    local title = header:CreateFontString(nil, "OVERLAY"); title:SetFont(FONT, 15)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0); title:SetText("Twisteds Combat Cues"); title:SetTextColor(unpack(C.text))

    local close = makeButton(mgr); close:Configure("X", 28, 28, "danger", function() mgr:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetFrameLevel(header:GetFrameLevel() + 5)  -- above the drag handle so clicks land

    if TCC.db.windowPos and TCC.db.windowPos.point then
        mgr:ClearAllPoints()
        mgr:SetPoint(TCC.db.windowPos.point, UIParent, TCC.db.windowPos.point, TCC.db.windowPos.x or 0, TCC.db.windowPos.y or 0)
    end

    -- Sidebar
    local side = CreateFrame("Frame", nil, mgr)
    side:SetPoint("TOPLEFT", 1, -HEADER_H); side:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1); side:SetWidth(SIDE_W)
    local sbg = side:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); paint(sbg, C.sidebar)
    local sedge = side:CreateTexture(nil, "ARTWORK"); paint(sedge, C.border); sedge:SetWidth(1)
    sedge:SetPoint("TOPRIGHT"); sedge:SetPoint("BOTTOMRIGHT")

    -- Page navigation rows (fixed, with icons + selection highlight).
    local PAGES = {
        { view = "getting-started", label = "Getting Started", icon = ICON_DIR .. "rocket.tga" },
        { view = "alerts",  label = "Alerts",          icon = ICON_DIR .. "bell.tga" },
        { view = "global",  label = "Global Options",   icon = ICON_DIR .. "settings.tga" },
        { view = "macros",  label = "Focus Tools",      icon = ICON_DIR .. "crosshair.tga" },
        { view = "debug",   label = "Live Diagnostics", icon = ICON_DIR .. "activity.tga" },
        { view = "help",    label = "Help & Commands",  icon = ICON_DIR .. "help.tga" },
        { view = "whatsnew", label = "What's New",       icon = ICON_DIR .. "star.tga" },
        { view = "credits", label = "About & Thanks",   icon = ICON_DIR .. "info-circle.tga" },
    }
    mgr.toolRows = {}
    local ty = -12
    for _, t in ipairs(PAGES) do
        local r = makeNavRow(side); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, ty)
        r.icon:SetTexture(t.icon); r.fs:SetText(t.label); r._view = t.view
        r:SetScript("OnClick", function() TCC.uiView = t.view; TCC.RefreshManager() end)
        mgr.toolRows[#mgr.toolRows + 1] = r
        ty = ty - 32
    end

    -- Bottom-of-sidebar action: drag every on-screen alert into place at once.
    local posBtn = makeButton(side)
    posBtn:Configure(("|T%scrosshair.tga:12:12:0:0|t  Set Alert Positions"):format(ICON_DIR), SIDE_W - 20, 28, "primary",
        function() TCC.StartPositionMode() end)
    posBtn:ClearAllPoints(); posBtn:SetPoint("BOTTOMLEFT", 10, 10)
    setTip(posBtn, "Set alert positions",
        "Hide this window and drag |cffffffffevery|r on-screen alert (text/icon) into place, then Save.")

    -- Content
    contentScroll = CreateFrame("ScrollFrame", nil, mgr)
    contentScroll:SetPoint("TOPLEFT", SIDE_W + 2, -HEADER_H - 6)
    contentScroll:SetPoint("BOTTOMRIGHT", -20, FOOTER_H + 6)   -- leave room for the scrollbar + footer
    content = CreateFrame("Frame", nil, contentScroll); content:SetSize(CONTENT_W, 1)
    contentScroll:SetScrollChild(content)

    -- Persistent live-search box for the Alerts page. Kept out of the widget pool so
    -- it holds keyboard focus while the list rebuilds on every keystroke.
    local asearch = makeEdit(content); asearch:SetSize(240, 24)
    asearch._ph = asearch:CreateFontString(nil, "OVERLAY"); asearch._ph:SetFont(FONT, 11)
    asearch._ph:SetPoint("LEFT", 8, 0); asearch._ph:SetTextColor(unpack(C.subtext)); asearch._ph:SetText("Search alerts...")
    asearch:SetScript("OnTextChanged", function(self)
        local t = self:GetText(); self._ph:SetShown(t == "")
        if t ~= (TCC._alertSearch or "") then TCC._alertSearch = t; TCC.RefreshManager() end
    end)
    asearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    setTip(asearch, "Search alerts", "Type to filter the list by |cffffffffname|r.")
    asearch:Hide()
    mgr.alertSearch = asearch

    -- Themed scrollbar (right edge of the body).
    local sbar = CreateFrame("Frame", nil, mgr); sbar:SetWidth(8)
    sbar:SetPoint("TOPRIGHT", -6, -HEADER_H - 8); sbar:SetPoint("BOTTOMRIGHT", -6, FOOTER_H + 8)
    local strack = sbar:CreateTexture(nil, "BACKGROUND"); strack:SetAllPoints(); paint(strack, C.card, 0.6)
    local sthumb = CreateFrame("Button", nil, sbar); sthumb:SetPoint("TOP"); sthumb:SetWidth(8); sthumb:SetHeight(40)
    local sthumbTex = sthumb:CreateTexture(nil, "ARTWORK"); sthumbTex:SetAllPoints()
    mgr.sbar, mgr.sthumb, mgr.sthumbTex = sbar, sthumb, sthumbTex

    updateScrollbar = function()
        local vh, ch = contentScroll:GetHeight(), content:GetHeight()
        -- Midnight: GetVerticalScrollRange()/GetVerticalScroll() come back "secret" when
        -- the scroll content shows secret values (e.g. the diagnostics page), and
        -- comparing a secret throws. The heights are plain numbers, so derive the
        -- scrollable range from them and only read the live scroll offset if it's safe.
        if not (TCC.CanRead(vh) and TCC.CanRead(ch)) then sbar:Hide(); return end
        local range = math.max(0, (ch or 0) - (vh or 0))
        if range > 1 and ch > 0 then
            sbar:Show()
            local trackH = sbar:GetHeight()
            local thumbH = math.max(24, trackH * (vh / ch))
            sthumb:SetHeight(thumbH)
            local pos = contentScroll:GetVerticalScroll()
            local frac = TCC.CanRead(pos) and (pos / range) or 0
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            sthumb:ClearAllPoints(); sthumb:SetPoint("TOP", sbar, "TOP", 0, -frac * (trackH - thumbH))
            paint(sthumbTex, C.accent)
        else
            sbar:Hide()
        end
    end

    -- Footer bar: addon name, author, version.
    local footer = CreateFrame("Frame", nil, mgr)
    footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(FOOTER_H)
    local fbg = footer:CreateTexture(nil, "BACKGROUND"); fbg:SetAllPoints(); paint(fbg, C.panel)
    local fedge = footer:CreateTexture(nil, "ARTWORK"); paint(fedge, C.border); fedge:SetHeight(1)
    fedge:SetPoint("TOPLEFT"); fedge:SetPoint("TOPRIGHT")
    local author = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Author"))
        or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Author")) or "Twistedfury-Zul'jin"
    local fname = footer:CreateFontString(nil, "OVERLAY"); fname:SetFont(FONT, 11)
    fname:SetPoint("LEFT", 14, 0); fname:SetTextColor(unpack(C.subtext))
    fname:SetText("Twisteds Combat Cues  |cff555c68·|r  by " .. author)
    local fver = footer:CreateFontString(nil, "OVERLAY"); fver:SetFont(FONT, 11)
    fver:SetPoint("RIGHT", -14, 0); fver:SetTextColor(unpack(C.accent))
    fver:SetText("v" .. (TCC.VERSION or "1.0.0"))

    -- Community: Discord invite. WoW can't open a browser, so a click pops the link in a
    -- copy dialog (Ctrl+C).
    local disc = CreateFrame("Button", nil, footer)
    disc.fs = disc:CreateFontString(nil, "OVERLAY"); disc.fs:SetFont(FONT, 11)
    disc.fs:SetPoint("CENTER"); disc.fs:SetText("Discord"); disc.fs:SetTextColor(unpack(C.accent))
    disc:SetSize(disc.fs:GetStringWidth() + 12, FOOTER_H)
    disc:SetPoint("CENTER", footer, "CENTER", 0, 0)
    disc:SetScript("OnEnter", function(self)
        self.fs:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Join the Discord", accentHeader())
        GameTooltip:AddLine("Click to copy the invite link.", 0.82, 0.86, 0.92, true); GameTooltip:Show()
    end)
    disc:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(C.accent)); GameTooltip_Hide() end)
    disc:SetScript("OnClick", function()
        ShowLinkDialog("Discord invite - copy this link (Ctrl+C)", "https://discord.com/invite/pN5vYDrQ5j")
    end)
    mgr.footer = footer

    -- Keep the Focus Tools keybind readout in sync: SetBinding doesn't reflect in
    -- GetBindingKey until the binding system fires this, so refresh on it.
    local bindWatcher = CreateFrame("Frame")
    bindWatcher:RegisterEvent("UPDATE_BINDINGS")
    bindWatcher:SetScript("OnEvent", function()
        if built and mgr and mgr:IsShown() and TCC.uiView == "macros" then TCC.RefreshManager() end
    end)

    contentScroll:EnableMouseWheel(true)
    contentScroll:SetScript("OnMouseWheel", function(self, delta) scrollWheel(self, delta); updateScrollbar() end)

    sthumb:RegisterForDrag("LeftButton")
    sthumb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local range = scrollMax(contentScroll)   -- heights-based; safe vs secret scroll range
            if range <= 0 then return end
            local trackH = sbar:GetHeight()
            local s = sbar:GetEffectiveScale()
            local _, cy = GetCursorPosition()
            local top = sbar:GetTop()
            if top and s and s > 0 then
                local frac = (top - (cy / s)) / math.max(1, trackH - self:GetHeight())
                frac = math.min(1, math.max(0, frac))
                contentScroll:SetVerticalScroll(frac * range)
                updateScrollbar()
            end
        end)
    end)
    sthumb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    StaticPopupDialogs["TWISTEDSCOMBATCUES_RESET"] = {
        text = "Twisteds Combat Cues: reset the ACTIVE profile's settings and alerts to defaults?",
        button1 = YES, button2 = NO,
        OnAccept = function() TCC.ResetSettings() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs["TWISTEDSCOMBATCUES_DELETE"] = {
        text = "Delete alert \"%s\"?",
        button1 = YES, button2 = NO,
        OnAccept = function() TCC.DeleteSelectedRule() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    built = true  -- only mark built after the whole window constructs successfully
end

-- Build the window, surfacing any construction error instead of half-building.
local function safeEnsure()
    if built then return true end
    local ok, err = pcall(EnsureManager)
    if not ok then
        print("|cffff5555Twisteds Combat Cues: window build error:|r " .. tostring(err))
        return false
    end
    return true
end

-- Show the window, self-healing size/scale/position so a corrupted saved state
-- can never leave it oversized or off-screen.
local function showManager()
    -- First ever open lands on Getting Started; after that, straight to Alerts.
    TCC.uiView = TCC.uiView or (TCC.db.seenIntro and "alerts" or "getting-started")
    local ws = TCC.db.windowScale
    if type(ws) ~= "number" or ws < 0.6 or ws > 1.5 then ws = 1; TCC.db.windowScale = 1 end
    mgr:SetScale(ws)
    mgr:SetSize(WIN_W, WIN_H)
    mgr:Show()
    local l, r, t, b = mgr:GetLeft(), mgr:GetRight(), mgr:GetTop(), mgr:GetBottom()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if (not l) or (r and r < 40) or (l and l > sw - 40) or (t and t < 40) or (b and b > sh - 4) then
        mgr:ClearAllPoints(); mgr:SetPoint("CENTER"); TCC.db.windowPos = nil
    end
    TCC.RefreshManager()
end

function TCC.OpenManager(view)
    if not safeEnsure() then return end
    if view then TCC.uiView = view end
    showManager()
end

function TCC.ToggleManager()
    if not safeEnsure() then return end
    if mgr:IsShown() then mgr:Hide() else showManager() end
end

function TCC.HideManager()
    if built and mgr then mgr:Hide() end
end

-- Themed Save/Cancel bar shown while dragging a rule's visual text.
local moverBar
function TCC.ShowMoverControls(anchor, onSave, onCancel)
    if not moverBar then
        moverBar = CreateFrame("Frame", "TwistedsCombatCuesMoverBar", UIParent)
        moverBar:SetSize(236, 36); moverBar:SetFrameStrata("FULLSCREEN_DIALOG"); moverBar:SetToplevel(true)
        stylePanel(moverBar, C.panel, C.accent)
        moverBar.save = makeButton(moverBar); moverBar.save:SetPoint("LEFT", 8, 0)
        moverBar.cancel = makeButton(moverBar); moverBar.cancel:SetPoint("RIGHT", -8, 0)
    end
    moverBar.save:Configure("Save Position", 124, 24, "primary", onSave)
    moverBar.cancel:Configure("Cancel", 88, 24, "default", onCancel)
    moverBar:ClearAllPoints()
    if anchor then moverBar:SetPoint("TOP", anchor, "BOTTOM", 0, -34) else moverBar:SetPoint("CENTER", 0, -160) end
    moverBar:Show()
end

function TCC.HideMoverControls()
    if moverBar then moverBar:Hide() end
end

-- Themed "Stop Test" bar shown while a rule is being test-fired.
local testBar
function TCC.ShowTestControls(name, onStop)
    if not testBar then
        testBar = CreateFrame("Frame", "TwistedsCombatCuesTestBar", UIParent)
        testBar:SetSize(260, 56); testBar:SetFrameStrata("FULLSCREEN_DIALOG"); testBar:SetToplevel(true)
        testBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
        stylePanel(testBar, C.panel, C.accent)
        testBar.label = testBar:CreateFontString(nil, "OVERLAY"); testBar.label:SetFont(FONT, 12, "")
        testBar.label:SetPoint("TOP", 0, -9); testBar.label:SetTextColor(unpack(C.text))
        testBar.stop = makeButton(testBar); testBar.stop:SetPoint("BOTTOM", 0, 9)
    end
    testBar.label:SetText("Testing: |cffffffff" .. (name or "cue") .. "|r")
    testBar.stop:Configure("Stop Test", 130, 24, "primary", onStop)
    testBar:Show()
end

function TCC.HideTestControls()
    if testBar then testBar:Hide() end
end

----------------------------------------------------------------------
-- Minimap button (self-contained; no LibDBIcon dependency)
----------------------------------------------------------------------
function TCC.InitMinimap()
    if TCC._minimap or not Minimap then return end
    local db = TCC.db
    db.minimap = db.minimap or { angle = 214, hide = false }

    local mb = CreateFrame("Button", "TwistedsCombatCuesMinimapButton", Minimap)
    mb:SetSize(31, 31); mb:SetFrameStrata("MEDIUM"); mb:SetFrameLevel(8)
    mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mb:RegisterForDrag("LeftButton")

    local overlay = mb:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
    local bg = mb:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetPoint("CENTER", 1, 1)
    local icon = mb:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19); icon:SetPoint("CENTER", 1, 1); icon:SetTexture(LOGO_PATH)
    if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    local function updatePos()
        local a = math.rad(db.minimap.angle or 214)
        local r = (Minimap:GetWidth() / 2) + 5
        mb:ClearAllPoints()
        mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end

    mb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            if mx and cx then
                db.minimap.angle = math.deg(math.atan2((cy / scale) - my, (cx / scale) - mx))
                updatePos()
            end
        end)
    end)
    mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mb:SetScript("OnClick", function(_, button)
        if button == "RightButton" then TCC.OpenManager("global") else TCC.ToggleManager() end
    end)
    mb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Twisteds Combat Cues", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open the Cue Manager", 0.8, 0.85, 0.92)
        GameTooltip:AddLine("Right-click: global options", 0.8, 0.85, 0.92)
        GameTooltip:AddLine("Drag: reposition on the minimap", 0.6, 0.62, 0.68)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", GameTooltip_Hide)

    TCC._minimap = mb
    updatePos()
    if db.minimap.hide then mb:Hide() end
end

function TCC.SetMinimapHidden(hide)
    TCC.db.minimap = TCC.db.minimap or {}
    TCC.db.minimap.hide = hide and true or false
    if TCC._minimap then if hide then TCC._minimap:Hide() else TCC._minimap:Show() end end
end

----------------------------------------------------------------------
-- Spell / buff picker popup (styled to match)
----------------------------------------------------------------------
-- The spell/item databases live in a Load-on-Demand companion addon so they cost
-- nothing until the picker is first used.
local DATA_ADDON = "TwistedsCombatCues_DB"
local dataLoaded
local function ensureDataLoaded()
    if dataLoaded ~= nil then return dataLoaded end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    dataLoaded = loader and (loader(DATA_ADDON) and true or false) or false
    return dataLoaded
end

-- We deliberately DO NOT build a persistent Lua index of the ~165k spells (that
-- was the ~10 MB bloat). Instead we scan the resident blob string on demand. The
-- only steady-state cost is the blob itself (held by the LoD data addon); search
-- allocations are transient (one line at a time) and collected after the search.

local function scanAuras(filter, lower, add)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for i = 1, 60 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if not a then break end
        if a.name and a.spellId and a.name:lower():find(lower, 1, true) then add(a.spellId, a.name, a.icon) end
    end
end

local function scanSpellbook(lower, add)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for l = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(l)
        if line then
            for s = (line.itemIndexOffset or 0) + 1, (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0) do
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, s, bank)
                if ok and info and info.spellID then
                    local si = C_Spell.GetSpellInfo(info.spellID)
                    local nm = (si and si.name) or info.name
                    if nm and nm:lower():find(lower, 1, true) then add(info.spellID, nm, (si and si.iconID) or info.iconID) end
                end
            end
        end
    end
end

local PP = {}
function TCC._pickerRebuild(text)
    local p = TCC._picker; if not p then return end
    local mode = p._mode or "spell"
    releaseAll(PP)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local results, seen = {}, {}
    local function add(id, name, icon)
        if id and name and not seen[id] then seen[id] = true; results[#results + 1] = { id = id, name = name, icon = icon } end
    end
    if text ~= "" then
        local num = tonumber(text)
        local lower = text:lower()
        if mode == "item" then
            if num then local _, nm, ic = TCC.ResolveItem(num); add(num, nm or ("Item " .. num), ic) end
            if #text >= 3 and ensureDataLoaded() then
                local blob = _G.TCC_ITEMDB_BLOB
                if blob then
                    for line in blob:gmatch("[^\n]+") do
                        if #results >= 250 then break end
                        local sep = line:find("\t", 1, true)
                        if sep and line:sub(sep + 1):lower():find(lower, 1, true) then
                            add(tonumber(line:sub(1, sep - 1)), line:sub(sep + 1))
                        end
                    end
                end
            end
        else
            if num then local info = C_Spell.GetSpellInfo(num); if info then add(info.spellID or num, info.name, info.iconID) end end
            scanAuras("HELPFUL", lower, add); scanAuras("HARMFUL", lower, add); scanSpellbook(lower, add)
            if #text >= 3 and ensureDataLoaded() then
                local blob = _G.TCC_SPELLDB_BLOB
                if blob then
                    for line in blob:gmatch("[^\n]+") do
                        if #results >= 250 then break end
                        local sep = line:find("\t", 1, true)
                        if sep and line:sub(sep + 1):lower():find(lower, 1, true) then
                            add(tonumber(line:sub(1, sep - 1)), line:sub(sep + 1))
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)

    local y, shown = -2, 0
    for _, r in ipairs(results) do
        if shown >= 80 then break end
        shown = shown + 1
        local btn = acq(PP, "row", function()
            local b = CreateFrame("Button", nil, p.child)
            b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18); b.hl:Hide()
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 4, 0); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.label = b:CreateFontString(nil, "OVERLAY"); b.label:SetFont(FONT, 12)
            b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.label:SetPoint("RIGHT", -4, 0); b.label:SetJustifyH("LEFT")
            b:SetScript("OnEnter", function(self) self.hl:Show() end)
            b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip_Hide() end)
            return b
        end)
        btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", 0, y); btn:SetPoint("RIGHT", p.child, "RIGHT", 0, 0); btn:SetHeight(22)
        local tex = r.icon
        if not tex then
            if mode == "item" then tex = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.id)) or nil
            else local si = C_Spell.GetSpellInfo(r.id); tex = si and si.iconID end
        end
        btn.icon:SetTexture(tex or QMARK)
        btn.label:SetText(string.format("%s  |cff7f8896%d|r", r.name, r.id))
        btn.label:SetTextColor(unpack(C.text))
        btn:SetScript("OnClick", function() if p._onPick then p._onPick(r.id, r.name) end p:Hide() end)
        btn:SetScript("OnEnter", function(self)
            self.hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if mode == "item" then GameTooltip:SetItemByID(r.id) else GameTooltip:SetSpellByID(r.id) end
            GameTooltip:Show()
        end)
        y = y - 22
    end

    p.empty:SetShown(shown == 0)
    if shown == 0 then
        local thing = (mode == "item") and "item" or "spell/buff"
        if text == "" then p.empty:SetText("Type a " .. thing .. " name, a partial (3+ letters), or an ID.")
        elseif #text < 3 then p.empty:SetText("Type at least 3 letters to search the full database, or paste an ID.")
        else p.empty:SetText("No matches. Check spelling, try fewer letters, or paste an ID.") end
    end
    p.child:SetHeight(math.max(1, -y + 2))
end

function TCC.OpenSpellPicker(anchor, current, onPick, mode)
    local p = TCC._picker
    if not p then
        p = CreateFrame("Frame", "TwistedsCombatCuesSpellPicker", UIParent)
        TCC._picker = p
        p:SetSize(320, 400); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetToplevel(true); p:SetClampedToScreen(true)
        stylePanel(p, C.panel, C.border)
        p:EnableMouse(true); p:SetMovable(true)
        tinsert(UISpecialFrames, "TwistedsCombatCuesSpellPicker")
        -- Reclaim the transient garbage from scanning the DB after the picker closes.
        p:SetScript("OnHide", function()
            if TCC._pickerTimer then TCC._pickerTimer:Cancel() end
            C_Timer.After(2, function() collectgarbage("collect") end)
        end)

        local hd = CreateFrame("Button", nil, p); hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(28)
        local hbg = hd:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); paint(hbg, C.card)
        hd:RegisterForDrag("LeftButton")
        hd:SetScript("OnDragStart", function() p:StartMoving() end)
        hd:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
        local t = hd:CreateFontString(nil, "OVERLAY"); t:SetFont(FONT, 13); t:SetPoint("LEFT", 10, 0)
        t:SetText("Find Spell / Buff"); t:SetTextColor(unpack(C.text))
        p.title = t
        local x = makeButton(p); x:Configure("X", 24, 22, "danger", function() p:Hide() end); x:SetPoint("TOPRIGHT", -4, -4)
        x:SetFrameLevel(hd:GetFrameLevel() + 5)

        local sb = makeEdit(p); sb:Configure(292, 24, "", nil); sb:ClearAllPoints(); sb:SetPoint("TOP", 0, -34)
        sb:SetScript("OnTextChanged", function(self)
            local t = self:GetText()
            if TCC._pickerTimer then TCC._pickerTimer:Cancel() end
            TCC._pickerTimer = C_Timer.NewTimer(0.15, function() TCC._pickerRebuild(t) end)
        end)
        sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        p.search = sb

        local sf = CreateFrame("ScrollFrame", nil, p)
        sf:SetPoint("TOPLEFT", 10, -66); sf:SetPoint("BOTTOMRIGHT", -10, 12)
        local child = CreateFrame("Frame", nil, sf); child:SetSize(290, 1); sf:SetScrollChild(child)
        sf:EnableMouseWheel(true); sf:SetScript("OnMouseWheel", scrollWheel)
        p.child = child

        local empty = child:CreateFontString(nil, "OVERLAY"); empty:SetFont(FONT, 11)
        empty:SetPoint("TOPLEFT", 4, -6); empty:SetPoint("RIGHT", -4, 0); empty:SetJustifyH("LEFT"); empty:SetTextColor(unpack(C.subtext))
        p.empty = empty
    end

    p._onPick = onPick
    p._mode = mode or "spell"
    if p.title then p.title:SetText(p._mode == "item" and "Find Item" or "Find Spell / Buff") end
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    p:Show()
    p.search:SetText(current and tostring(current) or "")
    TCC._pickerRebuild(p.search:GetText())
    p.search:SetFocus()
end
