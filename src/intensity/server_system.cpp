/* teh ugly file of stubs */

#include "engine.h"

int thirdperson   = 0;
int texdefscale   = 0;

void serverkeepalive()
{
    extern ENetHost *serverhost;
    if(serverhost)
        enet_host_service(serverhost, NULL, 0);
}

Texture *notexture = NULL;

void renderprogress(float bar, const char *text)
{
    // Keep connection alive
    serverkeepalive();

    printf("|");
    for (int i = 0; i < 10; i++)
    {
        if (i < int(bar*10))
            printf("#");
        else
            printf("-");
    }
    printf("| %s\r", text);
    fflush(stdout);
}

void clearparticleemitters() { };

vec worldpos;
dynent *player = NULL;
physent *camera1 = NULL;
float loadprogress = 0.333;

bool inbetweenframes = false;
int explicitsky = 0;
vtxarray *visibleva = NULL;

void clearshadowcache() {}

void calcmatbb(vtxarray *va, const ivec &co, int size, vector<materialsurface> &matsurfs) {}

void cleanupvolumetric() {};
void cleardeferredlightshaders() {};
void stopmapsounds() { };
void clearparticles() { };
void clearstains() { };
void clearlightcache(int e) { };
void initlights() { };
void setsurface(cube &c, int orient, const surfaceinfo &src, const vertinfo *srcverts, int numsrcverts) { };
void brightencube(cube &c) { };
int isvisiblesphere(float rad, const vec &cv) { return 0; };
ushort closestenvmap(int orient, const ivec &co, int size) { return 0; };
ushort closestenvmap(const vec &o) { return 0; };

vector<VSlot *> vslots;

int Slot::cancombine(int type) const
{
    return -1;
}

const char *Slot::name() const { return "slot"; }

Slot &lookupslot(int index, bool load)
{
    static Slot sl;
    static Shader sh;
    sl.shader = &sh;
    return sl;
};

VSlot &lookupvslot(int index, bool load)
{
    static VSlot vsl;
    static Slot sl = lookupslot(0, 0);
    vsl.slot = &sl;
    return vsl;
}

VSlot &Slot::emptyvslot()
{
    return lookupvslot(0, false);
}

VSlot *editvslot(const VSlot &src, const VSlot &delta)
{
    return &lookupvslot(0, 0);
}

void clearslots() {};
void compactvslots(cube *c, int n) {};
void compactvslot(int &index) {};
void compactvslot(VSlot &vs) {};
void mergevslot(VSlot &dst, const VSlot &src, const VSlot &delta) {};
VSlot *findvslot(Slot &slot, const VSlot &src, const VSlot &delta) { return &lookupvslot(0, 0); }

void packvslot(vector<uchar> &buf, const VSlot &src) {}
void packvslot(vector<uchar> &buf, int index) {}
void packvslot(vector<uchar> &buf, const VSlot *vs) {}
bool unpackvslot(ucharbuf &buf, VSlot &dst, bool delta) { return true; }

bool shouldreuseparams(Slot &s, VSlot &p) { return true; }

const char *DecalSlot::name() const { return "decal slot"; }

DecalSlot &lookupdecalslot(int index, bool load)
{
    static DecalSlot ds;
    return ds;
}

int DecalSlot::cancombine(int type) const { return -1; }

const char *getshaderparamname(const char *name, bool insert) { return ""; };

void setupmaterials(int start, int len) { };
int findmaterial(const char *name) { return 0; };
void genmatsurfs(const cube &c, const ivec &co, int size, vector<materialsurface> &matsurfs) { };
void resetqueries() { };
void initenvmaps() { };
int optimizematsurfs(materialsurface *matbuf, int matsurfs) { return 0; };

void rotatebb(vec &center, vec &radius, int yaw, int pitch, int roll) {}
void dropenttofloor(entity *e) {}
bool pointincube(const clipplanes &p, const vec &v) { return false; }
void resetclipplanes() {}
bool multiplayer(bool msg) { return false; }

namespace game {
    bool allowedittoggle() { return false; }
    void edittrigger(const selinfo &sel, int op, int arg1, int arg2, int arg3, const VSlot *vs) {}
    int parseplayer(const char *arg) { return -1; }
}

#ifndef __APPLE__
PFNGLDELETEBUFFERSARBPROC         glDeleteBuffers_            = NULL;
PFNGLGENBUFFERSARBPROC            glGenBuffers_               = NULL;
PFNGLBINDBUFFERARBPROC            glBindBuffer_               = NULL;
PFNGLBUFFERDATAARBPROC            glBufferData_               = NULL;
#else
void glDeleteBuffers(GLsizei n, const GLuint *buffers) {};
void glGenBuffers(GLsizei n, GLuint *buffers) {};
void glBindBuffer(GLenum target, GLuint buffer) {};
void glBufferData(GLenum target, GLsizeiptr size, const GLvoid *data, GLenum usage) {};
#endif

