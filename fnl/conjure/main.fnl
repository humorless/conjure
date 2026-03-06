(local {: autoload : define} (require :conjure.nfnl.module))
(local mapping (autoload :conjure.mapping))
(local config (autoload :conjure.config))
(local log (autoload :conjure.log))
(local nrepl-server (autoload :conjure.nrepl-server))

(local M (define :conjure.main))

(fn M.main []
  (mapping.init (config.filetypes))
  (log.setup-auto-flush)
  (vim.api.nvim_create_user_command
    :ConjureNreplServer
    (fn [opts]
      (if (= opts.args :stop)
        (nrepl-server.stop)
        (nrepl-server.start)))
    {:nargs "?"
     :complete (fn [] ["stop"])
     :desc "Start (or stop) the embedded Fennel nREPL server"}))

M
