--[[!<
    Provides the handling of externals. Not accessible from anywhere but the
    core library.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var capi = require("capi")

--! Module: externals
var M = {}

var externals = {}

--! Retrieves the external of the given name.
M.get = function(name)
    return externals[name]
end

--! Unsets the external of the given name, returns the previous value or nil.
M.unset = function(name)
    var old = externals[name]
    if old == nil do return nil end
    externals[name] = nil
    return old
end

--! Sets the external of the given name, returns the previous value or nil.
M.set = function(name, fun)
    var old = externals[name]
    externals[name] = fun
    return old
end

capi.external_hook(M.get)

return M
