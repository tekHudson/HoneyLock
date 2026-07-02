--[[
	DemonForm.lua - drop SoD demon form (Metamorphosis) at a flight master.

	Warlock demon form counts as a shapeshift, which blocks taxi use. The
	protected CancelShapeshiftForm() API can't be called from addon code, but
	running the `/cancelform` slash command via ChatEdit_SendText is unprotected
	and works out of combat -- which is when you talk to a flight master.

	Approach (same as the LetMeTaxi addon): when the taxi interaction is refused
	because we're shapeshifted, or the taxi map opens, send `/cancelform`.
]]

local NL = _G.HoneyLock

NL:RegisterDefaults({
	demonForm = {
		dropAtFlightMaster = true,
	},
})

-- Run a slash command from insecure code (out of combat only).
local function runSlash(cmd)
	if InCombatLockdown() then return end
	local eb = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
	if eb and ChatEdit_SendText then
		eb:SetText(cmd)
		ChatEdit_SendText(eb, 0)
	end
end

local function cancelForm()
	runSlash("/cancelform")
end

function NL:InitDemonForm()
	-- Taxi interaction refused while shapeshifted -> drop the form. Clicking
	-- the flight master option again then opens the taxi map.
	self:RegisterEvent("UI_ERROR_MESSAGE", function(_, arg1, arg2)
		if not self.db.demonForm.dropAtFlightMaster then return end
		local code = (type(arg1) == "number" and arg1) or nil   -- classic: (errType, msg)
		local msg  = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
		if code == ERR_TAXIPLAYERSHAPESHIFTED
			or (msg and ERR_TAXIPLAYERSHAPESHIFTED and msg == ERR_TAXIPLAYERSHAPESHIFTED) then
			cancelForm()
		end
	end)

	-- If the taxi map does open (e.g. dropped just in time), make sure we're
	-- out of form so the flight actually works.
	self:RegisterEvent("TAXIMAP_OPENED", function()
		if self.db.demonForm.dropAtFlightMaster then cancelForm() end
	end)
end
