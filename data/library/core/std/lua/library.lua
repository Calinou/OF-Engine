--[[! File: library/core/std/lua/library.lua

    About: Author
        q66 <quaker66@gmail.com>

    About: Copyright
        Copyright (c) 2011 OctaForge project

    About: License
        This file is licensed under MIT. See COPYING.txt for more information.

    About: Purpose
        Lua library system. Further accessible as "library". Used to set
        up a library, include something from it (or from something else)
        and get the current library string.
]]

local M = {}
local ffi = require "ffi"

--[[! Variable: current
    Stores a list of loaded libraries (name strings). Empty by default.
    Calling <use> will add to the list.
]]
M.current = {}

--[[! Function: reset
    Clears up the core library to the default state. Called on map exit.
]]
M.reset = function()
end

--[[! Function: use
    Loads a library of a given name. Does the required internal modifications.
    Executes the initializer script (init.lua). Returns the result of
    require() on the library, which is mostly irrelevant.
]]
M.use = function(name)
    if not name or name:find("..", 1, true) then
        M.current = nil
        return nil
    end

    local pdiv = "/"
    if ffi.os == "Windows" then pdiv = "\\" end

    local ptrn  = ";./data/library/" .. name .. "/?.lua"
    local ppath = package.path
    if not ppath:find(ptrn, 1, true) then
        package.path = ("%s;%sdata%slibrary%s%s%s?.lua%s"):format(ppath,
            _V.homedir, pdiv, pdiv, name, pdiv, ptrn)
    end

    M.current = name
    return require(name)
end

--[[! Function: include
    Includes a module, either from the core library, one of the loaded
    libraries or anywhere from data/ (useful to include various assets,
    for example, library.include("textures.foo") runs a script
    "data/textures/foo/init.lua"). Returns the result of require()
    on the module, which is mostly irrelevant.
]]
M.include = function(name)
    return require(name)
end

return M
