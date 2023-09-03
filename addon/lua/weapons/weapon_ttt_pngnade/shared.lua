if SERVER then
    AddCSLuaFile()
end
if not TTT2 then
    return
end

local BAD_CREATE = "Sorry, something went wrong trying to summon %s."
local BAD_CREATE_REFUND = BAD_CREATE .. " You have been refunded %s credit%s."

SWEP.Base = "weapon_tttbasegrenade"
DEFINE_BASECLASS(SWEP.Base)

SWEP.Kind = WEAPON_EQUIP2
SWEP.WeaponID = AMMO_MOLOTOV
SWEP.HoldType = "grenade"
SWEP.InLoadoutFor = nil
SWEP.LimitedStock = true
SWEP.AllowDrop = true
SWEP.IsSilent = false
SWEP.NoSights = true
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.ViewModel = "models/weapons/v_eq_flashbang.mdl"
SWEP.WorldModel = "models/weapons/w_eq_flashbang.mdl"
SWEP.UseHands = true
SWEP.Slot = 7
SWEP.Weight = 5
SWEP.AutoSpawnable = false
SWEP.CanBuy = nil
SWEP.notBuyable = true
if SERVER and navmesh.GetNavAreaCount() > 0 then  -- TODO Manage Faklib better.
    -- NPCs don't work well (or often at all!) without a navmesh.
    SWEP.CanBuy = {ROLE_TRAITOR}
    SWEP.notBuyable = false
end
if CLIENT then
    SWEP.PrintName = "PNG Grenade"
    SWEP.Icon = "fakas/friendly-npcs/fakas/primary.png"
    SWEP.EquipMenuData = {
        type = "Weapon",
        desc = "PNG Grenade!\nSummons a random PNG on detonation.\n\nBe careful! Loyalty is a foreign concept to most PNGs."
    }
    -- TODO Do I need to override DrawViewModel and ViewModelDrawn?
end

function SWEP:Initialize()
    BaseClass.Initialize(self)
    if SERVER then
        self.created = false  -- Have we created our in-world grenade ent? Usually if we've thrown it
        self.summon_class = self:pick_summon()  -- Hold on to our class name in case we need to reference it later
        self.summon = self:create_summon()  -- Try to preload our summonable entity if we can
        if not IsValid(self.summon) then
            self:on_bad_summon()
        end
    end
end

function SWEP:GetGrenadeName()
    return "ttt_pngnade_proj"
end

function SWEP:CreateGrenade(src, ang, vel, angimp, ply)
    if not IsValid(self.summon) then
        -- Our summonable entity isn't valid for some reason - did it get removed?
        return self:on_bad_summon()
    end
    local grenade = BaseClass.CreateGrenade(self, src, ang, vel, angimp, ply)
    if not IsValid(grenade) then
        -- Something went wrong creating our grenade ent, let the base class deal with that if it wants.
        return grenade
    end

    grenade.summon = self.summon
    grenade.price = self:get_price()
    self.created = true
end

function SWEP:OnRemove()
    if SERVER and not self.created and IsValid(self.summon) then
        self.summon:Remove()
    end
    BaseClass.OnRemove(self)
end

function SWEP:pick_summon()
    local pngs = {}
    hook.Run("FakasFriendlyNPCsModifyPNGList", pngs)
    PrintTable(pngs)
    return Fakas.Lib.random_member(pngs)
end

function SWEP:create_summon()
    if not SERVER then
        return
    end
    if not scripted_ents.Get(self.summon_class) then
        print(string.format("Warning: PNG Grenade tried to create a non-existent class '%s'!", self.summon_class))
        return nil
    end
    return ents.Create(self.summon_class)
end

function SWEP:on_bad_summon()
    if not SERVER then
        return
    end

    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then
        return self:Remove()
    end

    local price = self:get_price()
    if price then
        local plural = ""
        if price ~= 1 then
            plural = "s"
        end
        owner:AddCredits(price)
        owner:ChatPrint(string.format(BAD_CREATE_REFUND, self.summon_class, price, plural))
    else
        owner:ChatPrint(string.format(BAD_CREATE, self.summon_class))
    end
    return self:Remove()
end

function SWEP:get_price()
    if not SERVER then
        return
    end

    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() or not self:WasBought(owner) then
        return 1  -- TODO Find out how to get the actual price of an item!
    end
    return nil
end
