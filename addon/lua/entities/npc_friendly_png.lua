AddCSLuaFile()



ENT.Base = "npc_friendly_common"
DEFINE_BASECLASS(ENT.Base)
ENT.AutomaticFrameAdvance = false
ENT.scale = 1
ENT.textures = {}

function ENT:Initialize()
    if self.initialized then
        return
    end

    BaseClass.Initialize(self)

    self.material = self:create_material(self:GetTexture())

    self.render_mode = RENDERMODE_TRANSCOLOR
    self:SetRenderMode(self.render_mode)
    self.RenderGroup = RENDERGROUP_TRANSLUCENT
    self:SetSpawnEffect(false)

    self:SetColor(Color(255, 255, 255, 1))
end

function ENT:SetupDataTables()
    BaseClass.SetupDataTables(self)
    self:NetworkVar("String", 0, "Texture")
end

function ENT:pick_texture(_, _)
    error(string.format("pick_texture not overriden for %q!"), self)
end

function ENT:create_material(texture)
    return Fakas.Lib.Graphics.png_material(texture)
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
