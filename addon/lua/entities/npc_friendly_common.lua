AddCSLuaFile()

local function navmesh_error(ent)
    if not IsValid(ent) or ent:GetClass() ~= ent:get_name() or Fakas.Lib.navmesh.exists() then
        return
    end

    PrintMessage(HUD_PRINTTALK, "Sorry, " .. ent.pretty_name .. " needs a map with a navmesh to work!")
end



ENT.Base = "base_nextbot"
DEFINE_BASECLASS(ENT.Base)
ENT.PhysgunDisabled = false
ENT.AutomaticFrameAdvance = false

function ENT:get_name()
    return "npc_friendly_" .. self.name
end

function ENT:OnInjured(_)
    -- TODO Damage sounds
end

function ENT:seek_target()
    -- Find the closest valid target in our range
    local range = self.convars.seek_range:GetInt()
    local square = range * range
    local position = self:GetPos()
    local targets = ents.FindInSphere(position, range)
    local target = nil

    for _, ent in pairs(targets) do
        if not self:should_target(ent) then
            continue
        end

        local distance = position:DistToSqr(ent:GetPos())
        if distance < square then
            -- This is the closest valid target we've found so far
            target = ent
            square = distance  -- Any other target must be closer than this one to be considered
        end
    end

    return target
end

function ENT:distance(pos)
    return self:GetPos():Distance(pos)
end

function ENT:distance_to_ent(ent)
    if IsValid(ent) then
        return self:distance(ent:GetPos())
    end
    return nil
end

function ENT:distance_to_target()
    return self:distance_to_ent(self.current_target)
end

function ENT:should_target(ent)
    return IsValid(ent) and self:targetable_ent(ent)
end

function ENT:targetable_player(ent)
    return not self.ignore_players:GetBool() and
        ent:IsPlayer() and
        not Fakas.Lib.is_spectator(ent) and
        ent:Alive() and
        ent:Health() > 0
end

function ENT:targetable_npc(ent)
    return Fakas.Lib.NPCs.is_npc(ent) and not self:is_ally(ent)
end

function ENT:targetable_prop(_)
    -- Most NPCs won't target props. They can override this method if they do.
    return false
end

function ENT:targetable_ent(ent)
    return not ent:GetClass():find("bullseye") and (
        self:targetable_player(ent) or
        self:targetable_npc(ent) or
        self:targetable_prop(ent)
    )
end

function ENT:is_ally(ent)
    return ent:GetClass() == self:GetClass()
end

function ENT:attack()
    local targets = ents.FindInSphere(self:GetPos(), self.attack_range)
    local success = false

    for _, ent in pairs(targets) do
        if self:should_target(ent) then
            -- Valid target
            success = self:attack_target(ent)
        elseif ent:GetMoveType() == MOVETYPE_VPHYSICS then
            -- Physics prop
            success = self:attack_prop(ent)
        end
    end

    if success then
        self.last_attack = CurTime()
    end

    return success
end

function ENT:knockback(target)
    if target:IsNPC() or (target:IsPlayer() and not IsValid(target:GetVehicle())) then
        local direction = self:hit_direction(target:GetPos())
        if target:IsOnGround() then
            direction.z = math.max(direction.z, -0.5)
        else
            direction.z = math.max(direction.z, -0.8)
        end
        -- print("HIT DIRECTION:")
        -- print(direction)
        -- print(target:IsOnGround())
        local yeet = direction * self.attack_force + self:calculate_vertical_knockback(target)
        --if target:IsPlayer() then
        --    target:SetVelocity(-target:GetVelocity())  -- Zero the player's momentum
        --end
        target:SetVelocity(yeet)
    end
end

function ENT:calculate_vertical_knockback(_)
    return vector_up * self.attack_force * self.knockback_up
end

function ENT:attack_target(target)
    if target:IsPlayer() and IsValid(target:GetVehicle()) then
        -- Target is currently in a vehicle, so we need to apply some force to it
        return self:attack_vehicle(target:GetVehicle())
    else
        -- Yeet the target before we deal damage
        self:knockback(target)
        return self:damage_target(target)
    end
    -- TODO play attack sound
end

function ENT:attack_vehicle(vehicle)
    if IsValid(vehicle) then
        self:attack_phys(vehicle)
        vehicle:TakeDamage(self.convars.attack_damage:GetInt(), self, self)
        return true
    end
    return false
    -- TODO play vehicle-specific sounds?
end

function ENT:attack_prop(ent)
    if not self.convars.break_props:GetBool() then
        return false
    end
    if ent:IsVehicle() then
        return self:attack_vehicle(vehicle)
    end

    return self:attack_phys(ent) and self:damage_target(ent)
end

function ENT:attack_phys(ent)
    -- Override anything that might try to stop us
    constraint.RemoveAll(ent)

    for ii = 0, ent:GetPhysicsObjectCount() -1 do
        local phys = ent:GetPhysicsObjectNum(ii)
        if IsValid(phys) then
            local mass = phys:GetMass()
            local position = ent:LocalToWorld(ent:OBBCenter())
            -- Make sure physics is enabled
            phys:Wake()
            phys:EnableMotion(true)
            -- TODO Do I need to put force and mass in parentheses?
            phys:ApplyForceOffset(self:hit_direction(position) * self.attack_force * mass, ent:NearestPoint(self:hit_source()))
            return mass > 6  -- Very light objects don't count towards cooldowns
        end
    end
    return false
end

function ENT:damage_target(ent)
    if IsValid(ent) then
        local health = ent:Health()
        local info = DamageInfo()
        info:SetAttacker(self)
        info:SetInflictor(self)
        info:SetDamage(self.convars.attack_damage:GetInt())
        info:SetDamageForce(self:hit_direction(ent:GetPos()) * self.attack_force + vector_up * 500)
        ent:TakeDamageInfo(info)
        return ent:Health() < health  -- Did we successfully deal some damage?
    end
    return false
end

function ENT:Explode(damage)
    local attacker = nil
    if IsValid(self) then
        attacker = self
    end
    local pos = self:GetPos()
    util.BlastDamage(attacker, attacker, pos, self.attack_range * 2, damage)

    local effect = EffectData()
    effect:SetStart(pos)
    effect:SetOrigin(pos)
    effect:SetScale(1)
    util.Effect("Explosion", effect)

    return true
end

function ENT:OnKilled(info)
    if self.alive then
        self.alive = false
        BaseClass.OnKilled(self, info)
        self:Remove()
    end
end



function ENT:hit_source()
    return self:LocalToWorld(self:OBBCenter())
end

function ENT:hit_direction(target_position)
    return (target_position - self:hit_source()):GetNormal()
end

function ENT:hide()
    self:SetRenderMode(RENDERMODE_NONE)
end

function ENT:show()
    self:SetRenderMode(self.render_mode)
end

function ENT:jump_at_target(target)
    if not self:IsOnGround() then
        return false
    end

    local distance = self:distance(target)
    local height = target:GetPos().z - self:GetPos().z

    if distance <= math.pow(self.attack_range + 200, 2) and height >= self.attack_range then
        self.loco:SetJumpHeight(self.jump_height)
        self.loco:Jump()
        self.last_jump = CurTime()
    end
end

function ENT:teleport(pos)
    self:SetPos(pos)
end

function ENT:path(destination)
    local start = SysTime()
    if start - self.failed_pathing < 5 or destination == null then
        -- Pathing went wrong, wait a bit before we attempt this again
        return false
    end


    if not self.move_path:Compute(self, destination) then
        -- No valid path to our target :(
        self.failed_paths = self.failed_paths + 1
        self.failed_pathing = start
        print("Can't reach the target!!!")
        return false
    end
    local finish = SysTime()
    self.failed_paths = 0

    if finish - start > 0.005 then
        -- Pathing failed took longer than 5ms, instigate a cooldown so we don't lag the server
        self.failed_pathing = finish
    end

    return true
end

function ENT:distance(target)
    return (target:GetPos() - self:GetPos()):Length2DSqr()
end

function ENT:should_stop()
    return GetConVar("ai_disabled"):GetBool() or not self.alive
end

function ENT:BehaveStart()
    self:setup_path()
end

function ENT:setup_path()
    self.move_path = Path("Follow")
    self.move_path:SetMinLookAheadDistance(500)
    self.move_path:SetGoalTolerance(10)
end

function ENT:can_jump()
    return self.allow_jump and CurTime() - self.last_jump > 1
end

function ENT:update_phase(phase)
    if phase == nil then
        phase = 1
    end
    if self.current_phase == nil then
        self.current_phase = phase
    end
end

function ENT:start_phase(phase)
    if phase == nil then
        phase = self.current_phase
    end

    self:phases()[phase]()
end

function ENT:BehaveUpdate()
    if self:should_stop() then
        return
    end

    self:update_phase()
    self:start_phase()
    self:attempt_unstick()
end

function ENT:attempt_unstick()
    local start = CurTime()

    if start - self.last_unstick > 1 and self.unstick_attempts < 3 then
        -- Bypass stuck checks early in case of being stuck in the ceiling
        self:unstick()
    end

    if start - self.last_unstick > 5 then
        self.unstick_attempts = 0
    end
end

function ENT:phase_1()
    self:chase()
    self:attempt_attack()

    if not IsValid(self.current_target) then
        self.current_phase = 2
    end
end

function ENT:phase_2()
    -- TODO Patrolling behaviour
    self:update_target()
    if IsValid(self.current_target) then
        self.current_phase = 1
    end
end

function ENT:move()
    self.move_path:Update(self)
end

function ENT:attempt_attack()
    if CurTime() - self.last_attack <= self.attack_cooldown then
        return false
    end
    return self:attack()  -- Hit anything unfortunate enough to get in our way
end


function ENT:update_target()
    local start = CurTime()
    if start - self.last_seek > self.convars.seek_refresh:GetFloat() then
        local target = self:seek_target()
        if target ~= self.current_target then
            -- New target identified, update pathing now
            self.current_target = target
            self.last_path = 0
        end
        self.last_seek = start
    end
end

function ENT:lunge(target)
    -- Lunge when we're close
    local distance = self:distance(target)
    local now = CurTime()

    if now - self.last_lunge >= self.lunge_time and distance <= 7500 and self.can_lunge then
        -- Lunge at the target
        -- print("Lunging!")
        self.last_lunge = now
        self.loco:SetDesiredSpeed(self.speed * self.lunge_speed)
        self.loco:SetAcceleration(self.acceleration * self.lunge_accel)
        self.loco:SetDeceleration(self.deceleration * self.lunge_decel)
    elseif now - self.last_lunge >= self.lunge_cooldown or distance >= 6000 or not self.can_lunge then
        -- Lunge period expired, return to normal speed
        self.loco:SetDesiredSpeed(self.speed)
        self.loco:SetAcceleration(self.acceleration)
        self.loco:SetDeceleration(self.deceleration)
    end
end

function ENT:target_pos(target)
    -- Find the floor under the target - that's our destination

    if not IsValid(target) or not target:IsInWorld() then
        return nil
    end

    local pos = target:GetPos()
    local line = util.TraceEntity(
            Fakas.Lib.trace(
                    pos,
                    pos - Vector(0, 0, 16384), -- This should cast directly to the floor
                    target
            ),
            target
    )

    if line.Hit and util.IsInWorld(line.HitPos) then
        -- Double check that the target position is inside the world
        return line.HitPos
    end
    return pos
end

function ENT:chase_target(target)
    self:lunge(target)

    if self:can_jump() then
        self:jump_at_target(self.current_target)
    end

    if self:path(self:target_pos(target)) then
        self:move()
        return true
    end
    return false
end

function ENT:chase()
    self:update_target()
    local start = CurTime()
    if IsValid(self.current_target) and start - self.last_path > self.convars.chase_refresh:GetFloat() then
        self.last_path = start
        return self:chase_target(self.current_target)
    end
    return false
end

function ENT:unstick()
    if self:IsOnGround() then
        return
    end
    local position = self:GetPos()
    local hull_min, hull_max = self:GetCollisionBounds()
    local hull = hull_max - hull_min
    local top = position + vector_up * hull.z
    local line = util.TraceLine(Fakas.Lib.trace(position, top, self), self)

    if line.Hit and line.HitNormal ~= vector_origin and line.Fraction > 0.5 then
        self:SetPos(position + line.HitNormal * (hull.z * (1 - line.Fraction)))
    end
    self.last_unstick = CurTime()
    self.loco:ClearStuck()
end

function ENT:OnStuck()
    self.last_unstick = CurTime()
    self:SetPos(self.move_path:GetPositionOnPath(self.move_path:GetCursorPosition() + 40 * math.pow(2, self.unstick_attempts)))
    self.unstick_attempts = self.unstick_attempts + 1
    self.loco:ClearStuck()
end

function ENT:phases()
    return  {
        function() self:phase_1() end,
        function() self:phase_2() end
    }
end

function ENT:Initialize()
    -- Base defaults
    if self.scale == nil then
        self.scale = 1
    end
    if self.name == nil then
        self.name = "common"
    end
    if self.pretty_name == nil then
        self.pretty_name = "Friendly Base NPC"
    end
    if self.size == null then
        self.size = { Vector(-13, -13, 0), Vector(13, 13, 70) }
    end
    self:SetModelScale(self.scale)
    self:set_collision_bounds(self.size[1], self.size[2])
    self.resource_root = "fakas/friendly-npcs/" .. self.name

    if self.defaults == nil then
        self.defaults = {
            seek_range = 10000,
            seek_refresh = 1,
            chase_refresh = 0.1,
            spawn_range = 0,
            attack_damage = 50,
            break_props = 1,
            health = 250
        }
    end
    if self.convars == nil then
        self.convars = Fakas.Lib.NPCs.create_convars(self)
    end

    self.speed = 500
    self.acceleration = 500
    self.deceleration = 500
    self.jump_height = 350
    self.knockback_up = 1
    self.ignore_players = GetConVar("ai_ignoreplayers")
    self.draw_offset = Vector(0, 0, 64)
    self.allow_jump = true
    self.attack_force = 500
    self.attack_cooldown = 1
    self.attack_range = 75

    self.defaults = {
        seek_range = 10000,
        seek_refresh = 1,
        chase_refresh = 0.1,
        spawn_range = 0,
        attack_damage = 35,
        break_props = 1,
        health = 250
    }

    self.failed_pathing = 0
    self.failed_paths = 0
    self.last_seek = 0
    self.last_path = 0
    self.last_attack = 0
    self.last_jump = 0
    self.last_unstick = 0
    self.last_lunge = 0
    self.can_lunge = true
    self.lunge_cooldown = 5
    self.lunge_time = 2
    self.lunge_speed = 3
    self.lunge_accel = 3
    self.lunge_decel = 0.5
    self.unstick_attempts = 0
    self.current_target = nil
    self.preferred_target = nil
    self.move_path = nil
    self.current_phase = nil
    self.alive = true

    self.sound = {
        attack = {
            paths = {},
            cooldown = { 5, 5 }
        },
        taunt = {
            paths = {},
            cooldown = { 2.5, 10 }
        },
        hurt = {
            paths = {},
            cooldown = { 2, 5 }
        },
        patrol = {
            paths = {},
            cooldown = { 10, 60 }
        },
        ambush = {
            paths = {},
            cooldown = { 60, 60 }
        },
        discover = {
            paths = {},
            cooldown = { 60, 60 }
        },
        kill = {
            paths = {},
            cooldown = { 10, 10 }
        },
        die = {
            paths = {},
            cooldown = { 60, 60 }
        },
        music = {
            chase = {},
            patrol = {}
        }
    }

    if SERVER then
        self:SetMaxHealth(self.convars.health:GetInt())
        self:SetHealth(self:GetMaxHealth())

        self.loco:SetDeathDropHeight(6000)
        self.loco:SetDesiredSpeed(self.speed)
        self.loco:SetAcceleration(self.acceleration)
        self.loco:SetDeceleration(self.deceleration)
        self.loco:SetJumpHeight(self.jump_height)
    end

    if CLIENT then
        language.Add(self:get_name(), self.pretty_name)
    end
    hook.Add("PlayerSpawnedNPC", self:get_name() .. "_missing_navmesh", function()
        navmesh_error(self)
    end)
end

function ENT:OnReloaded()
    self:Initialize()
end

function ENT:OnRemove()
    -- Placeholder
end

function ENT:set_collision_bounds(min, max)
    -- To be overridden for special cases, like PNGs!
    self:SetCollisionBounds(min, max)
end

list.Set("NPC", "npc_friendly_common", {
    Name = "Friendly Common",
    Class = "npc_friendly_common",
    Category = "Friendly Group",
    AdminOnly = true
})
