
// Copyright 2010 Alon Zakai ('kripken'). All rights reserved.
// This file is part of Syntensity/the Intensity Engine, an open source project. See COPYING.txt for licensing.

#include "cube.h"
#include "engine.h"
#include "game.h"

#include "message_system.h"

#include "world_system.h"
#include "editing_system.h"
#include "client_engine_additions.h"
#include "targeting.h"

#include "client_system.h"
#include "of_world.h"

using namespace lua;

std::string ClientSystem::blankPassword = "1111111111"; // TODO: We should ensure the users can never have this for a real password!
                                                        // Note: Sending CEGUI characters that are invalid to enter in the field might
                                                        // seem like a nice solution here, but CEGUI has issues with that

int            ClientSystem::playerNumber       = -1;
CLogicEntity  *ClientSystem::playerLogicEntity  = NULL;
bool           ClientSystem::loggedIn           = false;
bool           ClientSystem::editingAlone       = false;
int            ClientSystem::uniqueId           = -1;
std::string    ClientSystem::currMap            = "";
std::string ClientSystem::currTransactionCode = "MISSING_TRANSACTION_CODE";
std::string ClientSystem::currHost = "";
int ClientSystem::currPort = -1;
std::string ClientSystem::currScenarioCode = "";

bool _scenarioStarted = false;
bool _mapCompletelyReceived = false;


#define USER_INFO_SECTION "UserInfo"
#define VIDEO_SECTION "Video"

std::string ClientSystem::getUsername()
{
    return "DUMMY_USERNAME";
}

std::string ClientSystem::getHashedPassword()
{
    return "DUMMY_HASH";
}

std::string ClientSystem::getVisualPassword()
{
    if (getHashedPassword() != "")
        return blankPassword; // Visually, we show just 8 or so letters, not the entire hash of course
    else
        return "";
}

void ClientSystem::connect(std::string host, int port)
{
    editingAlone = false;

    currHost = host;
    currPort = port;

    connectserv((char *)host.c_str(), port, "");
}

void ClientSystem::login(int clientNumber)
{
    Logging::log(Logging::DEBUG, "ClientSystem::login()\r\n");

    playerNumber = clientNumber;

    MessageSystem::send_LoginRequest(currTransactionCode.c_str());
}

void ClientSystem::finishLogin(bool local)
{
    editingAlone = local;
    loggedIn = true;

    Logging::log(Logging::DEBUG, "Now logged in, with unique_ID: %d\r\n", uniqueId);
}

void ClientSystem::doDisconnect()
{
    disconnect();
}

void ClientSystem::onDisconnect()
{
    editingAlone = false;
    playerNumber = -1;
    loggedIn     = false;
    _scenarioStarted  = false;
    _mapCompletelyReceived = false;

    // it's also useful to stop all mapsounds and gamesounds (but only for client that disconnects!)
    stopsounds();

    LogicSystem::clear();
}

void ClientSystem::sendSavedMap()
{
    assert(0); // Deprecated
}

/*
bool ClientSystem::mapCompletelyReceived()
{
    return _mapCompletelyReceived;
}
*/

bool ClientSystem::scenarioStarted()
{
    if (!_mapCompletelyReceived)
        Logging::log(Logging::INFO, "Map not completely received, so scenario not started\r\n");

    // If not already started, test if indeed started
    if (_mapCompletelyReceived && !_scenarioStarted)
    {
        if (engine.hashandle())
        {
            engine.getg("entity_store").t_getraw("test_scenario_started").call(0, 1);
            _scenarioStarted = engine.get<bool>(-1);
            engine.pop(2);
        }
    }

    return _mapCompletelyReceived && _scenarioStarted;
}

void ClientSystem::frameTrigger(int curtime)
{
    if (scenarioStarted())
    {
        PlayerControl::handleExtraPlayerMovements(curtime);
        TargetingControl::determineMouseTarget();
        SETV(can_edit, int(isAdmin()));
        dobgload();
    }

    ClientSystem::cleanupHUD();
}

void ClientSystem::gotoLoginScreen()
{
    assert(0);
}

void setTransactionCode(std::string code)
{
    ClientSystem::currTransactionCode = code;
}

//
// HUD
//

struct queuedHUDRect
{
    float x1, y1, x2, y2;
    int color;
    float alpha;
};

std::vector<queuedHUDRect> queuedHUDRects;

void ClientSystem::addHUDRect(float x1, float y1, float x2, float y2, int color, float alpha)
{
    queuedHUDRect q;
    q.x1 = x1;
    q.y1 = y1;
    q.x2 = x2;
    q.y2 = y2;
    q.color = color;
    q.alpha = alpha;
    queuedHUDRects.push_back(q);
}

struct queuedHUDImage
{
    std::string tex;
    float centerX, centerY; //!< In relative coordinates (to each axis, the center of where to draw the HUD
//    float widthInX, heightInY; //!< In axis-relative coordinates, how big the HUD should be.
//                               //!< E.g. widthInX 0.5 means its width is half of the X dimension
    float width, height;
    int color;
    float alpha;

    queuedHUDImage()
    {
        tex = "";
        centerX = 0.5; centerY = 0.5;
//        widthInX = 0; heightInY = 0;
        width = 0.61803399; height = 0.61803399;
        color = 0xFFFFFF, alpha = 1.0;
    }
};

std::vector<queuedHUDImage> queuedHUDImages;

void ClientSystem::addHUDImage(std::string tex, float centerX, float centerY, float width, float height, int color, float alpha)
{
    queuedHUDImage q;
    q.tex = tex;
    q.centerX = centerX;
    q.centerY = centerY;
    q.width = width;
    q.height = height;
    q.color = color;
    q.alpha = alpha;
    queuedHUDImages.push_back(q);
}

struct queuedHUDText
{
    std::string text;
    float x, y, scale;
    int color;
};

std::vector<queuedHUDText> queuedHUDTexts;

void ClientSystem::addHUDText(std::string text, float x, float y, float scale, int color)
{
    queuedHUDText q;
    q.text = text;
    q.x = x;
    q.y = y;
    q.scale = scale;
    q.color = color;
    queuedHUDTexts.push_back(q);
}

void ClientSystem::drawHUD(int w, int h)
{
    if (g3d_windowhit(true, false)) return; // Showing sauer GUI - do not show HUD

    float wFactor = float(h)/max(w,h);
    float hFactor = float(w)/max(w,h);

    // Rects

    glPushMatrix();
    glScalef(w, h, 1);

    for (unsigned int i = 0; i < queuedHUDRects.size(); i++)
    {
        queuedHUDRect& q = queuedHUDRects[i];
        if (q.x2 < 0)
        {
            float x1 = q.x1, y1 = q.y1;
            q.x1 = x1 - wFactor*fabs(q.x2)/2;
            q.y1 = y1 - hFactor*fabs(q.y2)/2;
            q.x2 = x1 + wFactor*fabs(q.x2)/2;
            q.y2 = y1 + hFactor*fabs(q.y2)/2;
        }

        vec rgb(q.color>>16, (q.color>>8)&0xFF, q.color&0xFF);
        rgb.mul(1.0/256.0);

        glColor4f(rgb[0], rgb[1], rgb[2], q.alpha);

        glDisable(GL_TEXTURE_2D);
        notextureshader->set();
        glBegin(GL_TRIANGLE_STRIP);
        glVertex2f(q.x1, q.y1);
        glVertex2f(q.x2, q.y1);
        glVertex2f(q.x1, q.y2);
        glVertex2f(q.x2, q.y2);
        glEnd();
        glEnable(GL_TEXTURE_2D);
        defaultshader->set();    
    }

    glPopMatrix();

    // Images

    glPushMatrix();
    glScalef(w, h, 1);

    for (unsigned int i = 0; i < queuedHUDImages.size(); i++)
    {
        queuedHUDImage& q = queuedHUDImages[i];
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        float x1 = q.centerX - (wFactor*q.width/2);
        float y1 = q.centerY - (hFactor*q.height/2);
        float x2 = q.centerX + (wFactor*q.width/2);
        float y2 = q.centerY + (hFactor*q.height/2);
        vec rgb(q.color>>16, (q.color>>8)&0xFF, q.color&0xFF);
        rgb.mul(1.0/256.0);

        glColor4f(rgb[0], rgb[1], rgb[2], q.alpha);
        settexture(q.tex.c_str(), 3);
        glBegin(GL_TRIANGLE_STRIP);
            glTexCoord2f(0.0f, 0.0f); glVertex2f(x1, y1);
            glTexCoord2f(1.0f, 0.0f); glVertex2f(x2, y1);
            glTexCoord2f(0.0f, 1.0f); glVertex2f(x1, y2);
            glTexCoord2f(1.0f, 1.0f); glVertex2f(x2, y2);
        glEnd();
    }

    glPopMatrix();

    // Texts

    for (unsigned int i = 0; i < queuedHUDTexts.size(); i++)
    {
        queuedHUDText& q = queuedHUDTexts[i];

        glPushMatrix();
        glScalef(q.scale, q.scale, 1);

        int b = q.color & 255;
        q.color = q.color >> 8;
        int g = q.color & 255;
        int r = q.color >> 8;

        draw_text(q.text.c_str(), w*q.x/q.scale - text_width(q.text.c_str())/2, h*q.y/q.scale - FONTH/2, r, g, b);

        glPopMatrix();
    }
}

void ClientSystem::drawMinimap(int w, int h)
{
    if (g3d_windowhit(true, false)) return; // Showing sauer GUI - do not show minimap

    float x, y;
    vec dir, pos;

    glPushMatrix();
    glScalef(h / 1000.0f, h / 1000.0f, 1); // we don't want the screen width

    // if we want it aligned to right, we need to move stuff through screen .. if not, we just set the x position value
    if (GETIV(minimaprightalign))
        x = (1000 * w) / h - GETFV(minimapradius) * 1000 - GETFV(minimapxpos) * 1000;
    else
        x = GETFV(minimapxpos) * 1000;

    y = GETFV(minimapypos) * 1000;
    glColor3f(1, 1, 1);

    glDisable(GL_BLEND);
    bindminimap();
    pos = vec(game::hudplayer()->o).sub(minimapcenter).mul(minimapscale).add(0.5f); // hudplayer, because we want minimap also when following someone.

    vecfromyawpitch(camera1->yaw, 0, 1, 0, dir);
    float scale = clamp(max(minimapradius.x, minimapradius.y) / 3, (GETIV(forceminminimapzoom) < 0) ? float(GETIV(minminimapzoom)) : float(GETIV(forceminminimapzoom)), (GETIV(forcemaxminimapzoom) < 0) ? float(GETIV(maxminimapzoom)) : float(GETIV(forcemaxminimapzoom)));

    glBegin(GL_TRIANGLE_FAN);

    loopi(GETIV(minimapsides)) // create a triangle for every side, together it makes triangle when minimapsides is 3, square when it's 4 and "circle" for any other value.
    {
        // this part manages texture
        vec tc = vec(dir).rotate_around_z((i / float(GETIV(minimapsides))) * 2 * M_PI);

        if (GETFV(minimaprotation) > 0) // rotate the minimap if we want to rotate it, if not, just skip this
            tc.rotate_around_z(GETFV(minimaprotation) * (M_PI / 180.0f));

        glTexCoord2f(pos.x + (tc.x * scale * minimapscale.x),
                     pos.y + (tc.y * scale * minimapscale.y));

        // this part actually creates the triangle which is the texture bind to
        vec v = vec(0, -1, 0).rotate_around_z((i / float(GETIV(minimapsides))) * 2 * M_PI);

        if (GETFV(minimaprotation) > 0)
            v.rotate_around_z(GETFV(minimaprotation) * (M_PI / 180.0f));

        glVertex2f(x + 500 * GETFV(minimapradius) * (1.0f + v.x),
                   y + 500 * GETFV(minimapradius) * (1.0f + v.y));
    }

    glEnd();
    glEnable(GL_BLEND);

    glPopMatrix();
}

void ClientSystem::cleanupHUD()
{
    queuedHUDRects.clear();
    queuedHUDImages.clear();
    queuedHUDTexts.clear();
}

int get_escape()
{
    return SDLK_ESCAPE;
}

void ClientSystem::finishLoadWorld()
{
    extern bool finish_load_world();
    finish_load_world();

    _mapCompletelyReceived = true; // We have the original map + static entities (still, scenarioStarted might want more stuff)

    EditingSystem::madeChanges = false; // Clean the slate

    ClientSystem::editingAlone = false; // Assume not in this mode

    SETV(mainmenu, 0); // (see prepareForMap)
}

void ClientSystem::prepareForNewScenario(std::string scenarioCode)
{
    _mapCompletelyReceived = false; // We no longer have a map. This implies scenarioStarted will return false, thus
                                    // stopping sending of position updates, as well as rendering

    SETV(mainmenu, 1); // Keep showing GUI meanwhile (in particular, to show the message about a new map on the way

    // Clear the logic system, as it is no longer valid - were it running, we might try to process messages from
    // the new map being set up on the server, even though they are irrelevant to the existing engine, set up for
    // another map with its Classes etc.
    LogicSystem::clear();

    currScenarioCode = scenarioCode;
}

void ClientSystem::handleConfigSettings()
{
    assert(0);
}

bool ClientSystem::isAdmin()
{
    bool isAdmin = false;
    if (!loggedIn) return isAdmin;
    if (!playerLogicEntity) return isAdmin;

    engine.getref(playerLogicEntity->luaRef);
    isAdmin = engine.t_get<bool>("_can_edit");
    engine.pop(1);

    return isAdmin;
}

