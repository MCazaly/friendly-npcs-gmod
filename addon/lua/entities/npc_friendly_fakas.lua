-- TODO: Cloak detection, spectator view, music, reunite faklib, en-route cloak? backstab?


AddCSLuaFile()

ENT.Base = "npc_friendly_png"
DEFINE_BASECLASS(ENT.Base)

ENT.name = "fakas"
ENT.pretty_name = "Fakas"
ENT.size = { Vector(-13, -13, 0), Vector(13, 13, 72) }

local DECLOAKED = 0
local CLOAKING = 1
local CLOAKED = 2
local DECLOAKING = 3

local CLOAK_STRING = "FakasFriendlyCloak"
local TRAILS = {}

if SERVER then
    -- Set up networking
    util.AddNetworkString(CLOAK_STRING)

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
end

function ENT:Initialize()
    print("Initialising Fakas!")
    self.defaults = {
        seek_range = 10000,
        seek_refresh = 1,
        chase_refresh = 0.1,
        spawn_range = 0,
        attack_damage = 50,
        break_props = 1,
        health = 1500
    }
    self.convars = Fakas.Lib.NPCs.create_convars(self)

    BaseClass.Initialize(self)

    self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)  -- We don't want players to get stuck on us

    self.knockback_up = 8
    self.default_knockback_up = 8
    self.attack_force = 70
    self.default_attack_force = 70
    self.attack_cooldown = 0.5
    self.attack_range = 75
    self.default_attack_range = 75
    self.damage_scale = 1
    self.can_lunge = false
    self.lunge_cooldown = 1
    self.lunge_time = 5
    self.cloak_time = 1
    self.cloak_start = 0
    self.cloak_status = DECLOAKED
    self.cloak_hook = "FakasCloak_" .. self:GetClass() .. "_" .. self:EntIndex()
    self.chase_start = nil
    self.chase_time = 45
    self.downtime_min = 15
    self.downtime_start = nil
    self.downtime_last = nil
    self.heal_rate = 25
    self.last_teleport = 0
    self.teleport_wait = 2
    self.haste = 1
    self.material = Material("fakas/npc_fakas.png", "smooth mips")  -- Avoid duplicating this, cloak breaks if we do
    self.sounds = {
        fadein = self.resource_root .. "/fadein.wav",
        fadeout = self.resource_root .. "/fadeout.wav",
        detected = self.resource_root .. "/detected.wav"
    }
end

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TargetID")
end

function ENT:attack_target(target)
    self:knockback(target)
    return self:Explode(self.convars.attack_damage:GetInt() * self.damage_scale)
end

function ENT:cloak_server()
    net.Start(CLOAK_STRING)
    net.WriteInt(self:EntIndex(), 32)
    net.WriteInt(self.cloak_status, 32)
    net.Broadcast()
end

function ENT:BehaveUpdate()
    BaseClass.BehaveUpdate(self)
end

function ENT:cloak_client()
    self.cloak_start = CurTime() - 0.001  -- Start a millisecond behind
    hook.Add("Think", self.cloak_hook, function()
        if not IsValid(self) then
            hook.Remove("Think", self.cloak_hook)
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
    self.material:SetFloat("$alpha", alpha)
end

function ENT:alpha_progress()
    duration = 0.6

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
    if not target:IsValid() then
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
            if self:can_fit(trail[ii]) then
                -- We can fit here! Good for teleporting to.
                return trail[ii]
            end
        end
        return nil -- Nowhere good to teleport to :(
    end

    return target:GetPos()  -- We don't give a shit about being fair to NPCs or props.
end

function ENT:update_target()
    local targets = {}
    for _, ply in pairs(player.GetAll()) do
        local teleport_pos = self:teleport_pos(ply)

        if self:should_target(ply) and teleport_pos ~= nil then
            table.insert(targets, {ply, teleport_pos})
        end
    end

    if #targets == 0 then
        -- We didn't find a player, target an NPC or something destructible this round instead
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
            targets = npcs
        end
        if #breakables > 0 then
            targets = breakables
        end
    end

    if #targets > 0 then
        local target = Fakas.Lib.random_member(targets)
        self:set_target(target[1])
        return target[2]
    end

    print("Couldn't find anything to target!")
    self.haste = 1
    self:set_target(nil)
    return nil  -- Oh dear. Nothing to target...
end

function ENT:should_target(ent)
    local class = ent:GetClass()
    local should = BaseClass.should_target(self, ent) or (class == "prop_physics" and ent:Alive() and ent:Health() > 0 and ent:GetMaxHealth() > 0)

    return should
end

function ENT:set_target(target)
    if not IsValid(target) or not target:Alive() then
        -- Not a valid target, reset to nil
        self.current_target = nil

        if self.haste <= 1 then  -- Don't spam clients with changes while we're in haste
            self:SetTargetID(0)  -- Inactive music
        end
        return
    end

    -- Something we can actually target!
    self.current_target = target
    self.haste = 1
    if self.current_target:GetClass() == "prop_physics" then
        self.haste = 10
    elseif Fakas.Lib.NPCs.is_npc(self.current_target) then
        self.haste = 5
    end

    if target:IsPlayer() then
        self:SetTargetID(target:UserID(self.current_target))  -- Chase music for target, active music for other players
        return
    end
    self:SetTargetID(-1)  -- Active music for all players
end

function ENT:attack_prop(ent)
    -- Use explosions for prop attacks too
    self:attack_target(ent)
    BaseClass.attack_target(self, ent)
end

function ENT:phase_1()
    -- We've just spawned or we've stopped chasing, cloak and teleport away so we can heal and/or wait for a target
    if self.cloak_status == DECLOAKED then
        self:cloak()
    end

    if self.cloak_status == CLOAKED and self:teleport_random() then
        self:start_downtime()
    end
end

function ENT:phase_2()
    -- We've teleported away, wait until we're fully healed and the minimum time has elapsed
    local detector = self:detected()
    if IsValid(detector) then
        self:EmitSound(self.sounds.detected, 100)
        self:set_target(detector)
        self:end_downtime()
        return
    end

    local now = CurTime()
    if now - self.downtime_last >= 1 then
        -- Heal until we've reached max health
        self:SetHealth(math.min(self:Health() + self.heal_rate, self:GetMaxHealth()))
    end

    if self:Health() == self:GetMaxHealth() and (now - self.downtime_start) * self.haste >= self.downtime_min then
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
    local now = CurTime()
    if not IsValid(self.current_target) or not self.current_target:Alive() or now - self.chase_start >= self.chase_time then
        -- We've lost our target or we've chased for too long, this one gets away...
        self:end_chase()
        return
    end

    self.attack_range = self.default_attack_range
    self.knockback_up = self.default_knockback_up
    self.attack_force = self.default_attack_force
    self.damage_scale = 1
    self.can_lunge = false

    if not self:IsOnGround() then
        -- Increase our attack range while we're in the air to make airshots easier, but also decrease damage a bit
        self.attack_range = self.default_attack_range * 2.3
        self.damage_scale = 0.7
    end
    if not self.current_target:IsOnGround() then
        self.can_lunge = true  -- Fakas can only lunge at airborne targets
        -- Try not to launch already airborne targets too high, fall damage isn't fun
        self.knockback_up = self.default_knockback_up * 0.33
        -- IF we get a successful airshot, push them away further so they have more time to escape
        self.attack_force = self.default_attack_force * 2.75
    end
    self:chase_target(self.current_target)
    self:attempt_attack()
end

function ENT:start_downtime()
    local now = CurTime()
    self.downtime_last = now
    self.downtime_start = now
    self.current_phase = 2
end

function ENT:end_downtime()
    self.downtime_last = nil
    self.downtime_start = nil
    self.current_phase = 3
end

function ENT:start_chase()
    local now = CurTime()
    self.chase_start = now
    self.current_phase = 4
end

function ENT:end_chase()
    self.chase_start = nil
    self:set_target(nil)
    self.current_phase = 1
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


hook.Add("EntityRemoved", "FriendlyNPCsFakasDeath", function(ent)
    if SERVER and IsValid(ent) and ent:GetClass() == "npc_friendly_fakas" and ent.alive == false then
        ent:Explode(100)
    end
end)

if CLIENT then
    local music = {}

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

    local function direct_music()  -- TODO Replace this with a proper server-side music director
        local fakases = ents.FindByClass("npc_friendly_fakas")
        local active = false

        if #fakases < 1 then
            stop_music()
            return
        end
        for _, fakas in pairs(fakases) do
            local target = fakas:GetTargetID()
            if target == LocalPlayer():UserID() then
                play_track(music.chase)
                return  -- Nothing takes priority over chase, exit early
            end
            if target ~= 0 then
                active = true
            end
        end

        if active then
            play_track(music.active)
            return
        end
        play_track(music.inactive)
    end

    timer.Create("FakasFriendlyFakasTrackTimer", 1, 0, function()
        if game.GetWorld() ~= nil then  -- Sometimes this takes a while, not sure why...
            music.inactive = create_track("fakas/friendly-npcs/fakas/inactive.wav")
            music.active = create_track("fakas/friendly-npcs/fakas/active.wav")
            music.chase = create_track("fakas/friendly-npcs/fakas/chase.wav")

            timer.Create("FakasFriendlyFakasMusicTimer", 1, 0, direct_music)
            timer.Remove("FakasFriendlyFakasTrackTimer")
        end
    end)

    net.Receive(CLOAK_STRING, function()
        local ent = Entity(net.ReadInt(32))
        if IsValid(ent) then
            ent.cloak_status = net.ReadInt(32)
            ent:cloak_client()
        end
    end)
end



list.Set("NPC", "npc_friendly_fakas", {
    Name = "Fakas",
    Class = "npc_friendly_fakas",
    Category = "Friendly Group",
    AdminOnly = true
})
