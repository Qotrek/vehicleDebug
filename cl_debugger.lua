Debugger = {
	speed = 0.0,
	bestAccelTime = 0.0,
	bestDecelTime = 0.0,
	accelTimerStart = nil,
	decelTimerStart = nil,
	toggle = false,
	toggleOn = Config.EnabledByDefault
}

--[[ Functions ]]--
function TruncateNumber(value)
	value = value * Config.Precision

	return (value % 1.0 > 0.5 and math.ceil(value) or math.floor(value)) / Config.Precision
end

function Debugger:Set(vehicle)
	self.vehicle = vehicle
	self:ResetStats()

	local handlingText = ""

	-- Loop fields.
	for key, field in pairs(Config.Fields) do
		-- Get field type.
		local fieldType = Config.Types[field.type]
		if fieldType == nil then error("no field type") end

		-- Get value.
		local value = fieldType.getter(vehicle, "CHandlingData", field.name)
		if type(value) == "vector3" then
			value = ("%s,%s,%s"):format(value.x, value.y, value.z)
		elseif field.type == "float" then
			value = TruncateNumber(value)
		end

		-- Get input.
		local input = ([[
			<input
				oninput='updateHandling(this.id, this.value)'
				id='%s'
				value=%s
			>
			</input>
		]]):format(key, value)

		-- Append text.
		handlingText = handlingText..([[
			<div class='tooltip'><span class='tooltip-text'>%s</span><span>%s</span>%s</div>
		]]):format(field.description or "Unspecified.", field.name, input)
	end

	-- Update text.
	self:Invoke("updateText", {
		["handling-fields"] = handlingText,
	})
end

function Debugger:UpdateVehicle()
	local ped = PlayerPedId()
	local isInVehicle = IsPedInAnyVehicle(ped, false)
	local vehicle = isInVehicle and GetVehiclePedIsIn(ped, false)

	if self.isInVehicle ~= isInVehicle or self.vehicle ~= vehicle then
		self.vehicle = vehicle
		self.isInVehicle = isInVehicle

		if isInVehicle and DoesEntityExist(vehicle) then
			self:Set(vehicle)
		end
	end
end

function Debugger:UpdateInput()
	if self.hasFocus then
		DisableControlAction(0, 1)
		DisableControlAction(0, 2)
	end
end

function Debugger:UpdateAverages()
	if not DoesEntityExist(self.vehicle or 0) then return end

	local speed = GetEntitySpeed(self.vehicle)
	local speedKmh = speed * 3.6

	-- 0-100 km/h logic
	if speedKmh < 1.0 then
		-- Vehicle is stationary, reset timer until we actually start moving
		self.accelTimerStart = nil
	elseif speedKmh >= 1.0 and speedKmh < 100.0 then
		if not self.accelTimerStart then
			-- Start timer only if speed is very low (e.g. just started moving from 0)
			-- Otherwise they were just cruising and we shouldn't start 0-100
			if speedKmh < 5.0 and IsControlPressed(0, 71) then
				self.accelTimerStart = GetGameTimer()
			end
		else
			-- We are measuring, cancel if they stop accelerating
			if not IsControlPressed(0, 71) then
				self.accelTimerStart = nil
			end
		end
	elseif speedKmh >= 100.0 then
		if self.accelTimerStart then
			local time = (GetGameTimer() - self.accelTimerStart) / 1000.0
			if self.bestAccelTime == 0.0 or time < self.bestAccelTime then
				self.bestAccelTime = time
			end
			self.accelTimerStart = nil
		end
	end

	-- Deceleration logic (Braking to 0)
	if speedKmh > 1.0 then
		if IsControlPressed(0, 72) then
			if not self.decelTimerStart then
				self.decelTimerStart = GetGameTimer()
			end
		else
			-- Cancel if they stop braking
			self.decelTimerStart = nil
		end
	elseif speedKmh <= 1.0 then
		if self.decelTimerStart then
			local time = (GetGameTimer() - self.decelTimerStart) / 1000.0
			if self.bestDecelTime == 0.0 or time < self.bestDecelTime then
				self.bestDecelTime = time
			end
			self.decelTimerStart = nil
		end
	end

	-- Set tops.
	self.speed = math.max(self.speed, speed)

	-- Format texts for UI
	local accelText = self.bestAccelTime > 0.0 and string.format("%.2f s", self.bestAccelTime) or "N/A"
	if self.accelTimerStart then
		local currentAccelTime = (GetGameTimer() - self.accelTimerStart) / 1000.0
		accelText = string.format("%.2f s (Pomiar...)", currentAccelTime)
	end

	local decelText = self.bestDecelTime > 0.0 and string.format("%.2f s", self.bestDecelTime) or "N/A"
	if self.decelTimerStart then
		local currentDecelTime = (GetGameTimer() - self.decelTimerStart) / 1000.0
		decelText = string.format("%.2f s (Pomiar...)", currentDecelTime)
	end

	-- Update text.
	self:Invoke("updateText", {
		["top-speed"] = string.format("%.2f", self.speed * 3.6),
		["top-accel"] = accelText,
		["top-decel"] = decelText,
	})
end

function Debugger:ResetStats()
	self.speed = 0.0
	self.bestAccelTime = 0.0
	self.bestDecelTime = 0.0
	self.accelTimerStart = nil
	self.decelTimerStart = nil
end

function Debugger:SetHandling(key, value)
	if not DoesEntityExist(self.vehicle or 0) then return end

	-- Get field.
	local field = Config.Fields[key]
	if field == nil then error("no field") end

	-- Get field type.
	local fieldType = Config.Types[field.type]
	if fieldType == nil then error("no field type") end

	-- Set field.
	fieldType.setter(self.vehicle, "CHandlingData", field.name, value)

	-- Needed for some values to work.
	ModifyVehicleTopSpeed(self.vehicle, 1.0)
end

function Debugger:CopyHandling()
	local text = ""

	-- Line writer.
	local function writeLine(append)
		if text ~= "" then
			text = text.."\n\t\t\t"
		end
		text = text..append
	end

	-- Get vehicle.
	local vehicle = self.vehicle
	if not DoesEntityExist(vehicle) then return end

	-- Loop fields.
	for key, field in pairs(Config.Fields) do
		-- Get field type.
		local fieldType = Config.Types[field.type]
		if fieldType == nil then error("no field type") end

		-- Get value.
		local value = fieldType.getter(vehicle, "CHandlingData", field.name, true)
		local nValue = tonumber(value)

		-- Append text.
		if nValue ~= nil then
			writeLine(("<%s value=\"%s\" />"):format(field.name, field.type == "float" and TruncateNumber(nValue) or nValue))
		elseif field.type == "vector" then
			writeLine(("<%s x=\"%s\" y=\"%s\" z=\"%s\" />"):format(field.name, value.x, value.y, value.z))
		end
	end

	-- Copy text.
	self:Invoke("copyText", text)
end

function Debugger:Focus(toggle)
	if toggle and not DoesEntityExist(self.vehicle or 0) then return end

	SetNuiFocus(toggle, toggle)
	SetNuiFocusKeepInput(toggle)

	self.hasFocus = toggle
	self:Invoke("setFocus", toggle)
end

function Debugger:ToggleOn(toggleData)
	self.toggleOn = toggleData
	self:Invoke("toggle", toggleData)
	
	-- Close the UI if we're disabling
	if not toggleData and self.hasFocus then
		self:Focus(false)
	end
end

function Debugger:Invoke(_type, data)
	SendNUIMessage({
		callback = {
			type = _type,
			data = data,
		},
	})
end

--[[ Threads ]]--
Citizen.CreateThread(function()
	while true do
		Citizen.Wait(1000)
		Debugger:UpdateVehicle()
	end
end)

Citizen.CreateThread(function()
	while true do
		if Debugger.isInVehicle then
			Citizen.Wait(0)
			Debugger:UpdateInput()
			Debugger:UpdateAverages()
		else
			Citizen.Wait(500)
		end
	end
end)

--[[ NUI Events ]]--
RegisterNUICallback("updateHandling", function(data, cb)
	cb(true)
	Debugger:SetHandling(tonumber(data.key), data.value)
end)

RegisterNUICallback("copyHandling", function(data, cb)
	cb(true)
	Debugger:CopyHandling()
end)

RegisterNUICallback("resetStats", function(data, cb)
	cb(true)
	Debugger:ResetStats()
end)

--[[ Commands ]]
RegisterCommand("+vehicleDebug", function()
	if Debugger.toggleOn == false then return end
	Debugger:Focus(not Debugger.hasFocus)
end, true)

RegisterKeyMapping("+vehicleDebug", "Vehicle Debugger", "keyboard", Config.Keybind)

RegisterCommand("vehdebug", function()
	Debugger.toggleOn = not Debugger.toggleOn
	Debugger:ToggleOn(Debugger.toggleOn)
	TriggerEvent('chat:addMessage', {
		color = {255, 255, 0},
		multiline = true,
		args = {"Vehicle Debugger", Debugger.toggleOn and "Enabled" or "Disabled"}
	})
end, false)
