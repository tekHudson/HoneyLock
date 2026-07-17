--[[
	Options.lua - a native Blizzard options panel (pure Lua, no XML, no AceGUI).

	Builds a canvas frame with standard checkboxes/sliders and registers it
	with the Settings system (Era 1.15). Falls back to the legacy
	InterfaceOptions API if needed.
]]

local HL = _G.HoneyLock

------------------------------------------------------------------------
-- Small widget helpers (Blizzard templates)
------------------------------------------------------------------------

local function newCheckbox(parent, label, tooltip, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb.Text:SetText(label)
	if cb.tooltipText ~= nil then cb.tooltipText = tooltip end
	cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb:SetChecked(get())
	return cb
end

local sliderCount = 0
local function newSlider(parent, label, minV, maxV, step, get, set)
	sliderCount = sliderCount + 1
	local name = "HoneyLockSlider" .. sliderCount
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetWidth(200)
	-- Resolve the template's label regions (named $parentLow/High/Text), with a
	-- fallback to the direct properties newer clients expose on the slider.
	s.Low  = _G[name .. "Low"]  or s.Low
	s.High = _G[name .. "High"] or s.High
	s.Text = _G[name .. "Text"] or s.Text
	if s.Text then s.Text:SetText(label) end
	if s.Low then s.Low:SetText(minV) end
	if s.High then s.High:SetText(maxV) end
	s:SetScript("OnShow", function(self) self:SetValue(get()) end)
	s:SetValue(get())
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		set(v)
	end)
	return s
end

local ddCount = 0
local function newDropdown(parent, label, choices, get, set)
	ddCount = ddCount + 1
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetText(label)
	local dd = CreateFrame("Frame", "HoneyLockDropdown" .. ddCount, parent, "UIDropDownMenuTemplate")
	dd.title = title

	local function textFor(value)
		for _, c in ipairs(choices) do if c.value == value then return c.text end end
		return tostring(value)
	end
	UIDropDownMenu_SetWidth(dd, 150)
	UIDropDownMenu_Initialize(dd, function()
		for _, c in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = c.text
			info.checked = (get() == c.value)
			info.func = function()
				set(c.value)
				UIDropDownMenu_SetText(dd, c.text)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	dd:SetScript("OnShow", function() UIDropDownMenu_SetText(dd, textFor(get())) end)
	UIDropDownMenu_SetText(dd, textFor(get()))
	-- expose a positioning anchor (the label sits just above the dropdown)
	dd.PlaceAt = function(_, px, py)
		title:SetPoint("TOPLEFT", parent, "TOPLEFT", px + 18, py)
		dd:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py - 16)
	end
	return dd
end

-- Available counter fonts (files present in every WoW client).
local FONT_CHOICES = {
	{ text = "Friz Quadrata (default)", value = "Fonts\\FRIZQT__.TTF" },
	{ text = "Arial Narrow",            value = "Fonts\\ARIALN.TTF" },
	{ text = "Skurri",                  value = "Fonts\\SKURRI.TTF" },
	{ text = "Morpheus",                value = "Fonts\\MORPHEUS.TTF" },
}

-- A small numeric (integer) input box with a label.
local function newIntBox(parent, label, minV, maxV, get, set)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetText(label)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetAutoFocus(false)
	eb:SetNumeric(true)
	eb:SetMaxLetters(3)
	eb:SetSize(44, 20)
	eb.title = title
	local function commit()
		local v = tonumber(eb:GetText()) or get()
		if minV then v = math.max(minV, v) end
		if maxV then v = math.min(maxV, v) end
		set(v)
		eb:SetText(tostring(v))
		eb:ClearFocus()
	end
	eb:SetScript("OnEnterPressed", commit)
	eb:SetScript("OnEditFocusLost", commit)
	eb:SetScript("OnShow", function() eb:SetText(tostring(get())) end)
	eb:SetText(tostring(get()))
	eb.PlaceAt = function(_, px, py)
		title:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
		eb:SetPoint("LEFT", title, "RIGHT", 10, 0)
	end
	return eb
end

------------------------------------------------------------------------
-- Build panel
------------------------------------------------------------------------

local function buildPanel()
	local panel = CreateFrame("Frame", "HoneyLockOptionsPanel", UIParent)
	panel.name = "HoneyLock"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("HoneyLock " .. tostring(HL.version))

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("Lightweight warlock helper for Season of Discovery.")

	-- Everything below the title scrolls -- the panel has grown past a single
	-- screen's worth of content, so it can no longer all fit statically.
	local scroll = CreateFrame("ScrollFrame", "HoneyLockOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -60)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -27, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(760, 1)   -- height is finalized once every row is laid out
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, w) if w > 0 then content:SetWidth(w) end end)

	-- Two-column layout with section headers for a compact, tidy panel.
	local COL1, COL2 = 22, 320
	local ROW = 26
	local y = -4

	local function header(text)
		y = y - 12
		local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		h:SetPoint("TOPLEFT", 16, y)
		h:SetText("|cffffd100" .. text .. "|r")
		local line = content:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 0.82, 0, 0.25)
		line:SetPoint("TOPLEFT", 16, y - 16)
		line:SetPoint("TOPRIGHT", content, "TOPLEFT", 560, y - 16)
		line:SetHeight(1)
		y = y - 22
	end

	-- Place a checkbox at a column on the current row (does not advance y).
	local function put(col, label, tooltip, get, set)
		local c = newCheckbox(content, label, tooltip, get, set)
		c:SetPoint("TOPLEFT", content, "TOPLEFT", col, y)
		return c
	end
	local function nextRow() y = y - ROW end

	-- Setter helper for per-button visibility toggles.
	local function showGet(key) return function() return HL.db.bar.show[key] end end
	local function showSet(key)
		return function(v)
			HL.db.bar.show[key] = v
			if InCombatLockdown() then HL.deferredRefresh = true else HL:LayoutBar() end
		end
	end

	header("Bar")
	put(COL1, "Show bar", "Toggle the warlock button bar.",
		function() return HL.db.bar.shown end,
		function(v) HL.db.bar.shown = v; HL:RefreshBar() end)
	put(COL2, "Lock position", "Prevent dragging the bar.",
		function() return HL.db.bar.locked end,
		function(v) HL.db.bar.locked = v end)
	nextRow()

	header("Buttons")
	put(COL1, "Buff menu", nil, showGet("buffmenu"), showSet("buffmenu"))
	put(COL2, "Pet menu", nil, showGet("petmenu"), showSet("petmenu"))
	nextRow()
	put(COL1, "Utility menu", "Rituals, Eye, Banish, stone creation.", showGet("utility"), showSet("utility"))
	put(COL2, "Mount", nil, showGet("mount"), showSet("mount"))
	nextRow()

	header("Menu defaults (left-click cast)")
	local function menuChoices(key)
		local t = {}
		for _, usage in ipairs(HL.MenuUsages[key]) do
			t[#t + 1] = { text = HL:GetCastName(usage) or usage, value = usage }
		end
		return t
	end
	local buffDD = newDropdown(panel, "Buff menu", menuChoices("buffmenu"),
		function() return HL.db.bar.menuDefault.buffmenu end,
		function(v) HL:SetMenuDefault("buffmenu", v) end)
	buffDD:PlaceAt(COL1 - 4, y)
	local petDD = newDropdown(panel, "Pet menu", menuChoices("petmenu"),
		function() return HL.db.bar.menuDefault.petmenu end,
		function(v) HL:SetMenuDefault("petmenu", v) end)
	petDD:PlaceAt(COL2 - 4, y)
	y = y - 52
	local utilDD = newDropdown(panel, "Utility menu", menuChoices("utility"),
		function() return HL.db.bar.menuDefault.utility end,
		function(v) HL:SetMenuDefault("utility", v) end)
	utilDD:PlaceAt(COL1 - 4, y)
	y = y - 48

	header("Soul shards")
	put(COL1, "Shard counter", "Show the shard count below the logo.",
		function() return HL.db.shards.showCounter end,
		function(v) HL.db.shards.showCounter = v; HL:UpdateShardDisplay() end)
	put(COL2, "Auto-organize", "Move loose shards into a soul bag.",
		function() return HL.db.shards.organize end,
		function(v) HL.db.shards.organize = v end)
	nextRow()
	put(COL1, "Show shard limit", "Show count as current/limit and warn when over.",
		function() return HL.db.shards.autoDestroy end,
		function(v) HL.db.shards.autoDestroy = v; HL:UpdateShardDisplay() end)
	local keepBox = newIntBox(panel, "Limit", 0, 999,
		function() return HL.db.shards.keep end,
		function(v) HL.db.shards.keep = v; HL:UpdateShardDisplay() end)
	keepBox:PlaceAt(COL2, y + 2)
	nextRow()
	-- counter font (dropdown) + size (integer)
	local fontDD = newDropdown(panel, "Counter font", FONT_CHOICES,
		function() return HL.db.shards.font end,
		function(v) HL.db.shards.font = v; HL:UpdateShardDisplay() end)
	fontDD:PlaceAt(COL1 - 4, y)
	local sizeBox = newIntBox(panel, "Size", 6, 48,
		function() return HL.db.shards.fontSize end,
		function(v) HL.db.shards.fontSize = v; HL:UpdateShardDisplay() end)
	sizeBox:PlaceAt(COL2, y - 16)
	y = y - 48

	header("Timers & alerts")
	put(COL1, "Timers", "Show Soulstone / Banish / Enslave timers.",
		function() return HL.db.timers.enabled end,
		function(v) HL.db.timers.enabled = v; if not v then HL:ClearTimers() end end)
	put(COL2, "Nightfall flash", "Flash when Shadow Trance procs.",
		function() return HL.db.alerts.nightfall end,
		function(v) HL.db.alerts.nightfall = v; if not v then HL:HideNightfall() end end)
	nextRow()
	put(COL1, "Nightfall sound", nil,
		function() return HL.db.alerts.sound end,
		function(v) HL.db.alerts.sound = v end)
	local soundDD = newDropdown(panel, "Sound", HL.NIGHTFALL_SOUND_CHOICES,
		function() return HL.db.alerts.soundId end,
		function(v) HL.db.alerts.soundId = v end)
	soundDD:PlaceAt(COL2 - 4, y)
	y = y - 48

	header("Season of Discovery")
	put(COL1, "Drop demon form at flight master", "Cancel Metamorphosis when a flight path is refused due to form.",
		function() return HL.db.demonForm.dropAtFlightMaster end,
		function(v) HL.db.demonForm.dropAtFlightMaster = v end)
	put(COL2, "Drop demon form to mount", "Cancel Metamorphosis before mounting (bag item, action button, or the HL mount button).",
		function() return HL.db.demonForm.dropOnMount end,
		function(v) HL.db.demonForm.dropOnMount = v end)
	nextRow()

	header("Display")
	y = y - 18
	local scale = newSlider(panel, "Bar scale", 0.5, 2.0, 0.05,
		function() return HL.db.bar.scale end,
		function(v) HL.db.bar.scale = v; HL:RefreshBar() end)
	scale:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1 + 8, y)

	return panel
end

------------------------------------------------------------------------
-- Register + open
------------------------------------------------------------------------

function HL:InitOptions()
	if self.optionsPanel then return end
	local panel = buildPanel()
	self.optionsPanel = panel

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		category.ID = panel.name
		Settings.RegisterAddOnCategory(category)
		self.settingsCategory = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function HL:OpenOptions()
	self:InitOptions()
	if Settings and Settings.OpenToCategory and self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory.ID or self.settingsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(self.optionsPanel) -- twice: Blizzard bug
	end
end
