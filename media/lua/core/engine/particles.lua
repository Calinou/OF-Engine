--[[!<
    Lua particle API for the client.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

--! Module: particles
var M = {}

@[server] do return M end

var capi = require("capi")
var ffi = require("ffi")

var assert = assert

ffi.cdef [[
    typedef struct particle_t {
        vec3f_t position, direction;
        int gravity, fade, millis;
        vec3f_t color;
        uchar flags;
        float size, val;
    } particle_t;
]]

var particle = ffi.metatype("particle_t", {
    __index = {
        get_owner = function(self)
            assert(self != nil)
            return capi.particle_get_owner(self)
        end,
        set_owner = function(self, ent)
            assert(self != nil)
            capi.particle_set_owner(self, ent.uid)
        end
    }
})

--[[!
    The flags available during particle renderer registration. Use bitwise
    OR to combine them. They include MOD (multiplied), RND4 (picks one of
    the corners at random), LERP (use sparingly, has order of blending
    issues), TRACK (for tracked particles with owner, mainly for
    muzzleflashes), BRIGHT, SOFT, HFLIP/VFLIP (randomly flipped),
    ROT (randomly rotated), FEW (initializes the renderer with fewparticles
    instead of maxparticles if it's lower), ICONGRID (NxN icon grid), SHRINK
    (particle will keep shrinking), GROW (particle will keep growing),
    COLLIDE (colliding particle with stain),  FLIP (a combination of HFLIP,
    VFLIP and ROT).
]]
M.flags = {:
    MOD      = 1 << 8,
    RND4     = 1 << 9,
    LERP     = 1 << 10,
    TRACK    = 1 << 11,
    BRIGHT   = 1 << 12,
    SOFT     = 1 << 13,
    HFLIP    = 1 << 14,
    VFLIP    = 1 << 15,
    ROT      = 1 << 16,
    FEW      = 1 << 17,
    ICONGRID = 1 << 18,
    SHRINK   = 1 << 19,
    GROW     = 1 << 20,
    COLLIDE  = 1 << 21,
    FLIP     = HFLIP | VFLIP | ROT
:}

--[[!
    Contains two predefined renderers that are mandatory - "text" and "icon".
]]
var renderers = {
    text = capi.particle_register_renderer_text("text"),
    icon = capi.particle_register_renderer_icon("icon")
}
M.renderers = renderers

--[[! Function: register_renderer_quad
    Registers a "quad renderer" (a renderer that draws individual textures).

    Arguments:
        - name - pick one.
        - tex - the texture path.
        - flags - see $flags, optional.
        - id - the stain id that gets spawned if the particle collides
          with geometry (the particle needs to have gravity and requires
          the COLLIDE flag to be set), optional.

    Returns:
        The particle renderer id (use to spawn particles) and a boolean value
        that is false when a renderer of such name is already registered
        (the id returned in this case is the id of the registered renderer).
]]
M.register_renderer_quad = capi.particle_register_renderer_quad

--[[! Function: register_renderer_tape
    Registers a tape renderer. See $register_renderer_quad, the parameters
    are the same.
]]
M.register_renderer_tape = capi.particle_register_renderer_tape

--[[! Function: register_renderer_trail
    Registers a trail renderer. See $register_renderer_quad, the parameters
    are the same.
]]
M.register_renderer_trail = capi.particle_register_renderer_trail

--[[! Function: register_renderer_fireball
    Registers a fireball renderer.

    Arguments:
        - name - pick one.
        - tex - the texture path.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_fireball = capi.particle_register_renderer_fireball

--[[! Function: register_renderer_lightning
    Registers a lightning renderer.

    Arguments:
        - name - pick one.
        - tex - the texture path.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_lightning = capi.particle_register_renderer_lightning

--[[! Function: register_renderer_flare
    Registers a lens flare renderer.

    Arguments:
        - name - pick one.
        - tex - the texture path.
        - flarecount - the maximum flare count (defaults to 64).
        - flags - optional.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_flare = capi.particle_register_renderer_flare

--[[! Function: register_renderer_text
    Registers a text renderer.

    Arguments:
        - name - pick one.
        - flags - optional.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_text = capi.particle_register_renderer_text

--[[! Function: register_renderer_icon
    Registers an icon renderer.

    Arguments:
        - name - pick one.
        - flags - optional.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_icon = capi.particle_register_renderer_icon

--[[! Function: register_renderer_meter
    Registers a progress meter renderer.

    Arguments:
        - name - pick one.
        - vs - if it's true, it's a two-color meter, otherwise only
          foreground on black.
        - flags - optional.

    Returns:
        See $register_renderer_quad.
]]
M.register_renderer_meter = capi.particle_register_renderer_meter

--[[! Function: get_renderer
    Given a name, returns the id of the renderer of that name
    or nothing (if no such renderer exists).
]]
M.get_renderer = capi.particle_get_renderer

--[[!
    Spawns a new generic particle.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - d - the target position (anything with x ,y, z).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - owner - optional (for tracking purposes, any dynamic entity can
          be and owner and it only takes effect when the TRACK flag is on).

    Returns:
        The particle object on which you can further set properties.
]]
M.new = function(tp, o, d, r, g, b, fade, size, gravity, owner)
    return capi.particle_new(tp, o.x, o.y, o.z,
        d.x, d.y, d.z, r, g, b, fade, size, gravity or 0,
        owner and owner.uid or -1)
end

--[[!
    Spawns a splash particle effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - rad - the radius.
        - num - the number of particles.
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - delay - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).
        - un - optional, makes the splash unbounded (alway keeps spawning
          particles).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.splash = function(tp, o, rad, num, r, g, b, fade, size, gravity, delay,
owner, un)
    return capi.particle_splash(tp, o.x, o.y, o.z, rad, num, r, g, b, fade,
        size, gravity or 0, delay or 0, owner and owner.uid or -1,
        un or false)
end

--[[!
    Spawns a trail particle effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - d - the target position (anything with x ,y, z).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.trail = function(tp, o, d, r, g, b, fade, size, gravity, owner)
    return capi.particle_trail(tp, o.x, o.y, o.z, d.x, d.y, d.z, r, g, b,
        fade, size, gravity or 0, owner and owner.uid or -1)
end

--[[!
    Spawns a text particle effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - text - the text to didsplay.
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.text = function(tp, o, text, r, g, b, fade, size, gravity, owner)
    return capi.particle_text(tp, o.x, o.y, o.z, text, #text, r, g, b, fade,
        size, gravity or 0, owner and owner.uid or -1)
end

--[[!
    Creates an icon. The renderer has to have an ICON flag set.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - ix, iy - horizontal and vertical position of the icon within
          the texture, supports 4x4 so the values are 0 to 3.
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.icon_generic = function(tp, o, ix, iy, r, g, b, fade, size, gravity, owner)
    return capi.particle_icon_generic(tp, o.x, o.y, o.z, ix, iy, r, g, b,
        fade, size, gravity or 0, owner and owner.uid or -1)
end

--[[!
    Creates an icon using a specialized icon renderer.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - itex - the icon texture.
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - gravity - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.icon = function(tp, o, itex, r, g, b, fade, size, gravity, owner)
    return capi.particle_icon(tp, o.x, o.y, o.z, itex, r, g, b, fade, size,
        gravity or 0, owner and owner.uid or -1)
end

--[[!
    Creates a meter particle. See also $meter_vs.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - val - the progress value (from 0 to 100).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.meter = function(tp, o, val, r, g, b, fade, size, owner)
    return capi.particle_meter(tp, o.x, o.y, o.z, val, r, g, b, 0, 0, 0,
        fade, size, owner and owner.uid or -1)
end

--[[!
    See $meter. The only difference is that you have to provide two sets
    of colors (r, g, b, r2, g2, b2).
]]
M.meter_vs = function(tp, o, val, r, g, b, r2, g2, b2, fade, size, owner)
    return capi.particle_meter(tp, o.x, o.y, o.z, val, r, g, b, r2, g2, b2,
        fade, size, owner and owner.uid or -1)
end

--[[!
    Creates a flare particle effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - d - the target position (anything with x ,y, z).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.flare = function(tp, o, d, r, g, b, fade, size, owner)
    return capi.particle_flare(tp, o.x, o.y, o.z, d.x, d.y, d.z, r, g, b,
        fade, size, owner and owner.uid or -1)
end

--[[!
    Creates a fireball effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - msize - the maximum fireball size (float).
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.fireball = function(tp, o, r, g, b, fade, size, msize, owner)
    return capi.particle_fireball(tp, o.x, o.y, o.z, r, g, b, fade, size,
        msize, owner and owner.uid or -1)
end

--[[!
    Creates a lens flare effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - sun - if true, it's a sun lens flare (fixed size regardless of
          the distance).
        - sparkle - true if a sparkle center should be displayed.
        - r, g, b - the color (three floats).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.lens_flare = function(tp, o, sun, sparkle, r, g, b)
    return capi.particle_lensflare(tp, o.x, o.y, o.z, sun, sparkle, r, g, b)
end

--[[!
    Creates a particle shape effect.

    The direction argument specifies the shape. From 0 to 2 you get a circle,
    3 to 5 is a cylinder shell, 6 to 11 is a cone shell, 12 to 14 is a plane
    volume, 15 to 20 is a line volume (wall), 21 is a sphere, 24 to 26 is
    a flat plane and adding 32 reverses the direction.

    The remainder of division of the direction argument by 3 specifies the
    actual direction - 0 is x, 1 is y, 2 is z (up).

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - rad - the radius.
        - dir - the direction.
        - num - the number of particles.
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - size - the particle size (float).
        - grav - optional, defaults to 0.
        - vel - the velocity (defaults to 200).
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.shape = function(tp, o, rad, dir, num, r, g, b, fade, size, grav, vel, owner)
    return capi.particle_shape(tp, o.x, o.y, o.z, rad, dir, num, r, g, b, fade,
        size, grav or 0, vel or 200, owner and owner.uid or -1)
end

--[[!
    Creaets a flame particle effect.

    Arguments:
        - tp - the renderer id.
        - o - the origin position (anything with x, y, z).
        - rad - the radius.
        - h - the height (float).
        - r, g, b - the color (three floats).
        - fade - the fade time in milliseconds.
        - dens - the density, optional, defaults to 3.
        - sc - the scale, optional, defaults to 2.
        - speed - optional, defaults to 200.
        - grav - optional, defaults to 0.
        - owner - optional (for tracking purposes, see $new).

    Returns:
        True on success, false on failure (with invalid type).
]]
M.flame = function(tp, o, rad, h, r, g, b, fade, dens, sc, speed, grav, owner)
    return capi.particle_flame(tp, o.x, o.y, o.z, rad, h, r, g, b, fade or 600,
        dens or 3, sc or 2, speed or 200, grav or -15,
        owner and owner.uid or -1)
end

return M
