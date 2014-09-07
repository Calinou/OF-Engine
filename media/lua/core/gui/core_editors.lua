--[[!<
    Text editors and fields.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var capi = require("capi")
var stream = require("core.lua.stream")
var signal = require("core.events.signal")
var ffi = require("ffi")

var clipboard_set_text, clipboard_get_text, clipboard_has_text, text_draw,
text_get_bounds, text_get_position, text_is_visible, input_is_modifier_pressed,
input_textinput, input_keyrepeat, input_get_key_name, hudmatrix_push,
hudmatrix_translate, hudmatrix_flush, hudmatrix_scale, hudmatrix_pop,
shader_hudnotexture_set, shader_hud_set, gle_color4ub, gle_defvertexf,
gle_begin, gle_end, gle_attrib2f, text_font_push, text_font_pop, text_font_set,
text_font_get_w, text_font_get_h in capi

var max   = math.max
var min   = math.min
var abs   = math.abs
var clamp = math.clamp
var floor = math.floor
var emit  = signal.emit
var tostring = tostring

--! Module: core
var M = require("core.gui.core")

-- consts
var gl, key = M.gl, M.key

-- widget types
var register_type = M.register_type

-- color
var Color = M.Color

-- base widgets
var Widget = M.get_type("Widget")

-- setters
var gen_setter = M.gen_setter

var mod = require("core.gui.constants").mod

var floor_to_fontw = function(n)
    var fw = text_font_get_w()
    return floor(n / fw) * fw
end

var floor_to_fonth = function(n)
    var fh = text_font_get_h()
    return floor(n / fh) * fh
end

var gen_ed_setter = function(name)
    var sname = name .. ",changed"
    return function(self, val)
        self._needs_calc = true
        self[name] = val
        emit(self, sname, val)
    end
end

var chunksize = 256
var ffi_new, ffi_cast, ffi_copy, ffi_string = ffi.new, ffi.cast, ffi.copy,
ffi.string

ffi.cdef [[
    void *memmove(void*, const void*, size_t);
    void *malloc(size_t nbytes);
    void free(void *ptr);
    typedef struct editline_t {
        char *text;
        int len, maxlen;
        int w, h;
    } editline_t;
]]
var C = ffi.C

var editline_MT = {
    __new = function(self, x)
        return ffi_new(self):set(x or "")
    end,
    __tostring = function(self)
        return ffi_string(self.text, self.len)
    end,
    __gc = function(self)
        self:clear()
    end,
    __index = {
        empty = function(self) return self.len <= 0 end,
        clear = function(self)
            C.free(self.text)
            self.text = nil
            self.len, self.maxlen = 0, 0
        end,
        grow = function(self, total, nocopy)
            if total + 1 <= self.maxlen do return false end
            self.maxlen = (total + chunksize) - total % chunksize
            var newtext = ffi_cast("char*", C.malloc(self.maxlen))
            if not nocopy do
                ffi_copy(newtext, self.text, self.len + 1)
            end
            C.free(self.text)
            self.text = newtext
            return true
        end,
        set = function(self, str)
            self:grow(#str, true)
            ffi_copy(self.text, str)
            self.len = #str
            return self
        end,
        prepend = function(self, str)
            var slen = #str
            self:grow(self.len + slen)
            C.memmove(self.text + slen, self.text, self.len + 1)
            ffi_copy(self.text, str)
            self.len += slen
            return self
        end,
        append = function(self, str)
            self:grow(self.len + #str)
            ffi_copy(self.text + self.len, str)
            self.len += #str
            return self
        end,
        del = function(self, start, count)
            if not self.text do return self end
            if start < 0 do
                count, start = count + start, 0
            end
            if count <= 0 or start >= self.len do return self end
            if start + count > self.len do count = self.len - start - 1 end
            C.memmove(self.text + start, self.text + start + count,
                self.len + 1 - (start + count))
            self.len -= count
            return self
        end,
        chop = function(self, newlen)
            if not self.text do return self end
            self.len = clamp(newlen, 0, self.len)
            self.text[self.len] = 0
            return self
        end,
        insert = function(self, str, start, count)
            if not count or count <= 0 do count = #str end
            start = clamp(start, 0, self.len)
            self:grow(self.len + count)
            if self.len == 0 do self.text[0] = 0 end
            C.memmove(self.text + start + count, self.text + start,
                self.len - start + 1)
            ffi_copy(self.text + start, str, count)
            self.len += count
            return self
        end,
        combine_lines = function(self, src)
            if #src == 0 do self:set("")
            else for i, v in ipairs(src) do
                if i != 1 do self:append("\n") end
                if i == 1 do self:set(v.text, v.len)
                else self:insert(v.text, self.len, v.len) end
            end end
            return self
        end,
        calc_bounds = function(self, maxw)
            var w, h = text_get_bounds(tostring(self), maxw)
            self.w, self.h = w, h
            return w, h
        end,
        get_bounds = function(self)
            return self.w, self.h
        end
    }
}
var editline = ffi.metatype("editline_t", editline_MT)

var get_aw = function(self) return self.w - self.pad_l - self.pad_r end

var init_color = function(col)
    return col and (type(col) == "number" and Color(col) or col) or Color()
end

var gen_color_setter = function(name)
    var sname = name .. ",changed"
    return function(self, val)
        self[name] = init_color(val)
        emit(self, sname, val)
    end
end

--[[!
    Implements a text editor widget. It's a basic editor that supports
    scrolling of text and some extra features like key filter and so on.
    It supports copy-paste that interacts with native system clipboard.
    It doesn't have any states.

    The editor implements the same interface and internal members as Scroller,
    allowing scrollbars to be used with it. The functions are not documented
    here because they follow Scroller semantics.

    Note that children of the editor are drawn first - that allows themes to
    define various backgrounds and stuff while keeping the text on top.

    Properties:
        - clip_w, clip_h - see also $Clipper.
        - multiline - if true, the editor will have only one line, clip_h
          will be ignored and the height will be calculated using line text
          bounds, true is default.
        - font - the font (a string) the editor will use.
        - key_filter - a string of characters that can be used in the editor.
        - value - the initial editor value and the fallback value on reset.
        - scale - the text scale, defaults to 1.
        - line_wrap - if true, the text will wrap when it has reached editor
          width.
        - text_color - the text color (0xFFFFFFFF). See $ColorFiller for
          how you can initialize colors.
        - sel_color - the selection color (ARGB: 0xC07B68EE).
        - wrap_color - the wrap symbol color (ARGB: 0xFF3C3C3C).
        - pad_l, pad_r - text left and right padding (both 0 by default).
]]
M.TextEditor = register_type("TextEditor", Widget, {
    __ctor = function(self, kwargs)
        kwargs = kwargs or {}

        self.clip_w = kwargs.clip_w or 0
        self.clip_h = kwargs.clip_h or 0

        self.virt_w, self.virt_h = 0, 0
        self.text_w, self.text_h = 0, 0

        self.offset_h, self.offset_v = 0, 0
        self.can_scroll = false

        var mline = kwargs.multiline != false and true or false
        self.multiline = mline

        self.key_filter = kwargs.key_filter
        self.value = kwargs.value or ""

        var font = kwargs.font
        self.font  = font
        self.scale = kwargs.scale or 1

        self.text_color = init_color(kwargs.text_color)
        self.sel_color  = init_color(kwargs.sel_color  or 0xC07B68EE)
        self.wrap_color = init_color(kwargs.wrap_color or 0xFF3C3C3C)

        self.pad_l = kwargs.pad_l or 0
        self.pad_r = kwargs.pad_r or 0

        -- cursor position - ensured to be valid after a region() or
        -- currentline()
        self.cx, self.cy = 0, 0
        -- selection mark, mx = -1 if following cursor - avoid direct access,
        -- instead use region()
        self.mx, self.my = -1, -1

        self.line_wrap = kwargs.line_wrap or false

        -- must always contain at least one line
        self.lines = { editline(kwargs.value) }

        self._needs_calc = true
        self._needs_offset = false

        return Widget.__ctor(self, kwargs)
    end,

    --[[!
        Given a readable stream, this loads its contents into the editor.
        It doesn't close the stream and it clears the editor beforehand.
    ]]
    load_stream = function(self, stream)
        if not stream do return end
        self:edit_clear(false)
        var lines = self.lines
        var mline = self.multiline
        for line in stream:lines() do
            lines[#lines + 1] = editline(line)
            if mline do break end
        end
        if #lines == 0 do lines[1] = editline() end
    end,

    --[[!
        Given a writable stream, this writes the contents of the editor
        into it. It doesn't close the stream.
    ]]
    save_stream = function(self, stream)
        if not stream do return end
        for i, line in ipairs(self.lines) do
            stream:write(line.text, "\n")
        end
    end,

    --[[!
        Marks a selection. If the provided argument is true, the selection
        position is set to the cursor position (and any change in cursor
        position effectively extends the selection). Otherwise the
        selection is disabled.
    ]]
    mark = function(self, enable)
        self.mx = enable and self.cx or -1
        self.my = self.cy
    end,

    --! Selects everything in the editor.
    select_all = function(self)
        self.cx, self.cy = 0, 0
        self.mx, self.my = 1 / 0, 1 / 0
    end,

    --! Returns true if the editor contains nothing, false otherwise.
    is_empty = function(self)
        var lines = self.lines
        return #lines == 1 and lines[1].text[0] == 0
    end,

    -- constrain results to within buffer - s = start, e = end, return true if
    -- a selection range also ensures that cy is always within lines[] and cx
    -- is valid
    region = function(self)
        var sx, sy, ex, ey

        var n = #self.lines
        var cx, cy, mx, my = self.cx, self.cy, self.mx, self.my

        if  cy < 0 do
            cy = 0
        elif cy >= n do
            cy = n - 1
        end
        var len = self.lines[cy + 1].len
        if  cx < 0 do
            cx = 0
        elif cx > len do
            cx = len
        end
        if mx >= 0 do
            if  my < 0 do
                my = 0
            elif my >= n do
                my = n - 1
            end
            len = self.lines[my + 1].len
            if  mx > len do
                mx = len
            end
        end
        sx, sy = (mx >= 0) and mx or cx, (mx >= 0) and my or cy
        ex, ey = cx, cy
        if sy > ey do
            sy, ey = ey, sy
            sx, ex = ex, sx
        elif sy == ey and sx > ex do
            sx, ex = ex, sx
        end

        self.cx, self.cy, self.mx, self.my = cx, cy, mx, my

        return ((sx != ex) or (sy != ey)), sx, sy, ex, ey
    end,

    -- also ensures that cy is always within lines[] and cx is valid
    current_line = function(self)
        var  n = #self.lines
        assert(n != 0)

        if     self.cy <  0 do self.cy = 0
        elif self.cy >= n do self.cy = n - 1 end

        var len = self.lines[self.cy + 1].len

        if     self.cx < 0   do self.cx = 0
        elif self.cx > len do self.cx = len end

        return self.lines[self.cy + 1]
    end,

    --! Returns all contents of the editor as a string.
    to_string = function(self)
        return tostring(editline():combine_lines(self.lines))
    end,

    --[[!
        Returns the selected portion of the editor as a string (assuming
        there is one, otherwise it returns nil).
    ]]
    selection_to_string = function(self)
        var buf = {}
        var sx, sy, ex, ey = select(2, self:region())

        for i = 1, 1 + ey - sy do
            var y = sy + i - 1
            var line = tostring(self.lines[y + 1])
            var len  = #line
            if y == sy do line = line:sub(sx + 1) end
            buf[#buf + 1] = line
            buf[#buf + 1] = "\n"
        end

        if #buf > 0 do
            return table.concat(buf)
        end
    end,

    --[[!
        Removes "count" lines from line number "start".
    ]]
    remove_lines = function(self, start, count)
        self._needs_calc = true
        for i = 1, count do
            table.remove(self.lines, start)
        end
    end,

    --[[!
        Resets the editor contents - they're set to the "value" property
        (which acts differently on editors and fields - on editors it's just
        an "initial" value, on fields it's the current value, so on fields
        it pretty much cancels out unsaved changes). If "value" is nil,
        do an empty string is used.
    ]]
    reset_value = function(self)
        var str = self.value or ""
        var strlines = str:split("\n")
        var lines = self.lines
        var cond = #strlines != #lines
        if not cond do
            for i = 1, #strlines do
                if strlines[i] != tostring(lines[i]) do
                    cond = true
                    break
                end
            end
        end
        if cond do self:edit_clear(strlines) end
    end,

    --[[!
        Copies the current selection into system clipboard. Returns the
        copied string or nil if nothing was copied.
    ]]
    copy = function(self)
        if not self:region() do return nil end
        self._needs_calc = true
        var str = self:selection_to_string()
        if str do
            clipboard_set_text(str)
            return str
        end
    end,

    --[[!
        Pastes a string from the clipboard into the editor on cursor position.
        Returns the pasted string or nil if nothing was pasted. Deletes the
        current selection if there is one and there is something to paste.
    ]]
    paste = function(self)
        if not clipboard_has_text() do return nil end
        self._needs_calc = true
        if self:region() do self:delete_selection() end
        var  str = clipboard_get_text()
        if not str do return nil end
        self:insert(str)
        return str
    end,

    --! Deletes the current selection if any, returns true if there was one.
    delete_selection = function(self)
        var b, sx, sy, ex, ey = self:region()
        if not b do
            self:mark()
            return false
        end

        self._needs_calc = true

        if sy == ey do
            if sx == 0 and ex == self.lines[ey + 1].len do
                self:remove_lines(sy + 1, 1)
            else self.lines[sy + 1]:del(sx, ex - sx)
            end
        else
            if ey > sy + 1 do
                self:remove_lines(sy + 2, ey - (sy + 1))
                ey = sy + 1
            end

            if ex == self.lines[ey + 1].len do
                self:remove_lines(ey + 1, 1)
            else
                self.lines[ey + 1]:del(0, ex)
            end

            if sx == 0 do
                self:remove_lines(sy + 1, 1)
            else
                self.lines[sy + 1]:del(sx, self.lines[sy].len - sx)
            end
        end

        if #self.lines == 0 do self.lines = { editline() } end
        self:mark()
        self.cx, self.cy = sx, sy

        var current = self:current_line()
        if self.cx > current.len and self.cy < #self.lines - 1 do
            current:append(tostring(self.lines[self.cy + 2]))
            self:remove_lines(self.cy + 2, 1)
        end

        return true
    end,

    --[[!
        Given a string, this inserts the string into the editor on cursor
        position (and deletes any selection before that if there is one).
    ]]
    insert = function(self, ch)
        if #ch > 1 do
            for c in ch:gmatch(".") do
                self:insert(c)
            end
            return
        end

        self._needs_calc = true

        self:delete_selection()
        var current = self:current_line()

        if ch == "\n" do
            if self.multiline do
                var newline = editline(tostring(current):sub(self.cx + 1))
                current:chop(self.cx)
                self.cy = min(#self.lines, self.cy + 1)
                table.insert(self.lines, self.cy + 1, newline)
            else
                current:chop(self.cx)
            end
            self.cx = 0
        else
            if self.cx <= current.len do
                current:insert(ch, self.cx, 1)
                self.cx = self.cx + 1
            end
        end
    end,

    --!
    bind_h_scrollbar = function(self, sb)
        if not sb do
            sb = self.h_scrollbar
            if not sb do return nil end
            sb.scroller, self.h_scrollbar = nil, nil
            return sb
        end
        self.h_scrollbar = sb
        sb.scroller = self
    end,

    --!
    bind_v_scrollbar = function(self, sb)
        if not sb do
            sb = self.v_scrollbar
            if not sb do return nil end
            sb.scroller, self.v_scrollbar = nil, nil
            return sb
        end
        self.v_scrollbar = sb
        sb.scroller = self
    end,

    --!
    get_h_limit = function(self) return max(self.virt_w - get_aw(self), 0) end,
    --!
    get_v_limit = function(self) return max(self.virt_h - self.h, 0) end,

    --!
    get_h_offset = function(self)
        return self.offset_h / max(self.virt_w, get_aw(self))
    end,

    --!
    get_v_offset = function(self)
        return self.offset_v / max(self.virt_h, self.h)
    end,

    --!
    get_h_scale = function(self)
        var w = get_aw(self)
        return w / max(self.virt_w, w)
    end,
    --!
    get_v_scale = function(self)
        var h = self.h
        return h / max(self.virt_h, h)
    end,

    --!
    set_h_scroll = function(self, hs)
        self.offset_h = clamp(hs, 0, self:get_h_limit())
        emit(self, "h_scroll,changed", self:get_h_offset())
    end,

    --!
    set_v_scroll = function(self, vs)
        self.offset_v = clamp(vs, 0, self:get_v_limit())
        emit(self, "v_scroll,changed", self:get_v_offset())
    end,

    --!
    scroll_h = function(self, hs) self:set_h_scroll(self.offset_h + hs) end,
    --!
    scroll_v = function(self, vs) self:set_v_scroll(self.offset_v + vs) end,

    --! Function: set_clip_w
    set_clip_w = gen_ed_setter "clip_w",
    --! Function: set_clip_h
    set_clip_h = gen_ed_setter "clip_h",

    --! Function: set_pad_l
    set_pad_l = gen_ed_setter "pad_l",
    --! Function: set_pad_r
    set_pad_r = gen_ed_setter "pad_r",

    --! Function: set_multiline
    set_multiline = gen_ed_setter "multiline",

    --! Function: set_key_filter
    set_key_filter = gen_setter "key_filter",

    --[[!
        Sets the value property, emits value,changed and calls $reset_value.
    ]]
    set_value = function(self, val)
        val = tostring(val)
        self.value = val
        emit(self, "value,changed", val)
        self:reset_value()
    end,

    --! Function: set_font
    set_font = gen_ed_setter "font",
    --! Function: set_line_wrap
    set_line_wrap = gen_ed_setter "line_wrap",

    clear = function(self)
        self:set_focused(false)
        self:bind_h_scrollbar()
        self:bind_v_scrollbar()
        return Widget.clear(self)
    end,

    edit_clear = function(self, init)
        self._needs_calc = true
        self.cx, self.cy =  0,  0
        self.mx, self.my = -1, -1
        self.offset_h, self.offset_v = 0, 0
        self:mark()
        if init == false do
            self.lines = {}
        else
            init = init or ""
            var lines = {}
            if type(init) != "table" do
                init = init:split("\n")
            end
            for i = 1, #init do lines[i] = editline(init[i]) end
            if #lines == 0 do lines[1] = editline() end
            self.lines = lines
        end
    end,

    movement_mark = function(self)
        self._needs_offset = true
        if input_is_modifier_pressed(mod.SHIFT) do
            if not self:region() do self:mark(true) end
        else
            self:mark(false)
        end
    end,

    key = function(self, code, isdown)
        if Widget.key(self, code, isdown) do return true end
        if not self:is_focused() do return false end

        if code == key.ESCAPE do
            if isdown do self:set_focused(false) end
            return true
        elif code == key.RETURN do
            if not self.multiline do
                if isdown do self:commit() end
                return true
            end
        elif code == key.KP_ENTER do
            if isdown do self:commit() end
            return true
        end
        if isdown do self:key_edit(code) end
        return true
    end,

    key_hover = function(self, code, isdown)
        if not self.multiline do
            return Widget.key_hover(self, code, isdown)
        end
        var hoverkeys = {
            [key.MOUSEWHEELUP  ] = true,
            [key.MOUSEWHEELDOWN] = true,
            [key.PAGEUP        ] = true,
            [key.PAGEDOWN      ] = true,
            [key.HOME          ] = true
        }
        if hoverkeys[code] do
            if isdown do self:key_edit(code) end
            return true
        end
        return Widget.key_hover(self, code, isdown)
    end,

    key_edit = function(self, code)
        var mod_keys = (ffi.os == "OSX") and mod.GUI or mod.CTRL
        if code == key.UP do
            self:movement_mark()
            if self.line_wrap do
                var str = tostring(self:current_line())
                text_font_push()
                text_font_set(self.font)
                var pw = floor(get_aw(self) / self:draw_scale())
                var x, y = text_get_position(str, self.cx + 1, pw)
                if y > 0 do
                    self.cx = text_is_visible(str, x, y - text_font_get_h(),
                        pw)
                    self._needs_offset = true
                    text_font_pop()
                    return
                end
                text_font_pop()
            end
            self.cy = self.cy - 1
            self._needs_offset = true
        elif code == key.DOWN do
            self:movement_mark()
            if self.line_wrap do
                var str = tostring(self:current_line())
                text_font_push()
                text_font_set(self.font)
                var pw = floor(get_aw(self) / self:draw_scale())
                var x, y = text_get_position(str, self.cx, pw)
                var width, height = text_get_bounds(str, pw)
                y = y + text_font_get_h()
                if y < height do
                    self.cx = text_is_visible(str, x, y, pw)
                    self._needs_offset = true
                    text_font_pop()
                    return
                end
                text_font_pop()
            end
            self.cy = self.cy + 1
            self._needs_offset = true
        elif code == key.MOUSEWHEELUP or code == key.MOUSEWHEELDOWN do
            if self.can_scroll do
                var sb = self.v_scrollbar
                var fac = 6 * text_font_get_h() * self:draw_scale()
                self:scroll_v((code == key.MOUSEWHEELUP and -fac or fac)
                    * (sb and sb.arrow_speed or 0.5))
            end
        elif code == key.PAGEUP do
            self:movement_mark()
            if input_is_modifier_pressed(mod_keys) do
                self.cy = 0
            else
                self.cy = self.cy - floor(self.h / (self:draw_scale()
                    * text_font_get_h()))
            end
            self._needs_offset = true
        elif code == key.PAGEDOWN do
            self:movement_mark()
            if input_is_modifier_pressed(mod_keys) do
                self.cy = 1 / 0
            else
                self.cy = self.cy + floor(self.h / (self:draw_scale()
                    * text_font_get_h()))
            end
            self._needs_offset = true
        elif code == key.HOME do
            self:movement_mark()
            self.cx = 0
            if input_is_modifier_pressed(mod_keys) do
                self.cy = 0
            end
            self._needs_offset = true
        elif code == key.END do
            self:movement_mark()
            self.cx = 1 / 0
            if input_is_modifier_pressed(mod_keys) do
                self.cy = 1 / 0
            end
            self._needs_offset = true
        elif code == key.LEFT do
            self:movement_mark()
            if     self.cx > 0 do self.cx = self.cx - 1
            elif self.cy > 0 do
                self.cx = 1 / 0
                self.cy = self.cy - 1
            end
            self._needs_offset = true
        elif code == key.RIGHT do
            self:movement_mark()
            if self.cx < self.lines[self.cy + 1].len do
                self.cx = self.cx + 1
            elif self.cy < #self.lines - 1 do
                self.cx = 0
                self.cy = self.cy + 1
            end
            self._needs_offset = true
        elif code == key.DELETE do
            if not self:delete_selection() do
                self._needs_calc = true
                var current = self:current_line()
                if self.cx < current.len do
                    current:del(self.cx, 1)
                elif self.cy < #self.lines - 1 do
                    -- combine with next line
                    current:append(tostring(self.lines[self.cy + 2]))
                    self:remove_lines(self.cy + 2, 1)
                end
            end
            self._needs_offset = true
        elif code == key.BACKSPACE do
            if not self:delete_selection() do
                self._needs_calc = true
                var current = self:current_line()
                if self.cx > 0 do
                    current:del(self.cx - 1, 1)
                    self.cx = self.cx - 1
                elif self.cy > 0 do
                    -- combine with previous line
                    self.cx = self.lines[self.cy].len
                    self.lines[self.cy]:append(tostring(current))
                    self:remove_lines(self.cy + 1, 1)
                    self.cy = self.cy - 1
                end
            end
            self._needs_offset = true
        elif code == key.RETURN do
            -- maintain indentation
            self._needs_calc = true
            var str = tostring(self:current_line())
            self:insert("\n")
            for c in str:gmatch "." do if c == " " or c == "\t" do
                self:insert(c) else break
            end end
            self._needs_offset = true
        elif code == key.TAB do
            var b, sx, sy, ex, ey = self:region()
            if b do
                self._needs_calc = true
                for i = sy, ey do
                    if input_is_modifier_pressed(mod.SHIFT) do
                        var rem = 0
                        for j = 1, min(4, self.lines[i + 1].len) do
                            if tostring(self.lines[i + 1]):sub(j, j) == " "
                            do
                                rem = rem + 1
                            else
                                if tostring(self.lines[i + 1]):sub(j, j)
                                == "\t" and j == 0 do
                                    rem = rem + 1
                                end
                                break
                            end
                        end
                        self.lines[i + 1]:del(0, rem)
                        if i == self.my do self.mx = self.mx
                            - (rem > self.mx and self.mx or rem) end
                        if i == self.cy do self.cx = self.cx -  rem end
                    else
                        self.lines[i + 1]:prepend("\t")
                        if i == self.my do self.mx = self.mx + 1 end
                        if i == self.cy do self.cx = self.cx + 1 end
                    end
                end
            elif input_is_modifier_pressed(mod.SHIFT) do
                if self.cx > 0 do
                    self._needs_calc = true
                    var cy = self.cy
                    var lines = self.lines
                    if tostring(lines[cy + 1]):sub(1, 1) == "\t" do
                        lines[cy + 1]:del(0, 1)
                        self.cx = self.cx - 1
                    else
                        for j = 1, min(4, #lines[cy + 1]) do
                            if tostring(lines[cy + 1]):sub(1, 1) == " " do
                                lines[cy + 1]:del(0, 1)
                                self.cx = self.cx - 1
                            end
                        end
                    end
                end
            else
                self:insert("\t")
            end
            self._needs_offset = true
        elif code == key.A do
            if not input_is_modifier_pressed(mod_keys) do
                self._needs_offset = true
                return
            end
            self:select_all()
            self._needs_offset = true
        elif code == key.C or code == key.X do
            if not input_is_modifier_pressed(mod_keys)
            or not self:region() do
                self._needs_offset = true
                return
            end
            self:copy()
            if code == key.X do self:delete_selection() end
            self._needs_offset = true
        elif code == key.V do
            if not input_is_modifier_pressed(mod_keys) do
                self._needs_offset = true
                return
            end
            self:paste()
            self._needs_offset = true
        else
            self._needs_offset = true
        end
    end,

    hit = function(self, hitx, hity, dragged)
        var k = self:draw_scale()
        var pw, ph = floor(get_aw(self) / k), floor(self.h / k)
        var max_width = self.line_wrap and pw or -1
        text_font_push()
        text_font_set(self.font)
        var fd = self:get_first_drawable_line()
        if fd do
            var h = 0
            hitx, hity = (hitx + self.offset_h) / k, hity / k
            for i = fd, #self.lines do
                if h > ph do break end
                var linestr = tostring(self.lines[i])
                var width, height = self.lines[i]:get_bounds()
                if hity >= h and hity <= h + height do
                    var x = text_is_visible(linestr, hitx, hity - h,
                        max_width)
                    if dragged do
                        self.mx, self.my = x, i - 1
                    else
                        self.cx, self.cy = x, i - 1
                    end
                    break
                end
                h = h + height
            end
        end
        text_font_pop()
    end,

    target = function(self, cx, cy)
        return Widget.target(self, cx, cy) or self
    end,

    hover = function(self, cx, cy)
        var oh, ov, vw, vh = self.offset_h, self.offset_v,
            self.virt_w, self.virt_h
        self.can_scroll = ((cx + oh) < vw) and ((cy + ov) < vh)
        return self:target(cx, cy) and self
    end,

    click = function(self, cx, cy)
        var oh, ov, vw, vh = self.offset_h, self.offset_v,
            self.virt_w, self.virt_h
        self.can_scroll = ((cx + oh) < vw) and ((cy + ov) < vh)
        return self:target(cx, cy) and self
    end,

    commit = function(self)
        self:set_focused(false)
    end,

    holding = function(self, cx, cy, code)
        if code == key.MOUSELEFT do
            var w, h, hs, vs = self.w, self.h, 0, 0
            if     cy > h do vs = cy - h
            elif cy < 0 do vs = cy end
            if     cx > w do hs = cx - w
            elif cx < 0 do hs = cx end
            cx, cy = clamp(cx, 0, w), clamp(cy, 0, h)
            if vs != 0 do self:scroll_v(vs) end
            if hs != 0 do self:scroll_h(hs) end
            self:hit(cx, cy, max(abs(cx - self._oh), abs(cy - self._ov))
                > (text_font_get_h() / 8 * self:draw_scale()))
        end
        Widget.holding(self, cx, cy, code)
    end,

    set_focused = function(self, foc)
        Widget.set_focused(self, foc)
        var ati = foc and self:allow_text_input() or false
        input_textinput(ati, 1 << 1) -- TI_GUI
        input_keyrepeat(ati, 1 << 1) -- KR_GUI
    end,

    clicked = function(self, cx, cy, code)
        self:set_focused(true)
        self:mark()
        self._oh, self._ov = cx, cy

        return Widget.clicked(self, cx, cy, code)
    end,

    allow_text_input = function(self) return true end,

    text_input = function(self, str)
        if Widget.text_input(self, str) do return true end
        if not self:is_focused() or not self:allow_text_input() do
            return false
        end
        var filter = self.key_filter
        if not filter do
            self:insert(str)
        else
            var buf = {}
            for ch in str:gmatch(".") do
                if filter:find(ch) do buf[#buf + 1] = ch end
            end
            self:insert(table.concat(buf))
        end
        return true
    end,

    draw_scale = function(self)
        var scale = self.scale
        return (abs(scale) * self:get_root():get_text_scale(scale < 0))
            / text_font_get_h()
    end,

    calc_dimensions = function(self, maxw)
        if not self._needs_calc do
            return self.text_w, self.text_h
        end
        self._needs_calc = false
        var lines = self.lines
        var w, h = 0, 0
        var ov = 0
        var k = self:draw_scale()
        maxw -= (self.pad_l + self.pad_r) / k
        for i = 1, #lines do
            var tw, th = lines[i]:calc_bounds(maxw)
            w, h = max(w, tw), h + th
        end
        w, h = w * k, h * k
        self.text_w, self.text_h = w, h
        return w, h
    end,

    get_first_drawable_line = function(self)
        var lines = self.lines
        var ov = self.offset_v / self:draw_scale()
        for i = 1, #lines do
            var tw, th = lines[i]:get_bounds()
            ov -= th
            if ov < 0 do return i end
        end
    end,

    get_last_drawable_line = function(self)
        var lines = self.lines
        var ov = (self.offset_v + self.h) / self:draw_scale()
        for i = 1, #lines do
            var tw, th = lines[i]:get_bounds()
            ov -= th
            if ov <= 0 do return i end
        end
    end,

    fix_h_offset = function(self, k, maxw, del)
        var fontw = text_font_get_w() * k
        var x, y = text_get_position(tostring(self.lines[self.cy + 1]),
            self.cx, maxw)

        x *= k
        var w, oh = get_aw(self), self.offset_h + self.pad_l
        if (x + fontw) > w + (del and 0 or oh) do
           self.offset_h = x + fontw - w
        elif x < oh do
            self.offset_h = x
        elif (x + fontw) <= w and oh >= fontw do
            self.offset_h = 0
        end
    end,

    fix_v_offset = function(self, k)
        var lines = self.lines

        var cy = self.cy + 1
        var oov = self.offset_v

        var yoff = 0
        for i = 1, cy do
            var tw, th = lines[i]:get_bounds()
            yoff += th
        end

        var h = self.h
        if yoff <= (oov / k) do
            self.offset_v += yoff * k - oov - text_font_get_h() * k
        elif yoff > ((oov + h) / k) do
            self.offset_v += yoff * k - (oov + h)
        end
    end,

    layout = function(self)
        Widget.layout(self)

        self._prev_tw = self.text_w

        text_font_push()
        text_font_set(self.font)
        if not self:is_focused() do
            self:reset_value()
        end

        var lw, ml = self.line_wrap, self.multiline
        var k = self:draw_scale()
        var pw, ph = self.clip_w / k
        if ml do
            ph = self.clip_h / k
        else
            var w, h = text_get_bounds(tostring(self.lines[1]),
                lw and pw or -1)
            ph = h
        end

        var maxw = lw and pw or -1
        var tw, th = self:calc_dimensions(maxw)

        self.virt_w = max(self.w, tw)
        self.virt_h = max(self.h, th)

        self.w = max(self.w, pw * k)
        self.h = max(self.h, ph * k)

        text_font_pop()
    end,

    adjust_layout = function(self, px, py, pw, ph)
        Widget.adjust_layout(self, px, py, pw, ph)
        if self._needs_offset do
            self:region()
            var k = self:draw_scale()
            var maxw = self.line_wrap and floor(get_aw(self) / k) or -1
            self:fix_h_offset(k, maxw, self._prev_tw > self.text_w)
            self:fix_v_offset(k)
            self._needs_offset = false
        end
    end,

    draw_selection = function(self, first_drawable, x, x2, y)
        var selection, sx, sy, ex, ey = self:region()
        if not selection do return end
        var k = self:draw_scale()
        var pw, ph = floor(get_aw(self) / k), floor(self.h / k)
        var max_width = self.line_wrap and pw or -1
        -- convert from cursor coords into pixel coords
        var psx, psy = text_get_position(tostring(self.lines[sy + 1]), sx,
            max_width)
        var pex, pey = text_get_position(tostring(self.lines[ey + 1]), ex,
            max_width)
        var maxy = #self.lines
        var h = 0
        var sc = self.sel_color
        for i = first_drawable, maxy do
            if h > ph do
                maxy = i
                break
            end
            var width, height = text_get_bounds(tostring(self.lines[i]),
                max_width)
            if i == sy + 1 do
                psy = psy + h
            end
            if i == ey + 1 do
                pey = pey + h
                break
            end
            h = h + height
        end
        maxy = maxy - 1
        if ey >= first_drawable - 1 and sy <= maxy do
            var fonth = text_font_get_h()
            -- crop top/bottom within window
            if  sy < first_drawable - 1 do
                sy = first_drawable - 1
                psy = 0
                psx = 0
            end
            if  ey > maxy do
                ey = maxy
                pey = ph - fonth
                pex = pw
            end

            shader_hudnotexture_set()
            gle_color4ub(sc.r, sc.g, sc.b, sc.a)
            gle_defvertexf(2)
            gle_begin(gl.QUADS)
            if psy == pey do
                -- one selection line - arbitrary bounds
                gle_attrib2f(x + psx, psy)
                gle_attrib2f(x + pex, psy)
                gle_attrib2f(x + pex, pey + fonth)
                gle_attrib2f(x + psx, pey + fonth)
            else
                -- multiple selection lines
                -- first line - always ends in the end of the visible area
                gle_attrib2f(x  + psx, psy)
                gle_attrib2f(x  + psx, psy + fonth)
                gle_attrib2f(x2 + pw,  psy + fonth)
                gle_attrib2f(x2 + pw,  psy)
                -- between first and last selected line
                -- a quad that fills the whole space
                if (pey - psy) > fonth do
                    gle_attrib2f(x2,      psy + fonth)
                    gle_attrib2f(x2 + pw, psy + fonth)
                    gle_attrib2f(x2 + pw, pey)
                    gle_attrib2f(x2,      pey)
                end
                -- last line - starts in the beginning of the visible area
                gle_attrib2f(x2,      pey)
                gle_attrib2f(x2,      pey + fonth)
                gle_attrib2f(x + pex, pey + fonth)
                gle_attrib2f(x + pex, pey)
            end
            gle_end()
            shader_hud_set()
        end
    end,

    draw_line_wrap = function(self, h, height)
        if not self.line_wrap do return end
        var fonth = text_font_get_h()
        shader_hudnotexture_set()
        var wc = self.wrap_color
        gle_color4ub(wc.r, wc.g, wc.b, wc.a)
        gle_defvertexf(2)
        gle_begin(gl.LINE_STRIP)
        gle_attrib2f(0, h + fonth)
        gle_attrib2f(0, h + height)
        gle_end()
        shader_hud_set()
    end,

    draw = function(self, sx, sy)
        Widget.draw(self, sx, sy)

        text_font_push()
        text_font_set(self.font)

        var cw, ch = get_aw(self), self.h
        var fontw  = text_font_get_w()
        var clip = (cw != 0 and (self.virt_w + fontw) > cw)
                  or (ch != 0 and  self.virt_h          > ch)

        if clip do self:get_root():clip_push(sx + self.pad_l, sy, cw, ch) end

        hudmatrix_push()

        hudmatrix_translate(sx, sy, 0)
        var k = self:draw_scale()
        hudmatrix_scale(k, k, 1)
        hudmatrix_flush()

        var hit = self:is_focused()

        var pw, ph = floor(get_aw(self) / k), floor(self.h / k)
        var max_width = self.line_wrap and pw or -1

        var fd = self:get_first_drawable_line()
        if fd do
            var xoff = self.pad_l / k
            var txof = xoff - self.offset_h / k

            self:draw_selection(fd, txof, xoff)

            var h = 0
            var fonth = text_font_get_h()
            var tc = self.text_color
            for i = fd, #self.lines do
                var line = tostring(self.lines[i])
                var width, height = text_get_bounds(line,
                    max_width)
                if h >= ph do break end
                text_draw(line, txof, h, tc.r, tc.g, tc.b, tc.a,
                    (hit and (self.cy == i - 1)) and self.cx or -1, max_width)

                if height > fonth do self:draw_line_wrap(h, height) end
                h = h + height
            end
        end

        hudmatrix_pop()
        if clip do self:get_root():clip_pop() end

        text_font_pop()
    end
})
var TextEditor = M.TextEditor

--[[!
    Represents a field, a specialization of $TextEditor. It has the same
    properties. The "value" property changed meaning - now it stores the
    current value - there is no fallback for fields (it still is the default
    value though).

    Fields are also by default not multiline. You can still explicitly
    override this in kwargs or by setting the property.
]]
M.Field = register_type("Field", TextEditor, {
    __ctor = function(self, kwargs)
        kwargs = kwargs or {}
        kwargs.multiline = kwargs.multiline or false
        return TextEditor.__ctor(self, kwargs)
    end,

    commit = function(self)
        TextEditor.commit(self)
        var val = tostring(self.lines[1])
        self.value = val
        -- trigger changed signal
        emit(self, "value,changed", val)
    end
})

--[[!
    Derived from $Field. Represents a keyfield - it catches keypresses and
    inserts key names. Useful when creating an e.g. keybinding GUI.
]]
M.KeyField = register_type("KeyField", M.Field, {
    allow_text_input = function(self) return false end,

    key_insert = function(self, code)
        var keyname = input_get_key_name(code)
        if keyname do
            if not self:is_empty() do self:insert(" ") end
            self:insert(keyname)
        end
    end,

    --! Overloaded. Commits on the escape key, inserts the name otherwise.
    key_raw = function(code, isdown)
        if Widget.key_raw(code, isdown) do return true end
        if not self:is_focused() or not isdown do return false end
        if code == key.ESCAPE do self:commit()
        else self:key_insert(code) end
        return true
    end
})
