if not TTT2 then
    return
end
if SERVER then
    AddCSLuaFile()
end

local THIS = "weapon_ttt_pngnade"
local BAD_CREATE = "Sorry, something went wrong trying to summon %s."
local BAD_CREATE_REFUND = BAD_CREATE .. " You have been refunded %s credit%s."
local BUYABLE_STRING = "FakasFriendlyPNGNadeSetBuyable"

local function send_buyable(ply)
    net.Start(BUYABLE_STRING)
    net.WriteBool(not weapons.GetStored(THIS).notBuyable)
    if ply then
        net.Send(ply)
        return
    end
    net.Broadcast()
end

local function set_buyable(buyable)
    print("BUYABLE:")
    print(buyable)

    local class = weapons.GetStored(THIS)
    if buyable then
        class.CanBuy = {ROLE_TRAITOR}
        class.credits = 1
        if SERVER then
            send_buyable()
            AddEquipmentToRole(ROLE_TRAITOR, class)
        end
    else
        class.CanBuy = {}
        if SERVER then
            send_buyable()
            RemoveEquipmentFromRole(ROLE_TRAITOR, class)
        end
    end
    PrintTable(class)
end

local function update_buyable()
    set_buyable(navmesh.GetNavAreaCount() > 0)  -- TODO: Handle FakLib better.
end

SWEP.Base = "weapon_tttbasegrenade"
DEFINE_BASECLASS(SWEP.Base)

SWEP.PrintName = "PNG Grenade"
SWEP.Icon = "fakas/friendly-npcs/fakas/primary.png"
SWEP.EquipMenuData = {
    type = "Weapon",
    desc = "PNG Grenade!\nSummons a random PNG on detonation.\n\nBe careful! Loyalty is a foreign concept to most PNGs."
}
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
SWEP.WorldModel = "models/pngbottle/pngbottle.mdl"
SWEP.UseHands = true
SWEP.Slot = 7
SWEP.Weight = 5
SWEP.AutoSpawnable = false
SWEP.CanBuy = {
    [ROLE_TRAITOR] = ROLE_TRAITOR
}
SWEP.notBuyable = false


if SERVER then
    util.AddNetworkString(BUYABLE_STRING)
    hook.Add("TTTBeginRound", "FakasFriendlyPNGNadeReload", function()
        update_buyable()
    end)
    --hook.Add("PlayerSpawn", "FakasFriendlyPNGNadePlayerUpdate", function(ply, _)
    --    if not IsValid(ply) then
    --        return
    --    end
    --    --send_buyable({ply})
    --    update_buyable()
    --end)
else
    net.Receive(BUYABLE_STRING, function()
        set_buyable(net.ReadBool())
    end)

    hook.Add("HUDPaintBackground", "FakasFriendlyDrawPNGNadeSprite", function()
        local weapon = LocalPlayer():GetActiveWeapon()
        if IsValid(weapon) and weapon:GetClass() == THIS and weapon.submaterial ~= nil then
            local size = {
                w = math.floor(math.min(ScrW(), ScrH()) / 8 + 0.5),
                h = math.floor(math.min(ScrW(), ScrH()) / 8 + 0.5)
            }
            local pos = {
                x = size.w,
                y = ScrH() - (size.h * 2)
            }
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(weapon.submaterial)
            surface.DrawTexturedRect(pos.x, pos.y, size.w, size.h)
        end
    end)

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

        for index, _  in pairs(self:GetMaterials()) do
            self:SetSubMaterial(index, self.summon.material)
            print(self:GetSubMaterial(index))
        end
    else
        self.submaterial = nil
    end
end

function SWEP:SetupDataTables()
    self:NetworkVar("String", 0, "SummonTexture")
    if BaseClass.SetupDataTables then
        BaseClass.SetupDataTables(self)
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

function SWEP:Think()
    if SERVER and self.summon ~= nil and self.summon.GetTexture ~= nil and #self:GetSummonTexture() == 0 then
        self:SetSummonTexture(self.summon:GetTexture())
    end
    if CLIENT then
        if self.submaterial == nil then
            self:update_submaterial()
        end
    end
    BaseClass.Think(self)
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
    local summon = ents.Create(self.summon_class)
    summon:Initialize()
    summon.ready = false
    return summon
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
        return nil
    end
    return self.credits
end

function SWEP:set_submaterial(texture)
    self.submaterial = Fakas.Lib.Graphics.png_material(texture)
end

function SWEP:update_submaterial()
    local texture = self:GetSummonTexture()
    if texture ~= nil and #texture ~= 0 then
        self:set_submaterial(texture)
        for index, _  in pairs(self:GetMaterials()) do
            self:SetSubMaterial(index, self.submaterial:GetName())
            print(self:GetSubMaterial(index))
        end
        return true
    end
    return false
end
