--[[
	Alerts.lua - Nightfall (Shadow Trance) proc alert.

	When the Shadow Trance buff appears on the player, flash its icon in the
	center of the screen (pulsing) and optionally play a sound. Hides when the
	buff is consumed/expires. No custom textures (uses the spell's own icon).
]]

local NL = _G.HoneyLock

NL:RegisterDefaults({
	alerts = {
		nightfall = true,
		sound = true,
		scale = 1.0,
	},
})

local function findShadowTrance()
	local name = NL.SHADOW_TRANCE_NAME
	if not name then return false end
	if AuraUtil and AuraUtil.FindAuraByName then
		return AuraUtil.FindAuraByName(name, "player") ~= nil
	end
	-- Fallback: classic buff scan
	for i = 1, 40 do
		local n = UnitBuff("player", i)
		if not n then break end
		if n == name then return true end
	end
	return false
end

local function ensureFrame()
	if NL.nightfallFrame then return NL.nightfallFrame end
	local f = CreateFrame("Frame", "HoneyLockNightfall", UIParent)
	f:SetSize(64, 64)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
	f:Hide()

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture((select(3, GetSpellInfo(NL.SHADOW_TRANCE_SPELLID))) or "Interface\\Icons\\Spell_Shadow_Twilight")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.icon = icon

	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("TOP", f, "BOTTOM", 0, -2)
	label:SetText("Nightfall!")
	f.label = label

	-- pulse animation
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local pulse = ag:CreateAnimation("Scale")
	pulse:SetDuration(0.5)
	if pulse.SetScaleTo then
		pulse:SetScaleTo(1.2, 1.2)
	else
		pulse:SetFromScale(1, 1); pulse:SetToScale(1.2, 1.2)
	end
	pulse:SetOrigin("CENTER", 0, 0)
	f.pulse = ag

	NL.nightfallFrame = f
	return f
end

function NL:ShowNightfall()
	if not self.db.alerts.nightfall then return end
	local f = ensureFrame()
	f:SetScale(self.db.alerts.scale)
	f:Show()
	if f.pulse then f.pulse:Play() end
	if self.db.alerts.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
	end
end

function NL:HideNightfall()
	if self.nightfallFrame then
		if self.nightfallFrame.pulse then self.nightfallFrame.pulse:Stop() end
		self.nightfallFrame:Hide()
	end
end

-- Called from the aura event handler.
function NL:CheckNightfall()
	local has = findShadowTrance()
	if has and not self.nightfallActive then
		self.nightfallActive = true
		self:ShowNightfall()
	elseif (not has) and self.nightfallActive then
		self.nightfallActive = false
		self:HideNightfall()
	end
end
