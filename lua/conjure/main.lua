-- [nfnl] fnl/conjure/main.fnl
local _local_1_ = require("conjure.nfnl.module")
local autoload = _local_1_.autoload
local define = _local_1_.define
local mapping = autoload("conjure.mapping")
local config = autoload("conjure.config")
local log = autoload("conjure.log")
local nrepl_server = autoload("conjure.nrepl-server")
local M = define("conjure.main")
M.main = function()
  mapping.init(config.filetypes())
  log["setup-auto-flush"]()
  return vim.api.nvim_create_user_command("ConjureNreplServer", function(opts)
    if (opts.args == "stop") then
      return nrepl_server.stop()
    else
      return nrepl_server.start()
    end
  end, {
    nargs = "?",
    complete = function() return {"stop"} end,
    desc = "Start (or stop) the embedded Fennel nREPL server",
  })
end
return M
