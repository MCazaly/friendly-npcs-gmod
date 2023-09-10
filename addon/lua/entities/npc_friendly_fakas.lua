-- TODO: Test the grenade more
-- TODO: Grenade model with dynamic texture
-- TODO: Boss-only health bar.
-- TODO: Generic chat message framework, use pretty name and colour attributes
-- TODO: Hitbox issues again?
-- TODO: reunite FakLib
-- TODO: How Unfortunate remove unused ents
-- TODO: How Unfortunate minigames



AddCSLuaFile()

local THIS = "npc_friendly_fakas"

if Fakas == nil then
    Fakas = {}
end
if Fakas.Lib == nil then
    Fakas.Lib = {}
end
function Fakas.Lib.world_elevation(ent)
    local pos = ent:GetPos()
    local line = util.TraceLine(
        Fakas.Lib.trace(
            pos,
            pos - Vector(0, 0, 16384), -- This should cast directly to the floor
            ents.GetAll()
        )
    )
    if line.Hit and util.IsInWorld(line.HitPos) then
        -- Double check that the target position is inside the world
        return math.abs(line.HitPos.z - pos.z)
    end

    return -1
end
function Fakas.Lib.random_remove(tbl)
    return table.remove(tbl, math.random(#tbl))
end

if Fakas.Lib.Loot == nil then
    Fakas.Lib.Loot = {}
    Fakas.Lib.Loot.modes = {
        SBOX = 1,
        TTT2 = 2
    }
    if TTT2 then
        Fakas.Lib.Loot.mode = Fakas.Lib.Loot.modes.TTT2
    end
end

function Fakas.Lib.Loot.grant(ply, guaranteed, random, random_max)
    -- Give a player some loot, can be random items or guaranteed items, or both!
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then
        return false
    end

    -- Fetch our randomly generated loot and then add the guaranteed items on top
    local loot = Fakas.Lib.Loot.select(random, random_max)
    for _, name in pairs(guaranteed) do
        local class = Fakas.Lib.Loot.get(name)
        if class then
            table.insert(loot, class)
        else
            -- print(string.format("Warning: Guaranteed loot class '%s' was not found!"), name)
        end
    end

    -- Give the player all the items they should receive
    for _, class in pairs(loot) do
        Fakas.Lib.Loot.give(ply, class)
    end

    return #loot
end

function Fakas.Lib.Loot.select(names, max)
    -- Randomly select valid classes from a list of class names, up to a certain number.
    -- Does not return duplicates, unless the same name is provided more than once.

    -- Start by verifying that the requested classes exist, discarding them if they don't.
    local all_classes = {}
    for _, name in pairs(names) do
        local class = Fakas.Lib.Loot.get(name)
        if class then
            table.insert(all_classes, class)
        end
    end

    -- We can only give as many "unique" classes as we've verified, or up to the specified max, whichever is lower.
    local quantity = math.min(#all_classes, max)
    if #all_classes == quantity then
        return all_classes
    end

    -- Make our random selection and return the results.
    local classes = {}
    for _ = 1, quantity do
        table.insert(classes, Fakas.Lib.random_remove(all_classes))
    end
    return classes
end

function Fakas.Lib.Loot.get(name, mode)
    -- Get the class for a given item, weapon, or other gamemode-specific thing that can be given to a player.
    -- Nil if the class does not exist.
    if mode == nil then
        mode = Fakas.Lib.Loot.mode
    end

    if Fakas.Lib.Loot.mode == Fakas.Lib.Loot.modes.TTT2 then  -- TTT2 gamemode
        local class = weapons.GetStored(name) or items.GetStored(name)
        if class then
            return class
        end
        print(string.format("Warning: TTT2 Loot class '%s' was not found!"), name)
    else
        print(string.format("Warning: Loot not implemented for mode '%s'!", mode))
    end
end

function Fakas.Lib.Loot.give(ply, class, mode)
    -- Award a single loot class directly to a player.
    if mode == nil then
        mode = Fakas.Lib.Loot.mode
    end

    if Fakas.Lib.Loot.mode == Fakas.Lib.Loot.modes.TTT2 then
        -- TTT2 treats weapons and items a bit differently, so we handle that here.
        if class.Base:find("^item_") then
            return IsValid(ply:GiveEquipmentItem(class.ClassName))
        elseif class.Base:find("^weapon_") then
            return IsValid(ply:GiveEquipmentWeapon(class.ClassName))
        else
            -- print(string.format("Cannot grant '%s' as it has an unrecognised base!"), class.ClassName)
        end
    else
        error(string.format("Loot not implemented for mode '%s'!", mode))
    end
end

local DECLOAKED = 0
local CLOAKING = 1
local CLOAKED = 2
local DECLOAKING = 3

local NONE = -1
local INACTIVE = 0
local ACTIVE = 1
local CHASE = 2

local CLOAK_STRING = "FakasFriendlyFakasCloak"
local MUSIC_STRING = "FakasFriendlyFakasMusic"
local KILL_STRING = "FakasFriendlyFakasKill"
local DETECTOR_HOOK = "FakasFriendlyFakasCanDetect"
local DETECTOR_EQUIP_HOOK = "FakasFriendlyTTT2ModifyDetectorEquipment"
local TRAILS = {}

local ORANGE = Color(255, 106, 0, 255)
local WHITE = Color(255, 255, 255, 255)

local SKINS = {
    "agent",
    "anti",
    "borg",
    "bot",
    "bw",
    "colossal",
    "freeman",
    "hashirama",
    "impmon",
    "joker",
    "naruto",
    "nose",
    "red",
    "spy",
    "sans",
    "nappa"
}
local USED_PRIMARY_SKIN = false


ENT.Base = "npc_friendly_png"
DEFINE_BASECLASS(ENT.Base)

ENT.name = "fakas"
ENT.pretty_name = "Fakas"
ENT.admin_only = true
ENT.size = { Vector(-13, -13, 0), Vector(13, 13, 70) }
ENT.colour = ORANGE
ENT.scale = 1


local function get_fakases()
    local fakases = {}
    for _, fakas in pairs(ents.FindByClass("npc_friendly_fakas")) do
        if IsValid(fakas) and fakas.ready and fakas.alive then
            table.insert(fakases, fakas)
        end
    end

    return fakases
end

local function is_detector(ply)
    return IsValid(ply) and (hook.Run(DETECTOR_HOOK, ply) or false)
end

local function kill_message(killer)
    if SERVER then
        local not_killer = RecipientFilter()
        not_killer:AddAllPlayers()
        if IsValid(killer) and killer:IsPlayer() then
            not_killer:RemovePlayer(killer)
            -- One message for the killer.
            net.Start(KILL_STRING)
            net.WriteBool(true)
            net.Send(killer)
        end
        -- One message for everyone else.
        net.Start(KILL_STRING)
        net.WriteBool(false)
        net.Send(not_killer)
        return
    end

    if net.ReadBool() then
        chat.AddText(
            ORANGE,
            "Fakas ",
            WHITE,
            "smiles upon you! You have been granted a ",
            ORANGE,
            "boon",
            WHITE,
            "."
        )
    else
        chat.AddText(
            ORANGE,
            "Fakas",
            WHITE,
            ": fuck"
        )
    end
    surface.PlaySound("misc/sniper_railgun_double_kill.wav")
end

if SERVER then
    local function send_music(mode, ply)
        if ply == nil then
            ply = player.GetAll()
        end
        -- print("Music " .. mode .. " will be sent to:")
        -- print(ply)
        net.Start(MUSIC_STRING)
        net.WriteInt(mode, 3)
        net.Send(ply)
    end

    local function omit_music(mode, players)
        -- print("Music " .. mode .. " will not be sent to:")
        PrintTable(players)
        net.Start(MUSIC_STRING)
        net.WriteInt(mode, 3)
        net.SendOmit(players)
    end

    local function direct_music()  -- TODO Replace this with a reusable music director
        -- print("Directing music...")
        local fakases = get_fakases()
        local haste = false

        if #fakases < 1 then
            send_music(NONE)
            return
        end

        local active = false
        local targets = {}
        for _, fakas in pairs(fakases) do
            haste = haste or fakas.haste > 1
            local valid_current = IsValid(fakas.current_target)
            local valid_preference = IsValid(fakas.preferred_target)

            if not IsValid(fakas.current_target) and not IsValid(fakas.preferred_target) then
                continue
            end
            active = true

            if valid_current and fakas.current_target:IsPlayer() then
                targets[fakas.current_target:UserID()] = fakas.current_target
                continue
            end
            if valid_preference and fakas.preferred_target:IsPlayer() then
                targets[fakas.preferred_target:UserID()] = fakas.preferred_target
            end
        end

        if not active and not haste then
            send_music(INACTIVE)
            return
        end
        for _, ply in ipairs(player.GetAll()) do
            if targets[ply:UserID()] ~= null or Fakas.Lib.is_spectator(ply) then
                -- print("Sending CHASE to " .. ply:Nick())
                send_music(CHASE, ply)
            else
                send_music(ACTIVE, ply)
                -- print("Sending ACTIVE to " .. ply:Nick())
            end
        end
    end


    -- Set up networking
    util.AddNetworkString(CLOAK_STRING)
    util.AddNetworkString(MUSIC_STRING)
    util.AddNetworkString(KILL_STRING)

    -- Start tracking player coordinates
    timer.Create("FakasFriendlyPlayerTracker", 1, 0, function()  -- Log each player's coordinates once every second
        local plys = player.GetAll()
        for _, ply in pairs(plys) do
            if IsValid(ply) and ply:Alive() then
                local id = ply:UserID()
                if TRAILS[id] == nil then
                    TRAILS[id] = {}
                end
                table.insert(TRAILS[id], ply:GetPos())
            end
        end
    end)

    timer.Create("FakasFriendlyFakasMusicTimer", 1, 0, direct_music)

    hook.Add("EntityRemoved", "FriendlyNPCsFakasDeath", function(ent)
        if IsValid(ent) and ent:GetClass() == "npc_friendly_fakas" and not ent.alive then
            ent:Explode(100)
        end
    end)
end

if TTT2 then
    -- TTT2-specific functionality.
    if SERVER then
        hook.Add("TTTEndRound", "FriendlyNPCsFakasTTTEndRound", function()
            -- Remove any active Fakases on round end.
            for _, fakas in pairs(get_fakases()) do
                if IsValid(fakas) then
                    fakas:Remove()
                end
            end
        end)
    end

    hook.Add("TTT2RolesLoaded", "FriendlyNPCsFakasTTT2Setup", function()
        roles.InitCustomTeam(
                "fakas",
                {
                    icon = "",  -- TODO
                    color = ORANGE
                }
        )

        hook.Add("TTT2ModifyWinningAlives", "FriendlyNPCsFakasTTT2ModifyAlive", function(aliveTeams)
            if #get_fakases() > 0 then
                table.insert(aliveTeams, TEAM_FAKAS)
            end
        end)
    end)

    hook.Add("TTT2CanUsePointer", "FriendlyNPCsFakasTTT2AllowPointer", function(ply, _, _, ent)
        if not IsValid(ply) or not IsValid(ent) or ent:GetClass() ~= "npc_friendly_fakas" then
            return nil
        end
        return ent.cloak_status == DECLOAKED or is_detector(ply)
    end)
end

function ENT:Initialize()
    if self.initialized then
        return
    end

    self.defaults = {
        seek_range = 10000,
        seek_refresh = 1,
        chase_refresh = 0.1,
        spawn_range = 0,
        attack_damage = 50,
        break_props = 1,
        health = 3250
    }
    self.convars = Fakas.Lib.NPCs.create_convars(self)

    BaseClass.Initialize(self)

    if SERVER then  -- We need this to be synchronised or people will see different textures!
        self:SetTexture(self:pick_texture(SKINS))
    end

    self.knockback_up = 3
    self.default_knockback_up = 2.5
    self.attack_force = 250
    self.default_attack_force = 250
    self.attack_cooldown = 0.5
    self.attack_range = 75
    self.default_attack_range = 75
    self.damage_scale = 1
    self.acceleration = 500
    self.deceleration = 500
    self.can_lunge = false
    self.lunge_cooldown = 1
    self.lunge_time = 3
    self.lunge_speed = 5
    self.lunge_accel = 5
    self.lunge_decel = 5
    self.cloak_time = 1
    self.cloak_start = 0
    self.cloak_status = DECLOAKED
    self.cloak_hook = "FakasCloak_" .. self:GetClass() .. "_" .. self:EntIndex()
    self.chase_start = nil
    self.chase_time = 45
    self.downtime_min = 15
    self.downtime_max = 25
    self.downtime_end = nil
    self.downtime_last = nil
    self.heal_rate = 25
    self.last_teleport = 0
    self.teleport_wait = 2
    self.haste = 1
    self.airshots = 0
    self.max_distance = 3500
    self.teleport_gap = 150

    self.sounds = {
        fadein = self.resource_root .. "/fadein.wav",
        fadeout = self.resource_root .. "/fadeout.wav",
        detected = self.resource_root .. "/detected.wav"
    }

    self:SetCollisionGroup(COLLISION_GROUP_PUSHAWAY) -- TODO
end

function ENT:pick_texture(options, _)
    local texture = nil
    local month = os.date("*t").month
    if month == 12 then
        texture = "christmas"
    elseif month == 10 then
        texture = "pumpkin"
    elseif #options == 0 or (not USED_PRIMARY_SKIN and math.random(0,1) == 0) then
        texture = "primary"
        USED_PRIMARY_SKIN = true
    else
        texture = Fakas.Lib.random_remove(options)
    end

    if not texture then
        error(string.format("Failed to pick a texture for %q!", self))
    end
    return self:texture(texture)
end


function ENT:OnTakeDamage(info)
    if info:IsExplosionDamage() then
        info:ScaleDamage(0)
    elseif not self.m_bApplyingDamage then
        self.m_bApplyingDamage = true
        self:TakeDamageInfo(info)
        self.m_bApplyingDamage = false

        local attacker = info:GetAttacker()
        if self.cloak_status == CLOAKED and (attacker:IsPlayer() or Fakas.Lib.NPCs.is_npc(attacker)) then
            self:reveal(attacker)
        end

        return true
    end
end

function ENT:OnRemove()
    hook.Remove("Think", self.cloak_hook)
    BaseClass.OnRemove(self)
end

function ENT:OnKilled(info)
    if SERVER then
        local attacker = info:GetAttacker()
        if TTT2 and IsValid(attacker) and attacker:IsPlayer() and Fakas.Lib.Loot.grant(
            attacker,
            {"item_ttt_noexplosiondmg"},
            {
                "weapon_ttt_sandwich",
                "weapon_ttt_teleport",
                "weapon_ttt_slam",
                "weapon_ttt_c4",
                "weapon_ttt_mine_turtle",
                "weapon_ttt_jihad_bomb",
                "weapon_ttt_rmgrenade",
                "ttt_tf2rocketlauncher",
                "weapon_ttt_confgrenade_s",
                "weapon_ttt_gimnade",
                "weapon_megumin"
            },
            1
        ) > 0 then
            kill_message(attacker)  -- Only send the nice message if we're actually giving them something.
        else
            kill_message(nil)
        end
    end
    BaseClass.OnKilled(self, info)
end

function ENT:attack()
    -- When dealing with explosions, we only attack once per cycle and always assume it's a success
    local targets = ents.FindInSphere(self:GetPos(), self.attack_range)
    local target = nil

    for _, ent in pairs(targets) do
        if not self:should_target(ent) then
            continue
        end
        target = ent
        if target == self.current_target then  -- Always prioritise our current target
            break
        end
    end

    if target == nil then
        return false
    end
    self.last_attack = CurTime()
    if self:targetable_prop(target) then
        self:attack_prop(target)
        -- Wait longer after attacking a prop, spamming explosions hurts performance
        self.last_attack = self.last_attack + 1
    else
        self:attack_target(target)
    end

    return true
end

function ENT:attack_target(target)
    if TTT2 and IsValid(target) and target:IsPlayer() and target:HasEquipmentItem("item_ttt_noexplosiondmg") then
        -- Our target is a killjoy and immune to explosions - we have to do this the old-fashioned way :(
        if self:ent_distance(target) > self.default_attack_range then
            return false  -- Melee attacks have a shorter range than explosions!
        end
        self.damage_scale = 0.5
        local success = BaseClass.attack_target(self, target)
        self.damage_scale = 1
        return success
    end
    self:knockback(target)
    self:Explode(self.convars.attack_damage:GetInt() * self.damage_scale)
    return true
end

function ENT:calculate_vertical_knockback(_)
    return vector_up * self.attack_force * self.knockback_up
end

function ENT:cloak_server()
    net.Start(CLOAK_STRING)
    net.WriteInt(self:EntIndex(), 32)
    net.WriteInt(self.cloak_status, 3)
    net.Broadcast()
end

function ENT:update_haste()
    self.haste = math.min(self.haste, 1)
    local haste_conditions = {
        -- Speedrun prop murder
        {self:should_target(self.current_target) and self.current_target:GetClass() == "prop_physics", 10},
        -- Speedrun through NPCs, but not quite as quickly
        {self:should_target(self.current_target) and Fakas.Lib.NPCs.is_npc(self.current_target), 5},
        -- We get impatient while waiting for our preferred target
        {self.should_target(self.preferred_target), 2},
        -- Not much time left!
        {TTT2 and GetGlobalFloat("ttt_round_end") - CurTime() <= 60, 2.5},
        -- One player left, we're not fucking around.
        {TTT2 and #self:targetable_players(player.GetAll()) == 1, 2}
    }

    for _, condition in pairs(haste_conditions) do
        if condition[1] then
            self.haste = math.max(self.haste, condition[2])
        end
    end
end

function ENT:BehaveUpdate()
    self:update_haste()
    BaseClass.BehaveUpdate(self)
end

--function ENT:target_pos(target)
--    if not IsValid(target) or not target:IsInWorld() then
--        return nil
--    end
--
--    if not self:IsOnGround() and not target:IsOnGround() then
--        return target:GetPos()  -- We're probably attempting an airshot, aim straight for our target
--    end
--
--    return BaseClass.target_pos(self, target)
--end

function ENT:cloak_client()
    self.cloak_start = CurTime() - 0.001  -- Start a millisecond behind
    hook.Add("Think", self.cloak_hook, function()
        if not IsValid(self) then
            pcall(function()
                hook.Remove("Think", self.cloak_hook)
            end)
        end

        local progress = self:alpha_progress()
        self:set_alpha(progress)
        if progress == 1 or progress == 0 then
            hook.Remove("Think", self.cloak_hook)
            return
        end
    end)

    local sound = self.sounds.fadein
    if self.cloak_status == CLOAKING then
        sound = self.sounds.fadeout
    end
    self:EmitSound(sound, 100)
end

function ENT:set_alpha(alpha)
    local min = 0
    if CLIENT and is_detector(LocalPlayer()) then
        min = 0.25
    end
    self.material:SetFloat("$alpha", math.max(alpha, min))
end

function ENT:alpha_progress()
    local duration = 0.6

    if self.cloak_status == CLOAKED then
        return 1
    end
    if self.cloak_status == DECLOAKED then
        return 0
    end

    local elapsed = CurTime() - self.cloak_start
    if self.cloak_status == CLOAKING then
        return math.max(1 - (elapsed / duration), 0)
    end
    if self.cloak_status == DECLOAKING then
        return math.min(0 + (elapsed / duration), 1)
    end
    return 1
end

function ENT:cloak()
    if self.cloak_status ~= DECLOAKED then
        return false
    end

    self.cloak_status = CLOAKING
    self:cloak_server()
    timer.Create("FakasFriendlyCloakTimer" .. self:EntIndex(), 1, 1, function()
        self.cloak_status = CLOAKED
    end)

    return true
end

function ENT:decloak()
    if self.cloak_status ~= CLOAKED then
        return false
    end

    self.cloak_status = DECLOAKING
    self:cloak_server()
    timer.Create("FakasFriendlyCloakTimer" .. self:EntIndex(), 1, 1, function()
        self.cloak_status = DECLOAKED
    end)

    return true
end

function ENT:teleport_random()
    local counter = 0
    local pos = nil
    while counter < 32 do  -- Try to find a good spot for us to bugger off to
        pos = Fakas.Lib.random_member(navmesh.GetAllNavAreas()):GetCenter()
        if self:can_fit(pos) then
            self:teleport(pos)
            return true
        end
    end
    -- We didn't find a good spot after 32 tries, we can try again later
    return false
end

function ENT:can_fit(pos)
    local mins, maxs = self:GetCollisionBounds()
    local hull = util.TraceHull({
        start = pos + mins,
        endpos = pos + maxs,
        mins = mins,
        maxs = maxs,
        mask = MASK_PLAYERSOLID
    })

    return not hull.Hit
end

function ENT:teleport_pos(target)
    if not IsValid(target) then
        return nil
    end
    if target:IsPlayer() then
        -- In the name of "fairness" we don't teleport inside players. Check their position history for a good spot.
        local trail = TRAILS[target:UserID()]

        if #trail < 24 then
            -- Player hasn't built up enough position history yet
            return nil
        end

        for ii = #trail - 8, #trail - 16, -1 do  -- A sample of the last few positions, in reverse order
            local pos = trail[ii]
            local distance = pos:Distance(target:GetPos())
            local min_distance = self.teleport_gap
            if self.haste > 1 then
                -- We'll get a bit closer when haste is active.
                min_distance = self.teleport_gap / 2
            end
            if distance <= self.max_distance and distance >= self.teleport_gap and self:can_fit(pos) then
                -- It's nearby and we can fit here! Good for teleporting to.
                return pos
            end
        end
        return nil -- Nowhere good to teleport to :(
    end

    return target:GetPos()  -- We don't give a shit about being fair to NPCs or props.
end

function ENT:target_player(ply)
    if not self:should_target(ply) then
        return nil
    end
    local teleport_pos = self:teleport_pos(ply)
    if teleport_pos ~= nil then
        self:set_target(ply)
        return teleport_pos
    end
end

function ENT:update_target()
    local teleport_pos = nil
    if self:should_target(self.preferred_target) then
        -- Try to go for our preferred target first
        teleport_pos = self:target_player(self.preferred_target)
        if teleport_pos ~= nil then
            self:set_target(self.preferred_target)
            return teleport_pos
        end
    else
        -- Our preference is no longer a valid target, time to move on...
        self.preferred_target = nil
    end

    teleport_pos = self:teleport_pos(self.last_target)
    local last_choice = nil
    if self:should_target(self.last_target) and teleport_pos ~= nil then
        last_choice = {self.last_target, teleport_pos}
    end

    local targets = {}
    for _, ply in pairs(player.GetAll()) do
        if ply == self.last_target then
            -- This is the last player we targeted. We'll try not to harass them again this cycle if we can avoid it
            continue
        end

        teleport_pos = self:teleport_pos(ply)
        if self:should_target(ply) and teleport_pos ~= nil then
            table.insert(targets, {ply, teleport_pos})
        end
    end

    if #targets == 0 and last_choice ~= nil then
        -- We always prioritise players over NPCs and props, even if they're our last target.
        table.insert(targets, last_choice)
    elseif #targets == 0 then
        -- We didn't find a player, target an NPC or something destructible this round instead.
        local npcs = {}
        local breakables = {}
        local ents = ents.GetAll()
        for _, ent in pairs(ents) do
            if Fakas.Lib.NPCs.is_npc(ent) and self:should_target(ent) then
                table.insert(npcs, {ent, self:teleport_pos(ent)})
                continue
            end

            if not ent:IsPlayer() and not Fakas.Lib.NPCs.is_npc(ent) and self:should_target(ent) then
                table.insert(breakables, {ent, self:teleport_pos(ent)})
            end
        end

        if #npcs > 0 then
            -- Prioritise NPCs over props
            targets = npcs
        elseif #breakables > 0 then
            -- When there's nothing alive for us to go after, we start breaking props
            targets = breakables
        end
    end

    if #targets > 0 then
        local target = Fakas.Lib.random_member(targets)
        self:set_target(target[1])
        return target[2]
    end

    -- print("Couldn't find anything to target!")
    self:set_target(nil)
    return nil  -- Oh dear. Nothing to target...
end

function ENT:targetable_prop(ent)
    -- Fakas likes to break things.
    return ent:GetClass() == "prop_physics" and ent:Health() > 0 and ent:GetMaxHealth() > 0
end

function ENT:set_target(target)
    if self:should_target(self.current_target) and self.current_target:IsPlayer() then
        self.last_target = self.current_target
    end

    if not IsValid(target) then
        -- Not a valid target, reset to nil
        self.current_target = nil
        return
    end

    -- Something we can actually target!
    self.current_target = target
end

function ENT:attack_prop(ent)
    -- Use explosions for prop attacks too
    BaseClass.attack_target(self, ent)
    return self:attack_target(ent)
end

function ENT:phase_1()
    -- We've just spawned or we've stopped chasing, cloak and teleport away so we can heal and/or wait for a target
    if self.cloak_status ~= CLOAKED then
        self:cloak()
        return
    end

    local pos = self:target_player(self.preferred_target)
    if pos ~= nil then
        -- Our preferred target is available, let's skip downtime and engage them.
        self:set_target(self.preferred_target)
        self:teleport(pos)
        return self:end_downtime()
    end

    if self:teleport_random() then
        return self:start_downtime()
    end
end

function ENT:phase_2()
    -- We've teleported away, wait until we're fully healed and the minimum time has elapsed
    if self.cloak_status ~= CLOAKED then
        self:cloak()
        return
    end

    local detector = self:detected()
    if IsValid(detector) then
        return self:reveal(detector)
    end

    local now = CurTime()
    if now - self.downtime_last >= 1 then
        -- Heal until we've reached max health
        self:SetHealth(math.min(self:Health() + self.heal_rate, self:GetMaxHealth()))
    end

    if now >= self.downtime_end then
        -- We're all healed up and we've waited the minimum duration, time to do some crimes
        local pos = self:update_target()
        if pos ~= nil then
            self:teleport(pos)
            self:end_downtime()
        end
    end
end

function ENT:phase_3()
    -- We've locked on to a target and teleported nearby, let's announce our presence!
    if CurTime() - self.last_teleport < self.teleport_wait then
        -- Wait a little after our teleport before decloaking to avoid showing interpolated movement
        return
    end

    if self.cloak_status ~= DECLOAKED then
        -- We'll give our victim a sporting chance - wait for the full decloak animation
        return self:decloak()
    end

    self:start_chase()  -- We're done waiting!
end

function ENT:phase_4()
    -- Time to chase down our victim!
    self:decloak()

    if not self:should_target(self.current_target) then
        -- Our target is dead or otherwise unavailable
        if self.current_target == self.preferred_target then
            -- Our preferred target is gone :(
            self.preferred_target = nil
        end
        return self:end_chase()
    end

    local now = CurTime()
    local too_far = self:target_distance() > self.max_distance  -- Our target is too far away
    local lost = too_far or self.failed_paths * self.path_cooldown >= 15  -- We can't reach our target
    local chase_done = not lost and now - self.chase_start >= self.chase_time  -- We've chased too long

    if chase_done then
        self.preferred_target = nil  -- Okay, you get away this time.
        return self:end_chase()
    end
    if lost and self.current_target:IsPlayer() and not self.should_target(self.preferred_target) then
        self.preferred_target = self.current_target  -- Let me show you why you shouldn't cheese my pathing...
        return self:end_chase()
    end
    if self:should_target(self.preferred_target) and self.preferred_target ~= self.current_target and self:target_player(self.preferred_target) then
        -- Our preferred target is available - let's go kill them!
        -- print("Rerouting to preferred target!")
        return self:end_chase()
    end

    self.attack_range = self.default_attack_range
    self.knockback_up = self.default_knockback_up
    self.attack_force = self.default_attack_force
    self.damage_scale = 1

    if self:IsOnGround() then
        self.airshots = 0
        self:chase_target(self.current_target)
    else
        -- Increase our attack range while we're in the air to make airshots easier, but also decrease damage
        self.attack_range = self.default_attack_range * math.min(self.airshots + 2.25, 3)
        self.damage_scale = 0.5
    end

    if not self.current_target:IsOnGround() then
        local force_multiplier = 1.25
        local min_multiplier = 1.1
        local airshot_value = 1
        if Fakas.Lib.world_elevation(self.current_target) <= 100 then
            -- If they're below this height, they're probably just jumping - adjust knockback accordingly.
            force_multiplier = 1
            min_multiplier = 1
            -- We don't count airshots unless they're above this height.
            airshot_value = 0
        end
        -- Try not to launch already airborne targets too high, fall damage isn't fun
        self.knockback_up = self.default_knockback_up / math.min(self.airshots + 2.25, 5)
        -- If we get a successful airshot, push them away further so they have more time to escape
        self.attack_force = self.default_attack_force * math.max(self.airshots * force_multiplier, min_multiplier)

        if self:attempt_attack() then
            self.airshots = self.airshots + airshot_value
            -- print("Elevation: " .. Fakas.Lib.world_elevation(self.current_target))
            -- print("Airshots: " .. self.airshots)
        end
        return
    end
    return self:attempt_attack()
end

function ENT:reveal(culprit)
    -- Something damaged us or got close enough to see through our cloak!
    if self:should_target(culprit) then
        self:set_target(culprit)
        if culprit:IsPlayer() then
            self.preferred_target = culprit  -- You really shouldn't disturb my nap-time...
        end
    end
    self:EmitSound(self.sounds.detected, 100)
    self:end_downtime()
end

function ENT:start_downtime()
    local now = CurTime()
    self.downtime_last = now
    self.downtime_end = now + (math.random(self.downtime_min, self.downtime_max) / math.min(self.haste, 10))
    self.current_phase = 2
end

function ENT:end_downtime()
    self.downtime_last = nil
    self.current_phase = 3
end

function ENT:start_chase()
    self.failed_paths = 0
    self.current_phase = 4
    self.chase_start = CurTime()
end

function ENT:end_chase()
    self.failed_paths = 0
    self.current_phase = 1
    self.chase_start = nil
    self:set_target(nil)
end

function ENT:detected()
    local pos = self:GetPos()
    local nearby = ents.FindInSphere(pos, self.attack_range)
    for _, ent in pairs(nearby) do
        if self:should_target(ent) and ent:IsPlayer() and not util.TraceLine(Fakas.Lib.trace(pos, ent:GetPos(), {self, ent})).Hit then
            return ent
        end
    end
    return nil
end

function ENT:phases()
    return  {
        function() self:phase_1() end,
        function() self:phase_2() end,
        function() self:phase_3() end,
        function() self:phase_4() end
    }
end

if CLIENT then
    local music = {}
    local music_ready = false
    local last_detector = nil

    local function update_cloaks()
        for _, fakas in pairs(get_fakases()) do
            fakas:set_alpha(fakas:alpha_progress())
        end
    end

    local function create_track(path)
        local sound = CreateSound(game.GetWorld(), path)
        sound:SetSoundLevel(0)
        return sound
    end

    local function stop_music(except)
        for _, other in pairs(music) do
            if other:IsPlaying() and other ~= except then
                other:FadeOut(0.5)
            end
        end
    end
    local function play_track(sound)
        if sound:IsPlaying() then
            return
        end

        stop_music(sound)
        sound:Play()
    end

    local function setup_tracks()
        local world = game.GetWorld()
        if IsValid(LocalPlayer()) and world ~= nil and world:IsWorld() then
            -- print("Initialising music!")
            music[INACTIVE] = create_track("fakas/friendly-npcs/fakas/inactive.wav")
            music[ACTIVE] = create_track("fakas/friendly-npcs/fakas/active.wav")
            music[CHASE] = create_track("fakas/friendly-npcs/fakas/chase.wav")
            return true
        end
        return false
    end

    -- Sometimes TTT likes to invalidate our music when the round changes, so we'll try and fix it
    hook.Add("TTTBeginRound", "FakasFriendlyFakasMusicSetup", setup_tracks)
    -- Make sure clients know how visible Fakas should be.
    hook.Add("InitPostEntity", "FakasFriendlyFakasPlayerSpawn", update_cloaks)

    timer.Create("FakasFriendlyFakasDetectorTimer", 1, 0, function()
        local ply = LocalPlayer()
        if not IsValid(ply) then
            return
        end
        local detector = is_detector(ply)
        if detector ~= last_detector then
            -- Just in case.
            last_detector = detector
            update_cloaks()
        end

    end)

    net.Receive(CLOAK_STRING, function()
        local ent = Entity(net.ReadInt(32))
        if IsValid(ent) then
            ent.cloak_status = net.ReadInt(3)
            ent:cloak_client()
        end
    end)

    net.Receive(MUSIC_STRING, function()
        if not music_ready then
            music_ready = setup_tracks()
            return
        end

        local mode = net.ReadInt(3)
        -- print("MUSIC MODE: " .. mode)
        if mode == NONE then
            return stop_music()
        end
        play_track(music[mode])
    end)

    net.Receive(KILL_STRING, kill_message)
end

list.Set(
    "NPC",
    THIS,
    {
        Name = ENT.pretty_name,
        Class = THIS,
        Category = "Friendly Group",
        AdminOnly = ENT.admin_only
    }
)

hook.Add("FakasFriendlyNPCsModifyPNGList", "FakasFriendlyNPCsAddFakasPNG", function(pngs)
    table.insert(pngs, THIS)
end)

hook.Add(DETECTOR_HOOK, "FakasFriendlyFakasBaseDetectors", function(ply)
    if Fakas.Lib.is_spectator(ply) then
        return true
    end
    return nil
end)
hook.Add(DETECTOR_HOOK, "FakasFriendlyFakasTTT2Detectors", function(ply)
    if not TTT2 then
        return nil
    end
    if ply:GetSubRoleData().isPolicingRole then  -- Detectives, etc. and Defectives can see through cloak.
        return true
    end

    local equipment = {
        items = {
            "item_ttt_radar",
            "item_ttt_tracker"
        },
        weapons = {}
    }
    hook.Run(DETECTOR_EQUIP_HOOK, equipment)
    for _, item in pairs(equipment.items) do
        if ply:HasEquipmentItem(item) then
            return true
        end
    end
    for _, weapon in pairs(equipment.weapons) do
        if ply:HasEquipmentWeapon(weapon) then
            return true
        end
    end
end)

--local function draw_bar(width, height, radius, x, y, r, g, b)
--    --surface.SetDrawColor(r, g, b, 255)
--    draw.RoundedBox(radius, x, y, width, height, Color(r,g,b, 255))
--    -- Reset the draw colour for anything else that needs it.
--    --surface.SetDrawColor(255, 255, 255, 255)
--end
--
--if CLIENT then
--    local function get_bars(fraction)
--        local bars = {}
--        while #bars < fraction do
--            local bar = {}
--            bar.fraction = math.min(fraction - #bars, 1)
--            if #bars == 0 then
--                -- Primary bar
--                if fraction <= 0.25 then
--                    -- Low health - red
--                    bar.r, bar.g, bar.b = 255, 0, 0
--                elseif fraction <= 0.5 then
--                    -- Medium health - yellow
--                    bar.r, bar.g, bar.b = 255, 255, 0
--                else
--                    -- High health - green
--                    bar.r, bar.g, bar.b = 0, 255, 0
--                end
--            elseif #bars % 2 == 1 then
--                -- Secondary bar - cyan
--                bar.r, bar.g, bar.b = 0, 255, 255
--            else
--                -- Tertiary bar - blue
--                bar.r, bar.g, bar.b = 0, 0, 255
--            end
--            table.insert(bars, bar)
--        end
--
--        return bars
--    end
--
--    local BARS = {}
--    local subjects = {}
--
--    local function setup_bars()
--        BARS.width = math.ceil(ScrW() * 0.75)
--        BARS.height = math.max(math.ceil(BARS.width * 0.01), 12)
--        BARS.x = (ScrW() / 2) - math.ceil(BARS.width / 2)
--        BARS.y = math.ceil(BARS.height * 4.5)
--        BARS.radius = math.floor(BARS.height) * 2
--        BARS.text_x = ScrW() / 2
--
--        surface.CreateFont(
--            "FakasFriendlyHealthBars",
--            {
--                font = "Roboto",
--                extended = false,
--                size = math.ceil(BARS.height),
--                weight = 1000,
--                blursize = 0,
--                scanlines = 0,
--                antialias = true,
--                italic = false,
--                strikeout = false,
--                symbol = false,
--                rotary = false,
--                shadow = true,
--                additive = false,
--                outline = false
--            }
--        )
--    end
--
--    hook.Add("OnScreenSizeChanged", "FakasFriendlyBarsSetup", setup_bars)
--
--    hook.Add("HUDPaint", "FakasFriendlyHealthBars", function()
--
--        hook.Run("FakasFriendlyBarsModifySubjectsList", subjects)
--
--        if #subjects == 0 then
--            return
--        end
--
--        local count = 1
--        for _, subject in pairs(subjects) do
--            local name = subject.name
--
--            if not name then
--                print("Bars subject has missing data!")
--                continue
--            end
--
--            local y = BARS.y + BARS.height * 3 * count
--            local bars = get_bars(subject.fraction)
--            if #bars > 1 then
--                -- Only draw up to two of the last bars
--                bars = {bars[#bars -1], bars[#bars]}
--            end
--            for _, bar in pairs(bars) do
--                draw_bar(
--                    BARS.width * bar.fraction,
--                    BARS.height,
--                    BARS.radius,
--                    BARS.x,
--                    y,
--                    bar.r,
--                    bar.g,
--                    bar.b
--                )
--            end
--
--            draw.SimpleTextOutlined(
--                name,
--                "FakasFriendlyHealthBars",
--                BARS.text_x,
--                y - math.ceil(BARS.height * 1.5),
--                ent.colour,
--                TEXT_ALIGN_CENTER,
--                TEXT_ALIGN_TOP,
--                1,
--                color_black
--            )
--
--            count = count + 1
--        end
--    end)
--
--    setup_bars()
--end