--[[!<
    Lua table extensions.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var capi = require("capi")

var ctable = capi.table_create
var pairs, ipairs = pairs, ipairs
var type, setmetatable = type, setmetatable
var rawget, rawset = rawget, rawset
var tostring = tostring
var tconc = table.concat
var pcall = pcall
var floor, log = math.floor, math.log

var ext_set = require("core.externals").set

--[[!
    Checks whether the given table is an array (that is, contains only a
    consecutive sequence of values with indexes from 1 to #table). If
    there is any non-array element found, returns false. Otherwise
    returns true.
]]
table.is_array = function(t)
    var i = 0
    while t[i + 1] do i = i + 1 end
    for _ in pairs(t) do
        i = i - 1 if i < 0 do return false end
    end
    return i == 0
end

var is_array = table.is_array

--[[!
    Implements the standard functional "map" higher order function. Returns
    a new table, leaving the old one alone.

    ```
    -- table of numbers
    foo = { bar = 5, baz = 10 }
    -- table of strings
    bar = map(foo, |v| tostring(v))
    ```

    Arguments:
        - t - the table.
        - f - the function.
]]
table.map = function(t, f)
    var r = {}
    for i, v in pairs(t) do r[i] = f(v) end
    return r
end

--[[!
    Merges two arrays. Contents of the other come after those of the first one.
]]
table.merge = function(ta, tb)
    var l1, l2 = #ta, #tb
    var r = ctable(l1 + l2)
    for i = 1, l1 do r[#r + 1] = ta[i] end
    for i = 1, l2 do r[#r + 1] = tb[i] end
    return r
end

--[[!
    Merges two associative arrays (maps). When a key overlaps, the latter
    value is preferred.
]]
table.merge_maps = function(ta, tb)
    var r = {}
    for a, b in pairs(ta) do r[a] = b end
    for a, b in pairs(tb) do r[a] = b end
    return r
end

--[[!
    Returns a copy of the given table. It's a shallow copy.
]]
table.copy = function(t)
    var r = ctable(#t)
    for a, b in pairs(t) do r[a] = b end
    return r
end

--[[!
    Implements the standard functional "filter" higher order function.
    Returns a new table, leaving the old one alone. The given function
    takes two arguments, the index and the value.

    For in-place equivalent, see $compact.

    ```
    -- a table to filter
    foo = { 5, 10, 15, 20 }
    -- the filtered table, contains just 5, 10, 20
    bar = filter(foo, function(k, v)
        if v == 15 do
            return false
        else
            return true
        end
    end)
    ```

    Arguments:
        - t - the table.
        - f - the function.

    See also:
        - $filter_map
]]
table.filter = function(t, f)
    var r = {}
    for i = 1, #t do if f(i, t[i]) do r[#r + 1] = t[i] end end
    return r
end

--[[!
    See $filter. Works the same, but operates on a hash map (the result
    is not guaranteed to be without holes).

    ```
    -- a table to filter
    foo = { a = 5, b = 10, c = 15, d = 20 }
    -- the filtered table, contains just key/value pairs a, b, d
    bar = filter_map(foo, function(k, v)
        if k == "c" do
            return false
        else
            return true
        end
    end)
    ```
]]
table.filter_map = function(t, f)
    var r = {}
    for a, b in pairs(t) do if f(a, b) do r[a] = b end end
    return r
end

--[[!
    Compacts an array - simply discards items that do not meet the condition
    (which is given by the function). If the function returns true (given the
    index and the value), the item stays; otherwise goes away (and items after
    that are shifted down). Returns the array. Works in-place on the array,
    unlike $filter.

    ```
    var t = { 5, 10, 15, 10, 20, 10, 25 }
    -- the compacted table is { 5, 15, 20, 25 }
    compact(t, |v| v != 10)
    ```

    Arguments:
        - t - the table.
        - f - the conditional function.
]]
table.compact = function(t, f)
    var olen, comp = #t, 0
    for i = 1, olen do
        var v = t[i]
        if not f(i, v) do comp += 1 elif comp > 0 do t[i - comp] = v end
    end
    for i = olen, olen - comp + 1, -1 do t[i] = nil end
    return t
end

--[[!
    Finds the key of an element in the given table.

    Arguments:
         - t - the table.
         - v - the element (its value).
]]
table.find = function(t, v)
    for a, b in pairs(t) do if v == b do return a end end
end

--[[!
    Implements the standard functional right fold higher order function.

    ```
        var a = { 5, 10, 15, 20 }
        assert(foldr(a, function(a, b) return a + b end) == 50)
    ```

    Arguments:
        - t - the table.
        - fun - the function.
        - z - the default value.

    See also:
        - $foldl
]]
table.foldr = function(t, fun, z)
    var idx = 1
    if not z do
        z   = t[1]
        idx = 2
    end

    for i = idx, #t do
        z = fun(z, t[i])
    end
    return z
end

--[[!
    Implements the standard functional left fold higher order function.

    See also:
        - $foldl
]]
table.foldl = function(t, fun, z)
    var len = #t
    if not z do
        z   = t[len]
        len = len - 1
    end
    
    for i = len, 1, -1 do
        z = fun(z, t[i])
    end
    return z
end

var function serialize_fn(v, stream, kwargs, simp, tables, indent)
    if simp do
        v = simp(v)
    end
    var tv = type(v)
    if tv == "string" do
        stream(v:escape())
    elif tv == "number" or tv == "boolean" do
        stream(tostring(v))
    elif tv == "table" do
        var mline   = kwargs.multiline
        var indstr  = kwargs.indent
        var asstr   = kwargs.assign or "="
        var sepstr  = kwargs.table_sep or ","
        var isepstr = kwargs.item_sep
        var endsep  = kwargs.end_sep
        var optk    = kwargs.optimize_keys
        var arr = is_array(v)
        var nline   = arr and kwargs.narr_line or kwargs.nrec_line or 0
        if tables[v] do
            stream() -- let the stream know about an error
            return false,
                "circular table reference detected during serialization"
        end
        tables[v] = true
        stream("{")
        if mline do stream("\n") end
        var first = true
        var n = 0
        for k, v in (arr and ipairs or pairs)(v) do
            if first do first = false
            else
                stream(sepstr)
                if mline do
                    if n == 0 do
                        stream("\n")
                    elif isepstr do
                        stream(isepstr)
                    end
                end
            end
            if mline and indstr and n == 0 do
                for i = 1, indent do stream(indstr) end
            end
            if arr do
                var ret, err = serialize_fn(v, stream, kwargs, simp, tables,
                    indent + 1)
                if not ret do return ret, err end
            else
                if optk and type(k) == "string"
                and k:match("^[%a_][%w_]*$") do
                    stream(k)
                else
                    stream("[")
                    var ret, err = serialize_fn(k, stream, kwargs, simp,
                        tables, indent + 1)
                    if not ret do return ret, err end
                    stream("]")
                end
                stream(asstr)
                var ret, err = serialize_fn(v, stream, kwargs, simp, tables,
                    indent + 1)
                if not ret do return ret, err end
            end
            n = (n + 1) % nline
        end
        if not first do
            if endsep do stream(sepstr) end
            if mline do stream("\n") end
        end
        if mline and indstr do
            for i = 2, indent do stream(indstr) end
        end
        stream("}")
    else
        stream()
        return false, ("invalid value type: " .. tv)
    end
    return true
end

var defkw = {
    multiline = false, indent = nil, assign = "=", table_sep = ",",
    end_sep = false, optimize_keys = true
}

var defkwp = {
    multiline = true, indent = "    ", assign = " = ", table_sep = ",",
    item_sep = " ", narr_line = 4, nrec_line = 2, end_sep = false,
    optimize_keys = true
}

--[[!
    Serializes a given table, returning a string containing a literal
    representation of the table. It tries to be compact by default so it
    avoids whitespace and newlines. Arrays and associative arrays are
    serialized differently (for compact output).

    Besides tables this can also serialize other Lua values. It serializes
    them in the same way as values inside a table, returning their literal
    representation (if serializable, otherwise just their tostring). The
    serializer allows strings, numbers, booleans and tables.

    Circular tables can't be serialized. The function normally returns either
    the string output or nil + an error message (which can signalize either
    circular references or invalid types).

    The function allows you to pass in a "kwargs" table as the second argument.
    It's a table of options. Those can be multiline (boolean, false by default,
    pretty much pretty-printing), indent (string, nil by default, specifies
    how an indent level looks), assign (string, "=" by default, specifies how
    an assignment between a key and a value looks), table_sep (table separator,
    by default ",", can also be ";" for tables, separates items in all cases),
    item_sep (item separator, string, nil by default, comes after table_sep
    but only if it isn't followed by a newline), narr_line (number, 0 by
    default, how many array elements to fit on a line), nrec_line (same,
    just for key-value pairs), end_sep (boolean, false by default, makes
    the serializer put table_sep after every item including the last one),
    optimize_keys (boolean, true by default, optimizes string keys like
    that it doesn't use string literals for keys that can be expressed
    as Lua names).

    If kwargs is nil or false, the values above are used. If kwargs is a
    boolean value true, pretty-printing defaults are used (multiline is
    true, indent is 4 spaces, assign is " = ", table_sep is ",", item_sep
    is one space, narr_line is 4, nrec_line is 2, end_sep is false,
    optimize_keys is true).

    This function is externally available as "table_serialize".

    Arguments:
        - val - the value to serialize.
        - kwargs - see above.
        - stream - optionally a function that is called every time a new piece
          is saved - when a custom stream is supplied, the function doesn't
          return a string, but it returns true or false depending on whether
          it succeeded and a potential error message.
        - simplifier - optionally a function that takes a value and simplifies
          it (returns another value the original should be replaced with),
          by default there is no simplifier.
]]
var serialize = function(val, kwargs, stream, simplifier)
    if kwargs == true do
        kwargs = defkwp
    elif not kwargs do
        kwargs = defkw
    else
        if  kwargs.optimize_keys == nil do
            kwargs.optimize_keys = true
        end
    end
    if stream do
        return serialize_fn(val, stream, kwargs, simplifier, {}, 1)
    else
        var t = {}
        var ret, err = serialize_fn(val, function(out)
            t[#t + 1] = out end, kwargs, simplifier, {}, 1)
        if not ret do
            return nil, err
        else
            return tconc(t)
        end
    end
end
table.serialize = serialize
ext_set("table_serialize", serialize)

var lex_get = function(ls)
    while true do
        var c = ls.curr
        if not c do break end
        ls.tname, ls.tval = nil, nil
        if c == "\n" or c == "\r" do
            var prev = c
            c = ls.rdr()
            if (c == "\n" or c == "\r") and c != prev do
                c = ls.rdr()
            end
            ls.curr = c
            ls.linenum = ls.linenum + 1
        elif c == " " or c == "\t" or c == "\f" or c == "\v" do
            ls.curr = ls.rdr()
        elif c == "." or c:byte() >= 48 and c:byte() <= 57 do
            var buf = { ls.curr }
            ls.curr = ls.rdr()
            while ls.curr and ls.curr:match("[epxEPX0-9.+-]") do
                buf[#buf + 1] = ls.curr
                ls.curr = ls.rdr()
            end
            var str = tconc(buf)
            var num = tonumber(str)
            if not num do error(("%d: malformed number near '%s'")
                :format(ls.linenum, str), 0) end
            ls.tname, ls.tval = "<number>", num
            return "<number>"
        elif c == '"' or c == "'" do
            var d = ls.curr
            ls.curr = ls.rdr()
            var buf = {}
            while ls.curr != d do
                var c = ls.curr
                if c == nil do
                    error(("%d: unfinished string near '<eos>'")
                        :format(ls.linenum), 0)
                elif c == "\n" or c == "\r" do
                    error(("%d: unfinished string near '<string>'")
                        :format(ls.linenum), 0)
                -- not complete escape sequence handling: handles only these
                -- that are or can be in the serialized output
                elif c == "\\" do
                    c = ls.rdr()
                    if c == "a" do
                        buf[#buf + 1] = "\a" ls.curr = ls.rdr()
                    elif c == "b" do
                        buf[#buf + 1] = "\b" ls.curr = ls.rdr()
                    elif c == "f" do
                        buf[#buf + 1] = "\f" ls.curr = ls.rdr()
                    elif c == "n" do
                        buf[#buf + 1] = "\n" ls.curr = ls.rdr()
                    elif c == "r" do
                        buf[#buf + 1] = "\r" ls.curr = ls.rdr()
                    elif c == "t" do
                        buf[#buf + 1] = "\t" ls.curr = ls.rdr()
                    elif c == "v" do
                        buf[#buf + 1] = "\v" ls.curr = ls.rdr()
                    elif c == "\\" or c == '"' or c == "'" do
                        buf[#buf + 1] = c
                        ls.curr = ls.rdr()
                    elif not c do
                        error(("%d: unfinished string near '<eos>'")
                            :format(ls.linenum), 0)
                    else
                        if not c:match("%d") do
                            error(("%d: invalid escape sequence")
                                :format(ls.linenum), 0)
                        end
                        var dbuf = { c }
                        c = ls.rdr()
                        if c:match("%d") do
                            dbuf[2] = c
                            c = ls.rdr()
                            if c:match("%d") do
                                dbuf[3] = c
                                c = ls.rdr()
                            end
                        end
                        ls.curr = c
                        buf[#buf + 1] = tconc(dbuf):char()
                    end
                else
                    buf[#buf + 1] = c
                    ls.curr = ls.rdr()
                end
            end
            ls.curr = ls.rdr() -- skip delim
            ls.tname, ls.tval = "<string>", tconc(buf)
            return "<string>"
        elif c:match("[%a_]") do
            var buf = { c }
            ls.curr = ls.rdr()
            while ls.curr and ls.curr:match("[%w_]") do
                buf[#buf + 1] = ls.curr
                ls.curr = ls.rdr()
            end
            var str = tconc(buf)
            if str == "true" or str == "false" or str == "nil" do
                ls.tname, ls.tval = str, nil
                return str
            else
                ls.tname, ls.tval = "<name>", str
                return "<name>"
            end
        else
            ls.curr = ls.rdr()
            ls.tname, ls.tval = c, nil
            return c
        end
    end
end

var function assert_tok(ls, tok, ...)
    if not tok do return end
    if ls.tname != tok do
        error(("%d: unexpected symbol near '%s'"):format(ls.linenum,
            ls.tname), 0)
    end
    lex_get(ls)
    assert_tok(ls, ...)
end

var function parse(ls)
    var tok = ls.tname
    if tok == "<string>" or tok == "<number>" do
        var v = ls.tval
        lex_get(ls)
        return v
    elif tok == "true"  do lex_get(ls) return true
    elif tok == "false" do lex_get(ls) return false
    elif tok == "nil"   do lex_get(ls) return nil
    else
        assert_tok(ls, "{")
        var tbl = {}
        if ls.tname == "}" do
            lex_get(ls)
            return tbl
        end
        repeat
            if ls.tname == "<name>" do
                var key = ls.tval
                lex_get(ls)
                assert_tok(ls, "=")
                tbl[key] = parse(ls)
            elif ls.tname == "[" do
                lex_get(ls)
                var key = parse(ls)
                assert_tok(ls, "]", "=")
                tbl[key] = parse(ls)
            else
                tbl[#tbl + 1] = parse(ls)
            end
        until (ls.tname != "," and ls.tname != ";") or not lex_get(ls)
        assert_tok(ls, "}")
        return tbl
    end
end

--[[!
    Takes a previously serialized table and converts it back to the original.
    Uses a simple tokenizer and a recursive descent parser to build the result
    so it's safe (doesn't evaluate anything). The input can also be a callable
    value that return the next character each call.
    External as "table_deserialize". This returns the deserialized value on
    success and nil + the error message on failure.
]]
table.deserialize = function(s)
    var stream = (type(s) == "string") and s:gmatch(".") or s
    var ls = { curr = stream(), rdr = stream, linenum = 1 }
    var r, v = pcall(lex_get, ls)
    if not r do return nil, v end
    r, v = pcall(parse, ls)
    if not r do return nil, v end
    return v
end
ext_set("table_deserialize", table.deserialize)

var sift_down = function(tbl, l, s, e, fun)
    var root = s
    while root * 2 - l + 1 <= e do
        var child = root * 2 - l + 1
        var swap  = root
        if fun(tbl[swap], tbl[child]) do
            swap = child
        end
        if child + 1 <= e and fun(tbl[swap], tbl[child + 1]) do
            swap = child + 1
        end
        if swap != root do
            tbl[root], tbl[swap] = tbl[swap], tbl[root]
            root = swap
        else return end
    end
end

var heapsort = function(tbl, l, r, fun)
    var start = floor((l + r) / 2)
    while start >= l do
        sift_down(tbl, l, start, r, fun)
        start = start - 1
    end
    var e = r
    while e > l do
        tbl[e], tbl[l] = tbl[l], tbl[e]
        e = e - 1
        sift_down(tbl, l, l, e, fun)
    end
end

var partition = function(tbl, l, r, pidx, fun)
    var pivot = tbl[pidx]
    tbl[pidx], tbl[r] = tbl[r], tbl[pidx]
    for i = l, r - 1 do
        if fun(tbl[i], pivot) do
            tbl[i], tbl[l] = tbl[l], tbl[i]
            l = l + 1
        end
    end
    tbl[l], tbl[r] = tbl[r], tbl[l]
    return l
end

var insertion_sort = function(tbl, l, r, fun)
    for i = l, r do
        var j, v = i, tbl[i]
        while j > 1 and not fun(tbl[j - 1], v) do
            tbl[j] = tbl[j - 1]
            j = j - 1
        end
        tbl[j] = v
    end
end

var function introloop(tbl, l, r, depth, fun)
    if (r - l) > 10 do
        if depth == 0 do
            return heapsort(tbl, l, r, fun)
        end
        var pidx = partition(tbl, l, r, floor((l + r) / 2), fun)
        introloop(tbl, l, pidx - 1, depth - 1, fun)
        introloop(tbl, pidx + 1, r, depth - 1, fun)
    else insertion_sort(tbl, l, r, fun) end
end

var introsort = function(tbl, l, r, fun)
    return introloop(tbl, l, r, 2 * floor(log(r - l + 1) / log(2)), fun)
end

var defaultcmp = function(a, b) return a < b end

--[[!
    A substitute for the original table.sort. Normally it behaves exactly
    like table.sort (takes a table, optionally a comparison function and
    sorts the table in-place), but it also takes two other arguments
    specifying from where to where to sort the table (the starting
    and ending indexes, both are inclusive). Under LuaJIT it's also
    considerably faster than vanilla table.sort (about 3x).

    Thanks to custom indexes and independence on type assumptions this
    can sort not only Lua arrays in a raw form, but also any kind of
    "virtual" array (for example a state array surrogate) or a FFI
    array.

    The sorting algorithm used here is introsort. It's a modification
    of quicksort that switches to heapsort when the recursion depth
    exceeds 2 * floor(log(nitems) / log(2)). It also uses insertion
    sort to sort small sublists (10 elements and smaller). The
    quicksort part uses a median of three pivot.
]]
table.sort = function(tbl, fun, l, r)
    l, r = l or 1, r or #tbl
    return introsort(tbl, l, r, fun or defaultcmp)
end

------------------
-- Object system -
------------------

--[[!
    Provides the basis for any object in OF. It implements a simple prototypal
    OO system.
]]
table.Object = {
    --[[!
        When you call an object, it's identical to $clone, but it also
        tries to call a __ctor field of the current object on the result,
        passing in any extra arguments (besides the new object as the first
        argument).
    ]]
    __call = function(self, ...)
        var r = {
            __index = self, __proto = self, __call = self.__call,
            __tostring = self.__tostring
        }
        setmetatable(r, r)
        if self.__ctor do self.__ctor(r, ...) end
        return r
    end,

    --[[!
        "Clones" an object. It's not an actual clone as it's delegative
        (doesn't copy, only hooks a metatable). Thanks to its delegative
        nature changes in parents also reflect in children.

        Arguments:
            tbl - optionally a table to serve as a basis for the new clone
            (this will modify the table and hook its metatable properly).

        Returns:
            The new clone.
    ]]
    clone = function(self, tbl)
        tbl = tbl or {}
        tbl.__index, tbl.__proto, tbl.__call = self, self, self.__call
        if not tbl.__tostring do tbl.__tostring = self.__tostring end
        setmetatable(tbl, tbl)
        return tbl
    end,

    --[[!
        Checks whether the current object is a either equal to the given
        object, is a child of the given object, or a child of a child
        of the given object, or anything down the tree.
    ]]
    is_a = function(self, base)
        if self == base do return true end
        var pt = self.__proto
        var is = (pt == base)
        while not is and pt do
            pt = pt.__proto
            is = (pt == base)
        end
        return is
    end,

    --[[!
        The default tostring result is in format "Object: NAME" where NAME
        is self.name.
    ]]
    __tostring = function(self)
        return ("Object: %s"):format(self.name or "unnamed")
    end
}
