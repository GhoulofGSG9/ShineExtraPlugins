--[[
	Shine Custom Timeout plugin.
]]

local Shine = Shine

local GetOwner = Server.GetOwner
local SharedTime = Shared.GetTime

local Plugin = Plugin
Plugin.Version = "1.0"
Plugin.PrintName = "CustomTimeout"

Plugin.HasConfig = true
Plugin.ConfigName = "CustomTimeout.json"

Plugin.DefaultConfig = {
	Timeout = 15,
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	if not self.Users then
		self.Users = Shine.Map()
	end

	-- Reset/Refresh client map
	local Time = SharedTime()

	for Client, DataTable in self.Users:Iterate() do
		if Shine:IsValidClient( Client ) then
			DataTable.LastMove = Time
		else
			self.Users:Remove( Client )
		end
	end

	local Clients, Count = Shine.GetAllClients()
	for i = 1, Count do
		local Client = Clients[ i ]
		if not self.Users:Get( Client ) then
			self:ClientConnect( Client )
		end
	end

	-- Evaluate players every second
	self:CreateTimer( "TimeoutCheck", 1, -1, function() self:EvaluatePlayers() end )

	self.Enabled = true

	return true

end

function Plugin:KickClient( Client )
	Client.DisconnectReason = "Timeout"
	Server.DisconnectClient( Client, Client.DisconnectReason )
end

function Plugin:EvaluatePlayers()
	local Time = SharedTime()

	for Client, DataTable in self.Users:Iterate() do
		self:EvaluatePlayer( Client, DataTable, Time )
	end
end

--[[
	Check if a player has been inactive for too long and disconnect them
]]
function Plugin:EvaluatePlayer( Client, DataTable, Now )
	if Now - DataTable.LastMove >= self.Config.Timeout then
		self:KickClient( Client )
	end
end

--[[
	On client connect, add the client to our map of clients.
]]
function Plugin:ClientConnect( Client )
	if not Client then return end

	if Client:GetIsVirtual() then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	self.Users:Add( Client , {
		LastMove = SharedTime(),
	})
end

--[[
	Hook into movement processing to detect inactive clients.
]]
function Plugin:OnProcessMove( Player )

	local Client = GetOwner( Player )

	if not Client then return end
	if Client:GetIsVirtual() then return end

	local DataTable = self.Users:Get( Client )
	if not DataTable then return end

	local Time = SharedTime()
	if DataTable.LastMove > Time then return end

	DataTable.LastMove = Time
end

--[[
	When a client disconnects, remove them from the player map.
]]
function Plugin:ClientDisconnect( Client )
	self.Users:Remove( Client )
end
