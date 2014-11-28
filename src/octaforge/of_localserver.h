/*
 * of_localserver.h, version 1
 * Local server handler for OctaForge (header)
 *
 * author: q66 <quaker66@gmail.com>
 * license: see COPYING.txt
 */

#ifndef OF_LOCALSTANDALONE_H
#define OF_LOCALSTANDALONE_H

namespace local_server
{
    bool is_running();
    void try_connect();
    void run(const char *map);
    void stop();
} /* end namespace local_server */

#define STANDALONE_READYFILE "STANDALONE_READY"

#endif
