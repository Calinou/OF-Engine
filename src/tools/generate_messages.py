
# Copyright 2010 Alon Zakai ('kripken'). All rights reserved.
# This file is part of Syntensity/the Intensity Engine, an open source project. See COPYING.txt for licensing.

"""
Automatic C++ code generator from template file. Generates message protocol
code in a safe, bug-free manner.

Processes messages.template into messages.h and messages.cpp.
"""

import os, stat


MESSAGE_TEMPLATE_FILE       = "intensity/messages.template"

GENERATED_MESSAGES_H_FILE     = "intensity/messages.h"
GENERATED_MESSAGES_CPP_FILE   = "intensity/messages.cpp"

COPYRIGHT_AND_LICENSE = """

// Copyright 2010 Alon Zakai ('kripken'). All rights reserved.
// This file is part of Syntensity/the Intensity Engine, an open source project. See COPYING.txt for licensing.

"""

def generate_messages():

    template_file        = open(MESSAGE_TEMPLATE_FILE,         'r')

    generated_h_file     = open(GENERATED_MESSAGES_H_FILE,     'w')
    generated_cpp_file   = open(GENERATED_MESSAGES_CPP_FILE,   'w')

    generated_h_file.write(COPYRIGHT_AND_LICENSE)
    generated_h_file.write("// Automatically generated from messages.template - DO NOT MODIFY THIS FILE!\n\n")

    generated_cpp_file.write(COPYRIGHT_AND_LICENSE)
    generated_cpp_file.write("// Automatically generated from messages.template - DO NOT MODIFY THIS FILE!\n\n")

    generated_cpp_file.write("""
#include "cube.h"
#include "engine.h"
#include "game.h"

#ifdef CLIENT
    #include "targeting.h"
#endif

#include "client_system.h"
#include "message_system.h"
#include "editing_system.h"
#include "world_system.h"
#include "network_system.h"
#include "of_world.h"
#include "of_tools.h"

using namespace lua;

/* Abuse generation from template for now */
void force_network_flush();
namespace server
{
    int& getUniqueId(int clientNumber);
    char*& getUsername(int clientNumber);
}

namespace MessageSystem
{
""")


    type_code = 1001 # The first message code, MUST be equal to INTENSITY_MSG_TYPE_MIN in message_system.h

    all_messages = []

    while True:
        line = template_file.readline()

        if line == '':
            break # We are done

        if line[0:2] == '//' or line == '\n':
            continue # This is a comment or blank line, ignore it

        if line[0] != ' ' and line[0:3] != 'end': # A new message

            name, direction        = line.split("(")
            direction              = direction[:-2]
            params                 = []
            send                   = ""
            receive                = ""
            curr_block             = ""
            implicit_client_number = False
            reliable               = True

            all_messages.append(name)

        elif line[:14] == '    unreliable':
            reliable = False
        elif line[:9] == '    send:':
            curr_block = 'send'
        elif line[:12] == '    receive:':
            curr_block = 'receive'
        elif line[:8] == '        ' or line == '\n': # Inside a send or receive block
            if curr_block == 'send':
                send    = send    + line
            else:
                receive = receive + line
        elif line[:3] == 'end':
            # Write out the finished message
            #

            # Generate param string (for sendf, and full - for parameters to send())
            param_string      = ''
            param_string_full = ''
            for param_type, param_name in params:
                if param_type == 'char*': param_type = 'const char*'
                param_string_full = param_string_full + param_type + " " + param_name + ", "
                if param_type == 'const char*':
                    param_string = param_string + 's'
                elif param_type in [ 'bool', 'int', 'float' ]:
                    if param_type != 'int' or param_name != 'clientNumber': # int clientNumber is implicit
                        param_string = param_string + 'i'
                else:
                    print "Error, invalid parameter type", param_type, ":", param_name
                    1/0.

            param_string_full = param_string_full[:-2] # Remove trailing ", "

            # Actual work
            if direction == "client->server":
                generated_h_file.write("""
// %s

struct %s : MessageType
{
    %s() : MessageType(%s, "%s") { };

#ifdef SERVER
    void receive(int receiver, int sender, ucharbuf &p);
#endif
};

void send_%s(%s);

""" % (name, name, name, type_code, name, name, param_string_full))
            elif direction == "server->client":
                generated_h_file.write("""
// %s

struct %s : MessageType
{
    %s() : MessageType(%s, "%s") { };

#ifdef CLIENT
    void receive(int receiver, int sender, ucharbuf &p);
#endif
};

void send_%s(%s);

""" % (name, name, name, type_code, name, name, param_string_full))
            elif direction in ["server->client,npc", "server->client,dummy"]:
                generated_h_file.write("""
// %s

struct %s : MessageType
{
    %s() : MessageType(%s, "%s") { };

    void receive(int receiver, int sender, ucharbuf &p);
};

void send_%s(%s);

""" % (name, name, name, type_code, name, name, param_string_full))
            else:
                print "Invalid direction: ", direction
                1/0.


            # Generate send

            if direction == "client->server":
                send = send + """
        logger::log(logger::DEBUG, "Sending a message of type %s (%s)\\r\\n");
        INDENT_LOG(logger::DEBUG);

        game::addmsg(%s, "%s%s", """ % (name, type_code, type_code, 'r' if reliable else '', param_string)
            else:
                if direction   == "server->client,npc":
                    dummy_server_string = "false"
                    all_npcs_string = "true"
                elif direction == "server->client,dummy":
                    dummy_server_string = "true"
                    all_npcs_string = "false"
                elif direction == "server->client":
                    dummy_server_string = "false"
                    all_npcs_string = "false"
                else:
                    print "Bad direction:", direction
                    1/0.
                
                send = """
        logger::log(logger::DEBUG, "Sending a message of type %s (%s)\\r\\n");
        INDENT_LOG(logger::DEBUG);

         %s

        int start, finish;
        if (clientNumber == -1)
        {
            // Send to all clients
            start  = 0;
            finish = getnumclients() - 1;
        } else {
            start  = clientNumber;
            finish = clientNumber;
        }

#ifdef SERVER
        int testUniqueId;
#endif
        for (clientNumber = start; clientNumber <= finish; clientNumber++)
        {
            if (clientNumber == exclude) continue;
#ifdef SERVER
            fpsent* fpsEntity = dynamic_cast<fpsent*>( game::getclient(clientNumber) );
            bool serverControlled = fpsEntity ? fpsEntity->serverControlled : false;

            testUniqueId = server::getUniqueId(clientNumber);
            if ( (!serverControlled && testUniqueId != DUMMY_SINGLETON_CLIENT_UNIQUE_ID) || // If a remote client, send even if negative (during login process)
                 (%s && testUniqueId == DUMMY_SINGLETON_CLIENT_UNIQUE_ID) || // If need to send to dummy server, send there
                 (%s && testUniqueId != DUMMY_SINGLETON_CLIENT_UNIQUE_ID && serverControlled) )  // If need to send to npcs, send there
#endif
            {
                #ifdef SERVER
                    logger::log(logger::DEBUG, "Sending to %%d (%%d) ((%%d))\\r\\n", clientNumber, testUniqueId, serverControlled);
                #endif
                sendf(clientNumber, MAIN_CHANNEL, "%si%s", %s, """ % (name, type_code, send, dummy_server_string, all_npcs_string, 'r' if reliable else '', param_string, type_code)

            for param_type, param_name in params:
                if implicit_client_number and param_type == 'int' and param_name == 'clientNumber':
                    continue

                pre_modifier = ""
                post_modifier = ""

                if param_type == "float":
                    pre_modifier = "int("
                    post_modifier = "*DMF)"
                send = send + "%s%s%s, " % (pre_modifier, param_name, post_modifier)
            send = send[:-2] + ");\n"

            if direction != "client->server":
                send = """
        int exclude = -1; // Set this to clientNumber to not send to
""" + send + """
            }
        }
"""

            # Generate receive

            temp_receive = ""
            for param_type, param_name in params:
                if param_type == 'int':
                    if implicit_client_number and param_name == 'clientNumber':
                        continue
                    temp_receive = temp_receive + "        int %s = getint(p);\n" % (param_name)
                elif param_type == 'float':
                    temp_receive = temp_receive + "        float %s = float(getint(p))/DMF;\n" % (param_name)
                elif param_type == 'bool':
                    temp_receive = temp_receive + "        bool %s = getint(p);\n" % (param_name)
                elif param_type == "char*":
                    temp_receive = temp_receive + """        static char %s[MAXTRANS];
        getstring(%s, p);
""" % (param_name, param_name)

            receive = '        logger::log(logger::DEBUG, "MessageSystem: Receiving a message of type %s (%s)\\r\\n");\n\n' % (name, type_code) + temp_receive + '\n' + receive;

            # Write out send and receive

            if direction == "client->server":
                generated_cpp_file.write("""
// %s

    void send_%s(%s)
    {%s    }

#ifdef SERVER
    void %s::receive(int receiver, int sender, ucharbuf &p)
    {
%s    }
#endif
""" % (name, name, param_string_full, send, name, receive))
            elif direction == "server->client":
                generated_cpp_file.write("""
// %s

    void send_%s(%s)
    {%s    }

#ifdef CLIENT
    void %s::receive(int receiver, int sender, ucharbuf &p)
    {
        bool is_npc;
        is_npc = false;
%s    }
#endif

""" % (name, name, param_string_full, send, name, receive))

            elif direction in ["server->client,npc", "server->client,dummy"]:
                generated_cpp_file.write("""
// %s

    void send_%s(%s)
    {%s    }

    void %s::receive(int receiver, int sender, ucharbuf &p)
    {
        bool is_npc;
#ifdef CLIENT
        is_npc = false;
#else // SERVER
        is_npc = true;
#endif
%s    }

""" % (name, name, param_string_full, send, name, receive))
            else:
                print "Invalid direction: ", direction
                1/0.

            #
            # Finished writing out the message

            # Increment the type code counter by one
            type_code += 1

        else: # Must be a parameter type, then
            line = line.strip()
            if line == "implicit clientNumber":
                line = "int clientNumber"
                implicit_client_number = True # Not sure if we need this
            elif line == "int clientNumber":
                print "Cannot have 'int clientNumber', this is used implicitly instead (see docs)"
            params.append(line.strip().split(' ')[0:2]) # type, name; ignore the comment

    # Generate code to register all messages

    generated_cpp_file.write("""
// Register all messages

void MessageManager::registerAll()
{""")

    for message in all_messages:
        generated_cpp_file.write("""
    registerMessageType( new %s() );""" % message)

    generated_cpp_file.write("""
}

}

""")

    generated_cpp_file.close()
    generated_h_file.close()
    template_file.close()


# Main

generate_messages()

'''
if os.stat(GENERATED_MESSAGES_H_FILE)[stat.ST_MTIME] < os.stat(MESSAGE_TEMPLATE_FILE)[stat.ST_MTIME]:
    print "\n    Generating messages:"
    try:
        generate_messages()
    except:
        print "Error in generating messages. Trying to 'touch' the template file so that it is processed next time, check this."
        import time
        time.sleep(0.1)
        os.utime(MESSAGE_TEMPLATE_FILE, None)
        raise
    else:
        print "    Finished generating messages\n"
else:
    print "Nothing to generate"
'''

