-- OctaForge scripting library version 1.0
-- Contains scripts compatible with OF API version 1.0

logging.log(logging.DEBUG, "Initializing library version %(1)s" % { library.current })

logging.log(logging.DEBUG, ":: Plugin system.")
library.include("plugins")

-- library.include("submodule.modulename")
