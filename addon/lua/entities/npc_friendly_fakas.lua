-- TODO: TTT map reset breaks music? delay round end until all fakases are dead, fakas grenade, disable pings while cloaked, reunite FakLib


AddCSLuaFile()

ENT.Base = "npc_friendly_png"
DEFINE_BASECLASS(ENT.Base)

ENT.name = "fakas"
ENT.pretty_name = "Fakas"
ENT.size = { Vector(-13, -13, 0), Vector(13, 13, 70) }
ENT.textures = {
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
    "nappa",
}

local DECLOAKED = 0
local CLOAKING = 1
local CLOAKED = 2
local DECLOAKING = 3

local NONE = -1
local INACTIVE = 0
local ACTIVE = 1
local CHASE = 2

local CLOAK_STRING = "FakasFriendlyCloak"
local MUSIC_STRING = "FakasFriendlyMusic"
local TRAILS = {}

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
        local fakases = ents.FindByClass("npc_friendly_fakas")
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
                -- print(fakas.current_target:Nick() .. " is a player!")
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
                send_music(CHASE, ply)
            else
                send_music(ACTIVE, ply)
            end
        end
    end


    -- Set up networking
    util.AddNetworkString(CLOAK_STRING)
    util.AddNetworkString(MUSIC_STRING)

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
        if IsValid(ent) and ent:GetClass() == "npc_friendly_fakas" and ent.alive == false then
            ent:Explode(100)
        end
    end)
    if engine.ActiveGamemode() == "terrortown" then
        hook.Add("TTTEndRound", "FriendlyNPCsFakasCleanupTTTEndRound", function()
            for _, fakas in ents.FindByClass("npc_friendly_fakas") do
                if IsValid(fakas) then
                    fakas:Remove()
                end
            end
        end)
    end

end

function ENT:Initialize()
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

    self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)  -- We don't want players to get stuck on us

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
    self.downtime_start = nil
    self.downtime_last = nil
    self.heal_rate = 25
    self.last_teleport = 0
    self.teleport_wait = 2
    self.haste = 1
    self.airshots = 0
    self.max_distance = 3500
    self.material = self:create_material()
    self.sounds = {
        fadein = self.resource_root .. "/fadein.wav",
        fadeout = self.resource_root .. "/fadeout.wav",
        detected = self.resource_root .. "/detected.wav"
    }
end

function ENT:create_material()
    local override = nil
    local month = os.date("*t").month
    if month == 12 then
        override = "christmas"
    elseif month == 10 then
        override = "pumpkin"
    end

    return BaseClass.create_material(self, override)
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

function ENT:attack()
    -- When dealing with explosions, we only attack once per cycle and always assume it's a success
    local targets = ents.FindInSphere(self:GetPos(), self.attack_range)
    local target = nil
    local prop = nil

    for _, ent in pairs(targets) do

        local targetable_prop = self:targetable_prop(ent)
        if self:should_target(ent) and not targetable_prop then
            target = ent
            break
        elseif prop == nil and targetable_prop then
            prop = self.current_target
        end
    end

    if target ~= nil then
        self:attack_target(target)
        self.last_attack = CurTime()
        return true
    elseif prop ~= nil then
        self:attack_prop(prop)
        -- Wait longer after attacking a prop, spamming explosions hurts performance
        self.last_attack = CurTime() + 1
        return true
    end

    return false
end

function ENT:attack_target(target)
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

function ENT:BehaveUpdate()
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
    if CLIENT and Fakas.Lib.is_spectator(LocalPlayer()) then
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
            if pos:Distance(target:GetPos()) < self.max_distance and self:can_fit(pos) then
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
        teleport_pos = self:target_player(self.preferred_target)
        if teleport_pos ~= nil then
            self:set_target(self.preferred_target)
            return teleport_pos
        end
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

    if #targets == 0 and last_choice ~= nil then
        print("Uh oh, we're falling back to our last choice!")
        table.insert(targets, last_choice)
    end

    if #targets > 0 then
        local target = Fakas.Lib.random_member(targets)
        self:set_target(target[1])
        return target[2]
    end

    print("Couldn't find anything to target!")
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
    self.haste = 1
    if self.current_target:GetClass() == "prop_physics" then
        self.haste = 10
    elseif Fakas.Lib.NPCs.is_npc(self.current_target) then
        self.haste = 5
    end
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
    local detector = self:detected()
    if IsValid(detector) then
        return self:reveal(detector)
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
    local should = self:should_target(self.current_target)  -- Our target is dead or unavailable
    if not should then
        return self:end_chase()
    end

    local now = CurTime()
    local chase_done = now - self.chase_start >= self.chase_time  -- We've chased too long
    local too_far = self:target_distance() > self.max_distance  -- Our target is too far away
    local lost = too_far or self.failed_paths >= 2  -- We can't reach our target

    -- print(self:target_distance())

    if chase_done then
        return self:end_chase()
    end
    if lost and self.current_target:IsPlayer() and not self.should_target(self.preferred_target) then
        self.haste = math.max(self.haste, 5)  -- We didn't quite get our fill, let's go early next time...
        self.preferred_target = self.current_target  -- Let me show you why you shouldn't cheese my pathing...
        print(self.preferred_target:Nick() .. " is now my preferred target!")
        return self:end_chase()
    end
    if self:should_target(self.preferred_target) and self.preferred_target ~= self.current_target and self:target_player(self.preferred_target) then
        -- Our preferred target is available - let's go kill them!
        print("Rerouting to preferred target!")
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
        -- Increase our attack range while we're in the air to make airshots easier, but also decrease damage a bit
        self.attack_range = self.default_attack_range * math.min(self.airshots + 2.25, 3)
        self.damage_scale = 0.5
    end
    if not self.current_target:IsOnGround() then
        -- Try not to launch already airborne targets too high, fall damage isn't fun
        self.knockback_up = self.default_knockback_up / math.min(self.airshots + 2.25, 5)
        -- IF we get a successful airshot, push them away further so they have more time to escape
        self.attack_force = self.default_attack_force * math.max(self.airshots * 1.25, 1.1)

        if self:attempt_attack() then
            self.airshots = self.airshots + 1
            -- print("Airshots: " .. self.airshots)
        end
        return
    end
    self:attempt_attack()
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
    self.downtime_start = now
    self.current_phase = 2
end

function ENT:end_downtime()
    self.downtime_last = nil
    self.downtime_start = nil
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
    local last_obs_mode = nil

    local function update_cloaks()
        for _, fakas in pairs(ents.FindByClass("npc_friendly_fakas")) do
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
            print("Initialising music!")
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

    timer.Create("FakasFriendlyFakasSpectatorTimer", 1, 0, function()
        local ply = LocalPlayer()
        if not IsValid(ply) then
            return
        end
        local obs_mode = ply:GetObserverMode()
        if obs_mode ~= last_obs_mode then
            -- Just in case.
            last_obs_mode = obs_mode
            update_cloaks()
        end

    end)

    timer.Create("FakasFriendlyFakasTrackTimer", 1, 0, function()
        if not music_ready then  -- Sometimes this takes a while, not sure why...
            music_ready = setup_tracks()
            timer.Remove("FakasFriendlyFakasTrackTimer")
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
        if not music_ready then  -- Music hasn't been set up yet, we'll wait for the next one
            return
        end

        local mode = net.ReadInt(3)
        -- print("MODE: " .. mode)
        if mode == NONE then
            return stop_music()
        end
        play_track(music[mode])
    end)
end


list.Set("NPC", "npc_friendly_fakas", {
    Name = "Fakas",
    Class = "npc_friendly_fakas",
    Category = "Friendly Group",
    AdminOnly = true
})
