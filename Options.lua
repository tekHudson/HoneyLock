--[[
	Options.lua - a native Blizzard options panel (pure Lua, no XML, no AceGUI).

	Builds a canvas frame with standard checkboxes/sliders and registers it
	with the Settings system (Era 1.15). Falls back to the legacy
	InterfaceOptions API if needed.
]]

local NL = _G.HoneyLock

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

------------------------------------------------------------------------
-- Build panel
------------------------------------------------------------------------

local function buildPanel()
	local panel = CreateFrame("Frame", "HoneyLockOptionsPanel", UIParent)
	panel.name = "HoneyLock"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("HoneyLock " .. tostring(NL.version))

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("Lightweight warlock helper for Season of Discovery.")

	local y = -60
	local function place(widget, indent)
		widget:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (indent or 0), y)
		y = y - 32
		return widget
	end

	-- Bar
	place(newCheckbox(panel, "Show bar", "Toggle the warlock button bar.",
		function() return NL.db.bar.shown end,
		function(v) NL.db.bar.shown = v; NL:RefreshBar() end))

	place(newCheckbox(panel, "Lock bar position", "Prevent dragging the bar.",
		function() return NL.db.bar.locked end,
		function(v) NL.db.bar.locked = v end))

	-- per-button visibility
	local toggles = {
		{ "spellstone", "Show Spellstone button" },
		{ "firestone",  "Show Firestone button" },
		{ "buffmenu",   "Show Buff menu" },
		{ "petmenu",    "Show Pet menu" },
		{ "mount",      "Show Mount button" },
		{ "destroy",    "Show Destroy-shards button" },
	}
	for _, t in ipairs(toggles) do
		local key = t[1]
		place(newCheckbox(panel, t[2], nil,
			function() return NL.db.bar.show[key] end,
			function(v)
				NL.db.bar.show[key] = v
				if InCombatLockdown() then NL.deferredRefresh = true else NL:LayoutBar() end
			end), 12)
	end

	y = y - 8
	place(newCheckbox(panel, "Show soul shard counter", nil,
		function() return NL.db.shards.showCounter end,
		function(v) NL.db.shards.showCounter = v; NL:UpdateShardDisplay() end))

	place(newCheckbox(panel, "Auto-organize shards into soul bag", nil,
		function() return NL.db.shards.organize end,
		function(v) NL.db.shards.organize = v end))

	y = y - 8
	place(newCheckbox(panel, "Timers enabled", nil,
		function() return NL.db.timers.enabled end,
		function(v) NL.db.timers.enabled = v end))

	y = y - 8
	place(newCheckbox(panel, "Nightfall alert", "Flash when Shadow Trance procs.",
		function() return NL.db.alerts.nightfall end,
		function(v) NL.db.alerts.nightfall = v; if not v then NL:HideNightfall() end end))

	place(newCheckbox(panel, "Nightfall sound", nil,
		function() return NL.db.alerts.sound end,
		function(v) NL.db.alerts.sound = v end))

	y = y - 24
	local scale = place(newSlider(panel, "Bar scale", 0.5, 2.0, 0.05,
		function() return NL.db.bar.scale end,
		function(v) NL.db.bar.scale = v; NL:RefreshBar() end))

	return panel
end

------------------------------------------------------------------------
-- Register + open
------------------------------------------------------------------------

function NL:InitOptions()
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

function NL:OpenOptions()
	self:InitOptions()
	if Settings and Settings.OpenToCategory and self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory.ID or self.settingsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(self.optionsPanel) -- twice: Blizzard bug
	end
end
