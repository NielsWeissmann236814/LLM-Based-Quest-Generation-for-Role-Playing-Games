Shader = {}

Shader.defaults = {
  desaturation = 0.25,
  brightness   = 0.85,
  contrast     = 1.1,
  vignetteStr  = -0.2,
  tint         = {0.85, 0.93, 0.80}
}

Shader.hit = {
  desaturation = 0.25,
  brightness   = 0.85,
  contrast     = 1.1,
  vignetteStr  = 0.1,
  tint         = {0.9, 0.2, 0.2}
}

Shader.hitTime     = 0      -- current hit flash timer
Shader.hitDuration = 0.3    -- how long the flash lasts in seconds

function Shader:Load()
  self.game = love.graphics.newShader([[
    extern number desaturation;
    extern number brightness;
    extern number contrast;
    extern number vignetteStr;
    extern vec3   tint;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 pixel = Texel(tex, tc);

      // desaturate
      float grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
      pixel.rgb  = mix(pixel.rgb, vec3(grey), desaturation);

      // tint
      pixel.rgb *= tint;

      // brightness
      pixel.rgb *= brightness;

      // contrast
      pixel.rgb = (pixel.rgb - 0.5) * contrast + 0.5;

      // vignette
      vec2  uv   = tc - vec2(0.5, 0.5);
      float dist = length(uv);
      float vign = smoothstep(0.8, 0.3, dist * (1.0 + vignetteStr));
      pixel.rgb *= vign;

      return pixel * color;
    }
  ]])
  self:SetDefault()
end

function Shader:SetDefault()
  local d = self.defaults
  self.game:send("desaturation", d.desaturation)
  self.game:send("brightness",   d.brightness)
  self.game:send("contrast",     d.contrast)
  self.game:send("vignetteStr",  d.vignetteStr)
  self.game:send("tint",         d.tint)
end

function Shader:TriggerHit()
  self.hitTime = self.hitDuration
end

function Shader:Update(dt)
  if self.hitTime <= 0 then return end

  self.hitTime = self.hitTime - dt
  if self.hitTime <= 0 then
    self.hitTime = 0
    self:SetDefault()
    return
  end

  -- t goes 1 -> 0 as hit fades out
  local t   = self.hitTime / self.hitDuration
  local d   = self.defaults
  local h   = self.hit

  local function lerp(a, b, tt) return a + (b - a) * tt end

  self.game:send("desaturation", lerp(d.desaturation, h.desaturation, t))
  self.game:send("brightness",   lerp(d.brightness,   h.brightness,   t))
  self.game:send("contrast",     lerp(d.contrast,     h.contrast,     t))
  self.game:send("vignetteStr",  lerp(d.vignetteStr,  h.vignetteStr,  t))
  self.game:send("tint", {
    lerp(d.tint[1], h.tint[1], t),
    lerp(d.tint[2], h.tint[2], t),
    lerp(d.tint[3], h.tint[3], t)
  })
end

function Shader:Apply()
  love.graphics.setShader(self.game)
end

function Shader:Clear()
  love.graphics.setShader()
end

function Shader:SetInterior()
  local d = self.defaults
  self.game:send("desaturation", d.desaturation)
  self.game:send("brightness",   d.brightness)
  self.game:send("contrast",     d.contrast)
  self.game:send("vignetteStr",  0.3)
  self.game:send("tint",         d.tint)
end

function Shader:SetExterior()
  self:SetDefault()
end