--[[!<
    Various types of light entities.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var svars = require("core.entities.svars")
var ents = require("core.entities.ents")
var lights = require("core.engine.lights")

var light_add = lights.add

--! Module: lights
var M = {}

var Marker = ents.Marker

--[[! Object: lights.DynamicLight
    A generic "dynamic light" entity prototype. It's not registered by default
    (a Light from the core set is already dynamic), it serves as a base for
    derived dynamic light types. Inherits from {{$ents.Marker}} entity type of
    the core set. Note: even though this type is not registered by default,
    it's fully functional.

    Properties overlap with the core Light entity type (but it lacks flags)
    including newent properties.
]]
var DynamicLight = Marker:clone {
    name = "DynamicLight",

    __properties = {
        radius = svars.StateInteger(),
        red    = svars.StateInteger(),
        green  = svars.StateInteger(),
        blue   = svars.StateInteger()
    },

    --! Set to true, as <__run> doesn't work on static entities by default.
    __per_frame = true,

    __init_svars = function(self, kwargs, nd)
        Marker.__init_svars(self, kwargs, nd)
        self:set_attr("radius", 100, nd[4])
        self:set_attr("red",    128, nd[1])
        self:set_attr("green",  128, nd[2])
        self:set_attr("blue",   128, nd[3])
    end,

    --[[!
        Overloaded to show the dynamic light. Derived dynamic light types
        need to override this accordingly.
    ]]
    __run = @[not server,function(self, millis)
        Marker.__run(self, millis)
        var pos = self:get_attr("position")
        light_add(pos, self:get_attr("radius"),
            self:get_attr("red") / 255, self:get_attr("green") / 255,
            self:get_attr("blue") / 255)
    end]
}
M.DynamicLight = DynamicLight

var max, random = math.max, math.random
var floor = math.floor
var flash_flag = lights.flags.FLASH

--[[! Object: lights.FlickeringLight
    A flickering light entity type derived from $DynamicLight. This one
    is registered. Delays are in milliseconds. It adds probability, min delay
    and max delay to newent properties of its parent.

    Properties:
        - probability - the flicker probability (from 0 to 1, defaults to 0.5).
        - min_delay - the minimal flicker delay (defaults to 100).
        - max_delay - the maximal flicker delay (defaults to 300).
]]
M.FlickeringLight = DynamicLight:clone {
    name = "FlickeringLight",

    __properties = {
        probability = svars.StateFloat(),
        min_delay   = svars.StateInteger(),
        max_delay   = svars.StateInteger(),
    },

    __init_svars = function(self, kwargs, nd)
        DynamicLight.__init_svars(self, kwargs, nd)
        self:set_attr("probability", 0.5, nd[5])
        self:set_attr("min_delay",   100, nd[6])
        self:set_attr("max_delay",   300, nd[7])
    end,

    __activate = @[not server,function(self, kwargs)
        Marker.__activate(self, kwargs)
        self.delay = 0
    end],

    __run = @[not server,function(self, millis)
        var d = self.delay - millis
        if  d <= 0 do
            d = max(floor(random() * self:get_attr("max_delay")),
                self:get_attr("min_delay"))
            if random() < self:get_attr("probability") do
                var pos = self:get_attr("position")
                light_add(pos, self:get_attr("radius"),
                    self:get_attr("red") / 255, self:get_attr("green") / 255,
                    self:get_attr("blue") / 255, d, 0, flash_flag)
            end
        end
        self.delay = d
    end]
}

ents.register_prototype(M.FlickeringLight)

return M
