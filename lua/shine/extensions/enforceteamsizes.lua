--[[
--Original idea and design by Andrew Krigline (https://github.com/akrigline)
--Original source can be found at https://github.com/akrigline/EnforceTeamSize
]]
local Shine = Shine

local Plugin = {}

Plugin.HasConfig = true
Plugin.ConfigName = "enforceteamsizes.json"

--[[
--TeamNumbers:
 - 0: RR
 - 1: Marines
 - 2: Aliens
 - 3: Spec
 ]]
Plugin.DefaultConfig = {
    Teams = {
        [1] = {
            MaxPlayers = 8,
            TooManyMessage = "The %s have currently too many players. Please Spectate until the round ends.",
            InformAboutFreeSpace = {3},
            InformMessage = "A player left the %s. So you can join up now."
        },
        [2] = {
            MaxPlayers = 8,
            TooManyMessage = "The %s have currently too many players. Please Spectate until the round ends.",
            InformAboutFreeSpace = {3},
            InformMessage = "A player left the %s. So you can join up now."
        }
    },
    MessageNameColor = {0, 255, 0}
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
    self.Enabled = true
    return true
end

function Plugin:Notify(Player, Message, OldTeam)
    Shine:NotifyDualColour( Player, self.Config.MessageNameColor[1], self.Config.MessageNameColor[2],
        self.Config.MessageNameColor[3], "EnforcedTeamSizes", 255, 255, 255,
       Message, true, Shine:GetTeamName(OldTeam, true) )
end

function Plugin:ClientDisconnect( Client )
    local Player = Client:GetControllingPlayer()
    if not Player then return end

    self:PostJoinTeam( GetGamerules(), Player, Player:GetTeamNumber() )
end

function Plugin:PostJoinTeam( Gamerules, _, OldTeam )
    if OldTeam < 0 then return end

    if self.Config.Teams[OldTeam] and #self.Config.Teams[OldTeam].InformAboutFreeSpace ~= 0 and
            Gamerules:GetTeam(OldTeam):GetNumPlayers() + 1 == self.Config.Teams[OldTeam].MaxPlayers then
        for _, i in ipairs(self.Config.Teams[OldTeam].InformAboutFreeSpace) do
            local Team = Gamerules:GetTeam(i)
            local Players = Team and Team:GetPlayers()
            if Players and #Players ~= 0 then
                self:Notify(Players, self.Config.Teams[OldTeam].InformMessage
                        or "A player left the %s team. So you can join up now.", OldTeam)
            end
        end
    end
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, _, ShineForce )
    if ShineForce or not self.Config.Teams[NewTeam] then return end

    --Check if team is above MaxPlayers
    if Gamerules:GetTeam(NewTeam):GetNumPlayers() >= self.Config.Teams[NewTeam].MaxPlayers then
        --Inform player
        self:Notify(Player, self.Config.Teams[NewTeam].TooManyMessage, NewTeam)
        return false
    end
end

function Plugin:CleanUp()
    self.BaseClass.CleanUp()
    self.Enabled = false
end

Shine:RegisterExtension("enforceteamsizes", Plugin )
