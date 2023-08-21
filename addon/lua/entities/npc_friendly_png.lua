AddCSLuaFile()



ENT.Base = "npc_friendly_common"
DEFINE_BASECLASS(ENT.Base)
ENT.AutomaticFrameAdvance = false
ENT.scale = 3

function ENT:Initialize()
    -- print("Initialising PNG!")

    BaseClass.Initialize(self)

    if self.name == "common" then
        self.material = Material("error")
    else
        self.material = Material("fakas/friendly-npcs/" .. self.name .. "/primary.png")
    end
    self.render_mode = RENDERMODE_TRANSCOLOR
    self:SetRenderMode(self.render_mode)
    self.RenderGroup = RENDERGROUP_TRANSLUCENT
    self:SetSpawnEffect(false)

    self:SetColor(Color(255, 255, 255, 1))
end

function ENT:RenderOverride()
    render.SetMaterial(self.material)
    render.DrawSprite(self:GetPos() + Vector(0, 0, 64), 128, 128)
end

function ENT:set_collision_bounds(min, max)
    -- TODO Get a better underlying model to handle collision and hit detection separately
    BaseClass.set_collision_bounds(self, min / self.scale, max / self.scale)
end
