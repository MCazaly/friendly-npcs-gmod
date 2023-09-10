AddCSLuaFile()

if Fakas == nil then
    Fakas = {}
end
if Fakas.Lib == nil then
    Fakas.Lib = {}
end

function Fakas.Lib.trace(start, endpos, filter)
    local line = { start = start, endpos = endpos }
    if filter ~= nil then
        line.filter = filter
    end
    return line
end

Fakas.FriendlyNPCs = {}
function Fakas.Lib.near_spawn(coordinates, range)
    if not GAMEMODE.SpawnPoints then
        return false
    end

    return false -- TODO
end

function Fakas.Lib.is_seen(coordinates)
    for _, ply in pairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and ply:IsLineOfSightClear(coordinates) then
            return true
        end
    end
    return false
end

function Fakas.Lib.can_fit(size, coordinates)
    -- Size should be a vector representing the size of the object to fit
    return not util.TraceLine(trace(coordinates, coordinates + size))
end

Fakas.Lib.NPCs = {}

local fcvars = bit.bor(FCVAR_NOTIFY, FCVAR_LUA_SERVER)

function Fakas.Lib.NPCs.create_convar(ent, name, minimum, maximum, description)
    return CreateConVar(
            ent:get_name() .. "_" .. name,
            ent.defaults[name],
            fcvars,
            description,
            minimum,
            maximum
    )
end

function Fakas.Lib.NPCs.create_convars(ent)
    local convars = {}
    convars.seek_range = Fakas.Lib.NPCs.create_convar(
            ent,
            "seek_range",
            1,
            math.huge,
            "How far to chase a target."
    )
    convars.seek_refresh = Fakas.Lib.NPCs.create_convar(
            ent,
            "seek_refresh",
            0.1,
            math.huge,
            "How many seconds to wait before searching for a new target."
    )
    convars.chase_refresh = Fakas.Lib.NPCs.create_convar(
            ent,
            "chase_refresh",
            0.01,
            math.huge,
            "How many seconds to wait before refreshing the path to a target."
    )
    convars.spawn_range = Fakas.Lib.NPCs.create_convar(
            ent,
            "spawn_range",
            0,
            math.huge,
            "How much space around a spawn point to consider 'safe' and not enter."
    )
    convars.attack_damage = Fakas.Lib.NPCs.create_convar(
            ent,
            "attack_damage",
            1,
            math.huge,
            "How much damage to deal in an attack."
    )
    convars.break_props = Fakas.Lib.NPCs.create_convar(
            ent,
            "break_props",
            1,
            0,
            "Whether or not to break props that are in the way."
    )
    convars.health = Fakas.Lib.NPCs.create_convar(
            ent,
            "health",
            1,
            math.huge,
            "How much health to spawn with."
    )
    return convars
end

function Fakas.Lib.NPCs.is_npc(ent)
    return IsValid(ent) and ent:IsNPC() or ent:IsNextBot()
end

function Fakas.Lib.is_spectator(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:GetObserverMode() ~= OBS_MODE_NONE
end

function Fakas.Lib.round(value)
    return math.floor(value + 0.5)
end

Fakas.Lib.Graphics = {}
function Fakas.Lib.Graphics.png_material(texture)
    return Material(texture, "smooth mips")
end
