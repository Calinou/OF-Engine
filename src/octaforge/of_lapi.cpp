#include "cube.h"
#include "engine.h"
#include "game.h"

#include "of_lapi.h"
#include "of_tools.h"

#ifdef CLIENT
    #include "client_engine_additions.h"
    #include "client_system.h"
    #include "targeting.h"
    #include "textedit.h"
#endif
#include "editing_system.h"
#include "message_system.h"

#include "of_entities.h"
#include "of_world.h"
#include "of_localserver.h"

#define LAPI_REG(name) t[#name] = &_lua_##name

#define LAPI_GET_ENT(name, tname, _log, retexpr) \
int uid = tname.get<int>("uid"); \
\
CLogicEntity *name = LogicSystem::getLogicEntity(uid); \
if (!name) \
{ \
    logger::log( \
        logger::ERROR, "Cannot find CLE for entity %i (%s).\n", uid, _log \
    ); \
    retexpr; \
}

#include "of_lapi_base.h"
#ifdef CLIENT
#include "of_lapi_blend.h"
#include "of_lapi_camera.h"
#endif
#include "of_lapi_edit.h"
#include "of_lapi_entity.h"
#ifdef CLIENT
#include "of_lapi_gui.h"
#include "of_lapi_input.h"
#endif
#include "of_lapi_messages.h"
#include "of_lapi_model.h"
#include "of_lapi_network.h"
#ifdef CLIENT
#include "of_lapi_parthud.h"
#include "of_lapi_shaders.h"
#endif
#include "of_lapi_sound.h"
#ifdef CLIENT
#include "of_lapi_tex.h"
#include "of_lapi_textedit.h"
#endif
#include "of_lapi_world.h"

#undef LAPI_GET_ENT
#undef LAPI_REG

using namespace types;
using namespace filesystem;
using namespace lua;

extern string homedir;

Table md3commands();
Table md5commands();
Table iqmcommands();
Table smdcommands();
Table objcommands();

namespace lapi
{
    State  state;
    String mod_dir;
    bool initialized;

    void panic(const State& s, const char *msg)
    {
        logger::log(logger::ERROR, "OF::Lua: %s\n", msg);
    }

    void setup_binds();

    void init(const char *dir)
    {
        if (initialized) return;
            initialized  = true;

        mod_dir = dir;

        state.set_panic_handler(&panic);

        state.open_base   ();
        state.open_table  ();
        state.open_string ();
        state.open_math   ();
        state.open_package();
        state.open_debug  ();

        lua_State *L  = state.state();
        Table loaded  = state.registry()["_LOADED"];
        Table package = loaded["package"];

        /* home directory paths */
        lua_pushfstring(
            L, ";%sdata%c?%cinit.lua",
            homedir, PATHDIV, PATHDIV
        );
        lua_pushfstring(
            L, ";%sdata%clibrary%c?%cinit.lua",
            homedir, PATHDIV, PATHDIV, PATHDIV
        );

        /* root paths */
        lua_pushliteral(L, ";./data/library/core/?.lua");
        lua_pushliteral(L, ";./data/library/core/?/init.lua");
        lua_pushliteral(L, ";./data/?/init.lua");
        lua_pushliteral(L, ";./data/library/?/init.lua");

        lua_concat(L,  6);
        Object str(L, -1);
        lua_pop   (L,  1);
        package["path"] = str;

        /* restrict package */
        Table pkg = state.new_table(0, 1);
        pkg  ["seeall" ] = package["seeall"];
        state["package"] = pkg;

        setup_binds();
    }

    void load_module(const char *name)
    {
        logger::log(
            logger::DEBUG, "Loading OF Lua module: %s%c%s.lua.\n",
            mod_dir.get_buf(), filesystem::separator(), name
        );

        types::String p(mod_dir);
        p += filesystem::separator();
        p += name;
        p += ".lua";

        auto err = state.do_file(p, lua::ERROR_TRACEBACK);
        if (types::get<0>(err))
            logger::log(logger::ERROR, "%s\n", types::get<1>(err));
    }

    void unload_module(const char *name)
    {
        Table loaded = state.registry().get<Table>("_LOADED");

        state [name] = nil;
        loaded[name] = nil;
        loaded.get<Table>("package")
              .get<Table>("loaded" )[name] = nil;
    }

    void setup_binds()
    {
#ifdef CLIENT
        state["CLIENT"] = true;
        state["SERVER"] = false;
#else
        state["CLIENT"] = false;
        state["SERVER"] = true;
#endif
        state["OF_CFG_VERSION"] = OF_CFG_VERSION;

        lua::Table api_all = state.new_table();

        #define CAPI_REG(name) lapi_binds::reg_##name(api_all)
        CAPI_REG(base);
#ifdef CLIENT
        CAPI_REG(blend);
        CAPI_REG(camera);
#endif
        CAPI_REG(edit);
        CAPI_REG(entity);
#ifdef CLIENT
        CAPI_REG(gui);
        CAPI_REG(input);
#endif
        CAPI_REG(messages);
        CAPI_REG(model);
        CAPI_REG(network);
#ifdef CLIENT
        CAPI_REG(parthud);
        CAPI_REG(shaders);
#endif
        CAPI_REG(sound);
#ifdef CLIENT
        CAPI_REG(tex);
        CAPI_REG(textedit);
#endif
        CAPI_REG(world);
        #undef CAPI_REG

        api_all["INFO"   ] = (int)logger::INFO;
        api_all["DEBUG"  ] = (int)logger::DEBUG;
        api_all["WARNING"] = (int)logger::WARNING;
        api_all["ERROR"  ] = (int)logger::ERROR;

        state.register_module("CAPI", api_all);
        state.register_module("obj",  objcommands());
        state.register_module("md3",  md3commands());
        state.register_module("md5",  md5commands());
        state.register_module("iqm",  iqmcommands());
        state.register_module("smd",  smdcommands());

        load_module("init");
    }

    void reset()
    {
        Vector<String> list;

        list.push_back("table");
        list.push_back("string");
        list.push_back("math");
        list.push_back("package");
        list.push_back("debug");
        list.push_back("obj");
        list.push_back("coroutine");
        list.push_back("_G");
        list.push_back("CAPI");
        list.push_back("md3");
        list.push_back("md5");
        list.push_back("smd");
        list.push_back("iqm");
        list.push_back("obj");

        Table t = state.get<Table>("library")["unresettable"];
        for (Table::it it = t.begin(); it != t.end(); ++it)
            list.push_back((*it).to<const char*>());

        t = state.registry()["_LOADED"];
        for (Table::pit it = t.pbegin(); it != t.pend(); ++it)
        {
            const char *key = (*it).second.to<const char*>();
            if (!key) continue;

            for (size_t i = 0; i < list.length(); ++i)
                if (list[i] == key) goto end;

            unload_module(key);
end:
            continue;
        }

        load_module("init");
    }

    bool load_library(const char *version)
    {
        Function tonumber = state["tonumber"];
        if (tonumber.call<Object>(version).is_nil())
            return false;

        Table package = state.registry().get<Object>("package", "_LOADED");

        String pattern = String().format(";./data/library/%s/?.lua", version);
        Function  find = state.get<Object>("string", "find");

        if (find.call<Object>(package["path"], pattern).is_nil())
            return true;

        lua_State *L  = state.state();

        /* original path */
        package["path"].push();

        /* home directory path */
        lua_pushfstring(
            L, ";%sdata%clibrary%c%s%c?.lua",
            homedir, PATHDIV, PATHDIV, version, PATHDIV
        );

        /* root path */
        lua_pushfstring(L, ";./data/library/%s/?.lua", version);

        lua_concat(L,  3);
        Object str(L, -1);
        lua_pop   (L,  1);
        package["path"] = str;

        return true;
    }
} /* end namespace lapi */