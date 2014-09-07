--[[!<
    Reusable teleporter entities.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var log = require("core.logger")
var sound = require("core.engine.sound")
var signal = require("core.events.signal")
var svars = require("core.entities.svars")
var ents = require("core.entities.ents")

var play = sound.play
var connect = signal.connect
var get_by_tag = ents.get_by_tag

var rand = math.random
var unpack = unpack

--! Module: teleporters
var M = {}

var Obstacle = ents.Obstacle

--[[! Object: teleporters.Teleporter
    A regular invisible teleporter. Derives from {{$ents.Obstacle}}. Properties
    can be specified on creation as first two parameters to newent (the rest
    applies to {{$ents.Obstacle}} properties).

    In edit mode, the links from teleporter to destinations are visualized.

    Properties:
        - destination - an integer from 1 to N (0 by default, as in invalid),
          specifies the teleporter destination number (which is a marker
          tagged teledest_N), there can be multiple destinations and the
          teleporter will select one at random.
        - sound_name - name of the sound to play on teleportation, empty
          by default.
]]
M.Teleporter = Obstacle:clone {
    name = "Teleporter",

    __properties = {
        destination = svars.StateInteger(),
        sound_name  = svars.StateString()
    },

    __init_svars = function(self, kwargs, nd)
        Obstacle.__init_svars(self, kwargs, { unpack(nd, 3) })
        self:set_attr("destination", 0, nd[1])
        self:set_attr("sound_name", "", nd[2])
    end,

    __activate = @[not server,function(self, kwargs)
        Obstacle.__activate(self, kwargs)
        connect(self, "collision", self.on_collision)
    end],

    on_collision = function(self, collider)
        var dest = self:get_attr("destination")
        if dest <= 0 do return end
        var dests = get_by_tag("teledest_" .. dest)
        if #dests == 0 do
            log.log(log.ERROR, "No teledest found.")
            return
        end
        dests[rand(1, #dests)]:place_entity(collider)
        var sn = self:get_attr("sound_name")
        if sn != "" do play(sn) end
    end,

    get_attached_next = function(self)
        var dest = self:get_attr("destination")
        if dest <= 0 do return end
        return unpack(get_by_tag("teledest_" .. dest))
    end
}

ents.register_prototype(M.Teleporter)

return M
