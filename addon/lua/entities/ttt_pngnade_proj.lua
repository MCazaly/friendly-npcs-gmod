if SERVER then
    AddCSLuaFile()
end
if not TTT2 then
    return
end

local BAD_CREATE = "Sorry, something went wrong trying to summon %s."
local BAD_CREATE_REFUND = BAD_CREATE .. " You have been refunded %s credit%s."

ENT.Base = "ttt_basegrenade_proj"
DEFINE_BASECLASS(ENT.Base)

ENT.Type = "anim"
ENT.Model = Model("models/weapons/w_eq_flashbang_thrown.mdl")
ENT.ExplosionDamage = 0
ENT.ExplosionRadius = 0

AccessorFunc(ENT, "radius", "Radius", FORCE_NUMBER)
AccessorFunc(ENT, "dmg", "Dmg", FORCE_NUMBER)

function ENT:Initialize()
    self.summon = self.summon or Entity(-1)
    self.price = self.price or -1
    self.spawned = false

    return self.BaseClass.Initialize(self)
end

function ENT:Explode(tr)
    -- Detonate the grenade
    if SERVER then
        if not IsValid(self.summon) then
            -- Something's gone wrong, so we'll pretend to be an incendiary grenade.
            scripted_ents.Get("ttt_firegrenade_proj").Explode(self, tr)
            return self:on_bad_summon()
        end
        self:SetRadius(256)
        self:SetDmg(0)

        -- For all intents and purposes, the grenade no longer exists
        self:SetNoDraw(true)
        self:SetSolid(SOLID_NONE)

        -- Make sure we're not in the ground
        if tr.Fraction ~= 1.0 then
            self:SetPos(tr.HitPos + tr.HitNormal * 0.6)
        end

        -- Create our explosion
        local pos = self:GetPos()
        local effect = EffectData()
        effect:SetStart(pos)
        effect:SetOrigin(pos)
        effect:SetScale(self.ExplosionRadius * 0.3)
        effect:SetRadius(self.ExplosionRadius)
        effect:SetMagnitude(self.ExplosionDamage)
        if tr.Fraction ~= 1.0 then
            effect:SetNormal(tr.HitNormal)
        end
        util.Effect("Explosion", effect, true, true)
        util.BlastDamage(self, self:GetThrower(), pos, self.ExplosionRadius, self.ExplosionDamage)
        -- There's exactly zero documentation on what this does. Annoying.
        -- Looking at the TTT source, it looks like it's used for the detonation timer, but that shouldn't matter if
        -- we're already exploding?
        self:SetDetonateExact(0)
        self:spawn_summon()
        return self:Remove()
    end

    scripted_ents.Get("ttt_firegrenade_proj").Explode(self, tr)  -- Let the base class handle clientside stuff.
end

function ENT:OnRemove()
    if not self.spawned and IsValid(self.summon) then
        self.summon:Remove()
    end
end

function ENT:spawn_summon()
    if not IsValid(self.summon) then
        return self:on_bad_summon()
    end
    local pos = self:GetPos()
    self.summon:SetPos(pos)
    self.summon:Spawn()
    self.summon:Activate()
    self.spawned = true

    if self.summon.current_target then
        local nearest = nil
        local min_distance = math.huge
        local max_distance = self.summon.max_distance or 3500
        for _, ply in pairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() and not Fakas.Lib.is_spectator(ply) then
                local distance = pos:Distance(ply:GetPos())
                if distance < min_distance and distance < max_distance then
                    min_distance = distance
                    nearest = ply
                end
            end
        end
        if nearest then
            self.summon.current_target = nearest
        end
    end
    if self.summon.start_chase then
        self.summon:start_chase()
    end
end

function ENT:on_bad_summon()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then
        return
    end

    if self.price ~= -1 then
        local plural = ""
        if self.price ~= 1 then
            plural = "s"
        end
        owner:AddCredits(self.price)
        owner:ChatPrint(string.format(BAD_CREATE_REFUND, self.summon_class, self.price, plural))
    else
        owner:ChatPrint(string.format(BAD_CREATE, self.summon_class))
    end
end
