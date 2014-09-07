--[[!<
    A reusable health system that integrates with the game manager and
    other modules (the game manager is required).

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

--! Module: health
var M = {}

var gui = require("core.gui.core")
var frame = require("core.events.frame")
var actions = require("core.events.actions")
var signal = require("core.events.signal")
var model = require("core.engine.model")
var edit = require("core.engine.edit")
var svars = require("core.entities.svars")
var ents = require("core.entities.ents")

var eactions = require("extra.events.actions")

var connect, emit = signal.connect, signal.emit
var min, max = math.min, math.max
var floor = math.floor

--[[!
    This module adds three new animations, "dead", "dying" and "pain",
    on the client. They're stored in this enumeration.
]]
var anims = @[not server,{:
    dead  = model.register_anim "dead",
    dying = model.register_anim "dying",
    pain  = model.register_anim "pain"
:}]
M.anims = anims

--[[!
    Derives from {{$actions.LocalAnimationAction}} and is queued as a pain
    effect. The default duration is 600 milliseconds and it uses the
    previously defined PAIN animation. It also cannot be used more than
    once at a time. It only exists on the client.
]]
var PainAction = @[not server,eactions.LocalAnimationAction:clone {
    name            = "PainAction",
    millis_left     = 600,
    local_animation = anims.pain,
    allow_multiple  = false
}]
M.PainAction = PainAction

--[[!
    Derives from a regular Action. Represents player death and the default
    duration is 5 seconds. Like pain, it cannot be used more than once at
     a time and it's not cancelable. It only exists on the server.
]]
var DeathAction = @[server,actions.Action:clone {
    name            = "DeathAction",
    allow_multiple  = false,
    cancelable      = false,
    millis_left     = 5000,

    --[[!
        Makes the player unable to move, sets up a possible ragdoll, clears
        the player's actions (except itself as it's not cancelable) and
        emits the "killed" signal on the player.
    ]]
    __start = function(self)
        var actor = self.actor
        actor:set_attr("can_move", false)
        actor:clear_actions()
        emit(actor, "killed")
    end,

    --! Triggers a respawn.
    __finish = function(self)
        self.actor:game_manager_respawn()
    end
}]
M.DeathAction = DeathAction

--[[!
    The player plugin - use it when baking your player entity prototype. Must be
    used after the game manager player plugin has been baked in (it overrides
    some of its stuff).

    Properties:
        - health - the player's current health.
        - max_health - the maximum health a player can have.
]]
M.player_plugin = {
    __properties = {
        health = svars.StateInteger     { client_set = true },
        max_health = svars.StateInteger { client_set = true }
    },

    __init_svars = function(self)
        self:set_attr("health", 100)
        self:set_attr("max_health", 100)
    end,

    __activate = function(self)
        connect(self, "health,changed", self.health_on_health)
    end,

    --[[!
        Overrides the serverside spawn stage 4. In addition to the default
        behavior it restores the player's health.
    ]]
    game_manager_spawn_stage_4 = @[server,function(self, auid)
        self:set_attr("health", self:get_attr("max_health"))
        self:set_attr("can_move", true)
        self:set_attr("spawn_stage", 0)
        self:cancel_sdata_update()
    end],

    get_animation = function(self)
        var ret = self.__parent_ent_proto.get_animation(self)
        var INDEX, idle = model.anims.INDEX, model.anims.idle
        if self:get_attr("health") > 0 do
            if (ret & INDEX) == anims.dying or (ret & INDEX) == anims.dead do
                self:set_local_animation(idle | model.anim_control.LOOP)
                self.prev_bt = nil
                ret = self:get_attr("animation")
            end
        end
        return ret
    end,

    --[[!
        Overriden so that the "dying" animation is displayed correctly.
    ]]
    decide_base_time = function(self, anim)
        if (anim & model.anims.INDEX) == anims.dying do
            var pbt = self.prev_bt
            if not pbt do
                pbt = frame.get_last_millis()
                self.prev_bt = pbt
            end
            return pbt
        end
        return self:get_attr("start_time")
    end,

    --[[!
        Overriden so that the "dying" animation can be used when health is 0
        (and "dead" when at least 1 second after death).
    ]]
    decide_animation = @[not server,function(self, ...)
        if self:get_attr("health") > 0 do
            return self.__parent_ent_proto.decide_animation(self, ...)
        else
            var anim
            var pbt = self.prev_bt
            if pbt and (frame.get_last_millis() - pbt) > 1000 do
                anim = anims.dead | model.anim_control.LOOP
            else
                anim = anims.dying
            end
            return anim | model.anim_flags.NOPITCH | model.anim_flags.RAGDOLL
        end
    end],

    health_on_health = function(self, health, server_orig)
        var oh = self.old_health
        self.old_health = health
        if not oh do return end
        self:health_changed(health, health - oh, server_orig)
    end,

    --[[!
        There are two variants of this one, for the client and for the server.

        Server:
            Handles death, so the serverside version queues the death action
            if health is <= 0.

        Client:
            The clientside variant handles pain, so it queues the pain action
            if health is > 0 and the diff is lower than -5.

        Arguments:
            - health - the current health.
            - diff - the difference from the old health state.
            - server_orig - true if the change originated on the server.
    ]]
    health_changed = @[server,function(self, health, diff, server_orig)
        if health <= 0 do self:enqueue_action(DeathAction()) end
    end,function(self, health, diff, server_orig)
        if diff <= -5 and health > 0 do
            self:enqueue_action(PainAction())
        end
    end],

    --[[!
        Adds to player's health. If the provided amount is zero, it does
        nothing. The current health also must be larger than 0. Negative
        amount does damage to the player. The result is always clamped
        at 0 on the bottom and at max_health on the top.
    ]]
    health_add = function(self, amount)
        var ch = self:get_attr("health")
        if ch > 0 and amount != 0 do
            var mh = self:get_attr("max_health")
            self:set_attr("health", min(mh, max(0, ch + amount)))
        end
    end
}

--[[! Function: health.is_valid_target
    Returns true if the given player entity is a valid target (for example
    for shooting or other kind of damage). The player must not be editing
    or lagged, its health must be higher than 0 and it must be already
    spawned (the spawn stage must be 0).
]]
var is_valid_target = function(ent)
    if not ent or ent.deactivated do return false end

    var cs = ent:get_attr("client_state")
    if cs == 3 or cs == 4 do return false end -- editing, lagged

    var health, sstage = ent:get_attr("health"     ) or 0,
                            ent:get_attr("spawn_stage") or 0

    return health > 0 and sstage == 0
end
M.is_valid_target = is_valid_target

var HealthAction = actions.Action:clone {
    cancelable = false,

    __ctor = function(self, kwargs)
        actions.Action.__ctor(self, kwargs)
        self.health_step = kwargs.health_step
    end,

    __finish = function(self)
        self.actor:health_add(self.health_step)
    end
}

var gethcolor = function(v, maxv)
    var mid = maxv / 2
    var r = 1 - max(v - mid, 0) * (1 / mid)
    var g = min(v, mid) * (1 / mid)
    return (floor(g * 0xFF) << 8) | (floor(r * 0xFF) << 16)
end

--[[!
    A bunch of example uses of the code included in this module.
]]
M.plugins = {
    --[[!
        A plugin that turns an entity (colliding one) into a "health area". It
        hooks a collision signal to the entity that changes the collider's
        health in steps (optionally, and only if it's a valid target). Bake
        it with an obstacle.
    
        When any of the properties is zero, this won't do anything.
    
        Properties:
            - health_step - the amount of health points to add (when positive)
              or subtract (when negative) in one step.
            - health_step_millis - the amount of time one health step takes
              (the health is taken away at the end of each step). When this
              is negative, the area won't work in steps, instead it'll kill
              the collider when `health_step` is negative or restore maximum
              health when it's positive.
    ]]
    area = {
        __properties = {
            health_step = svars.StateInteger(),
            health_step_millis = svars.StateInteger()
        },

        __init_svars = function(self)
            self:set_attr("health_step", -10)
            self:set_attr("health_step_millis", 1000)
        end,

        health_area_on_collision = function(self, collider)
            if collider != ents.get_player() do return end
            if is_valid_target(collider) do
                var step = self:get_attr("health_step")
                if    step == 0 do return end
                var step_millis = self:get_attr("health_step_millis")
                if    step_millis == 0 do return end
    
                if step_millis < 0 do
                    var oldhealth = collider:get_attr("health")
                    collider:set_attr("health", step < 0 and 0
                        or max(oldhealth, collider:get_attr("max_health")))
                else
                    var prev = self.health_previous_act
                    if not prev or prev.finished do
                        self.health_previous_act = collider:enqueue_action(
                            HealthAction { millis_left = step_millis,
                                health_step = step })
                    end
                end
            end
        end,

        __activate = @[not server,function(self)
            signal.connect(self, "collision", self.health_area_on_collision)
        end]
    },

    --[[!
        Displays a simple HUD health status on the player.
    ]]
    player_hud = {
        __activate = @[not server,function(self)
            gui.get_hud():append(gui.Spacer { pad_h = 0.1, pad_v = 0.1,
                align_h = 1, align_v = 1
            }, |sp| do
                self.health_hud_status = sp:append(gui.Label {
                    scale = 2.5, font = "default_outline"
                }, |st| do
                    var curh, maxh
                    var updatehud = || do
                        st:set_text(tostring(curh))
                        st:set_color(gethcolor(curh, maxh))
                    end
                    connect(self, "max_health,changed", |self, v| do
                        maxh = v; if curh do updatehud() end
                    end)
                    connect(self, "health,changed", |self, v| do
                        curh = v; if maxh do updatehud() end
                    end)
                end)
            end)
        end],

        __deactivate = @[not server,function(self)
            self.health_hud_status:destroy()
        end]
    },

    --! Kills the player when he falls off the map.
    player_off_map = {
        __activate = @[not server,function(self)
            connect(self, "off_map", |ent| do
                if not is_valid_target(ent) do return end
                ent:set_attr("health", 0)
            end)
        end]
    },

    --[[!
        Kills the player when in a deadly area, at once when in the `death`
        material and gradually when in lava.
    ]]
    player_in_deadly_material = {
        __activate = @[not server,function(self)
            connect(self, "in_deadly", |ent, mat| do
                if not is_valid_target(ent) do return end
                if mat == edit.material.LAVA do
                    ent:health_add(-1)
                else
                    ent:set_attr("health", 0)
                end
            end)
        end]
    }
}

return M
