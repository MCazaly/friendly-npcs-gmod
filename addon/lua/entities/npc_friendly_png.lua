AddCSLuaFile()



ENT.Base = "npc_friendly_common"
DEFINE_BASECLASS(ENT.Base)
ENT.AutomaticFrameAdvance = false
ENT.scale = 3
ENT.textures = {}

function ENT:Initialize()
    BaseClass.Initialize(self)

    if self.name == "common" then
        self.material = Material("error")
    else
        self.material = self:create_material()
    end
    self.render_mode = RENDERMODE_TRANSCOLOR
    self:SetRenderMode(self.render_mode)
    self.RenderGroup = RENDERGROUP_TRANSLUCENT
    self:SetSpawnEffect(false)

    self:SetColor(Color(255, 255, 255, 1))
end

function ENT:create_material(override)
    local texture = "primary"

    if override ~= nil then
        texture = override
    elseif math.random(0,1) == 1 then
        texture = self:random_texture()
    end

    return Material(self:texture(texture), "smooth mips")
end

function ENT:random_texture()
    return Fakas.Lib.random_member(self.textures)
end

function ENT:texture(name)
    return self.resource_root .. "/" .. name .. ".png"
end


function ENT:RenderOverride()
    render.SetMaterial(self.material)
    render.DrawSprite(self:GetPos() + Vector(0, 0, 64), 128, 128)
end

function ENT:set_collision_bounds(min, max)
    -- TODO Get a better underlying model to handle collision and hit detection separately
    BaseClass.set_collision_bounds(self, min / self.scale, max / self.scale)
end
