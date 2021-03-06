--[[
    OctaScript

    Copyright (C) 2014 Daniel "q66" Kolesa

    See COPYING.txt for licensing.
]]

local ffi = require("ffi")

local M = {}

M.Object = {
    __call = function(self, ...)
        local r = self:clone()
        if self.__ctor then self.__ctor(r, ...) end
        return r
    end,

    clone = function(self, tbl)
        tbl = tbl or {}
        tbl.__index, tbl.__proto, tbl.__call = self, self, self.__call
        setmetatable(tbl, tbl)
        return tbl
    end,
}

M.error = function(msg)
   if string.sub(msg, 1, 9) == "OFS_ERROR" then
        return false, "octascript: " .. string.sub(msg, 10)
    else
        error(msg)
    end
end

M.null = ffi.cast("void*", 0)

return M
