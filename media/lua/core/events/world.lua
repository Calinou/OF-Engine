--[[!<
    Registers several world events. Override these as you wish.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var edit = require("core.engine.edit")
var signal = require("core.events.signal")

var set_external = require("core.externals").set

var emit = signal.emit
var ents

--[[! Function: physics_off_map
    Called when a client falls off the map (keeps calling until the client
    changes its state). By default emits the `off_map` signal on the client.

    Arguments:
        - uid - the client entity uid.
]]
set_external("physics_off_map", function(uid)
    if not ents do ents = require("core.entities.ents") end
    emit(ents.get(uid), "off_map")
end)

--[[! Function: physics_in_deadly
    Called when a client is in a deadly material (lava or death). By default
    emits the `in_deadly` signal on the client, passing the material ID as
    an extra argument.

    Arguments:
        - uid - the client entity uid.
        - mat - the material id (see $edit).
]]
set_external("physics_in_deadly", function(uid, mat)
    if not ents do ents = require("core.entities.ents") end
    emit(ents.get(uid), "in_deadly", mat)
end)

-- flags for physics_state_change
var FLAG_WATER = 1 << 0
var FLAG_LAVA  = 2 << 0
var FLAG_ABOVELIQUID = 1 << 2
var FLAG_BELOWLIQUID = 2 << 2
var FLAG_ABOVEGROUND = 1 << 4
var FLAG_BELOWGROUND = 2 << 4

--[[! Function: physics_state_change
    Called when a client changes their physical state.

    By default this activates physics trigger state var on the client
    (see {{$ents.Character}}).

    Arguments:
        - ent - the unique ID of the client entity.
        - loc - fale for multiplayer prediction.
        - flevel - the floor level specifying a delta from the previous state,
          1 when the client went up, 0 when stayed the same, -1 when down.
        - llevel - the liquid level.
        - mat - the material id (fore xample when jumping out of/into water,
          it's the water material id, see $edit).
]]
set_external("physics_state_change", function(uid, loc, flevel, llevel, mat)
    @[server] do return end

    if not ents do ents = require("core.entities.ents") end
    var ent = ents.get(uid)

    var flags = 0
    if mat == edit.material.WATER do
        flags |= FLAG_WATER
    elif mat == edit.material.LAVA do
        flags |= FLAG_LAVA
    end

    if llevel > 0 do -- liquid level
        flags |= FLAG_ABOVELIQUID
    elif llevel < 0 do
        flags |= FLAG_BELOWLIQUID
    end
    if flevel > 0 do -- floor level
        flags |= FLAG_ABOVEGROUND
    elif flevel < 0 do
        flags |= FLAG_BELOWGROUND
    end
    if flags != 0 do ent:set_attr("physics_trigger", flags) end
end)

--[[! Function: event_text_message
    Called on a text message event. Emits a signal of the same name with
    the unique ID of the client and the text as arguments on the global table.
]]
set_external("event_text_message", function(uid, text)
    emit(_G, "event_text_message", uid, text)
end)

@[server] do
--[[! Function: event_player_login
    Serverside. Called after a server sends all the active entities to the
    client. Emits a signal of the same name with the unique ID of the player
    entity as an argument on the global table.
]]
set_external("event_player_login", function(uid)
    emit(_G, "event_player_login", uid)
end)
end
