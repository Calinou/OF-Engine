--[[!<
    A day manager module. It can control all kinds of things, from a basic
    day-night cycle to weather. It's server controlled (time management
    happens on the server) with clientside effect.

    The controller entity runs in the background.
]]

--! Module: day_manager
var M = {}

var signal = require("core.events.signal")
var ents = require("core.entities.ents")
var svars = require("core.entities.svars")
var lights = require("core.engine.lights")
var edit = require("core.engine.edit")

var connect, emit = signal.connect, signal.emit

var assert = assert

var get

var Entity = ents.Entity

--[[!
    This is the day manager entity prototype.
]]
var DayManager = Entity:clone {
    name = "DayManager",

    __properties = {
        day_seconds = svars.StateInteger(),
        day_progress = svars.StateInteger { reliable = false }
    },

    __init_svars = function(self)
        Entity.__init_svars(self)
        self:set_attr("day_seconds", 40)
        self:set_attr("day_progress", 0)
    end,

    __activate = @[server,function(self)
        Entity.__activate(self)
        self.day_seconds_s = self:get_attr("day_seconds")
        connect(self, "day_seconds,changed", |self, v| do
            self.day_seconds_s = v
        end)
        self.day_progress_s = 0
    end],

    __run = function(self, millis)
        @[not server] do return end
        Entity.__run(self, millis)
        var dm = self.day_seconds_s * 1000
        if dm == 0 do return end
        var dp = self.day_progress_s
        dp += millis
        if dp >= dm do dp -= dm end
        self:set_attr("day_progress", dp)
        self.day_progress_s = dp
    end
}

var dayman

--! Gets the day manager instance.
M.get = function()
    if not dayman do
        dayman = ents.get_by_prototype("DayManager")[1]
    end
    assert(dayman)
    return dayman
end
get = M.get

--[[!
    Sets up the day manager. You should call this in your map script before
    {{$ents.load}}. You can provide various plugins. This module implements
    a handful of plugins that you can use. On the server this returns the
    entity.
]]
M.setup = function(plugins)
    ents.register_prototype(DayManager, plugins)
    @[server] do
        dayman = ents.new("DayManager")
        return dayman
    end
end

var getsunscale = function(dayprog)
    -- the numbers here are very approximate, in reality they'd depend
    -- on the which part of the year it is - here the sun is at the horizon
    -- by 6 AM and 6 PM respectively (equally long night and day) so we need
    -- the sunlightscale at 0 by 6 PM and rising up to 1 from 6 AM (so that
    -- we don't get shadows from the bottom) - both dawn and dusk take 2
    -- hours... TODO: more configurable system where you can set how long
    -- is day and night (and affect actual seasons)
    var r1, r2 = 0.67, 0.75 -- dusk: 4 - 6 hrs
    var d1, d2 = 0.25, 0.33 -- dawn: 6 - 8 hrs
    if dayprog > d2 and dayprog < r1 do return 1 end
    if dayprog > r2  or dayprog < d1 do return 0 end
    if dayprog > r1 do
        return (r2 - dayprog) / (r2 - r1)
    end
    return (dayprog - d1) / (d2 - d1)
end

var getsunparams = function(daytime, daylen)
    var mid = daylen / 2
    var yaw = 360 - (daytime / daylen) * 360
    var pitch
    if daytime <= mid do
        pitch = (daytime / mid) * 180 - 90
    else
        pitch = 90 - ((daytime - mid) / mid) * 180
    end
    return yaw, pitch, getsunscale(daytime / daylen)
end

--[[!
    Various plugins for the day manager.
]]
M.plugins = {
    --[[!
        A plugin that adds day/night cycles to the day manager. It works
        by manipulating the sunlight yaw and pitch.
    ]]
    day_night = {
        __activate = @[not server,function(self)
            var daylen
            connect(self, "day_seconds,changed", |self, v| do
                daylen = v
            end)
            connect(self, "day_progress,changed", |self, v| do
                if not daylen do return end
                if edit.player_is_editing() do return end
                self.sun_changed_dir = true
                var yaw, pitch, scale = getsunparams(v, daylen * 1000)
                lights.set_sun_yaw_pitch(yaw, pitch)
                lights.set_sunlight_scale(scale)
                lights.set_skylight_scale(scale)
            end)
        end],

        __run = @[not server,function(self)
            if self.sun_changed_dir and edit.player_is_editing() do
                lights.reset_sun()
                self.sun_changed_dir = false
            end
        end]
    }
}

return M
