#ifndef __CUBE_H__
#define __CUBE_H__

#define _FILE_OFFSET_BITS 64

#ifdef __GNUC__
#define gamma __gamma
#endif

#ifdef WIN32
#define _USE_MATH_DEFINES
#endif
#include <math.h>

#ifdef __GNUC__
#undef gamma
#endif

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdarg.h>
#include <limits.h>
#include <float.h>
#include <assert.h>
#include <time.h>

extern "C" {
    #include "lua.h"
    #include "lualib.h"
    #include "lauxlib.h"
}

#ifdef WIN32
  #define WIN32_LEAN_AND_MEAN
  #ifdef _WIN32_WINNT
  #undef _WIN32_WINNT
  #endif
  #define _WIN32_WINNT 0x0500
  #include "windows.h"
  #ifndef _WINDOWS
    #define _WINDOWS
  #endif
  #ifndef __GNUC__
    #include <eh.h>
    #include <dbghelp.h>
    #include <intrin.h>
  #endif
  #define ZLIB_DLL
#endif

#ifdef __APPLE__
#include "SDL2/SDL.h"
#include "SDL2/SDL_opengl.h"
#define main SDL_main
#else
#include <SDL.h>
#include <SDL_opengl.h>
#endif

#ifdef STANDALONE
#ifdef main
#undef main
#endif
#endif

#include <enet/enet.h>

#include <zlib.h>

#ifdef swap
#undef swap
#endif
#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif

#include "tools.h"
#include "geom.h"
#include "ents.h"
#include "command.h"

#ifndef STANDALONE
#include "glexts.h"
#include "glemu.h"
#endif

#include "iengine.h"
#include "igame.h"

#include "of_logger.h"
#include "of_lua.h"

#endif

