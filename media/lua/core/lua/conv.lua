--[[!<
    Provides extra conversion functions.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

--! Module: conv
var M = {}

--[[!
    Converts an integral value to be treated as hexadecimal color code to
    r, g, b values (ranging 0-255). Returns three separate values.
]]
M.hex_to_rgb = function(hex)
    return hex >> 16, (hex >> 8) & 0xFF, hex & 0xFF
end

--[[!
    Converts r, g, b color values (0-255) to a hexadecimal color code.
]]
M.rgb_to_hex = function(r, g, b)
    return b | (g << 8) | (r << 16)
end

--[[!
    Takes the r, g, b values (0-255) and returns the matching h, s, l
    values (0-1).
]]
M.rgb_to_hsl = function(r, g, b)
    r, g, b = (r / 255), (g / 255), (b / 255)
    var mx = math.max(r, g, b)
    var mn = math.min(r, g, b)
    var h, s
    var l = (mx + mn) / 2

    if mx == mn do
        h = 0
        s = 0
    else
        var d = mx - mn
        s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
        if     mx == r do h = (g - b) / d + (g < b and 6 or 0)
        elif mx == g do h = (b - r) / d + 2
        elif mx == b do h = (r - g) / d + 4 end
        h = h / 6
    end

    return h, s, l
end

--[[!
    Takes the r, g, b values (0-255) and returns the matching h, s, v
    values (0-1).
]]
M.rgb_to_hsv = function(r, g, b)
    r, g, b = (r / 255), (g / 255), (b / 255)
    var mx = math.max(r, g, b)
    var mn = math.min(r, g, b)
    var h, s
    var v = mx

    var d = mx - mn
    s = (mx == 0) and 0 or (d / mx)

    if mx == mn do
        h = 0
    else
        if     mx == r do h = (g - b) / d + (g < b and 6 or 0)
        elif mx == g do h = (b - r) / d + 2
        elif mx == b do h = (r - g) / d + 4 end
        h = h / 6
    end

    return h, s, v
end

--[[!
    Takes the h, s, l values (0-1) and returns the matching r, g, b
    values (0-255).
]]
M.hsl_to_rgb = function(h, s, l)
    var r, g, b

    if s == 0 do
        r = l
        g = l
        b = l
    else
        var hue2rgb = function(p, q, t)
            if t < 0 do t = t + 1 end
            if t > 1 do t = t - 1 end
            if t < (1 / 6) do return p + (q - p) * 6 * t end
            if t < (1 / 2) do return q end
            if t < (2 / 3) do return p + (q - p) * (2 / 3 - t) * 6 end
            return p
        end

        var q = l < 0.5 and l * (1 + s) or l + s - l * s
        var p = 2 * l - q

        r = hue2rgb(p, q, h + 1 / 3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1 / 3)
    end

    return (r * 255), (g * 255), (b * 255)
end

--[[!
    Takes the h, s, v values (0-1) and returns the matching r, g, b
    values (0-255).
]]
M.hsv_to_rgb = function(h, s, v)
    var r, g, b

    var i = math.floor(h * 6)
    var f = h * 6 - i
    var p = v * (1 - s)
    var q = v * (1 - f * s)
    var t = v * (1 - (1 - f) * s)

    if i % 6 == 0 do
        r, g, b = v, t, p
    elif i % 6 == 1 do
        r, g, b = q, v, p
    elif i % 6 == 2 do
        r, g, b = p, v, t
    elif i % 6 == 3 do
        r, g, b = p, q, v
    elif i % 6 == 4 do
        r, g, b = t, p, v
    elif i % 6 == 5 do
        r, g, b = v, p, q
    end

    return (r * 255), (g * 255), (b * 255)
end

return M
