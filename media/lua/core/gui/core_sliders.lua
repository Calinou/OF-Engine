--[[!<
    Slider widgets.

    Author:
        q66 <quaker66@gmail.com>

    License:
        See COPYING.txt.
]]

var capi = require("capi")
var signal = require("core.events.signal")

var get_millis in capi

var max   = math.max
var min   = math.min
var abs   = math.abs
var clamp = math.clamp
var round = math.round
var emit  = signal.emit

--! Module: core
var M = require("core.gui.core")

-- consts
var key = M.key

-- widget types
var register_type = M.register_type

-- base widgets
var Widget = M.get_type("Widget")

-- setters
var gen_setter = M.gen_setter

-- orientation
var orient = M.orient

-- alignment/clamping
var adjust = M.adjust

var SliderButton

--[[!
    Implements a base type for either horizontal or vertical slider.

    Changes of "value" performed internally emit the "value,changed" signal
    with the new value as an argument.

    Properties:
        - min_valie, max_value, value - the minimum, maximum and current
          values of the slider.
        - arrow_size - sliders can arrow-scroll like scrollbars.
        - step_size - the size of one slider step, defaults to 1.
        - step_time - the time to perform a step during arrow scroll,
          defaults to 100.
]]
M.Slider = register_type("Slider", Widget, {
    __ctor = function(self, kwargs)
        kwargs = kwargs or {}
        self.min_value = kwargs.min_value or 0
        self.max_value = kwargs.max_value or 0
        self.value     = kwargs.value     or 0

        self.arrow_size = kwargs.arrow_size or 0
        self.step_size  = kwargs.step_size  or 1
        self.step_time  = kwargs.step_time  or 100

        self.last_step = 0
        self.arrow_dir = 0

        return Widget.__ctor(self, kwargs)
    end,

    --! Jumps by n steps on the slider.
    do_step = function(self, n)
        var mn, mx, ss = self.min_value, self.max_value, self.step_size

        var maxstep = abs(mx - mn) / ss
        var curstep = (self.value - min(mn, mx)) / ss
        var newstep = clamp(curstep + n, 0, maxstep)

        var val = min(mx, mn) + newstep * ss
        self.value = val
        emit(self, "value,changed", val)
    end,

    --! Sets the nth step.
    set_step = function(self, n)
        var mn, mx, ss = self.min_value, self.max_value, self.step_size

        var steps   = abs(mx - mn) / ss
        var newstep = clamp(n, 0, steps)

        var val = min(mx, mn) + newstep * ss
        self.value = val
        emit(self, "value,changed", val)
    end,

    --[[!
        You can change the slider value using the up, left keys (goes back
        by one step), down, right keys (goes forward by one step) and mouse
        scroll (goes forward/back by 3 steps).
    ]]
    key_hover = function(self, code, isdown)
        if code == key.UP or code == key.LEFT do
            if isdown do self:do_step(-1) end
            return true
        elif code == key.MOUSEWHEELUP do
            if isdown do self:do_step(-3) end
            return true
        elif code == key.DOWN or code == key.RIGHT do
            if isdown do self:do_step(1) end
            return true
        elif code == key.MOUSEWHEELDOWN do
            if isdown do self:do_step(3) end
            return true
        end
        return Widget.key_hover(self, code, isdown)
    end,

    choose_direction = function(self, cx, cy)
        return 0
    end,

    --[[!
        The slider can be hovered on unless some of its children want the
        hover instead.
    ]]
    hover = function(self, cx, cy)
        return Widget.hover(self, cx, cy) or
                     (self:target(cx, cy) and self)
    end,

    --[[!
        The slider can be clicked on unless some of its children want the
        click instead.
    ]]
    click = function(self, cx, cy, code)
        return Widget.click(self, cx, cy, code) or
                     (self:target(cx, cy) and self)
    end,

    scroll_to = function(self, cx, cy) end,

    --[[!
        Clicking inside the slider area but outside the arrow area jumps
        in the slider.
    ]]
    clicked = function(self, cx, cy, code)
        if code == key.MOUSELEFT do
            var d = self.choose_direction(self, cx, cy)
            self.arrow_dir = d
            if d == 0 do
                self:scroll_to(cx, cy)
            end
        end
        return Widget.clicked(self, cx, cy, code)
    end,

    arrow_scroll = function(self, d)
        var tmillis = get_millis(true)
        if (self.last_step + self.step_time) > tmillis do return end

        self.last_step = tmillis
        self.do_step(self, d)
    end,

    holding = function(self, cx, cy, code)
        if code == key.MOUSELEFT do
            var d = self:choose_direction(cx, cy)
            self.arrow_dir = d
            if d != 0 do self:arrow_scroll(d) end
        end
        Widget.holding(self, cx, cy, code)
    end,

    hovering = function(self, cx, cy)
        if not self:is_clicked(key.MOUSELEFT) do
            self.arrow_dir = self:choose_direction(cx, cy)
        end
        Widget.hovering(self, cx, cy)
    end,

    move_button = function(self, o, fromx, fromy, tox, toy) end,

    --! Function: set_min_value
    set_min_value = gen_setter "min_value",

    --! Function: set_max_value
    set_max_value = gen_setter "max_value",

    --! Function: set_value
    set_value = gen_setter "value",

    --! Function: set_step_size
    set_step_size = gen_setter "step_size",

    --! Function: set_step_time
    set_step_time = gen_setter "step_time",

    --! Function: set_arrow_size
    set_arrow_size = gen_setter "arrow_size"
})
var Slider = M.Slider

var clicked_states = {
    [key.MOUSELEFT   ] = "clicked_left",
    [key.MOUSEMIDDLE ] = "clicked_middle",
    [key.MOUSERIGHT  ] = "clicked_right",
    [key.MOUSEBACK   ] = "clicked_back",
    [key.MOUSEFORWARD] = "clicked_forward"
}

--[[!
    A slider button you can put inside a slider and drag. The slider
    will adjust the button width (in case of horizontal slider) and height
    (in case of vertical slider) depending on the slider size and values.

    A slider button has seven states, "default", "hovering", "clicked_left",
    "clicked_right", "clicked_middle", "clicked_back" and "clicked_forward".
]]
M.SliderButton = register_type("SliderButton", Widget, {
    __ctor = function(self, kwargs)
        self.offset_h = 0
        self.offset_v = 0

        return Widget.__ctor(self, kwargs)
    end,

    choose_state = function(self)
        return clicked_states[self:is_clicked()] or
            (self:is_hovering() and "hovering" or "default")
    end,

    hover = function(self, cx, cy)
        return self:target(cx, cy) and self
    end,

    click = function(self, cx, cy)
        return self:target(cx, cy) and self
    end,

    holding = function(self, cx, cy, code)
        var p = self.parent
        if p and code == key.MOUSELEFT and p.type == Slider.type do
            p.arrow_dir = 0
            p:move_button(self, self.offset_h, self.offset_v, cx, cy)
        end
        Widget.holding(self, cx, cy, code)
    end,

    clicked = function(self, cx, cy, code)
        if code == key.MOUSELEFT do
            self.offset_h = cx
            self.offset_v = cy
        end
        return Widget.clicked(self, cx, cy, code)
    end,

    layout = function(self)
        var lastw = self.w
        var lasth = self.h

        Widget.layout(self)

        if self:is_clicked(key.MOUSELEFT) do
            self.w = lastw
            self.h = lasth
        end
    end
})
SliderButton = M.SliderButton

--[[!
    A specialization of $Slider. Has the "orient" member set to
    the HORIZONTAL field of $orient. Overloads some of the Slider
    methods specifically for horizontal direction.

    Has thirteen states - "default", "(left|right)_hovering",
    "(left|right)_clicked_(left|right|middle|back|forward)".
]]
M.HSlider = register_type("HSlider", Slider, {
    orient = orient.HORIZONTAL,

    choose_state = function(self)
        var ad = self.arrow_dir

        if ad == -1 do
            var clicked = clicked_states[self:is_clicked()]
            return clicked and "left_" .. clicked or
                (self:is_hovering() and "left_hovering" or "default")
        elif ad == 1 do
            var clicked = clicked_states[self:is_clicked()]
            return clicked and "right_" .. clicked or
                (self:is_hovering() and "right_hovering" or "default")
        end
        return "default"
    end,

    choose_direction = function(self, cx, cy)
        var as = self.arrow_size
        return cx < as and -1 or (cx >= (self.w - as) and 1 or 0)
    end,

    scroll_to = function(self, cx, cy)
        var  btn = self:find_child(SliderButton.type, nil, false)
        if not btn do return end

        var as = self.arrow_size
        var sw, bw = self.w, btn.w

        var pos = clamp((cx - as - bw / 2) / (sw - 2 * as - bw), 0, 1)
        var steps = abs(self.max_value - self.min_value) / self.step_size
        var step = round(steps * pos)

        self.set_step(self, step)
    end,

    adjust_children = function(self)
        var  btn = self:find_child(SliderButton.type, nil, false)
        if not btn do return end
        btn._slider = self

        var mn, mx, ss = self.min_value, self.max_value, self.step_size

        var steps   = abs(mx - mn) / self.step_size
        var curstep = (self.value - min(mx, mn)) / ss

        var as = self.arrow_size

        var width = max(self.w - 2 * as, 0)

        btn.w = max(btn.w, width / steps)
        btn.x = as + (width - btn.w) * curstep / steps
        btn.adjust = btn.adjust & ~adjust.ALIGN_HMASK

        Widget.adjust_children(self)
    end,

    move_button = function(self, o, fromx, fromy, tox, toy)
        self:scroll_to(o.x + o.w / 2 + tox - fromx, o.y + toy)
    end
}, Slider.type)

--[[!
    See $HSlider above. Has different states, "default", "(up|down)_hovering"
    and  "(up|down)_clicked_(left|right|middle|back|forward)".
]]
M.VSlider = register_type("VSlider", Slider, {
    choose_state = function(self)
        var ad = self.arrow_dir

        if ad == -1 do
            var clicked = clicked_states[self:is_clicked()]
            return clicked and "up_" .. clicked or
                (self:is_hovering() and "up_hovering" or "default")
        elif ad == 1 do
            var clicked = clicked_states[self:is_clicked()]
            return clicked and "down_" .. clicked or
                (self:is_hovering() and "down_hovering" or "default")
        end
        return "default"
    end,

    choose_direction = function(self, cx, cy)
        var as = self.arrow_size
        return cy < as and -1 or (cy >= (self.h - as) and 1 or 0)
    end,

    scroll_to = function(self, cx, cy)
        var  btn = self:find_child(SliderButton.type, nil, false)
        if not btn do return end

        var as = self.arrow_size
        var sh, bh = self.h, btn.h

        var pos = clamp((cy - as - bh / 2) / (sh - 2 * as - bh), 0, 1)
        var steps = abs(self.max_value - self.min_value) / self.step_size
        var step = round(steps * pos)

        self.set_step(self, step)
    end,

    adjust_children = function(self)
        var  btn = self:find_child(SliderButton.type, nil, false)
        if not btn do return end
        btn._slider = self

        var mn, mx, ss = self.min_value, self.max_value, self.step_size

        var steps   = (max(mx, mn) - min(mx, mn)) / ss + 1
        var curstep = (self.value - min(mx, mn)) / ss

        var as = self.arrow_size

        var height = max(self.h - 2 * as, 0)

        btn.h = max(btn.h, height / steps)
        btn.y = as + (height - btn.h) * curstep / steps
        btn.adjust = btn.adjust & ~adjust.ALIGN_VMASK

        Widget.adjust_children(self)
    end,

    move_button = function(self, o, fromx, fromy, tox, toy)
        self.scroll_to(self, o.x + o.h / 2 + tox, o.y + toy - fromy)
    end
}, Slider.type)
