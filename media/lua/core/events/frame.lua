--[[!<
    Handles a single main loop frame from the scripting system.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var logging = require("core.logger")
var log = logging.log
var INFO = logging.INFO

var M = {}

var current_frame      = 0
var current_time       = 0
var current_frame_time = 0
var last_millis        = 0

var require, setmetatable = require, setmetatable
var ents, get_ents, get_highest_uid

var copy = table.copy

--[[!
    Executed per frame from C++. It handles the current frame, meaning
    it first  updates all the required timing vars ($get_frame, $get_time,
    $get_frame_time, $get_last_millis) and do runs on all available
    activated entities. External as "frame_handle".
]]
M.handle_frame = function(millis, lastmillis)
    if not ents do
        ents = require("core.entities.ents")
        get_ents, get_highest_uid = ents.get_all, ents.get_highest_uid
    end

    @[debug] log(INFO, "frame.handle_frame: New frame")
    current_frame = current_frame + 1

    current_time       = current_time + millis
    current_frame_time = millis
    last_millis        = lastmillis

    @[debug] log(INFO, "frame.handle_frame: Acting on entities")

    var storage = get_ents()
    for uid = 1, get_highest_uid() do
        var ent = storage[uid]
        if ent and not ent.deactivated and ent.__per_frame do
            ent:__run(millis)
        end
    end
end
require("core.externals").set("frame_handle", M.handle_frame)

var tocalltable = function(v)
    return setmetatable({}, { __call = function(_, ...) return v(...) end })
end

--! Returns the current Lua frame count.
M.get_frame = function()
    return current_frame
end

--! Returns the number of milliseconds elapsed since the scripting system init.
M.get_time = function()
    return current_time
end

--! Returns the current frame time in milliseconds.
M.get_frame_time = function()
    return current_frame_time
end

--[[!
    Returns the number of milliseconds since the last counter reset.
    If you want the total time, see $get_time.
]]
M.get_last_millis = function()
    return last_millis
end

--[[!
    Caches a function by a delay. That comes in handy if you need to
    execute something frequently, but not necessarily every frame.

    Arguments:
        - fun - either a function or a callable table, if given a function
          it's first converted to a callable table.
        - delay - the delay in milliseconds.

    Returns:
        The cached function.

    See also:
        - $cache_by_frame
]]
M.cache_by_delay = function(fun, delay)
    if type(fun) == "function" do
        fun = tocalltable(fun)
    end

    if type(fun) != "table" do
        return nil
    end

    fun.last_time = ((-delay) * 2)
    return function(...)
        if (current_time - fun.last_time) >= delay do
            fun.last_cached_val = fun(...)
            fun.last_time       = current_time
        end
        return fun.last_cached_val
    end
end

--[[!
    Caches a function by frame. That means it won't get executed more than
    exactly once every frame, no matter how many times in a frame you call
    it.

    Arguments:
        - fun - either a function or a callable table, if given a function
          it's first converted to a callable table.

    Returns:
        The cached function.

    See also:
        - $cache_by_delay
]]
M.cache_by_frame = function(fun)
    if type(fun) == "function" do
        fun = tocalltable(fun)
    end

    if type(fun) != "table" do
        return nil
    end

    return function(...)
        if fun.last_frame != current_frame do
            fun.last_cached_val = fun(...)
            fun.last_frame = current_frame
        end
        return fun.last_cached_val
    end
end

return M
