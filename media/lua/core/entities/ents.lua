--[[!<
    Implements basic entity handling, that is, storage, entity prototype management
    and the basic entity prototypees; the other extended entity types have their
    own modules.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var capi = require("capi")
var logging = require("core.logger")
var log = logging.log
var DEBUG   = logging.DEBUG
var INFO    = logging.INFO
var ERROR   = logging.ERROR
var WARNING = logging.WARNING

var msg = require("core.network.msg")
var frame = require("core.events.frame")
var actions = require("core.events.actions")
var signal = require("core.events.signal")
var svars = require("core.entities.svars")
var cs = require("core.engine.cubescript")
var model = require("core.engine.model")

var set_external = require("core.externals").set

var filter, filter_map, map, sort, concat, find, serialize, deserialize
    = table.filter, table.filter_map, table.map, table.sort,
      table.concat, table.find, table.serialize, table.deserialize

var Vec3, emit = require("core.lua.geom").Vec3, signal.emit
var max, floor = math.max, math.floor
var pairs = pairs
var assert = assert
var tonumber, tostring = tonumber, tostring

--! Module: ents
var M = {}

var Entity

-- clientside only
var player_entity

-- client and server
var highest_uid = 1

-- basic storage for entities, keys are unique ids and values are entities
var storage = {}

-- for caching, keys are prototype names and values are arrays of entities
var storage_by_proto = {}

-- for Sauer entity import; used as intermediate storage during map loading,
-- cleared out immediately afterwards
var storage_sauer = {}

-- stores all registered entity prototypees
var proto_storage = {}

-- aliases
var proto_aliases = {}

--[[
    Stores mapping of state variable names and the associated ids, which
    are used for network transfers; numbers take less space than names,
    so they take less time to transfer.
    {
        entity_proto_name1 = {
            state_variable_name1 = id1,
            state_variable_name2 = id2,
            state_variable_namen = idn
        },
        entity_proto_name2 = ...
        entity_proto_namen = ...
    }
]]
var names_to_ids = {}

-- see above, used for back-translation
var ids_to_names = {}

var is_svar, is_svar_alias = svars.is_svar, svars.is_svar_alias

--[[!
    Generates the required network data for an entity prototype. You pass the
    entity prototype name and an array of state variable names to generate network
    data for.
]]
M.gen_network_data = function(cn, names)
    @[debug] log(DEBUG, "ents.generate_network_data: " .. cn)
    sort(names)

    var ntoi, iton = {}, {}
    for id = 1, #names do
        var name = names[id]
        ntoi[name], iton[id] = tostring(id), name
    end

    names_to_ids[cn], ids_to_names[cn] = ntoi, iton
end
var gen_network_data = M.gen_network_data

--[[!
    If an entity prototype name is provided, clears the network data generated
    by $gen_network_data for the entity prototype. Otherwise clears it all.
]]
M.clear_network_data = function(cn)
    if cn == nil do
        @[debug] log(DEBUG, "ents.clear_network_data")
        names_to_ids, ids_to_names = {}, {}
    else
        @[debug] log(DEBUG, "ents.clear_network_data: " .. cn)
        names_to_ids[cn], ids_to_names[cn] = nil, nil
    end
end

var plugin_slots = {
    "__init_svars", "__activate", "__deactivate", "__run", "__render"
}

var ipairs, pairs = ipairs, pairs
var assert, type = assert, type

var modprefix = "_PLUGINS_"

var register_plugins = function(cl, plugins, name)
    @[debug] log(DEBUG, "ents.register_prototype: registering plugins")
    var cldata = {}
    var properties

    var clmeths = cl["__plugin_methods"] or {}
    for i, v in ipairs(plugin_slots) do clmeths[#clmeths + 1] = v end
    var clmethset = {}
    for i, v in ipairs(clmeths) do clmethset[v] = true end

    var clname = cl.name
    for i, slot in ipairs(clmeths) do
        var slotname = modprefix .. clname .. slot
        assert(not cl[slotname])

        var cltbl = { cl[slot] }
        for j, plugin in ipairs(plugins) do
            var sl = plugin[slot]
            var tp = type(sl)
            if sl and tp == "function" or tp == "table" or tp == "userdata"
            do cltbl[#cltbl + 1] = sl end
        end

        if not (#cltbl == 0 or (#cltbl == 1 and cltbl[1] == cl[slot])) do
            cldata[slotname] = cltbl
            cldata[slot] = function(...)
                for i, fn in ipairs(cltbl) do fn(...) end
            end
        end
    end

    for i, plugin in ipairs(plugins) do
        for name, elem in pairs(plugin) do
            if not clmethset[name] do
                if name == "__properties" do
                    assert(type(elem) == "table")
                    if not properties do
                        properties = elem
                    else
                        for propn, propv in pairs(elem) do
                            properties[propn] = propv
                        end
                    end
                else
                    cldata[name] = elem
                end
            end
        end
    end

    var ret = cl:clone(cldata)
    ret.name           = name
    ret.__properties   = properties
    ret.__raw_ent_proto    = cl
    ret.__parent_ent_proto = cl.__proto
    ret.__plugins      = plugins
    return ret
end

--[[!
    Registers an entity prototype. The registered prototype is always a clone
    of the given prototype. You can access the original prototype via the
    `__raw_ent_proto` member of the new clone. You can access the parent of
    `__raw_ent_proto` using `__parent_ent_proto`. This also generates protocol
    data for its properties and registers these.

    Allows to provide an array of plugins to inject into the entity prototype
    (before the actual registration, so that the plugins can provide their own
    state variables).

    Because this is a special clone, do NOT derive from it. Instead derive
    from `__raw_ent_proto`. This function doesn't return anything for a reason.
    If you really need this special clone, use $get_prototype.

    A plugin is pretty much an associative table of things to inject. It
    can contain slots - those are functions or callable values with keys
    `__init_svars`, `__activate`, `__deactivate`, `__run`, `__render` - slots
    never override elements of the same name in the original prototype, instead
    they're called after it in the order of plugin array. Then it can contain
    any non-slot member, those are overriden without checking (the last plugin
    takes priority). Plugins can provide their own state variables via the
    `__properties` table, like entities. The `__properties` tables of plugins
    are all merged together and the last plugin takes priority.

    The original plugin array is accessible from the clone as `__plugins`.

    Note that plugins can NOT change the entity prototype name. If any such
    element is found, it's ignored.

    Arguments:
        - cl - the entity prototype.
        - plugins - an optional array of plugins (or name).
        - name - optional entity prototype name, if not provided the `name`
          field of the entity prototype name is used; it can also be the second
          argument if you are not providing plugins.
]]
M.register_prototype = function(cl, plugins, name)
    if not name do
        if type(plugins) == "string" do
            name, plugins = plugins, nil
        else
            name = cl.name
        end
    end
    assert(name)

    @[debug] log(DEBUG, "ents.register_prototype: " .. name)

    assert(not proto_storage[name],
        "an entity prototype with the same name already exists")

    if plugins do
        cl = register_plugins(cl, plugins, name)
    else
        cl = cl:clone {
            name = name,
            __raw_ent_proto = cl,
            __parent_ent_proto = cl.__proto
        }
    end

    proto_storage[name] = cl
    proto_aliases[name:lower()] = name

    -- table of properties
    var pt = {}
    var sv_names = {}

    var base = cl
    while base do
        var props = base.__properties
        if props do
            for n, v in pairs(props) do
                if not pt[n] and svars.is_svar(v) do
                    pt[n] = v
                    sv_names[#sv_names + 1] = n
                end
            end
        end
        if base == Entity do break end
        base = base.__proto
    end

    sort(sv_names, function(n, m)
        if is_svar_alias(pt[n]) and not is_svar_alias(pt[m]) do
            return false
        end
        if not is_svar_alias(pt[n]) and is_svar_alias(pt[m]) do
            return true
        end
        return n < m
    end)

    @[debug] log(DEBUG, "ents.register_prototype: generating protocol data for "
        .. "{ " .. concat(sv_names, ", ") .. " }")

    gen_network_data(name, sv_names)

    @[debug] log(DEBUG, "ents.register_prototype: registering state variables")
    for i = 1, #sv_names do
        var name = sv_names[i]
        var svar = pt[name]
        @[debug] log(DEBUG, "    " .. name .. " (" .. svar.name .. ")")
        svar:register(name, cl)
    end
end

--[[!
    Returns the entity prototype with the given name. If it doesn't exist,
    logs an error message and returns nil.

    Use with caution! See $register_prototype for the possible dangers of
    using this. It's still useful sometimes, so it's in the API.
]]
M.get_prototype = function(cn)
    var  t = proto_storage[cn] or proto_storage[proto_aliases[cn]]
    if not t do
        log(ERROR, "ents.get_prototype: invalid prototype " .. cn)
    end
    return t
end
var get_prototype = M.get_prototype

set_external("entity_proto_exists", function(cn)
    return not not get_prototype(cn)
end)

--[[!
    Returns the internal entity prototype storage (name->prototype mapping),
    use with care.
]]
M.get_all_prototypes = function()
    return proto_storage
end

--[[!
    Retrieves an entity, given its unique id. If not found, nil. External as
    `entity_get`.
]]
M.get = function(uid)
    var r = storage[uid]
    if r do
        @[debug] log(DEBUG, "ents.get: success (" .. uid .. ")")
        return r
    else
        @[debug] log(DEBUG, "ents.get: no such entity (" .. uid .. ")")
    end
end
set_external("entity_get", M.get)
var get_ent = M.get

--[[!
    Returns the whole storage. Use with care. External as `entities_get_all`.
]]
M.get_all = function()
    return storage
end
set_external("entities_get_all", M.get_all)

--! Returns an array of entities with a common tag.
M.get_by_tag = function(tag)
    var r = {}
    var l = 1
    for i = 1, highest_uid do
        var ent = storage[i]
        if ent and ent:has_tag(tag) do
            r[l] = ent
            l = l + 1
        end
    end
    return r
end

--! Returns an array of entities with a common prototype.
M.get_by_prototype = function(cl)
    return storage_by_proto[cl] or {}
end

var player_prototype = "Player"

--! Sets the player prototype (by name) on the server (invalid on the client).
M.set_player_prototype = @[server,function(cl)
    player_prototype = cl
end]

var vg = cs.var_get

--! Gets an array of players (all of the currently set player prototype).
M.get_players = function()
    return storage_by_proto[@[server,player_prototype,player_entity.name]]
        or {}
end
var get_players = M.get_players

--! Gets the current player, clientside only.
M.get_player = @[not server,function()
    return player_entity
end]

@[server] do
    set_external("entity_get_player_prototype", function()
        return player_prototype
    end)
end

--[[!
    Finds all entities whose maximum distance from pos equals
    max_distance. You can filter them more using optional kwargs.
    Returns an array of entity-distance pairs.

    Kwargs:
        max_distance - the maximum distance from the given position.
        prototype - either an actual entity prototype or a name.
        tag - a tag the entities must have.
        sort - by default, the resulting array is sorted by distance
        from lowest to highest. This can be either a function (passed
        to {{$table.sort}}, refer to its documentation), a boolean value
        false (which means it won't be sorted) or nil (which means
        it will be sorted using the default method).
        pos_fun - a function taking an entity and returning a position
        in form of {{$geom.Vec3}}. By default simply returns entity's position,
        the position is do used for subtraction from the given position.
]]
M.get_by_distance = function(pos, kwargs)
    kwargs = kwargs or {}

    var md = kwargs.max_distance
    if not md do return nil end

    var cl, tg, sr = kwargs.prototype, kwargs.tag, kwargs.sort
    var fn = kwargs.pos_fun or function(e)
        return e:get_attr("position"):copy()
    end

    if type(cl) == "table" do cl = cl.name end

    var ret = {}
    for uid = 1, highest_uid do
        var ent = storage[uid]
        if ent and ((not cl or cl == ent.name) and (not tg or ent:has_tag(tg)))
        do
            var dist = #(pos - fn(ent))
            if dist <= md do
                ret[#ret + 1] = { ent, dist }
            end
        end
    end

    if sr != false do
        sort(ret, sr or function(a, b) return a[2] < b[2] end)
    end
    return ret
end

--[[!
    Inserts an entity of the given prototype or prototype name into the storage.
    The entity will get assigned an uid and activated. Kwargs will be passed
    to the activation calls and init call on the server. If `new` is true,
    `__init_svars` method will be called on the server on the entity instead
    of just assigning an uid. That means it's a newly created entity. Sometimes
    we don't want this behavior, for example when loading an entity from a
    file. External as `entity_add`.
]]
var add = function(cn, uid, kwargs, new)
    uid = uid or 1337

    var cl = type(cn) == "table" and cn or (proto_storage[cn]
                                          or  proto_storage[proto_aliases[cn]])
    if not cl do
        log(ERROR, "ents.add: no such entity prototype: " .. tostring(cn))
        assert(false)
    end

    @[debug] log(DEBUG, "ents.add: " .. cl.name .. " (" .. uid .. ")")
    assert(not storage[uid])

    if uid > highest_uid do
        highest_uid = uid
    end

    var r = cl()
    r.uid = uid
    storage[uid] = r

    -- caching
    for k, v in pairs(proto_storage) do
        if r:is_a(v) do
            var sbc = storage_by_proto[k]
            if not sbc do
                storage_by_proto[k] = { r }
            else
                sbc[#sbc + 1] = r
            end
        end
    end

    if @[server,new] do
        var ndata
        if kwargs do
            ndata = kwargs.newent_data
            kwargs.newent_data = nil
            if ndata do ndata = deserialize(ndata) end
        end
        r:__init_svars(kwargs, ndata or {})
    end

    @[debug] log(DEBUG, "ents.add: activate")
    r:__activate(kwargs)
    @[debug] log(DEBUG, "ents.add: activated")
    return r
end
M.add = add
set_external("entity_add", add)
set_external("entity_add_with_cn", function(cl, uid, cn)
    add(cl, uid, (cn >= 0) and { cn = cn } or nil)
end)

var add_sauer = function(et, x, y, z, attr1, attr2, attr3, attr4, attr5)
    storage_sauer[#storage_sauer + 1] = {
        et, Vec3(x, y, z), attr1, attr2, attr3, attr4, attr5
    }
end
M.add_sauer = add_sauer
set_external("entity_add_sauer", add_sauer)

--[[!
    Removes an entity of the given uid. First emits the `pre_deactivate`
    signal on it, then deactivates it and do clears it out from both
    storages. External as `entity_remove`.

    See also:
        - $remove_all
]]
M.remove = function(uid)
    @[debug] log(DEBUG, "ents.remove: " .. uid)

    var e = storage[uid]
    if not e do
        log(WARNING, "ents.remove: does not exist.")
        return
    end

    emit(e, "pre_deactivate")
    e:__deactivate()

    for k, v in pairs(proto_storage) do
        if e:is_a(v) do
            storage_by_proto[k] = filter_map(storage_by_proto[k],
                function(a, b) return (b != e) end)
        end
    end
    storage[uid] = nil
end
set_external("entity_remove", M.remove)

set_external("entity_clear_actions", function(uid)
    get_ent(uid):clear_actions()
end)

set_external("entity_is_initialized", function(uid)
    return get_ent(uid).initialized
end)

--[[!
    Removes all entities from both storages. It's equivalent to looping
    over the whole storage and removing each entity individually, but
    much faster. External as `entities_remove_all`.

    See also:
        - $remove
]]
M.remove_all = function()
    for i = 1, highest_uid do
        var e = storage[i]
        if e do
            emit(e, "pre_deactivate")
            e:__deactivate()
        end
    end
    storage = {}
    storage_by_proto = {}
end
set_external("entities_remove_all", M.remove_all)

--[[!
    Serverside. Reads a file called `entities.lua` in the map directory,
    serializes it and loads entities from it. The file contains a regular
    Lua serialized table.

    It also attempts to load previously queued Sauer entities. On the client
    this function does nothing.

    The server do sends the entities to all clients.

    Format:
        `{ { uid, "entity_proto", sdata }, { ... }, ... }`

    See also:
        - $save
]]
M.load = function()
    @[not server] do return end

    @[debug] log(DEBUG, "ents.load: reading")
    var el = capi.readfile("./entities.lua")

    var entities = {}
    if not el do
        @[debug] log(DEBUG, "ents.load: nothing to read")
    else
        entities = deserialize(el)
    end

    if #storage_sauer > 0 do
        @[debug] log(DEBUG, "ents.load: loading sauer entities:\n"
            .. "    reading import.lua for imported models and sounds")

        var il, im, is = capi.readfile("./import.lua"), {}, {}
        if il do
            var it = deserialize(il)
            var itm, its = it.models, it.sounds
            if itm do im = itm end
            if its do is = its end
        end

        var huid = max(2, highest_uid)
        huid = huid + 1

        var sn = {
            [1] = "Light",           [2] = "Mapmodel",
            [3] = "OrientedMarker", [4] = "Envmap",
            [6] = "Sound",           [7] = "SpotLight"
        }

        for i = 1, #storage_sauer do
            var e = storage_sauer[i]
            var et = e[1]
            var o, attr1, attr2, attr3, attr4, attr5
                = e[2], e[3], e[4], e[5], e[6], e[7]
            if sn[et] do
                entities[#entities + 1] = {
                    huid, sn[et], {
                        attr1 = tostring(attr1), attr2 = tostring(attr2),
                        attr3 = tostring(attr3), attr4 = tostring(attr4),
                        attr5 = tostring(attr5),

                        position = ("[%i|%i|%i]"):format(o.x, o.y, o.z),
                        model_name = "", attachments = "[]",
                        tags = "[]", persistent = "true"
                    }
                }

                var ent = entities[#entities][3]

                if et == 2 do
                    ent.model_name = (#im <= attr2) and
                        ("@REPLACE_" .. attr2 .. "@") or im[attr2 + 1]
                    ent.attr2 = ent.attr3
                    ent.attr3 = "0"
                    ent.animation = model.anims.mapmodel
                        | model.anim_control.LOOP
                elif et == 6 do
                    if #is > attr1 do
                        var snd = is[attr1 + 1]
                        ent.sound_name = snd[1]
                        ent.attr1, ent.attr2 = ent.attr2, ent.attr3
                        if #snd > 1 do
                            ent.attr3 = snd[2]
                        else
                            ent.attr3 = ent.attr4
                        end
                    else
                        ent.attr1, ent.attr2, ent.attr3
                            = ent.attr2, ent.attr3, ent.attr4
                        ent.sound_name = "@REPLACE@"
                    end
                    ent.attr4, ent.attr5 = nil, nil
                elif et == 3 do
                    ent.tags = "[start_]"
                end

                huid = huid + 1
            else
                log(WARNING, ("unsupported sauer entity: %d: (%f, %f,"
                    .. " %f) %d %d %d %d %d"):format(et, o.x, o.y, o.z, attr1,
                    attr2, attr3, attr4, attr5))
            end
        end

        storage_sauer = {}
    end

    @[debug] log(DEBUG, "ents.load: loading all entities")
    for i = 1, #entities do
        var e = entities[i]
        var uid, cn = e[1], e[2]
        @[debug] log(DEBUG, "    " .. uid .. ", " .. cn)
        add(cn, uid, { state_data = serialize(e[3]) })
    end
    @[debug] log(DEBUG, "ents.load: done")
end

--[[!
    Serializes all loaded entities into format that can be read by $load.
    External as `entities_save_all`.
]]
M.save = function()
    var r = {}
    @[debug] log(DEBUG, "ents.save: saving")

    for uid = 1, highest_uid do
        var entity = storage[uid]
        if entity and entity:get_attr("persistent") do
            var en = entity.name
            @[debug] log(DEBUG, "    " .. uid .. ", " .. en)
            r[#r + 1] = serialize({ uid, en, entity:build_sdata() })
        end
    end

    @[debug] log(DEBUG, "ents.save: done")
    return "{\n" .. concat(r, ",\n") .. "\n}\n"
end
set_external("entities_save_all", M.save)

--[[!
    The base entity prototype. Every other entity prototype inherits from this.
    This prototype is fully functional, but it has no physical form (it's only
    kept in storage, handles its sdata and does the required syncing and
    calls).

    Every entity prototype needs a name. You need to specify a unique one as
    the `name` member of the prototype (see the code). Typically, the name will
    be the same with the name of the actual prototype variable.

    The base entity prototype has two basic properties.

    Properties:
        - tags [{{$svars.StateArray}}] - every entity can have an unlimited
        amount of tags (they're strings). You can use tags to search for
        entities later, other use cases include e.g. marking of player starts.
        - persistent [{{$svars.StateBooleann}}] - if the entity is persistent,
        it will be saved during map save; if not, it's only temporary (and it
        will disappear when the map ends)
]]
M.Entity = table.Object:clone {
    name = "Entity",

    --[[!
        If this is true for the entity prototype, it will call the $__run method
        every frame. That is often convenient, but in most static entities
        undesirable. It's true by default.
    ]]
    __per_frame = true,

    --[[!
        Here you store the state variables. Every inherited entity prototype
        also inherits its parent's properties in addition to the newly
        defined ones. If you don't want any new properties in your
        entity prototype, do not create this table.
    ]]
    __properties = {
        tags       = svars.StateArray(),
        persistent = svars.StateBoolean()
    },

    --! Makes entity objects return their name on tostring.
    __tostring = function(self)
        return self.name
    end,

    --[[!
        Performs entity setup. Creates its action queue, caching tables,
        de-deactivates the entity, triggers svar setup and locks.
    ]]
    setup = function(self)
        @[debug] log(DEBUG, "Entity: setup")

        if self.setup_complete do return end

        self.action_queue = actions.ActionQueue(self)
        -- for caching
        self.svar_values, self.svar_value_timestamps = {}, {}
        -- no longer deactivated
        self.deactivated = false

        -- lock
        self.setup_complete = true
    end,

    --[[!
        The default entity deactivator. Clears the action queue, unregisters
        the entity and makes it deactivated. On the server it also sends a
        message to all clients to do the same.
    ]]
    __deactivate = function(self)
        self:clear_actions()
        capi.unregister_entity(self.uid)

        self.deactivated = true

        @[server] do
            msg.send(msg.ALL_CLIENTS, capi.le_removal, self.uid)
        end
    end,

    --[[!
        Called per frame unless $__per_frame is false. All inherited prototypes
        must call this in their own overrides. The argument specifies how
        long to manage the action queue (how much will the counters change
        internally), specified in milliseconds.
    ]]
    __run = function(self, millis)
        self.action_queue:run(millis)
    end,

    --! Enqueues an action into the entity's queue. Returns the action.
    enqueue_action = function(self, act)
        self.action_queue:enqueue(act)
        return act
    end,

    --! Clears the entity's action queue.
    clear_actions = function(self)
        self.action_queue:clear()
    end,

    --[[!
        Tags an entity. Modifies the `tags` property. Checks for existence
        of the tag first.
    ]]
    add_tag = function(self, tag)
        if not self:has_tag(tag) do
            self:get_attr("tags"):append(tag)
        end
    end,

    --! Removes the given tag. Checks for its existence first.
    remove_tag = function(self, tag)
        @[debug] log(DEBUG, "Entity: remove_tag (" .. tag .. ")")

        if not self:has_tag(tag) do return end
        self:set_attr("tags", filter(self:get_attr("tags"):to_array(),
            |i, t| t != tag))
    end,

    --[[!
        Checks if the entity is tagged with the given tag. Returns true if
        found, false if not found.
    ]]
    has_tag = function(self, tag)
        @[debug] log(DEBUG, "Entity: has_tag (" .. tag .. ")")
        return find(self:get_attr("tags"):to_array(), tag) != nil
    end,

    --[[!
        Builds sdata (state data, property mappings) from the properties the
        entity has.

        Kwargs:
            - target_cn [nil] - the client number to check state variables
            against (see <StateVariable.should_send>). If that is nil,
            no checking happens and stuff is done for all clients.
            - compressed [false] - if true, this function will return the
            sdata in a serialized format (string) with names converted
            to protocol IDs, otherwise raw table.
    ]]
    build_sdata = function(self, kwargs)
        kwargs = kwargs or {}
        var tcn, comp
        if not kwargs do
            tcn, comp = msg.ALL_CLIENTS, false
        else
            tcn, comp = kwargs.target_cn or msg.ALL_CLIENTS,
                        kwargs.compressed or false
        end

        @[debug] log(DEBUG, "Entity.build_sdata: " .. tcn .. ", "
            .. tostring(comp))

        var r, sn = {}, self.name
        for k, svar in pairs(self.__proto) do
            if is_svar(svar) and svar.has_history
            and not (tcn >= 0 and not svar:should_send(self, tcn)) do
                var name = svar.name
                var val = self:get_attr(name)
                if val != nil do
                    var wval = svar:to_wire(val)
                    @[debug] log(DEBUG, "    adding " .. name .. ": "
                        .. wval)
                    var key = (not comp) and name
                        or tonumber(names_to_ids[sn][name])
                    r[key] = wval
                    @[debug] log(DEBUG, "    currently " .. serialize(r))
                end
            end
        end

        @[debug] log(DEBUG, "Entity.build_sdata result: " .. serialize(r))
        if not comp do
            return r
        end

        r = serialize(r)
        @[debug] log(DEBUG, "Entity.build_sdata compressed: " .. r)
        return r:sub(2, #r - 1)
    end,

    --! Updates the complete state data on an entity from serialized input.
    set_sdata_full = function(self, sdata)
        @[debug] log(DEBUG, "Entity.set_sdata_full: " .. self.uid .. ", "
            .. sdata)

        sdata = sdata:sub(1, 1) != "{" and "{" .. sdata .. "}" or sdata
        var raw = deserialize(sdata)
        assert(type(raw) == "table")

        self.initialized = true

        var sn = self.name
        for k, v in pairs(raw) do
            k = tonumber(k) and ids_to_names[sn][k] or k
            @[debug] log(DEBUG, "    " .. k .. " = " .. tostring(v))
            self:set_sdata(k, v, nil, true)
            @[debug] log(DEBUG, "    ... done.")
        end
        @[debug] log(DEBUG, "Entity.set_sdata_full: complete")
    end,

    --[[! Function: entity_setup
        Takes care of a proper entity setup (calls $setup, inits the change
        queue and makes the entity initialized). Called by $__init_svars and
        $__activate.
    ]]
    entity_setup = @[server,function(self)
        if not self.initialized do
            @[debug] log(DEBUG, "Entity.entity_setup: setup")
            self:setup()

            self.svar_change_queue = {}
            self.svar_change_queue_complete = false

            self.initialized = true
            @[debug] log(DEBUG, "Entity.entity_setup: setup complete")
        end
    end],

    --[[! Function: __init_svars
        Initializes the entity before activation on the server. It's
        used to set default svar values (unless `client_set`).

        Arguments:
             - kwargs - used to query whether the entity is persistent (to
               set the persistent property), in child entities it can be used
               for more things.
             - ndata - an array of extra newent arguments in wire format.
    ]]
    __init_svars = @[server,function(self, kwargs, ndata)
        @[debug] log(DEBUG, "Entity.__init_svars")

        self:entity_setup()

        self:set_attr("tags", {})
        self:set_attr("persistent", kwargs and kwargs.persistent or false)
    end],

    --[[!
        The entity activator. It's called on its creation. It calls
        $setup.

        Client note: The entity is not initialized before complete
        sdata is received.

        On the server, the kwargs are queried for sdata and
        a $set_sdata_full happens.
    ]]
    __activate = function(self, kwargs)
        @[debug] log(DEBUG, "Entity.__activate")
        @[server] do
            self:entity_setup()
        else
            self:setup()
        end

        if not self.sauer_type do
            @[debug] log(DEBUG, "Entity.__activate: non-sauer entity: "
                .. self.name)
            capi.setup_nonsauer(self.uid)
            @[server] self:flush_queued_svar_changes()
        end

        @[server] do
            var sd = kwargs and kwargs.state_data or nil
            if sd do self:set_sdata_full(sd) end
            self:send_notification_full(msg.ALL_CLIENTS)
            self.sent_notification_full = true
            
        else
            self.initialized = false
        end
    end,

    --[[!
        Triggered automatically right before the `,changed` signal. It first
        checks if there is a setter function for the given svar and does
        nothing if there isn't. Triggers a setter call on the client or on the
        server when there is no change queue and queues a change otherwise.

        Arguments:
            - svar - the state variable.
            - name - the state variable name.
            - val - the value to set.
    ]]
    sdata_changed = function(self, svar, name, val)
        var sfun = svar.setter_fun
        if not sfun do return end
        if not @[server,self.svar_change_queue] do
            @[debug] log(INFO, "Calling setter function for " .. name)
            sfun(self.uid, val)
            @[debug] log(INFO, "Setter called")

            self.svar_values[name] = val
            self.svar_value_timestamps[name] = frame.get_frame()
        else
            self:queue_svar_change(name, val)
        end
    end,

    --[[! Function: set_sdata
        The entity state data setter. Has different variants for the client
        and the server.

        If this is on the client and the change didn't come from here (or if
        the property is `client_set`), it performs a var update. The local
        update first calls $sdata_changed and do triggers the `,changed`
        signal (before setting). The new value is passed to the signal
        during the emit along with a boolean equaling to `actor_uid != -1`.

        On the server it triggers a var change in the same manner.

        Arguments:
            - key - the key.
            - val - the value.
            - actor_uid - unique ID of the change source. On the client, -1
              means it's the client itself, on the server it means all clients.
              If the change came from this client on the client and the entity
              doesn't use a custom syncing method, this sends a notification
              to the server.
            - iop - on the server, a boolean value, if it's true it makes
              this an internal server operaton; that always forces the value
              to convert from wire format (otherwise converts only when setting
              on a specific client number).
    ]]
    set_sdata = @[not server,function(self, key, val, actor_uid)
        @[debug] log(DEBUG, "Entity.set_sdata: " .. key .. " = "
            .. serialize(val) .. " for " .. self.uid)

        var svar = self["_SV_" .. key]
        var csfh = svar.custom_sync and self.controlled_here
        var cset = svar.client_set

        var nfh = actor_uid != -1

        -- from client-side script, send a server request unless the svar
        -- is controlled here (synced using some other method)
        -- if this variable is set on the client, send a notification
        if not nfh and not csfh do
            @[debug] log(DEBUG, "    sending server request/notification.")
            -- TODO: supress sending of the same val, at least for some SVs
            msg.send(svar.reliable and capi.statedata_changerequest
                or capi.statedata_changerequest_unreliable,
                self.uid, names_to_ids[self.name][svar.name],
                svar:to_wire(val))
        end

        -- from a server or set clientside, update now
        if nfh or cset or csfh do
            @[debug] log(INFO, "    var update")
            -- from the server, in wire format
            if nfh do
                val = svar:from_wire(val)
            end
            -- TODO: avoid assertions
            assert(svar:validate(val))
            self:sdata_changed(svar, key, val)
            emit(self, key .. ",changed", val, nfh)
            self.svar_values[key] = val
        end
    end,function(self, key, val, actor_uid, iop)
        @[debug] log(DEBUG, "Entity.set_sdata: " .. key .. " = "
            .. serialize(val) .. " for " .. self.uid)

        var svar = self["_SV_" .. key]

        if not svar do
            log(WARNING, "Entity.set_sdata: ignoring sdata setting"
                .. " for an unknown variable " .. key)
            return
        end

        if actor_uid and actor_uid != -1 do
            val = svar:from_wire(val)
            if not svar.client_write do
                log(ERROR, "Entity.set_sdata: client " .. actor_uid
                    .. " tried to change " .. key)
                return
            end
        elif iop do
            val = svar:from_wire(val)
        end

        self:sdata_changed(svar, key, val)
        emit(self, key .. ",changed", val, actor_uid)
        if self.sdata_update_cancel do
            self.sdata_update_cancel = nil
            return
        end

        self.svar_values[key] = val
        @[debug] log(INFO, "Entity.set_sdata: new sdata: " .. tostring(val))

        var csfh = svar.custom_sync and self.controlled_here
        if not iop and svar.client_read and not csfh do
            if not self.sent_notification_full do
                return
            end

            var args = {
                nil, svar.reliable and capi.statedata_update
                    or capi.statedata_update_unreliable,
                self.uid,
                names_to_ids[self.name][key],
                svar:to_wire(val),
                (svar.client_set and actor_uid and actor_uid != -1)
                    and storage[actor_uid].cn or msg.ALL_CLIENTS
            }

            var cns = map(get_players(), function(p) return p.cn end)
            for i = 1, #cns do
                var n = cns[i]
                if svar:should_send(self, n) do
                    args[1] = n
                    msg.send(unpack(args))
                end
            end
        end
    end],

    --[[!
        Cancels a state data update (on the server). Useful when called
        from `,changed` signal slots.
    ]]
    cancel_sdata_update = function(self)
        self.sdata_update_cancel = true
    end,

    --[[! Function: send_notification_full
        On the server, sends a full notification to a specific client
        or all clients.
    ]]
    send_notification_full = @[server,function(self, cn)
        var acn = msg.ALL_CLIENTS
        cn = cn or acn

        var cns = (cn == acn) and map(get_players(), function(p)
            return p.cn end) or { cn }

        var uid = self.uid
        @[debug] log(DEBUG, "Entity.send_notification_full: " .. cn .. ", "
            .. uid)

        var scn, sname = self.cn, self.name
        for i = 1, #cns do
            var n = cns[i]
            msg.send(n, capi.le_notification_complete,
                scn and scn or acn, uid, sname, self:build_sdata(
                    { target_cn = n, compressed = true }))
        end

        @[debug] log(DEBUG, "Entity.send_notification_full: done")
    end],

    --[[! Function: queue_svar_change
        Queues a svar change (Happens before full update, when the
        entity is being created). Server only.
    ]]
    queue_svar_change = @[server,function(self, key, val)
        self.svar_change_queue[key] = val
    end],

    --[[! Function: flush_queued_svar_changes
        Flushes the SV change queue (applies all the changes). After this,
        there is no change queue anymore.
    ]]
    flush_queued_svar_changes = @[server,function(self)
        var changes = self.svar_change_queue
        if not changes do return end
        self.svar_change_queue = nil

        for k, v in pairs(changes) do
            var rv = self.svar_values[k]
            @[debug] log(DEBUG, "Entity: flushing queued svar change: "
                .. k .. " == " .. tostring(v) .. " (real: "
                .. tostring(rv) .. ")")
            self:set_attr(k, rv)
        end

        self.svar_change_queue_complete = true
    end],

    --[[!
        Returns the next attached entity. This implementation doesn't do
        anything though - you need to overload it for your entity type
        accordingly. The core entity system doesn't manage attached
        entities at all. See also $get_attached_prev.
    ]]
    get_attached_next = function(self)
    end,

    --[[!
        Returns the previous attached entity. Like $get_attached_next,
        you need to overload this.
    ]]
    get_attached_prev = function(self)
    end,

    --[[!
        Given a GUI property name (`gui_name` or `name` if not defined in the
        svar), this returns the property value in a wire (string) format.

        See also:
            - $get_attr
            - $get_gui_attrs
            - $set_gui_attr
    ]]
    get_gui_attr = function(self, prop)
        var svar = self["_SV_GUI_" .. prop]
        if not svar or not svar.has_history do return nil end
        var val = self:get_attr(svar.name)
        if val != nil do
            return svar:to_wire(val)
        end
    end,

    --[[!
        Like $get_gui_attr, but returns all available attributes as an
        array of key-value pairs. The second argument (defaults to true)
        specifies whether to sort the result by attribute name.
    ]]
    get_gui_attrs = function(self, sortattrs)
        if sortattrs == nil do sortattrs = true end
        var r = {}
        for k, svar in pairs(self) do
            if is_svar(svar) and svar.has_history and svar.gui_name != false do
                var name = svar.name
                var val = self:get_attr(name)
                if val != nil do
                    r[#r + 1] = { svar.gui_name or name, svar:to_wire(val) }
                end
            end
        end
        if sortattrs do sort(r, function(a, b) return a[1] < b[1] end) end
        return r
    end,

    --[[!
        Given a GUI property name and a value in a wire format, this sets
        the property on the entity.

        See also:
            - $set_attr
            - $get_gui_attr
    ]]
    set_gui_attr = function(self, prop, val)
        var svar = self["_SV_GUI_" .. prop]
        if not svar or not svar.has_history do return end
        self:set_attr(svar.name, svar:from_wire(val))
    end,

    --[[!
        Returns the entity property of the given name.

        See also:
            - $set_attr
            - $get_gui_attr
    ]]
    get_attr = function(self, prop)
        var fun = self["__get_" .. prop]
        if fun do return fun(self) end
        return nil
    end,

    --[[! Function: set_attr
        Sets the entity property of the given name to the given value.

        Arguments:
             - prop - the property name.
             - val - the value.
             - nd - optionally provides a non-wire default value that takes
               preference (if it's provided, it's converted from wire format
               and if that succeeds, it's used in place of the actual value).

        See also:
            - $get_attr
            - $set_gui_attr
    ]]
    set_attr = function(self, prop, val, nd)
        if nd do
            var svar = self["_SV_" .. prop]
            if svar do
                var nw = svar:from_wire(nd)
                if nw != nil do val = nw end
            end
        end
        var fun = self["__set_" .. prop]
        return fun and fun(self, val) or nil
    end
}
Entity = M.Entity

--[[!
    See {{$Entity.get_gui_attr}}. Externally accessible as
    `entity_get_gui_attr` (using uid). See also $set_gui_attr.
]]
M.get_gui_attr = function(ent, prop)
    return ent:get_gui_attr(prop)
end
set_external("entity_get_gui_attr", function(uid, prop)
    return get_ent(uid):get_gui_attr(prop)
end)

--[[!
    See {{$Entity.set_gui_attr}}. Externally accessible as
    `entity_set_gui_attr` (using uid). See also $get_gui_attr.
]]
M.set_gui_attr = function(ent, prop, val)
    return ent:set_gui_attr(prop, val)
end
set_external("entity_set_gui_attr", function(uid, prop, val)
    return get_ent(uid):set_gui_attr(prop, val)
end)

--[[!
    See {{$Entity.get_attr}}. Externally accessible as `entity_get_attr`
    (using the uid). See also $set_attr.
]]
M.get_attr = function(ent, prop)
    return ent:get_attr(prop)
end
set_external("entity_get_attr", function(uid, prop)
    var ent = storage[uid]
    if not ent do return nil end
    return ent:get_attr(prop)
end)

set_external("entity_refresh_attr", function(uid, prop)
    var ent = get_ent(uid)
    ent:set_attr(prop, ent:get_attr(prop))
end)

--[[!
    See {{$Entity.set_attr}}. Externally accessible as `entity_set_attr`
    (using the uid). See also $get_attr.
]]
M.set_attr = function(ent, prop, val)
    return ent:set_attr(prop, val)
end
set_external("entity_set_attr", function(uid, prop, val)
    var ent = storage[uid]
    if not ent do return nil end
    return ent:set_attr(prop, val)
end)

set_external("entity_draw_attached", function(uid)
    var ent = storage[uid]
    if not ent do return end
    var ents = { ent:get_attached_next() }
    if #ents > 0 do
        for i = 1, #ents do capi.entity_draw_attachment(uid, ents[i].uid) end
        return
    end
    ents = { ent:get_attached_prev() }
    if #ents > 0 do
        for i = 1, #ents do capi.entity_draw_attachment(ents[i].uid, uid) end
        return
    end
end)

--[[! Function: entity_get_proto_name
    An external that returns the name of the prototype of the given entity uid.
]]
set_external("entity_get_proto_name", function(uid)
    return get_ent(uid).name
end)

--[[! Function: render
    Main render hook. External as `game_render`. Calls individual `render`
    method on each entity (if defined). Clientside only. See also $render_hud.
]]
M.render = @[not server,function(tp, fpsshadow)
    @[debug] log(INFO, "game_render")
    var  player = player_entity
    if not player do return end

    for uid = 1, highest_uid do
        var entity = storage[uid]
        if entity and not entity.deactivated do
            var rd = entity.__render
            -- first arg to rd is hudpass, false because we aren't rendering
            -- the HUD model, second is needhud, which is true if the model
            -- should be shown as HUD model and that happens if we're not in
            -- thirdperson and the current entity is the player
            -- third is whether we're rendering a first person shadow
            if  rd do
                rd(entity, false, not tp and entity == player, fpsshadow)
            end
        end
    end
end]
var render = M.render
set_external("game_render", render)

--[[! Function: render_hud
    Renders the player HUD model if needed. External as `game_render_hud`.
    Clientside only. See also $render.
]]
M.render_hud = @[not server,function()
    @[debug] log(INFO, "game_render_hud")
    var  player = player_entity
    if not player do return end

    if player:get_attr("hud_model_name") and not player:get_editing() do
        player:__render(true, true, false)
    end
end]
var render_hud = M.render_hud
set_external("game_render_hud", render_hud)

--[[! Function: init_player
    Assigns the player entity using the given uid. External as `player_init`,
    clientside.
]]
M.init_player = @[not server,function(uid)
    assert(uid)
    @[debug] log(DEBUG, "Initializing player with uid " .. uid)

    player_entity = storage[uid]
    assert(player_entity)
    player_entity.controlled_here = true
end]
var init_player = M.init_player
set_external("player_init", init_player)

--[[!
    Converts the protocol ID to a real key and sets the state data on the
    entity with the given unique ID.

    External as `entity_set_sdata`.

    Arguments:
        - uid - an unique ID.
        - kpid - a key in protocol ID format.
        - value - a value.
        - auid - optional (on the server only) actor unique ID, an unique ID
          of the client that triggered the change. When set to -1, it means
          the server triggered it.
]]
M.set_sdata = function(uid, kpid, value, auid)
    var ent = storage[uid]
    if ent do
        var key = ids_to_names[ent.name][kpid]
        @[debug] log(DEBUG, "set_sdata: " .. uid .. ", " .. kpid .. ", "
            .. key)
        ent:set_sdata(key, value, auid)
    end
end
set_external("entity_set_sdata", M.set_sdata)

set_external("entity_set_sdata_full", function(uid, sd)
    get_ent(uid):set_sdata_full(sd)
end)

set_external("entity_serialize_sdata", function(uid, x, y, z)
    var sd = get_ent(uid):build_sdata()
    if not x do
        sd.position = nil
    else
        sd.position = ("[%f|%f|%f]"):format(x, y, z)
    end
    return serialize(sd) or "{}"
end)

--[[ Function: scene_is_ready
    On the client, used to check if the current scene is ready and we can
    actually start (checks whether the player exists and whether all the
    entities are initialized). External as `scene_is_ready`.
!]]
M.scene_is_ready = @[not server,function()
    @[debug] log(INFO, "Scene ready?")

    if player_entity == nil do
        @[debug] log(INFO, "...not ready, player entity missing.")
        return false
    end

    @[debug] log(INFO, "...player ready, trying other entities.")
    for uid = 1, highest_uid do
        var ent = storage[uid]
        if ent and not ent.initialized do
            @[debug] log(INFO, "...entity " .. uid .. " not ready.")
            return false
        end
    end

    @[debug] log(INFO, "...yes!")
    return true
end]
set_external("scene_is_ready", M.scene_is_ready)

--[[! Function: gen_uid
    Generates a new entity unique ID. It's larger than the previous largest
    by one. Serverside. External as `entity_gen_uid`.
]]
M.gen_uid = @[server,function()
    @[debug] log(DEBUG, "Generating an UID, last highest UID: "
        .. highest_uid)
    return highest_uid + 1
end]
var gen_uid = M.gen_uid
set_external("entity_gen_uid", gen_uid)

--! Returns the highest entity unique ID used.
M.get_highest_uid = function()
    return highest_uid
end

set_external("entity_set_cn", function(uid, cn)
    get_ent(uid).cn = cn
end)

--[[! Function: new
    Creates a new entity on the server. External as `entity_new`.

    Arguments:
        - cl - the entity prototype.
        - kwargs - passed directly to $add.
        - fuid - optional forced unique ID, otherwise $gen_uid.

    Returns:
         The new entity.
]]
M.new = @[server,function(cl, kwargs, fuid)
    fuid = fuid or gen_uid()
    @[debug] log(DEBUG, "New entity: " .. fuid)
    return add(cl, fuid, kwargs, true)
end]
var ent_new = M.new

set_external("entity_new_with_sd", function(cl, x, y, z, sd, nd)
    var ent = ent_new(cl, { position = { x = x, y = y, z = z },
        state_data = sd, newent_data = nd })
    @[debug] log(DEBUG, ("Created entity: %d - %s (%f, %f, %f)")
        :format(ent.uid, cl, x, y, z))
end)

set_external("entity_new_with_cn", function(cl, cn, can_edit, char_name, fuid)
    var ent = ent_new(cl, { cn = cn }, fuid)
    assert(ent.cn == cn)
    if can_edit do ent:set_attr("can_edit", can_edit) end
    ent:set_attr("character_name", char_name)
end)

--[[! Function: send
    Notifies a client of the number of entities on the server and do
    send a complete notification for each of them. Takes the client number.
    Works only serverside. External as `entities_send_all`.
]]
M.send = @[server,function(cn)
    @[debug] log(DEBUG, "Sending active entities to " .. cn)
    var nents, uids = 0, {}
    for uid = 1, highest_uid do
        if storage[uid] do
            nents = nents + 1
            uids[nents] = uid
        end
    end
    sort(uids)
    msg.send(cn, capi.notify_numents, nents)
    for i = 1, nents do
        storage[uids[i]]:send_notification_full(cn)
    end
end]
set_external("entities_send_all", M.send)

return M
