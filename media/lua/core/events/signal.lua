--[[!<
    Lua signal system. Allows connecting and further emitting signals.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var log = require("core.logger")

var type = type
var rawget, rawset = rawget, rawset
var clamp = math.clamp
var tfind = table.find

--! Module: signal
var M = {}

--[[!
    Connects a signal to a slot inside a table. The callback has to be a
    function.

    You can later use $emit to call the connected slot(s), passing
    arguments to it (them).

    Slots take at least one argument, the table they're connected to.
    They're called in the order they were conected. Any further arguments
    passed to $emit are also passed to any connected slot.

    ```
    Foo = {}
    signal.connect(Foo, "blah", function(self, a, b, c)
        echo(a)
        echo(b)
        echo(c)
    end)
    signal.emit(Foo, "blah", 5, 10, 15)
    ```

    Arguments:
        - self - the table we're connecting on.
        - name - the signal name.
        - callback - the callback.

    Returns:
        The id for the slot, you can later use that to $disconnect the
        slot, it also returns the number of currently connected slots.
]]
M.connect = function(self, name, callback)
    if type(callback) != "function" do
        log.log(log.ERROR, "Not connecting non-function callback: " .. name)
        return nil
    end
    var clistn = "_sig_conn_" .. name

    var  clist = rawget(self, clistn)
    if not clist do
           clist = { slotcount = 0 }
           rawset(self, clistn, clist)
    end

    var id = #clist + 1
    clist[id] = callback

    clist.slotcount = clist.slotcount + 1

    var cb = rawget(self, "__connect")
    if    cb do cb (self, name, callback) end

    return id, clist.slotcount
end

--[[!
    Disconnects a slot (or slots).

    Arguments:
        - self - the table we're disconnecting on.
        - name - the signal name.
        - id - either the id (see $connect) or the slot itself (what you
          connected). If not provided, it disconnects all slots associated
          with the signal.

    Returns:
        The number of connected slots after disconnect (or nil if nothing
        could be disconnected).
]]
M.disconnect = function(self, name, id)
    var clistn = "_sig_conn_" .. name
    var clist  = rawget(self, clistn)
    var cb     = rawget(self, "__disconnect")
    if clist do
        if not id do
            rawset(self, clistn, nil)
            if cb do cb(self, name) end
            return 0
        end
        if type(id) != "number" do
            id = tfind(clist, id)
        end
        if id and id <= #clist do
            var scnt = clist.slotcount - 1
            clist.slotcount = scnt
            rawset(clist, id, false)
            if cb do cb(self, name, id, scnt) end
            return scnt
        end
    end
end

--[[!
    Emits a signal, calling all the slots associated with it in the
    order of connection, passing all extra arguments to it (besides
    the "self" argument). External as "signal_emit".

    Arguments:
        - self - the table we're emitting on.
        - name - the signal name.
        - ... - any further arguments passed to each callback.
]]
M.emit = function(self, name, ...)
    var clistn = "_sig_conn_" .. name
    var clist  = rawget(self, clistn)
    if not clist do
        return 0
    end

    var ncalled = 0
    for i = 1, #clist do
        var cb = clist[i]
        if cb do
            ncalled = ncalled + 1
            cb(self, ...)
        end
    end

    return ncalled
end

return M
