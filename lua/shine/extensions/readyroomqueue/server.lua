local Notify = Shared.Message

local TableConcat = table.concat

local Plugin = ...
Plugin.PrintName = "Ready Room Queue"

Plugin.HasConfig = true

Plugin.ConfigName = "ReadRoomQueue.json"
Plugin.DefaultConfig = {
    RestoreQueueAfterMapchange = true,
    QueuePositionMaxReservationTime = 300, -- how long we reserve a queue position after a map change.
    QueueHistoryLifeTime = 300 -- max amount of time the queue history is preserved after a mapchange. Increase/decrease this value based on server loading time
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.QueueHistoryFile = "config://shine/temp/rr_queue_history.json"

function Plugin:Initialise()
    self.Enabled = true

    self.PlayerQueue = Shine.Map()
    self.ReservedQueue = Shine.Map() -- for players with reserved slots

    self:LoadQueueHistory()

    self:CreateCommands()

    return true
end

function Plugin:LoadQueueHistory()
    self.HistoricPlayers = Shine.Set()

    if not self.Config.RestoreQueueAfterMapchange then return end

    local QueueHistory = Shine.LoadJSONFile( self.QueueHistoryFile ) or {}

    local now = Shared.GetSystemTime()

    local TimeStamp = QueueHistory.TimeStamp
    if not TimeStamp or tonumber( TimeStamp ) + self.Config.QueueHistoryLifeTime < now then
        return
    end

    if QueueHistory.PlayerQueue then
        for i = 1, #QueueHistory.PlayerQueue do
            local SteamId = QueueHistory.PlayerQueue[i]
            self.PlayerQueue:Add( SteamId, i )
            self.HistoricPlayers:Add( SteamId )
        end
    end

    if QueueHistory.ReservedQueue then
        for i = 1, #QueueHistory.ReservedQueue do
            local SteamId = QueueHistory.ReservedQueue[i]
            self.ReservedQueue:Add(SteamId, i)
        end
    end

    local function ClearHistory()
        self.HistoricPlayers = Shine.Set()

        self:UpdateQueuePositions( self.PlayerQueue )
        self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
    end

    self:SimpleTimer( self.Config.QueuePositionMaxReservationTime, ClearHistory )
end

function Plugin:SaveQueueHistory()
    local QueueHistory = {
        PlayerQueue = self.PlayerQueue:GetKeys(),
        ReservedQueue = self.ReservedQueue:GetKeys(),
        TimeStamp = Shared.GetSystemTime()
    }
    Shine.SaveJSONFile( QueueHistory, self.QueueHistoryFile )
end


function Plugin:OnFirstThink()
    Shine.Hook.SetupClassHook( "Gamerules", "GetCanJoinPlayingTeam", "OnGetCanJoinPlayingTeam", function( OldFunc, self, player, skipHook )
        local result = OldFunc( self, player )

        if not skipHook then
            Shine.Hook.Call( "OnGetCanJoinPlayingTeam", self, player, result )
        end

        return result
    end )

    Shine.Hook.SetupClassHook( "NS2Gamerules", "UpdateToReadyRoom", "OnUpdateToReadyRoom", "Halt")
end

function Plugin:ClientDisconnect( Client )
    if not Client or Client:GetIsVirtual() then return end

    if Client:GetIsSpectator() then
        self:Dequeue( Client )
    else
        Client:SetIsSpectator(true)
        self:Pop()
    end
end

function Plugin:OnGetCanJoinPlayingTeam( _, Player, Allowed)
    if not Allowed and Player:GetIsSpectator() then
        local Client = Player:GetClient()
        if Client then
            self:Enqueue(Client)
        end
    end
end

-- Fix that spectators are moved into the RR at round end
function Plugin:OnUpdateToReadyRoom(Gamerules, Force)
    local state = Gamerules:GetGameState()
    if(state == kGameState.Team1Won or state == kGameState.Team2Won or state == kGameState.Draw) and not GetConcedeSequenceActive() then
        if Force or Gamerules.timeSinceGameStateChanged >= 8 then
            -- Force the commanders to logout before we spawn people
            -- in the ready room
            Gamerules:LogoutCommanders()

            -- Set all players to ready room team
            local function SetReadyRoomTeam(player)
                if player:GetIsSpectator() then return end

                player:SetCameraDistance(0)
                Gamerules:JoinTeam(player, kTeamReadyRoom)
            end
            Server.ForAllPlayers(SetReadyRoomTeam)

            -- Spawn them there and reset teams
            Gamerules:ResetGame()
        end

    end
end

function Plugin:GetQueuePosition(Client)
    local SteamId = Client:GetUserId()

    return self.PlayerQueue:Get(SteamId)
end

function Plugin:PostJoinTeam( Gamerules, Player, _, NewTeam)
    if NewTeam ~= kSpectatorIndex then

        -- Make sure clients don't stay in the queue if they get moved to a playing slot
        local Client = Player:GetClient()
        self:Dequeue(Client)

        return
    end

    local SteamId = Player:GetSteamId()

    local position = 0
    if SteamId and self.HistoricPlayers:Contains( SteamId ) then
        self.HistoricPlayers:Remove( SteamId )
        position = self.PlayerQueue:Get( SteamId ) or 0
    end

    self:Pop()

    if not Gamerules:GetCanJoinPlayingTeam(Player, true) then
        local Client = Player:GetClient()
        if Client then
            if position == 0 then
                self:SendTranslatedNotify(Client, "QUEUE_INFORM", {
                    Position = self.PlayerQueue:GetCount()
                })
            else
                self:SendTranslatedNotify(Client, "QUEUE_WELCOME_BACK", {
                    Position = position
                })
            end
        end
    end
end

function Plugin:Enqueue( Client )
    if not Client:GetIsSpectator() then
        self:NotifyTranslatedError("ENQUEUE_ERROR_PLAYER")
    end

    local SteamID = Client:GetUserId()

    if not SteamID or SteamID < 1 then return end

    local position = self.PlayerQueue:Get( SteamID )
    if position then
        self:SendTranslatedNotify(Client, "QUEUE_POSITION", {
            Position = position
        })

        return
    end

    position = self.PlayerQueue:GetCount() + 1
    self.PlayerQueue:Add(SteamID, position)
    self:SendTranslatedNotify(Client, "QUEUE_ADDED", {
        Position = position
    })

    if GetHasReservedSlotAccess( SteamID ) then
        position = self.ReservedQueue:GetCount() + 1
        self.ReservedQueue:Add(SteamID, position)
        self:SendTranslatedNotify(Client, "PIORITY_QUEUE_ADDED", {
            Position = position
        })
    end
end

function Plugin:UpdateQueuePositions(Queue, Message)
    Message = Message or "QUEUE_CHANGED"

    local i = 1
    for SteamId, Position in Queue:Iterate() do
        local Client = Shine.GetClientByNS2ID( SteamId )
        if Client then

            if Position ~= i then
                Queue:Add( SteamId, i )
                self:SendTranslatedNotify( Client, Message, {
                    Position = i
                })
            end
            i = i + 1

        -- Historic player entry
        elseif self.HistoricPlayers:Contains(SteamId) then

            Queue:Add( SteamId, i )
            i = i + 1

        -- player disconnected but somehow wasn't removed
        else
            Queue:Remove( SteamId )
        end
    end
end

function Plugin:Dequeue( Client )
    if not Client then return end

    local SteamId = Client:GetUserId()

    local position = self.PlayerQueue:Remove( SteamId )
    if not position then return false end

    self:UpdateQueuePositions( self.PlayerQueue )

    position = self.ReservedQueue:Remove( SteamId )
    if position then
        self:UpdateQueuePositions( self.ReservedQueue, "PIORITY_QUEUE_CHANGED" )
    end

    return true
end

function Plugin:GetFirstClient( Queue )
    for SteamId in Queue:Iterate() do
        if not self.HistoricPlayers:Contains( SteamId ) then
            local QueuedClient = Shine.GetClientByNS2ID( SteamId )
            if QueuedClient then
                return QueuedClient
            end
        end
    end
end

function Plugin:PopReserved()
    local Gamerules = GetGamerules()
    if not Gamerules then -- abort mission
        return
    end

    local First = self:GetFirstClient(self.ReservedQueue)
    if not First then return end --empty queue

    local Player = Client:GetControllingPlayer()
    if not Player or Gamerules:GetCanJoinPlayingTeam(Player, true) then
        return false
    end

    if not Gamerules:JoinTeam(Player, kTeamReadyRoom ) then
        return false
    end

    Player:SetCameraDistance(0)

    self.ReservedQueue:Remove(First)
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    self:UpdateQueuePositions(self.ReservedQueue, "PIORITY_QUEUE_CHANGED")

    return true
end

function Plugin:Pop()
    local Gamerules = GetGamerules()
    if not Gamerules then -- abort mission
        return
    end

    local First = self:GetFirstClient(self.PlayerQueue)
    if not First then return end --empty queue

    local Player = Client:GetControllingPlayer()

    if not Gamerules:GetCanJoinPlayingTeam(Player, true) then
        return self:PopReserved()
    end

    if not Gamerules:JoinTeam(Player, kTeamReadyRoom) then
        return false
    end

    Player:SetCameraDistance(0)

    self.PlayerQueue:Remove(First)
    self:NotifyTranslated( Client, "QUEUE_LEAVE" )

    self:UpdateQueuePositions(self.PlayerQueue)

    return true
end

function Plugin:PrintQueue( Client )
    local Message = {}

    if self.PlayerQueue:GetCount() == 0 then
        Message[1] = "Player Slot Queue is currently empty."
    else

        Message[#Message + 1] = "Player Slot Queue:"
        for SteamId, Position in self.PlayerQueue:Iterate() do
            local ClientName = "Unknown"
            local QueuedClient = Shine.GetClientByNS2ID( SteamId )
            if QueuedClient then
                ClientName = Shine.GetClientName( QueuedClient )
            end

            Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
        end

        if self.ReservedQueue:GetCount() > 0 then
            Message[#Message + 1] = "\n Reserved Slot Queue:"

            for SteamId, Position in self.ReservedQueue:Iterate() do
                local ClientName = "Unknown"
                local QueuedClient = Shine.GetClientByNS2ID( SteamId )
                if QueuedClient then
                    ClientName = Shine.GetClientName( QueuedClient )
                end

                Message[#Message + 1] = string.format("%d - %s[%d]", Position, ClientName, SteamId)
            end
        end

    end

    if not Client then
        Notify( TableConcat( Message, "\n" ) )
    else
        for i = 1, #Message do
            ServerAdminPrint( Client, Message[ i ] )
        end
    end
end

function Plugin:CreateCommands()
    local function EnqueuPlayer( Client )
        if not Client then return end

        self:Enqueue(Client)
    end
    local Enqueue = self:BindCommand( "sh_rr_enqueue", "rr_enqueue", EnqueuPlayer, true )
    Enqueue:Help("Enter the queue for a player slot")

    local function DequeuePlayer( Client )

        if not self:Dequeue(Client) then
            self:NotifyTranslatedError( Client, "DEQUEUE_FAILED")
        end


        self:NotifyTranslated( Client, "DEQUEUE_SUCCESS")
    end

    local Dequeue = self:BindCommand( "sh_rr_dequeue", "rr_dequeue", DequeuePlayer, true )
    Dequeue:Help("Leave the player slot queue")

    local function DisplayPosition( Client )
        local position = self:GetQueuePosition(Client)
        if not position then
            self:NotifyTranslatedError( Client, "QUEUE_POSITION_UNKNOWN")
            return
        end

        self:SendTranslatedNotify(Client, "QUEUE_POSITION", {
            Position = position
        })
    end
    local Position = self:BindCommand( "sh_rr_position", "rr_position", DisplayPosition, true )
    Position:Help("Returns your current position in the player slot queue")

    local function PrintQueue(Client)
        self:PrintQueue(Client)
    end
    local Print = self:BindCommand( "sh_rr_printqueue", nil , PrintQueue, true )
end

function Plugin:MapChange()
    if not self.Config.RestoreQueueAfterMapchange then return end
    
    self:SaveQueueHistory()
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup( self )
    self.Enabled = false
end