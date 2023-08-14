AddCSLuaFile()



ENT.Base = "npc_friendly_common"
DEFINE_BASECLASS(ENT.Base)
ENT.AutomaticFrameAdvance = false

function ENT:Initialize()
    print("Initialising PNG!")
    if self.material == nil then
        self.material = Material("error")
    end

    BaseClass.Initialize(self)

    self.render_mode = RENDERMODE_TRANSCOLOR
    self:SetRenderMode(self.render_mode)
    self.RenderGroup = RENDERGROUP_TRANSLUCENT
    self:SetSpawnEffect(false)

    self:SetColor(Color(255, 255, 255, 1))
    self:SetModelScale(3)

    self:SetCollisionBounds(self.size[1], self.size[2])
end

function ENT:RenderOverride()
    render.SetMaterial(self.material)
    render.DrawSprite(self:GetPos() + Vector(0, 0, 64), 128, 128)
end
