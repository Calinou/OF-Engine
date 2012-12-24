// worldio.cpp: loading & saving of maps and savegames

#include "engine.h"
#include "game.h" // INTENSITY

// INTENSITY
#include "message_system.h"
#ifdef CLIENT
    #include "client_system.h"
#endif
#include "of_world.h"
#include "of_entities.h"
#ifdef SERVER
#include "of_localserver.h"
#include "of_tools.h"
#endif

void backup(char *name, char *backupname)
{
    string backupfile;
    copystring(backupfile, findfile(backupname, "wb"));
    remove(backupfile);
    rename(findfile(name, "wb"), backupfile);
}

string ogzname, bakname, cfgname, picname;

void cutogz(char *s)
{
    char *ogzp = strstr(s, ".ogz");
    if(ogzp) *ogzp = '\0';
}

void getmapfilenames(const char *fname, const char *cname, char *pakname, char *mapname, char *cfgname)
{
    if(!cname) cname = fname;
    string name;
    copystring(name, cname, 100);
    cutogz(name);
    char *slash = strpbrk(name, "/\\");
    if(slash)
    {
        copystring(pakname, name, slash-name+1);
        copystring(cfgname, slash+1);
    }
    else
    {
        copystring(pakname, "maps");
        copystring(cfgname, name);
    }
    if(strpbrk(fname, "/\\")) copystring(mapname, fname);
    else formatstring(mapname)("maps/%s", fname);
    cutogz(mapname);
}

VARP(savebak, 0, 2, 2);

void setmapfilenames(const char *fname, const char *cname = 0)
{
    string pakname, mapname, mcfgname;
    getmapfilenames(fname, cname, pakname, mapname, mcfgname);

    formatstring(ogzname)("data/%s.ogz", mapname);
    if(savebak==1) formatstring(bakname)("data/%s.BAK", mapname);
    else formatstring(bakname)("data/%s_%d.BAK", mapname, totalmillis);
    formatstring(cfgname)("data/%s/%s.cfg", pakname, mcfgname);
    formatstring(picname)("data/%s.jpg", mapname);

    path(ogzname);
    path(bakname);
    path(cfgname);
    path(picname);
}

enum { OCTSAV_CHILDREN = 0, OCTSAV_EMPTY, OCTSAV_SOLID, OCTSAV_NORMAL, OCTSAV_LODCUBE };

#define LM_PACKW 512
#define LM_PACKH 512
enum { LMID_AMBIENT = 0, LMID_AMBIENT1, LMID_BRIGHT, LMID_BRIGHT1, LMID_DARK, LMID_DARK1, LMID_RESERVED };
#define LAYER_DUP (1<<7)

struct surfacecompat
{
    uchar texcoords[8];
    uchar w, h;
    ushort x, y;
    uchar lmid, layer;
};

struct normalscompat
{
    bvec normals[4];
};

struct mergecompat
{
    ushort u1, u2, v1, v2;
};

struct polysurfacecompat
{
    uchar lmid[2];
    uchar verts, numverts;
};

static int savemapprogress = 0;

void savec(cube *c, const ivec &o, int size, stream *f, bool nolms)
{
    if((savemapprogress++&0xFFF)==0) renderprogress(float(savemapprogress)/allocnodes, "saving octree...");

    loopi(8)
    {
        ivec co(i, o.x, o.y, o.z, size);
        if(c[i].children)
        {
            f->putchar(OCTSAV_CHILDREN);
            savec(c[i].children, co, size>>1, f, nolms);
        }
        else
        {
            int oflags = 0, surfmask = 0, totalverts = 0;
            if(c[i].material!=MAT_AIR) oflags |= 0x40;
            if(!nolms)
            {
                if(c[i].merged) oflags |= 0x80;
                if(c[i].ext) loopj(6) 
                {
                    const surfaceinfo &surf = c[i].ext->surfaces[j];
                    if(!surf.used()) continue;
                    oflags |= 0x20; 
                    surfmask |= 1<<j; 
                    totalverts += surf.totalverts(); 
                }
            }

            if(c[i].children) f->putchar(oflags | OCTSAV_LODCUBE);
            else if(isempty(c[i])) f->putchar(oflags | OCTSAV_EMPTY);
            else if(isentirelysolid(c[i])) f->putchar(oflags | OCTSAV_SOLID);
            else
            {
                f->putchar(oflags | OCTSAV_NORMAL);
                f->write(c[i].edges, 12);
            }
    
            loopj(6) f->putlil<ushort>(c[i].texture[j]);

            if(oflags&0x40) f->putlil<ushort>(c[i].material);
            if(oflags&0x80) f->putchar(c[i].merged);
            if(oflags&0x20) 
            {
                f->putchar(surfmask);
                f->putchar(totalverts);
                loopj(6) if(surfmask&(1<<j))
                {
                    surfaceinfo surf = c[i].ext->surfaces[j];
                    vertinfo *verts = c[i].ext->verts() + surf.verts;
                    int layerverts = surf.numverts&MAXFACEVERTS, numverts = surf.totalverts(), 
                        vertmask = 0, vertorder = 0,
                        dim = dimension(j), vc = C[dim], vr = R[dim];
                    if(numverts)
                    {
                        if(c[i].merged&(1<<j)) 
                        {
                            vertmask |= 0x04;
                            if(layerverts == 4)
                            {
                                ivec v[4] = { verts[0].getxyz(), verts[1].getxyz(), verts[2].getxyz(), verts[3].getxyz() };
                                loopk(4) 
                                {
                                    const ivec &v0 = v[k], &v1 = v[(k+1)&3], &v2 = v[(k+2)&3], &v3 = v[(k+3)&3];
                                    if(v1[vc] == v0[vc] && v1[vr] == v2[vr] && v3[vc] == v2[vc] && v3[vr] == v0[vr])
                                    {
                                        vertmask |= 0x01;
                                        vertorder = k;
                                        break;
                                    }
                                }
                            }
                        }
                        else
                        {
                            int vis = visibletris(c[i], j, co.x, co.y, co.z, size);
                            if(vis&4 || faceconvexity(c[i], j) < 0) vertmask |= 0x01;
                            if(layerverts < 4 && vis&2) vertmask |= 0x02; 
                        }
                        bool matchnorm = true;
                        loopk(numverts) 
                        { 
                            const vertinfo &v = verts[k]; 
                            if(v.norm) { vertmask |= 0x80; if(v.norm != verts[0].norm) matchnorm = false; }
                        }
                        if(matchnorm) vertmask |= 0x08;
                    }
                    surf.verts = vertmask;
                    polysurfacecompat psurf;
                    psurf.lmid[0] = psurf.lmid[1] = LMID_AMBIENT;
                    psurf.verts = surf.verts;
                    psurf.numverts = surf.numverts;
                    f->write(&psurf, sizeof(polysurfacecompat));
                    bool hasxyz = (vertmask&0x04)!=0, hasnorm = (vertmask&0x80)!=0;
                    if(layerverts == 4)
                    {
                        if(hasxyz && vertmask&0x01)
                        {
                            ivec v0 = verts[vertorder].getxyz(), v2 = verts[(vertorder+2)&3].getxyz();
                            f->putlil<ushort>(v0[vc]); f->putlil<ushort>(v0[vr]);
                            f->putlil<ushort>(v2[vc]); f->putlil<ushort>(v2[vr]);
                            hasxyz = false;
                        }
                    } 
                    if(hasnorm && vertmask&0x08) { f->putlil<ushort>(verts[0].norm); hasnorm = false; }
                    if(hasxyz || hasnorm) loopk(layerverts)
                    {
                        const vertinfo &v = verts[(k+vertorder)%layerverts];
                        if(hasxyz) 
                        { 
                            ivec xyz = v.getxyz(); 
                            f->putlil<ushort>(xyz[vc]); f->putlil<ushort>(xyz[vr]); 
                        }
                        if(hasnorm) f->putlil<ushort>(v.norm); 
                    }
                }
            }

            if(c[i].children) savec(c[i].children, co, size>>1, f, nolms);
        }
    }
}

cube *loadchildren(stream *f, const ivec &co, int size, bool &failed);

void convertoldsurfaces(cube &c, const ivec &co, int size, surfacecompat *srcsurfs, int hassurfs, normalscompat *normals, int hasnorms, mergecompat *merges, int hasmerges)
{
    surfaceinfo dstsurfs[6];
    vertinfo verts[6*2*MAXFACEVERTS];
    int totalverts = 0;
    memset(dstsurfs, 0, sizeof(dstsurfs));
    loopi(6) if((hassurfs|hasnorms|hasmerges)&(1<<i))
    {
        surfaceinfo &dst = dstsurfs[i];
        vertinfo *curverts = NULL;
        int numverts = 0;
        surfacecompat *src = NULL;
        if(hassurfs&(1<<i))
        {
            src = &srcsurfs[i];
            if(src->layer&2) dst.numverts |= LAYER_BLEND;
            else if(src->layer == 1) dst.numverts |= LAYER_BOTTOM;
            else dst.numverts |= LAYER_TOP;
        }
        else dst.numverts |= LAYER_TOP;
        bool uselms = hassurfs&(1<<i) && dst.numverts&~LAYER_TOP,
             usemerges = hasmerges&(1<<i) && merges[i].u1 < merges[i].u2 && merges[i].v1 < merges[i].v2,
             usenorms = hasnorms&(1<<i) && normals[i].normals[0] != bvec(128, 128, 128);
        if(uselms || usemerges || usenorms)
        {
            ivec v[4], pos[4], e1, e2, e3, n, vo = ivec(co).mask(0xFFF).shl(3);
            genfaceverts(c, i, v); 
            n.cross((e1 = v[1]).sub(v[0]), (e2 = v[2]).sub(v[0]));
            if(usemerges)
            {
                const mergecompat &m = merges[i];
                int offset = -n.dot(v[0].mul(size).add(vo)),
                    dim = dimension(i), vc = C[dim], vr = R[dim];
                loopk(4)
                {
                    const ivec &coords = facecoords[i][k];
                    int cc = coords[vc] ? m.u2 : m.u1,
                        rc = coords[vr] ? m.v2 : m.v1,
                        dc = -(offset + n[vc]*cc + n[vr]*rc)/n[dim];
                    ivec &mv = pos[k];
                    mv[vc] = cc;
                    mv[vr] = rc;
                    mv[dim] = dc;
                }
            }
            else
            {
                int convex = (e3 = v[0]).sub(v[3]).dot(n), vis = 3;
                if(!convex)
                {
                    if(ivec().cross(e3, e2).iszero()) { if(!n.iszero()) vis = 1; } 
                    else if(n.iszero()) vis = 2;
                }
                int order = convex < 0 ? 1 : 0;
                pos[0] = v[order].mul(size).add(vo);
                pos[1] = vis&1 ? v[order+1].mul(size).add(vo) : pos[0];
                pos[2] = v[order+2].mul(size).add(vo);
                pos[3] = vis&2 ? v[(order+3)&3].mul(size).add(vo) : pos[0];
            }
            curverts = verts + totalverts;
            loopk(4)
            {
                if(k > 0 && (pos[k] == pos[0] || pos[k] == pos[k-1])) continue;
                vertinfo &dv = curverts[numverts++];
                dv.setxyz(pos[k]);
                dv.norm = usenorms && normals[i].normals[k] != bvec(128, 128, 128) ? encodenormal(normals[i].normals[k].tovec().normalize()) : 0;
            }
            dst.verts = totalverts;
            dst.numverts |= numverts;
            totalverts += numverts;
        }    
    }
    setsurfaces(c, dstsurfs, verts, totalverts);
}

static inline int convertoldmaterial(int mat)
{
    return ((mat&7)<<MATF_VOLUME_SHIFT) | (((mat>>3)&3)<<MATF_CLIP_SHIFT) | (((mat>>5)&7)<<MATF_FLAG_SHIFT);
}
 
void loadc(stream *f, cube &c, const ivec &co, int size, bool &failed)
{
    bool haschildren = false;
    int octsav = f->getchar();
    switch(octsav&0x7)
    {
        case OCTSAV_CHILDREN:
            c.children = loadchildren(f, co, size>>1, failed);
            return;

        case OCTSAV_LODCUBE: haschildren = true;    break;
        case OCTSAV_EMPTY:  emptyfaces(c);          break;
        case OCTSAV_SOLID:  solidfaces(c);          break;
        case OCTSAV_NORMAL: f->read(c.edges, 12); break;
        default: failed = true; return;
    }
    loopi(6) c.texture[i] = mapversion<14 ? f->getchar() : f->getlil<ushort>();
    if(mapversion < 7) f->seek(3, SEEK_CUR);
    else if(mapversion <= 31)
    {
        uchar mask = f->getchar();
        if(mask & 0x80) 
        {
            int mat = f->getchar();
            if(mapversion < 27)
            {
                static ushort matconv[] = { MAT_AIR, MAT_WATER, MAT_CLIP, MAT_GLASS|MAT_CLIP, MAT_NOCLIP, MAT_LAVA|MAT_DEATH, MAT_GAMECLIP, MAT_DEATH };
                c.material = size_t(mat) < sizeof(matconv)/sizeof(matconv[0]) ? matconv[mat] : MAT_AIR;
            }
            else c.material = convertoldmaterial(mat);
        }
        surfacecompat surfaces[12];
        normalscompat normals[6];
        mergecompat merges[6];
        int hassurfs = 0, hasnorms = 0, hasmerges = 0;
        if(mask & 0x3F)
        {
            int numsurfs = 6;
            loopi(numsurfs)
            {
                if(i >= 6 || mask & (1 << i))
                {
                    f->read(&surfaces[i], sizeof(surfacecompat));
                    lilswap(&surfaces[i].x, 2);
                    if(mapversion < 10) ++surfaces[i].lmid;
                    if(mapversion < 18)
                    {
                        if(surfaces[i].lmid >= LMID_AMBIENT1) ++surfaces[i].lmid;
                        if(surfaces[i].lmid >= LMID_BRIGHT1) ++surfaces[i].lmid;
                    }
                    if(mapversion < 19)
                    {
                        if(surfaces[i].lmid >= LMID_DARK) surfaces[i].lmid += 2;
                    }
                    if(i < 6)
                    {
                        if(mask & 0x40) { hasnorms |= 1<<i; f->read(&normals[i], sizeof(normalscompat)); }
                        if(surfaces[i].layer != 0 || surfaces[i].lmid != LMID_AMBIENT) 
                            hassurfs |= 1<<i;
                        if(surfaces[i].layer&2) numsurfs++;
                    }
                }
            }
        }
        if(mapversion <= 8) edgespan2vectorcube(c);
        if(mapversion <= 11)
        {
            swap(c.faces[0], c.faces[2]);
            swap(c.texture[0], c.texture[4]);
            swap(c.texture[1], c.texture[5]);
            if(hassurfs&0x33)
            {
                swap(surfaces[0], surfaces[4]);
                swap(surfaces[1], surfaces[5]);
                hassurfs = (hassurfs&~0x33) | ((hassurfs&0x30)>>4) | ((hassurfs&0x03)<<4);
            }
        }
        if(mapversion >= 20)
        {
            if(octsav&0x80)
            {
                int merged = f->getchar();
                c.merged = merged&0x3F;
                if(merged&0x80)
                {
                    int mask = f->getchar();
                    if(mask)
                    {
                        hasmerges = mask&0x3F;
                        loopi(6) if(mask&(1<<i))
                        {
                            mergecompat *m = &merges[i];
                            f->read(m, sizeof(mergecompat));
                            lilswap(&m->u1, 4);
                            if(mapversion <= 25)
                            {
                                int uorigin = m->u1 & 0xE000, vorigin = m->v1 & 0xE000;
                                m->u1 = (m->u1 - uorigin) << 2;
                                m->u2 = (m->u2 - uorigin) << 2;
                                m->v1 = (m->v1 - vorigin) << 2;
                                m->v2 = (m->v2 - vorigin) << 2;
                            }
                        }
                    }
                }
            }    
        }                
        if(hassurfs || hasnorms || hasmerges)
            convertoldsurfaces(c, co, size, surfaces, hassurfs, normals, hasnorms, merges, hasmerges);
    }
    else
    {
        if(octsav&0x40) 
        {
            if(mapversion <= 32)
            {
                int mat = f->getchar();
                c.material = convertoldmaterial(mat);
            }
            else c.material = f->getlil<ushort>();
        }
        if(octsav&0x80) c.merged = f->getchar();
        if(octsav&0x20)
        {
            int surfmask, totalverts;
            surfmask = f->getchar();
            totalverts = f->getchar();
            newcubeext(c, totalverts, false);
            memset(c.ext->surfaces, 0, sizeof(c.ext->surfaces));
            memset(c.ext->verts(), 0, totalverts*sizeof(vertinfo));
            int offset = 0;
            loopi(6) if(surfmask&(1<<i)) 
            {
                surfaceinfo &surf = c.ext->surfaces[i];
                polysurfacecompat psurf;
                f->read(&psurf, sizeof(polysurfacecompat));
                surf.verts = psurf.verts;
                surf.numverts = psurf.numverts;
                int vertmask = surf.verts, numverts = surf.totalverts();
                if(!numverts) { surf.verts = 0; continue; }
                surf.verts = offset;
                vertinfo *verts = c.ext->verts() + offset;
                offset += numverts;
                ivec v[4], n;
                int layerverts = surf.numverts&MAXFACEVERTS, dim = dimension(i), vc = C[dim], vr = R[dim], bias = 0;
                genfaceverts(c, i, v);
                bool hasxyz = (vertmask&0x04)!=0, hasuv = (vertmask&0x40)!=0, hasnorm = (vertmask&0x80)!=0;
                if(hasxyz)
                { 
                    ivec e1, e2, e3;
                    n.cross((e1 = v[1]).sub(v[0]), (e2 = v[2]).sub(v[0]));   
                    if(n.iszero()) n.cross(e2, (e3 = v[3]).sub(v[0]));
                    bias = -n.dot(ivec(v[0]).mul(size).add(ivec(co).mask(0xFFF).shl(3)));
                }
                else
                {
                    int vis = layerverts < 4 ? (vertmask&0x02 ? 2 : 1) : 3, order = vertmask&0x01 ? 1 : 0, k = 0;
                    ivec vo = ivec(co).mask(0xFFF).shl(3);
                    verts[k++].setxyz(v[order].mul(size).add(vo));
                    if(vis&1) verts[k++].setxyz(v[order+1].mul(size).add(vo));
                    verts[k++].setxyz(v[order+2].mul(size).add(vo));
                    if(vis&2) verts[k++].setxyz(v[(order+3)&3].mul(size).add(vo));
                }
                if(layerverts == 4)
                {
                    if(hasxyz && vertmask&0x01)
                    {
                        ushort c1 = f->getlil<ushort>(), r1 = f->getlil<ushort>(), c2 = f->getlil<ushort>(), r2 = f->getlil<ushort>();
                        ivec xyz;
                        xyz[vc] = c1; xyz[vr] = r1; xyz[dim] = -(bias + n[vc]*xyz[vc] + n[vr]*xyz[vr])/n[dim];
                        verts[0].setxyz(xyz);
                        xyz[vc] = c1; xyz[vr] = r2; xyz[dim] = -(bias + n[vc]*xyz[vc] + n[vr]*xyz[vr])/n[dim];
                        verts[1].setxyz(xyz);
                        xyz[vc] = c2; xyz[vr] = r2; xyz[dim] = -(bias + n[vc]*xyz[vc] + n[vr]*xyz[vr])/n[dim];
                        verts[2].setxyz(xyz);
                        xyz[vc] = c2; xyz[vr] = r1; xyz[dim] = -(bias + n[vc]*xyz[vc] + n[vr]*xyz[vr])/n[dim];
                        verts[3].setxyz(xyz);
                        hasxyz = false;
                    }
                    if(hasuv && vertmask&0x02)
                    {
                        loopk(4) f->getlil<ushort>();
                        if(surf.numverts&LAYER_DUP) loopk(4) f->getlil<ushort>();
                        hasuv = false;
                    } 
                }
                if(hasnorm && vertmask&0x08)
                {
                    ushort norm = f->getlil<ushort>();
                    loopk(layerverts) verts[k].norm = norm;
                    hasnorm = false;
                }
                if(hasxyz || hasuv || hasnorm) loopk(layerverts)
                {
                    vertinfo &v = verts[k];
                    if(hasxyz)
                    {
                        ivec xyz;
                        xyz[vc] = f->getlil<ushort>(); xyz[vr] = f->getlil<ushort>();
                        xyz[dim] = -(bias + n[vc]*xyz[vc] + n[vr]*xyz[vr])/n[dim];
                        v.setxyz(xyz);
                    }
                    if(hasuv) { f->getlil<ushort>(); f->getlil<ushort>(); }    
                    if(hasnorm) v.norm = f->getlil<ushort>();
                }
                if(surf.numverts&LAYER_DUP) loopk(layerverts)
                {
                    if(hasuv) { f->getlil<ushort>(); f->getlil<ushort>(); }
                }
            }
        }    
    }

    c.children = (haschildren ? loadchildren(f, co, size>>1, failed) : NULL);
}

cube *loadchildren(stream *f, const ivec &co, int size, bool &failed)
{
    cube *c = newcubes();
    loopi(8) 
    {
        loadc(f, c[i], ivec(i, co.x, co.y, co.z, size), size, failed);
        if(failed) break;
    }
    return c;
}

VAR(dbgvars, 0, 0, 1);

void savevslot(stream *f, VSlot &vs, int prev)
{
    f->putlil<int>(vs.changed);
    f->putlil<int>(prev);
    if(vs.changed & (1<<VSLOT_SHPARAM))
    {
        f->putlil<ushort>(vs.params.length());
        loopv(vs.params)
        {
            SlotShaderParam &p = vs.params[i];
            f->putlil<ushort>(strlen(p.name));
            f->write(p.name, strlen(p.name));
            loopk(4) f->putlil<float>(p.val[k]);
        }
    }
    if(vs.changed & (1<<VSLOT_SCALE)) f->putlil<float>(vs.scale);
    if(vs.changed & (1<<VSLOT_ROTATION)) f->putlil<int>(vs.rotation);
    if(vs.changed & (1<<VSLOT_OFFSET))
    {
        f->putlil<int>(vs.xoffset);
        f->putlil<int>(vs.yoffset);
    }
    if(vs.changed & (1<<VSLOT_SCROLL))
    {
        f->putlil<float>(vs.scrollS);
        f->putlil<float>(vs.scrollT);
    }
    if(vs.changed & (1<<VSLOT_LAYER)) f->putlil<int>(vs.layer);
    if(vs.changed & (1<<VSLOT_ALPHA))
    {
        f->putlil<float>(vs.alphafront);
        f->putlil<float>(vs.alphaback);
    }
    if(vs.changed & (1<<VSLOT_COLOR)) 
    {
        loopk(3) f->putlil<float>(vs.colorscale[k]);
    }
    if(vs.changed & (1<<VSLOT_REFRACT))
    {
        f->putlil<float>(vs.refractscale);
        loopk(3) f->putlil<float>(vs.refractcolor[k]);
    }
}

/* OctaForge: Shared_Ptr */
void savevslots(stream *f, int numvslots)
{
    if(vslots.empty()) return;
    int *prev = new int[numvslots];
    memset(prev, -1, numvslots*sizeof(int));
    loopi(numvslots)
    {
        VSlot *vs = vslots[i].get();
        if(vs->changed) continue;
        for(;;)
        {
            VSlot *cur = vs;
            do vs = vs->next; while(vs && vs->index >= numvslots);
            if(!vs) break;
            prev[vs->index] = cur->index;
        } 
    }
    int lastroot = 0;
    loopi(numvslots)
    {
        VSlot &vs = *(vslots[i].get());
        if(!vs.changed) continue;
        if(lastroot < i) f->putlil<int>(-(i - lastroot));
        savevslot(f, vs, prev[i]);
        lastroot = i+1;
    }
    if(lastroot < numvslots) f->putlil<int>(-(numvslots - lastroot));
    if (numvslots > 0) delete[] prev; // INTENSITY - check for numvslots, for server
}
            
void loadvslot(stream *f, VSlot &vs, int changed)
{
    vs.changed = changed;
    if(vs.changed & (1<<VSLOT_SHPARAM))
    {
        int numparams = f->getlil<ushort>();
        string name;
        loopi(numparams)
        {
            SlotShaderParam &p = vs.params.add();
            int nlen = f->getlil<ushort>();
            f->read(name, min(nlen, MAXSTRLEN-1));
            name[min(nlen, MAXSTRLEN-1)] = '\0';
            if(nlen >= MAXSTRLEN) f->seek(nlen - (MAXSTRLEN-1), SEEK_CUR);
            p.name = getshaderparamname(name);
            p.loc = -1;
            loopk(4) p.val[k] = f->getlil<float>();
        }
    }
    if(vs.changed & (1<<VSLOT_SCALE)) vs.scale = f->getlil<float>();
    if(vs.changed & (1<<VSLOT_ROTATION)) vs.rotation = f->getlil<int>();
    if(vs.changed & (1<<VSLOT_OFFSET))
    {
        vs.xoffset = f->getlil<int>();
        vs.yoffset = f->getlil<int>();
    }
    if(vs.changed & (1<<VSLOT_SCROLL))
    {
        vs.scrollS = f->getlil<float>();
        vs.scrollT = f->getlil<float>();
    }
    if(vs.changed & (1<<VSLOT_LAYER)) vs.layer = f->getlil<int>();
    if(vs.changed & (1<<VSLOT_ALPHA))
    {
        vs.alphafront = f->getlil<float>();
        vs.alphaback = f->getlil<float>();
    }
    if(vs.changed & (1<<VSLOT_COLOR)) 
    {
        loopk(3) vs.colorscale[k] = f->getlil<float>();
    }
    if(vs.changed & (1<<VSLOT_REFRACT))
    {
        vs.refractscale = f->getlil<float>();
        loopk(3) vs.refractcolor[k] = f->getlil<float>();
    }
}

void loadvslots(stream *f, int numvslots)
{
    int *prev = new int[numvslots];
    memset(prev, -1, numvslots*sizeof(int));
    while(numvslots > 0)
    {
        int changed = f->getlil<int>();
        if(changed < 0)
        {
            loopi(-changed) vslots.add(new VSlot(NULL, vslots.length()));
            numvslots += changed;
        }
        else
        {
            prev[vslots.length()] = f->getlil<int>();
            loadvslot(f, *(vslots.add(new VSlot(NULL, vslots.length())).get()), changed);    
            numvslots--;
        }
    }
    loopv(vslots) if(vslots.inrange(prev[i])) vslots[prev[i]]->next = vslots[i].get();
    delete[] prev;
}

bool save_world(const char *mname, bool nolms)
{
#ifdef CLIENT
    types::String map_name(mname);
    if (map_name.is_empty()) map_name = game::getclientmap();
    setmapfilenames(!map_name.is_empty() ? map_name.get_buf() : "untitled");
    if(savebak) backup(ogzname, bakname);
    stream *f = opengzfile(ogzname, "wb");
    if(!f) { conoutf(CON_WARN, "could not write map to %s", ogzname); return false; }

    int numvslots = vslots.length();
    if(!nolms && !multiplayer(false))
    {
        numvslots = compactvslots();
        allchanged();
    }

    savemapprogress = 0;
    renderprogress(0, "saving map...");

    octaheader hdr;
    memcpy(hdr.magic, "OCTA", 4);
    hdr.version = MAPVERSION;
    hdr.headersize = sizeof(hdr);
    hdr.worldsize = worldsize;
    hdr.numents = 0;
    hdr.numpvs = nolms ? 0 : getnumviewcells();
    hdr.lightmaps = 0;
    hdr.blendmap = shouldsaveblendmap();
    hdr.numvars = 0;
    hdr.numvslots = numvslots;
    for (varsys::Variable_Map::cit it = varsys::variables->begin(); it != varsys::variables->end(); ++it)
    {
        varsys::Variable *v = it->second;
        if (
            (v->flags & varsys::FLAG_OVERRIDE) != 0 &&
            (v->flags & varsys::FLAG_READONLY) == 0 &&
            (v->flags & varsys::FLAG_OVERRIDEN) != 0
        ) hdr.numvars++;
    }
    lilswap(&hdr.version, 9);
    f->write(&hdr, sizeof(hdr));
   
    for (varsys::Variable_Map::cit it = varsys::variables->begin(); it != varsys::variables->end(); ++it)
    {
        varsys::Variable *v = it->second;
        if(
            (v->flags & varsys::FLAG_OVERRIDE) == 0 ||
            (v->flags & varsys::FLAG_READONLY) != 0 ||
            (v->flags & varsys::FLAG_OVERRIDEN) == 0
        ) continue;
        f->putchar(v->type);
        f->putlil<ushort>(  strlen(v->name));
        f->write(v->name, strlen(v->name));
        switch(v->type)
        {
            case varsys::TYPE_I:
            {
                int val = varsys::get_int(v);
                if(dbgvars) conoutf(CON_DEBUG, "wrote var %s: %d", v->name, val);
                f->putlil<int>(val);
                break;
            }
            case varsys::TYPE_F:
            {
                float val = varsys::get_float(v);
                if(dbgvars) conoutf(CON_DEBUG, "wrote fvar %s: %f", v->name, val);
                f->putlil<float>(val);
                break;
            }
            case varsys::TYPE_S:
            {
                const char *val = varsys::get_string(v);
                if(dbgvars) conoutf(CON_DEBUG, "wrote svar %s: %s", v->name, val);
                f->putlil<ushort>(strlen(val));
                f->write(val, strlen(val));
                break;
            }
        }
    }

    if(dbgvars) conoutf(CON_DEBUG, "wrote %d vars", hdr.numvars);

    f->putchar((int)strlen(game::gameident()));
    f->write(game::gameident(), (int)strlen(game::gameident())+1);
    f->putlil<ushort>(0);
    vector<char> extras;
    game::writegamedata(extras);
    f->putlil<ushort>(extras.length());
    f->write(extras.getbuf(), extras.length());
    
    f->putlil<ushort>(texmru.length());
    loopv(texmru) f->putlil<ushort>(texmru[i]);

    savevslots(f, numvslots);

    renderprogress(0, "saving octree...");
    savec(worldroot, ivec(0, 0, 0), worldsize>>1, f, nolms);

    if(!nolms) 
    {
        if(getnumviewcells()>0) { renderprogress(0, "saving pvs..."); savepvs(f); }
    }
    if(shouldsaveblendmap()) { renderprogress(0, "saving blendmap..."); saveblendmap(f); }

    delete f;
    conoutf("wrote map file %s", ogzname);

    return true;
#else
    return false;
#endif
}

static uint mapcrc = 0;

uint getmapcrc() { return mapcrc; }
void clearmapcrc() { mapcrc = 0; }

bool finish_load_world(); // INTENSITY: Added this, and use it inside load_world

const char *_saved_mname = NULL; // INTENSITY
const char *_saved_cname = NULL; // INTENSITY
octaheader *saved_hdr = NULL; // INTENSITY

bool load_world(const char *mname, const char *cname)        // still supports all map formats that have existed since the earliest cube betas!
{
    world::loading = true; // INTENSITY
    LogicSystem::init(); // INTENSITY: Start our game data system, wipe all existing LogicEntities, and add the player

    setmapfilenames(mname, cname);

    _saved_mname = mname; // INTENSITY
    _saved_cname = cname; // INTENSITY

    stream *f = opengzfile(ogzname, "rb");
    if(!f) { conoutf(CON_ERROR, "could not read map %s", ogzname); return false; }
    saved_hdr = new octaheader; // INTENSITY
    octaheader& hdr = *saved_hdr; // INTENSITY
    if(f->read(&hdr, 7*sizeof(int))!=int(7*sizeof(int))) { conoutf(CON_ERROR, "map %s has malformatted header", ogzname); delete f; return false; }
    lilswap(&hdr.version, 6);
    if(memcmp(hdr.magic, "OCTA", 4) || hdr.worldsize <= 0|| hdr.numents < 0) { conoutf(CON_ERROR, "map %s has malformatted header", ogzname); delete f; return false; }
    if(hdr.version>MAPVERSION) { conoutf(CON_ERROR, "map %s requires a newer version of OctaForge", ogzname); delete f; return false; }
    compatheader chdr;
    if(hdr.version <= 28)
    {
        if(f->read(&chdr.lightprecision, sizeof(chdr) - 7*sizeof(int)) != int(sizeof(chdr) - 7*sizeof(int))) { conoutf(CON_ERROR, "map %s has malformatted header", ogzname); delete f; return false; }
    }
    else 
    {
        int extra = 0;
        if(hdr.version <= 29) extra++; 
        if(f->read(&hdr.blendmap, sizeof(hdr) - (7+extra)*sizeof(int)) != int(sizeof(hdr) - (7+extra)*sizeof(int))) { conoutf(CON_ERROR, "map %s has malformatted header", ogzname); delete f; return false; }
    }

    resetmap();
    Texture *mapshot = textureload(picname, 3, true, false);
    renderbackground("loading...", mapshot, mname, game::getmapinfo());

    SETVFN(mapversion, hdr.version);

    if(hdr.version <= 28)
    {
        lilswap(&chdr.lightprecision, 3);
        if(chdr.lightprecision) SETVF(lightprecision, chdr.lightprecision);
        if(chdr.lighterror) SETVF(lighterror, chdr.lighterror);
        if(chdr.bumperror) SETVF(bumperror, chdr.bumperror);
        SETVF(lightlod, chdr.lightlod);
        if(chdr.ambient) SETVF(ambient, chdr.ambient);
        SETVF(skylight, (int(chdr.skylight[0])<<16) | (int(chdr.skylight[1])<<8) | int(chdr.skylight[2]));
        SETVF(watercolour, (int(chdr.watercolour[0])<<16) | (int(chdr.watercolour[1])<<8) | int(chdr.watercolour[2]));
        SETVF(waterfallcolour, (int(chdr.waterfallcolour[0])<<16) | (int(chdr.waterfallcolour[1])<<8) | int(chdr.waterfallcolour[2]));
        SETVF(lavacolour, (int(chdr.lavacolour[0])<<16) | (int(chdr.lavacolour[1])<<8) | int(chdr.lavacolour[2]));
        SETVF(fullbright, 0);
        if(chdr.lerpsubdivsize || chdr.lerpangle) SETVF(lerpangle, chdr.lerpangle);
        if(chdr.lerpsubdivsize)
        {
            SETVF(lerpsubdiv, chdr.lerpsubdiv);
            SETVF(lerpsubdivsize, chdr.lerpsubdivsize);
        }
        SETVF(maptitle, chdr.maptitle);
        hdr.blendmap = chdr.blendmap;
        hdr.numvars = 0; 
        hdr.numvslots = 0;
    }
    else 
    {
        lilswap(&hdr.blendmap, 2);
        if(hdr.version <= 29) hdr.numvslots = 0;
        else lilswap(&hdr.numvslots, 1);
    }

    renderprogress(0, "clearing world...");

    freeocta(worldroot);
    worldroot = NULL;

    SETVFN(mapsize, hdr.worldsize);
    int worldscale = 0;
    while(1<<worldscale < hdr.worldsize) worldscale++;
    SETVFN(mapscale, worldscale);

    renderprogress(0, "loading vars...");

    loopi(hdr.numvars)
    {
        int type = f->getchar(), ilen = f->getlil<ushort>();
        string name;
        f->read(name, min(ilen, MAXSTRLEN-1));
        name[min(ilen, MAXSTRLEN-1)] = '\0';
        if(ilen >= MAXSTRLEN) f->seek(ilen - (MAXSTRLEN-1), SEEK_CUR);
        varsys::Variable *v = varsys::get(name);
        lua::Function tostring(lapi::state.get<lua::Object>("tostring"));
        lua::Function tonumber(lapi::state.get<lua::Object>("tonumber"));
        const char *str = NULL;
        string tmp;
        switch (type)
        {
            case varsys::TYPE_I: str = tostring.call<const char*>(f->getlil<int>()); break;
            case varsys::TYPE_F: str = tostring.call<const char*>(f->getlil<float>()); break;
            case varsys::TYPE_S:
            {
                int slen = f->getlil<ushort>();
                f->read(tmp, min(slen, MAXSTRLEN-1));
                tmp[min(slen, MAXSTRLEN-1)] = '\0';
                if(slen >= MAXSTRLEN) f->seek(slen - (MAXSTRLEN-1), SEEK_CUR);
                str = tostring.call<const char*>(tmp);
                break;
            }
            default: continue;
        }
        if (v && ((v->flags) & varsys::FLAG_OVERRIDE)) switch (v->type)
        {
            case varsys::TYPE_I:
            {
                int i = tonumber.call<int>(str);
                varsys::Int_Variable *iv = (varsys::Int_Variable*)v;
                if (iv->min_v <= iv->max_v && i >= iv->min_v && i <= iv->max_v)
                {
                    varsys::set((varsys::Variable*)iv, i, true, false);
                    if(dbgvars) conoutf(CON_DEBUG, "read var %s: %d", name, i);
                }
                break;
            }
 
            case varsys::TYPE_F:
            {
                float f = tonumber.call<float>(str);
                varsys::Float_Variable *fv = (varsys::Float_Variable*)v;
                if (fv->min_v <= fv->max_v && f >= fv->min_v && f <= fv->max_v)
                {
                    varsys::set((varsys::Variable*)fv, f, true, false);
                    if(dbgvars) conoutf(CON_DEBUG, "read var %s: %f", name, f);
                }
                break;
            }
    
            case varsys::TYPE_S:
            {
                varsys::set(v, str, true);
                if(dbgvars) conoutf(CON_DEBUG, "read svar %s: %s", name, str);
                break;
            }
        }
    }
    if(dbgvars) conoutf(CON_DEBUG, "read %d vars", hdr.numvars);

    string gametype;
    copystring(gametype, "fps");
    bool samegame = true;
    int eif = 0;
    if(hdr.version>=16)
    {
        int len = f->getchar();
        f->read(gametype, len+1);
    }
    if(strcmp(gametype, game::gameident())!=0)
    {
        samegame = false;
        conoutf(CON_WARN, "WARNING: loading map from %s game, ignoring entities except for lights/mapmodels", gametype);
    }
    if(hdr.version>=16)
    {
        eif = f->getlil<ushort>();
        int extrasize = f->getlil<ushort>();
        vector<char> extras;
        f->read(extras.pad(extrasize), extrasize);
        if(samegame) game::readgamedata(extras);
    }
    
    texmru.shrink(0);
    if(hdr.version<14)
    {
        uchar oldtl[256];
        f->read(oldtl, sizeof(oldtl));
        loopi(256) texmru.add(oldtl[i]);
    }
    else
    {
        ushort nummru = f->getlil<ushort>();
        loopi(nummru) texmru.add(f->getlil<ushort>());
    }

    renderprogress(0, "loading entities...");

    loopi(min(hdr.numents, MAXENTS))
    {
//        extentity &e = *(new extentity);
//        ents.add(&e);
        extentity e; // INTENSITY: Do *NOT* actually load entities from .ogz files - we use our own system.
                     // But, read the data from the file so we can move on (might be a sauer .ogz)
                     // So 'e' here is just a dummy

        f->read(&e, sizeof(entity));
        lilswap(&e.o.x, 3);
        lilswap(&e.attr1, 5);
        e.spawned = false;
        e.inoctanode = false;
        if(hdr.version <= 10 && e.type >= 7) e.type++;
        if(hdr.version <= 12 && e.type >= 8) e.type++;
        if(hdr.version <= 14 && e.type >= ET_MAPMODEL && e.type <= 16)
        {
            if(e.type == 16) e.type = ET_MAPMODEL;
            else e.type++;
        }
        if(hdr.version <= 20 && e.type >= ET_ENVMAP) e.type++;
        if(hdr.version <= 21 && e.type >= ET_PARTICLES) e.type++;
        if(hdr.version <= 22 && e.type >= ET_SOUND) e.type++;
        if(hdr.version <= 23 && e.type >= ET_SPOTLIGHT) e.type++;
        if(hdr.version <= 30 && (e.type == ET_MAPMODEL || e.type == ET_PLAYERSTART)) e.attr1 = (int(e.attr1)+180)%360;
        if (!samegame)
        {
            if(eif > 0) f->seek(eif, SEEK_CUR);
        }
        if(!insideworld(e.o))
        {
            if(e.type != ET_LIGHT && e.type != ET_SPOTLIGHT)
            {
                conoutf(CON_WARN, "warning: ent outside of world: enttype[%s] index %d (%f, %f, %f)", entities::getname(e.type), i, e.o.x, e.o.y, e.o.z);
            }
        }
        if(hdr.version <= 14 && e.type == ET_MAPMODEL)
        {
            e.o.z += e.attr3;
            if(e.attr4) conoutf(CON_WARN, "warning: mapmodel ent (index %d) uses texture slot %d", i, e.attr4);
            e.attr3 = e.attr4 = 0;
        }

        switch (e.type) // check if to write the entity
        {
            case ET_LIGHT:
            case ET_SPOTLIGHT:
            case ET_ENVMAP:
            case ET_PARTICLES:
            case ET_MAPMODEL:
            case ET_SOUND:
            case ET_PLAYERSTART:
            case 19: /* TELEPORT */
            case 20: /* TELEDEST */
            case 23: /* JUMPPAD */
                lapi::state.get<lua::Function>("LAPI", "World", "Entity", "add_sauer")(
                    (int)e.type, e.o.x, e.o.y, e.o.z, e.attr1, e.attr2, e.attr3, e.attr4, e.attr5
                );
                break;
            default:
                break;
        }
    }

    if(hdr.numents > MAXENTS) 
    {
        conoutf(CON_WARN, "warning: map has %d entities", hdr.numents);
        f->seek((hdr.numents-MAXENTS)*(samegame ? sizeof(entity) : eif), SEEK_CUR);
    }

    renderprogress(0, "loading slots...");
    loadvslots(f, hdr.numvslots);

    renderprogress(0, "loading octree...");
    bool failed = false;
    worldroot = loadchildren(f, ivec(0, 0, 0), hdr.worldsize>>1, failed);
    if(failed) conoutf(CON_ERROR, "garbage in map");

    renderprogress(0, "validating...");
    validatec(worldroot, hdr.worldsize>>1);

#ifdef CLIENT // INTENSITY: Server doesn't need lightmaps, pvs and blendmap (and current code for server wouldn't clean
              //            them up if we did read them, so would have a leak)
    if(!failed)
    {
        if(hdr.version >= 7) loopi(hdr.lightmaps)
        {
            int type = 0;
            if(hdr.version >= 17)
            {
                type = f->getchar();
                if(hdr.version >= 20 && type&0x80)
                {
                    f->getlil<ushort>();
                    f->getlil<ushort>();
                }
            }
            int bpp = 3;
            if(type&(1<<4) && (type&0x0F)!=2) bpp = 4;
            f->seek(bpp*512*512, SEEK_CUR);
        }

        if(hdr.version >= 25 && hdr.numpvs > 0) loadpvs(f, hdr.numpvs);
        if(hdr.version >= 28 && hdr.blendmap) loadblendmap(f, hdr.blendmap);
    }
#endif // INTENSITY

//    mapcrc = f->getcrc(); // INTENSITY: We use our own signatures
    delete f;

#ifdef CLIENT
    lapi::state.get<lua::Function>("external", "gui_clear")();
#endif

    varsys::overridevars = true;
    if (lapi::state.state())
    {
        lapi::state.do_file("data/cfg/default_map_settings.lua");
        world::run_mapscript();
    }
    varsys::overridevars = false;
   
#ifdef CLIENT // INTENSITY: Stop, finish loading later when we have all the entities
    renderprogress(0, "requesting entities...");
    logger::log(logger::DEBUG, "Requesting active entities...\r\n");
    MessageSystem::send_ActiveEntitiesRequest(ClientSystem::currScenarioCode.get_buf()); // Ask for the NPCs and other players, which are not part of the map proper
#else // SERVER
    logger::log(logger::DEBUG, "Finishing loading of the world...\r\n");
    finish_load_world();
#endif

    return true;
}

bool finish_load_world() // INTENSITY: Second half, after all entities received
{
    renderprogress(0, "finalizing world..."); // INTENSITY

    const char *mname = _saved_mname; // INTENSITY
    const char *cname = _saved_cname; // INTENSITY

    loadprogress = 0;

    game::preload();
#ifdef CLIENT
    flushpreloadedmodels();
#endif

    entitiesinoctanodes();
    attachentities();
    initlights();
    allchanged(true);

//    if(maptitle[0] && strcmp(maptitle, "Untitled Map by Unknown")) conoutf(CON_ECHO, "%s", maptitle); // INTENSITY

    startmap(cname ? cname : mname);
    
    logger::log(logger::DEBUG, "load_world complete.\r\n"); // INTENSITY
    world::loading = false; // INTENSITY

    printf("\r\n\r\n[[MAP LOADING]] - Success.\r\n"); // INTENSITY
#ifdef SERVER
    extern string homedir;
    defformatstring(path)("%s%s", homedir, SERVER_READYFILE);
    tools::fempty(path);
#endif

    return true;
}

void writeobj(char *name)
{
    defformatstring(fname)("%s.obj", name);
    stream *f = openfile(path(fname), "w"); 
    if(!f) return;
    f->printf("# obj file of Cube 2 level\n\n");
    defformatstring(mtlname)("%s.mtl", name);
    path(mtlname);
    f->printf("mtllib %s\n\n", mtlname); 
    extern vector<vtxarray *> valist;
    vector<vec> verts;
    vector<vec2> texcoords;
    hashtable<vec, int> shareverts(1<<16);
    hashtable<vec2, int> sharetc(1<<16);
    hashtable<int, vector<ivec> > mtls(1<<8);
    vector<int> usedmtl;
    vec bbmin(1e16f, 1e16f, 1e16f), bbmax(-1e16f, -1e16f, -1e16f);
    loopv(valist)
    {
        vtxarray &va = *valist[i];
        ushort *edata = NULL;
        uchar *vdata = NULL;
        if(!readva(&va, edata, vdata)) continue;
        int vtxsize = VTXSIZE;
        ushort *idx = edata;
        loopj(va.texs)
        {
            elementset &es = va.eslist[j];
            if(usedmtl.find(es.texture) < 0) usedmtl.add(es.texture);
            vector<ivec> &keys = mtls[es.texture];
            loopk(es.length)
            {
                int n = idx[k] - va.voffset;
                const vec &pos = ((const vertex *)&vdata[n*vtxsize])->pos;
                vec2 tc(((const vertex *)&vdata[n*vtxsize])->u, ((const vertex *)&vdata[n*vtxsize])->v);
                ivec &key = keys.add();
                key.x = shareverts.access(pos, verts.length());
                if(key.x == verts.length()) 
                {
                    verts.add(pos);
                    loopl(3)
                    {
                        bbmin[l] = min(bbmin[l], pos[l]);
                        bbmax[l] = max(bbmax[l], pos[l]);
                    }
                }
                key.y = sharetc.access(tc, texcoords.length());
                if(key.y == texcoords.length()) texcoords.add(tc);
            }
            idx += es.length;
        }
        delete[] edata;
        delete[] vdata;
    }

    vec center(-(bbmax.x + bbmin.x)/2, -(bbmax.y + bbmin.y)/2, -bbmin.z);
    loopv(verts)
    {
        vec v = verts[i];
        v.add(center);
        if(v.y != floor(v.y)) f->printf("v %.3f ", -v.y); else f->printf("v %d ", int(-v.y));
        if(v.z != floor(v.z)) f->printf("%.3f ", v.z); else f->printf("%d ", int(v.z));
        if(v.x != floor(v.x)) f->printf("%.3f\n", v.x); else f->printf("%d\n", int(v.x));
    } 
    f->printf("\n");
    loopv(texcoords)
    {
        const vec2 &tc = texcoords[i];
        f->printf("vt %.6f %.6f\n", tc.x, 1-tc.y);  
    }
    f->printf("\n");

    usedmtl.sort();
    loopv(usedmtl)
    {
        vector<ivec> &keys = mtls[usedmtl[i]];
        f->printf("g slot%d\n", usedmtl[i]);
        f->printf("usemtl slot%d\n\n", usedmtl[i]);
        for(int i = 0; i < keys.length(); i += 3)
        {
            f->printf("f");
            loopk(3) f->printf(" %d/%d", keys[i+2-k].x+1, keys[i+2-k].y+1);
            f->printf("\n");
        }
        f->printf("\n");
    }
    delete f;

    f = openfile(mtlname, "w");
    if(!f) return;
    f->printf("# mtl file of Cube 2 level\n\n");
    loopv(usedmtl)
    {
        VSlot &vslot = lookupvslot(usedmtl[i], false);
        f->printf("newmtl slot%d\n", usedmtl[i]);
        f->printf("map_Kd %s\n", vslot.slot->sts.empty() ? notexture->name : path(makerelpath("data", vslot.slot->sts[0].name)));
        f->printf("\n");
    } 
    delete f;
}
