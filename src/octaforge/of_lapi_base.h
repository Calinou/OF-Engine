int preload_sound(const char *name, int vol);

extern string homedir;

namespace EditingSystem
{
    extern vec saved_pos;
}

namespace lapi_binds
{
    int _lua_log(lua_State *L) {
        logger::log((logger::loglevel)luaL_checkint(L, 1),
            "%s\n", luaL_checkstring(L, 2));
        return 0;
    }

    int _lua_should_log(lua_State *L) {
        lua_pushboolean(L, logger::should_log(
            (logger::loglevel)luaL_checkint(L, 1)));
        return 1;
    }

    int _lua_echo(lua_State *L) {
        conoutf("\f1%s", luaL_checkstring(L, 1));
        return 0;
    }

    int _lua_lastmillis(lua_State *L) {
        lua_pushinteger(L, lastmillis);
        return 1;
    }

    int _lua_totalmillis(lua_State *L) {
        lua_pushinteger(L, totalmillis);
        return 1;
    }

    int _lua_currtime(lua_State *L) {
        lua_pushinteger(L, tools::currtime());
        return 1;
    }

    int _lua_cubescript(lua_State *L) {
        tagval v;
        executeret(luaL_checkstring(L, 1), v);
        switch (v.type) {
            case VAL_INT:
                lua_pushinteger(L, v.getint());
            case VAL_FLOAT:
                lua_pushnumber(L, v.getfloat());
            case VAL_STR:
                lua_pushstring(L, v.getstr());
            default:
                lua_pushnil(L);
        }
        return 1;
    }

    int _lua_readfile(lua_State *L) {
        const char *p = luaL_checkstring(L, 1);

        if (!p || !p[0] || p[0] == '/' ||p[0] == '\\'
        || strstr(p, "..") || strchr(p, '~')) {
            return 0;
        }

        char *loaded = NULL;
        types::String buf;

        if (strlen(p) >= 2 && p[0] == '.' && (p[1] == '/' || p[1] == '\\')) {
            buf = world::get_mapfile_path(p + 2);
        } else {
            buf.format("data%c%s", PATHDIV, p);
        }

        if (!(loaded = loadfile(path(buf.get_buf(), true), NULL))) {
            logger::log(logger::ERROR, "count not read \"%s\"", p);
            return 0;
        }
        lua_pushstring(L, loaded);
        return 1;
    }

    int _lua_getserverlogfile(lua_State *L) {
        lua_pushliteral(L, SERVER_LOGFILE);
        return 1;
    }

    int _lua_setup_library(lua_State *L) {
        lua_pushboolean(L, lapi::load_library(luaL_checkstring(L, 1)));
        return 1;
    }
#ifdef CLIENT
    int _lua_save_mouse_position(lua_State *L) {
        EditingSystem::saved_pos = TargetingControl::worldPosition;
        return 0;
    }
#else
    LAPI_EMPTY(save_mouse_position)
#endif

    void _lua_var_reset(const char *name) {
        resetvar((char*)name);
    }

    void _lua_var_new_i(const char *name, int min, int def, int max,
        int flags) {
        if (!name) return;
        ident *id = getident(name);
        if (!id) {
            int *st = new int;
            *st = variable(name, min, def, max, st, NULL, flags | IDF_ALLOC);
        } else {
            logger::log(logger::ERROR, "variable %s already exists\n", name);
        }
    }

    void _lua_var_new_f(const char *name, float min, float def, float max,
        int flags) {
        if (!name) return;
        ident *id = getident(name);
        if (!id) {
            float *st = new float;
            *st = fvariable(name, min, def, max, st, NULL, flags | IDF_ALLOC);
        } else {
            logger::log(logger::ERROR, "variable %s already exists\n", name);
        }
    }

    void _lua_var_new_s(const char *name, const char *def, int flags) {
        if (!name) return;
        ident *id = getident(name);
        if (!id) {
            char **st = new char*;
            *st = svariable(name, def, st, NULL, flags | IDF_ALLOC);
        } else {
            logger::log(logger::ERROR, "variable %s already exists\n", name);
        }
    }

    void _lua_var_set_i(const char *name, int value) {
        setvar(name, value);
    }

    void _lua_var_set_f(const char *name, float value) {
        setfvar(name, value);
    }

    void _lua_var_set_s(const char *name, const char *value) {
        setsvar(name, value);
    }

    int _lua_var_get_i(const char *name) {
        return getvar(name);
    }

    float _lua_var_get_f(const char *name) {
        return getfvar(name);
    }

    const char *_lua_var_get_s(const char *name) {
        return getsvar(name);
    }

    int _lua_var_get_min_i(const char *name) {
        return getvarmin(name);
    }

    float _lua_var_get_min_f(const char *name) {
        return getfvarmin(name);
    }

    int _lua_var_get_max_i(const char *name) {
        return getvarmax(name);
    }

    float _lua_var_get_max_f(const char *name) {
        return getfvarmax(name);
    }

    int _lua_var_get_def_i(const char *name) {
        ident *id = getident(name);
        if (!id || id->type != ID_VAR) return 0;
        return id->overrideval.i;
    }

    float _lua_var_get_def_f(const char *name) {
        ident *id = getident(name);
        if (!id || id->type != ID_FVAR) return 0.0f;
        return id->overrideval.f;
    }

    const char *_lua_var_get_def_s(const char *name) {
        ident *id = getident(name);
        if (!id || id->type != ID_SVAR) return NULL;
        return id->overrideval.s;
    }

    int _lua_var_get_type(const char *name) {
        ident *id = getident(name);
        if (!id || id->type > ID_SVAR)
            return -1;
        return id->type;
    }

    bool _lua_var_exists(const char *name) {
        ident *id = getident(name);
        return (!id || id->type > ID_SVAR)
            ? false : true;
    }

    bool _lua_var_is_hex(const char *name) {
        ident *id = getident(name);
        return (!id || !(id->flags&IDF_HEX)) ? false : true;
    }

    bool _lua_var_emits(const char *name) {
        ident *id = getident(name);
        return (!id || !(id->flags&IDF_SIGNAL)) ? false : true;
    }

    void _lua_var_emits_set(const char *name, bool v) {
        ident *id = getident(name);
        if (!id) return;
        if (v) id->flags |= IDF_SIGNAL;
        else id->flags &= ~IDF_SIGNAL;
    }

#ifdef CLIENT
    void _lua_varray_begin(uint mode) { varray::begin(mode); }
    int _lua_varray_end() { return varray::end(); }
    void _lua_varray_disable() { varray::disable(); }

    #define EAPI_VARRAY_DEFATTRIB(name) \
        void _lua_varray_def##name(int size) { varray::def##name(size, GL_FLOAT); }

    EAPI_VARRAY_DEFATTRIB(vertex)
    EAPI_VARRAY_DEFATTRIB(color)
    EAPI_VARRAY_DEFATTRIB(texcoord0)
    EAPI_VARRAY_DEFATTRIB(texcoord1)

    #define EAPI_VARRAY_INITATTRIB(name) \
        void _lua_varray_##name##1f(float x) { varray::name##f(x); } \
        void _lua_varray_##name##2f(float x, float y) { varray::name##f(x, y); } \
        void _lua_varray_##name##3f(float x, float y, float z) { varray::name##f(x, y, z); } \
        void _lua_varray_##name##4f(float x, float y, float z, float w) { varray::name##f(x, y, z, w); }

    EAPI_VARRAY_INITATTRIB(vertex)
    EAPI_VARRAY_INITATTRIB(color)
    EAPI_VARRAY_INITATTRIB(texcoord0)
    EAPI_VARRAY_INITATTRIB(texcoord1)

    #define EAPI_VARRAY_INITATTRIBN(name, suffix, type) \
        void _lua_varray_##name##3##suffix(type x, type y, type z) { varray::name##suffix(x, y, z); } \
        void _lua_varray_##name##4##suffix(type x, type y, type z, type w) { varray::name##suffix(x, y, z, w); }

    EAPI_VARRAY_INITATTRIBN(color, ub, uchar)

    #define EAPI_VARRAY_ATTRIB(suffix, type) \
        void _lua_varray_attrib##1##suffix(type x) { varray::attrib##suffix(x); } \
        void _lua_varray_attrib##2##suffix(type x, type y) { varray::attrib##suffix(x, y); } \
        void _lua_varray_attrib##3##suffix(type x, type y, type z) { varray::attrib##suffix(x, y, z); } \
        void _lua_varray_attrib##4##suffix(type x, type y, type z, type w) { varray::attrib##suffix(x, y, z, w); }

    EAPI_VARRAY_ATTRIB(f, float)
    EAPI_VARRAY_ATTRIB(d, double)
    EAPI_VARRAY_ATTRIB(b, char)
    EAPI_VARRAY_ATTRIB(ub, uchar)
    EAPI_VARRAY_ATTRIB(s, short)
    EAPI_VARRAY_ATTRIB(us, ushort)
    EAPI_VARRAY_ATTRIB(i, int)
    EAPI_VARRAY_ATTRIB(ui, uint)

    /* hudmatrix */

    void _lua_hudmatrix_push () { pushhudmatrix (); }
    void _lua_hudmatrix_pop  () { pophudmatrix  (); }
    void _lua_hudmatrix_flush() { flushhudmatrix(); }
    void _lua_hudmatrix_reset() { resethudmatrix(); }

    void _lua_hudmatrix_translate(float x, float y, float z) { hudmatrix.translate(vec(x, y, z)); }
    void _lua_hudmatrix_scale(float x, float y, float z) { hudmatrix.scale(vec(x, y, z)); }
    void _lua_hudmatrix_ortho(float l, float r, float b, float t, float zn, float zf) {
        hudmatrix.ortho(l, r, b, t, zn, zf);
    }

    /* gl */

    void _lua_gl_shader_hud_set() {
        hudshader->set();
    }

    void _lua_gl_shader_hudnotexture_set() {
        hudnotextureshader->set();
    }

    void _lua_gl_scissor_enable() {
        glEnable(GL_SCISSOR_TEST);
    }

    void _lua_gl_scissor_disable() {
        glDisable(GL_SCISSOR_TEST);
    }

    void _lua_gl_scissor(int x, int y, int w, int h) {
        glScissor(x, y, w, h);
    }

    void _lua_gl_blend_enable() {
        glEnable(GL_BLEND);
    }

    void _lua_gl_blend_disable() {
        glDisable(GL_BLEND);
    }

    void _lua_gl_blend_func(uint sf, uint df) {
        glBlendFunc(sf, df);
    }

    void _lua_gl_bind_texture(int tex) {
        glBindTexture(GL_TEXTURE_2D, tex);
    }

    void _lua_gl_texture_param(uint pn, int pr) {
        glTexParameteri(GL_TEXTURE_2D, pn, pr);
    }

    /* input */

    int _lua_input_get_modifier_state() {
        return SDL_GetModState();
    }

    /* gui */

    void _lua_gui_set_mainmenu(int v) {
        mainmenu = v;
    }

    types::Tuple<int, int> _lua_gui_text_bounds(const char *str, int maxw) {
        int w, h;
        text_bounds(str, w, h, maxw);
        return types::make_tuple(w, h);
    }

    types::Tuple<float, float> _lua_gui_text_bounds_f(const char *str, int maxw) {
        float w, h;
        text_boundsf(str, w, h, maxw);
        return types::make_tuple(w, h);
    }

    types::Tuple<int, int> _lua_gui_text_pos(const char *str, int cur, int maxw) {
        int cx, cy;
        text_pos(str, cur, cx, cy, maxw);
        return types::make_tuple(cx, cy);
    }

    types::Tuple<int, int> _lua_gui_text_pos_f(const char *str, int cur, int maxw) {
        float cx, cy;
        text_posf(str, cur, cx, cy, maxw);
        return types::make_tuple(cx, cy);
    }

    int _lua_gui_text_visible(const char *str, float hitx, float hity, int maxw) {
        return text_visible(str, hitx, hity, maxw);
    }

    void _lua_gui_draw_text(const char *str, int left, int top,
        int r, int g, int b, int a, int cur, int maxw) {
        draw_text(str, left, top, r, g, b, a, cur, maxw);
    }
#endif

    void reg_base(lua::Table& t)
    {
        LAPI_REG(log);
        LAPI_REG(should_log);
        LAPI_REG(echo);
        LAPI_REG(lastmillis);
        LAPI_REG(totalmillis);
        LAPI_REG(currtime);
        LAPI_REG(cubescript);
        LAPI_REG(readfile);
        LAPI_REG(getserverlogfile);
        LAPI_REG(setup_library);
        LAPI_REG(save_mouse_position);

        LAPI_REG(var_reset);
        LAPI_REG(var_new_i);
        LAPI_REG(var_new_f);
        LAPI_REG(var_new_s);
        LAPI_REG(var_set_i);
        LAPI_REG(var_set_f);
        LAPI_REG(var_set_s);
        LAPI_REG(var_get_i);
        LAPI_REG(var_get_f);
        LAPI_REG(var_get_s);
        LAPI_REG(var_get_min_i);
        LAPI_REG(var_get_min_f);
        LAPI_REG(var_get_max_i);
        LAPI_REG(var_get_max_f);
        LAPI_REG(var_get_def_i);
        LAPI_REG(var_get_def_f);
        LAPI_REG(var_get_def_s);
        LAPI_REG(var_get_type);
        LAPI_REG(var_exists);
        LAPI_REG(var_is_hex);
        LAPI_REG(var_emits);
        LAPI_REG(var_emits_set);

#ifdef CLIENT
        LAPI_REG(varray_begin);
        LAPI_REG(varray_end);
        LAPI_REG(varray_disable);
        LAPI_REG(varray_defvertex);
        LAPI_REG(varray_defcolor);
        LAPI_REG(varray_deftexcoord0);
        LAPI_REG(varray_deftexcoord1);
        LAPI_REG(varray_vertex1f);
        LAPI_REG(varray_vertex2f);
        LAPI_REG(varray_vertex3f);
        LAPI_REG(varray_vertex4f);
        LAPI_REG(varray_color1f);
        LAPI_REG(varray_color2f);
        LAPI_REG(varray_color3f);
        LAPI_REG(varray_color4f);
        LAPI_REG(varray_texcoord01f);
        LAPI_REG(varray_texcoord02f);
        LAPI_REG(varray_texcoord03f);
        LAPI_REG(varray_texcoord04f);
        LAPI_REG(varray_texcoord11f);
        LAPI_REG(varray_texcoord12f);
        LAPI_REG(varray_texcoord13f);
        LAPI_REG(varray_texcoord14f);
        LAPI_REG(varray_color3ub);
        LAPI_REG(varray_color4ub);
        LAPI_REG(varray_attrib1f);
        LAPI_REG(varray_attrib2f);
        LAPI_REG(varray_attrib3f);
        LAPI_REG(varray_attrib4f);
        LAPI_REG(varray_attrib1d);
        LAPI_REG(varray_attrib2d);
        LAPI_REG(varray_attrib3d);
        LAPI_REG(varray_attrib4d);
        LAPI_REG(varray_attrib1b);
        LAPI_REG(varray_attrib2b);
        LAPI_REG(varray_attrib3b);
        LAPI_REG(varray_attrib4b);
        LAPI_REG(varray_attrib1ub);
        LAPI_REG(varray_attrib2ub);
        LAPI_REG(varray_attrib3ub);
        LAPI_REG(varray_attrib4ub);
        LAPI_REG(varray_attrib1s);
        LAPI_REG(varray_attrib2s);
        LAPI_REG(varray_attrib3s);
        LAPI_REG(varray_attrib4s);
        LAPI_REG(varray_attrib1us);
        LAPI_REG(varray_attrib2us);
        LAPI_REG(varray_attrib3us);
        LAPI_REG(varray_attrib4us);
        LAPI_REG(varray_attrib1i);
        LAPI_REG(varray_attrib2i);
        LAPI_REG(varray_attrib3i);
        LAPI_REG(varray_attrib4i);
        LAPI_REG(varray_attrib1ui);
        LAPI_REG(varray_attrib2ui);
        LAPI_REG(varray_attrib3ui);
        LAPI_REG(varray_attrib4ui);
        LAPI_REG(hudmatrix_push);
        LAPI_REG(hudmatrix_pop);
        LAPI_REG(hudmatrix_flush);
        LAPI_REG(hudmatrix_reset);
        LAPI_REG(hudmatrix_translate);
        LAPI_REG(hudmatrix_scale);
        LAPI_REG(hudmatrix_ortho);
        LAPI_REG(gl_shader_hud_set);
        LAPI_REG(gl_shader_hudnotexture_set);
        LAPI_REG(gl_scissor_enable);
        LAPI_REG(gl_scissor_disable);
        LAPI_REG(gl_scissor);
        LAPI_REG(gl_blend_enable);
        LAPI_REG(gl_blend_disable);
        LAPI_REG(gl_blend_func);
        LAPI_REG(gl_bind_texture);
        LAPI_REG(gl_texture_param);

        LAPI_REG(input_get_modifier_state);
        LAPI_REG(gui_set_mainmenu);
        LAPI_REG(gui_text_bounds);
        LAPI_REG(gui_text_bounds_f);
        LAPI_REG(gui_text_pos);
        LAPI_REG(gui_text_pos_f);
        LAPI_REG(gui_text_visible);
        LAPI_REG(gui_draw_text);
#endif
    }
}
