--[[!<
    A test "game" for OctaForge that lets you draw on the world geometry.
    Left click to draw, right click to stop drawing, middle click to change
    colors.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var log = require("core.logger")

var input = require("core.engine.input")
var inputev = require("core.events.input")
var cs = require("core.engine.cubescript")
var signal = require("core.events.signal")
var svars = require("core.entities.svars")
var ents = require("core.entities.ents")
var conv = require("core.lua.conv")
var particles = require("core.engine.particles")

var splash, flare = particles.splash, particles.flare
var quadrenderer, taperenderer = particles.register_renderer_quad,
    particles.register_renderer_tape

var hextorgb = conv.hex_to_rgb

var game_manager = require("extra.game_manager")
var day_manager = require("extra.day_manager")
var health = require("extra.health")

var connect = signal.connect
var Vec4 = require("core.lua.geom").Vec4
var ipairs = ipairs

var colors = {
    0xFFFFFF, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF
}

var Player = ents.Player


@[not server,noscope] do
    var SPARK = quadrenderer("spark", "media/particle/spark",
        particles.flags.FLIP | particles.flags.BRIGHT)
    var STREAK = taperenderer("streak", "media/particle/flare",
        particles.flags.BRIGHT)
end

--[[! Object: GamePlayer
    This serves as a base for our player. It defines all the basic entry
    points for the drawing game.

    Properties:
        - new_mark - contains mark data. It's required because it has to sync
          over the server (e.g. in coop).
]]
var GamePlayer = Player:clone {
    name = "GamePlayer",

    __properties = {
        new_mark = svars.StateArrayFloat {
            client_set = true, has_history = false
        }
    },

    next_color = function(self)
        if  self.color_id < #colors do
            self.color_id = self.color_id + 1
        else
            self.color_id = 1
        end
        self.color = colors[self.color_id]
        log.echo(("color switch: 0x%.6X"):format(self.color))
    end,

    reset_mark = function(self)
        self:set_attr("new_mark", { -1, -1, -1 })
        self.stop_batch = true
    end,

    --[[! Function: __activate
        Called on entity activation. Connects a callback to state data
        change of new_mark.
    ]]
    __activate = @[not server,function(self, kwargs)
        Player.__activate(self, kwargs)
        self.marks = {}
        self.color_id = 1
        self.color    = colors[1]
        connect(self, "new_mark,changed", function(self, nm)
            if #nm == 3 do
                nm = Vec4(nm[1], nm[2], nm[3], self.color)
            else
                nm = nil
            end
            var marks = self.marks
            marks[#marks + 1] = nm
        end)
    end],

    --[[! Function: __run
        Called every frame. It goes over the marks and draws everything.
    ]]
    __run = @[not server,function(self, millis)
        Player.__run(self, millis)
        var last = nil
        var marks = self.marks

        for i, mark in ipairs(marks) do
            if last and mark and mark.x >= 0 and last.x >= 0 do
                var r, g, b = hextorgb(mark.w)
                flare(STREAK, mark, last, r / 255, g / 255, b / 255, 0, 1)
                flare(STREAK, last, mark, r / 255, g / 255, b / 255, 0, 1)
            end
            last = mark
        end

        var newb = #marks == 0 or not marks[#marks - 1]
        var conb = #marks  > 0 and    marks[#marks - 1]

        if conb and not self.stop_batch do
            var mark = marks[#marks - 1]
            var r, g, b = hextorgb(mark.w)
            splash(SPARK, mark, 25, 10, r / 255, g / 255, b / 255, 150, 1, 1)
        end

        if self.pressing do
            var newp = input.get_target_position()
            var topl = self:get_attr("position"):sub_new(newp)
            newp:add(topl:normalize())
            if newb or marks[#marks - 1]:dist(newp) > 5 do
                self:set_attr("new_mark", newp:to_array())
            end
        end
    end]
}

ents.register_prototype(GamePlayer, {
    game_manager.player_plugin,
    health.player_plugin,
    health.plugins.player_hud,
    health.plugins.player_off_map,
    health.plugins.player_in_deadly_material
})
ents.register_prototype(ents.Obstacle, { health.plugins.area },
    "HealthArea")

day_manager.setup({ day_manager.plugins.day_night })

@[not server] do
    inputev.set_event("click", function(btn, down, x, y, z, uid, cx, cy)
        var ent = ents.get(uid)
        if ent and ent.click do
            return ent:click(btn, down, x, y, z, cx, cy)
        end
        if btn == 1 do
            ents.get_player().pressing   = down
            ents.get_player().stop_batch = false
        elif btn == 2 and down do
            ents.get_player():reset_mark()
        elif btn == 3 and down do
            ents.get_player():next_color()
        end
    end)
else
    ents.set_player_prototype("GamePlayer")
end
