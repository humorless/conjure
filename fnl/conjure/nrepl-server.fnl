(local {: autoload : define} (require :conjure.nfnl.module))
(local bencode (autoload :conjure.remote.transport.bencode))
(local repl-mod (autoload :conjure.nfnl.repl))
(local fennel (autoload :conjure.nfnl.fennel))
(local uuid (autoload :conjure.uuid))
(local core (autoload :conjure.nfnl.core))
(local str (autoload :conjure.nfnl.string))

(local M (define :conjure.nrepl-server))

(local uv vim.uv)
(local state {:server nil :port-file nil})

(fn write-port-file [port]
  (let [path (.. (vim.fn.getcwd) "/.nrepl-port")
        f (io.open path :w)]
    (when f
      (f:write (tostring port))
      (f:close)
      (set state.port-file path))))

(fn delete-port-file []
  (when state.port-file
    (os.remove state.port-file)
    (set state.port-file nil)))

(fn send [client msg]
  (client:write (bencode.encode msg)))

(fn new-session []
  (let [last-error {}
        repl-fn (repl-mod.new
                  {:on-error (fn [err-type err]
                               (tset last-error :msg (.. "[" err-type "] " err)))})]
    {:repl repl-fn :last-error last-error}))

(fn handle-msg [client sessions msg]
  (let [op (. msg :op)
        id (. msg :id)
        session-id (. msg :session)]
    (fn reply [response]
      (let [r (vim.tbl_extend :force response {})]
        (when id (tset r :id id))
        (when session-id (tset r :session session-id))
        (send client r)))
    (match op
      :describe
      (reply {:ops {:eval {} :clone {} :describe {} :close {}}
              :status ["done"]})

      :clone
      (let [new-id (uuid.v4)]
        (tset sessions new-id (new-session))
        (reply {:new-session new-id :status ["done"]}))

      :eval
      (let [code (. msg :code)
            sess (or (and session-id (. sessions session-id))
                     (let [s (new-session)]
                       (when session-id (tset sessions session-id s))
                       s))
            repl-fn (. sess :repl)
            result (repl-fn (.. code "\n"))
            err (. sess :last-error :msg)]
        (tset (. sess :last-error) :msg nil)
        (if err
          (reply {:ex err :err err :status ["done" "eval-error"]})
          (let [result-str (if (and result (> (length result) 0))
                             (str.join "\n" (core.map fennel.view result))
                             "nil")]
            (reply {:value result-str :ns "user" :status ["done"]}))))

      :close
      (do
        (when session-id (tset sessions session-id nil))
        (reply {:status ["done"]}))

      _
      (reply {:status ["done" "unknown-op"]}))))

(fn on-connect [server]
  (let [client (uv.new_tcp)
        sessions {}
        dec-state (bencode.new)]
    (server:accept client)
    (client:read_start
      (fn [err chunk]
        (if err
          (client:close)
          chunk
          (let [msgs (bencode.decode-all dec-state chunk)]
            (vim.schedule
              #(each [_ msg (ipairs msgs)]
                 (handle-msg client sessions msg))))
          (client:close))))))

(fn M.start []
  (when (not state.server)
    (let [server (uv.new_tcp)]
      (server:bind "127.0.0.1" 0)
      (let [addr (server:getsockname)]
        (server:listen 128 #(on-connect server))
        (set state.server server)
        (write-port-file addr.port)
        (vim.api.nvim_create_autocmd
          :VimLeavePre
          {:callback #(do
                        (delete-port-file)
                        (when state.server
                          (state.server:close)
                          (set state.server nil)))
           :once true})))))

(fn M.stop []
  (delete-port-file)
  (when state.server
    (state.server:close)
    (set state.server nil)))

M
