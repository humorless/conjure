-- [nfnl] fnl/conjure/nrepl-server.fnl
local _local_1_ = require("conjure.nfnl.module")
local autoload = _local_1_.autoload
local define = _local_1_.define
local bencode = autoload("conjure.remote.transport.bencode")
local repl_mod = autoload("conjure.nfnl.repl")
local fennel = autoload("conjure.nfnl.fennel")
local uuid = autoload("conjure.uuid")
local core = autoload("conjure.nfnl.core")
local str = autoload("conjure.nfnl.string")
local M = define("conjure.nrepl-server")
local uv = vim.uv
local state = {server = nil, ["port-file"] = nil}
local function write_port_file(port)
  local path = (vim.fn.getcwd() .. "/.nrepl-port")
  local f = io.open(path, "w")
  if f then
    f:write(tostring(port))
    f:close()
    state["port-file"] = path
  end
end
local function delete_port_file()
  if state["port-file"] then
    os.remove(state["port-file"])
    state["port-file"] = nil
  end
end
local function send(client, msg)
  return client:write(bencode.encode(msg))
end
local function new_session()
  local last_error = {}
  local repl_fn = repl_mod.new({
    ["on-error"] = function(err_type, err)
      last_error.msg = ("[" .. err_type .. "] " .. err)
    end,
  })
  return {repl = repl_fn, ["last-error"] = last_error}
end
local function handle_msg(client, sessions, msg)
  local op = msg["op"]
  local id = msg["id"]
  local session_id = msg["session"]
  local function reply(response)
    local r = vim.tbl_extend("force", response, {})
    if id then
      r["id"] = id
    end
    if session_id then
      r["session"] = session_id
    end
    return send(client, r)
  end
  local _2_ = op
  if (_2_ == "describe") then
    return reply({ops = {eval = {}, clone = {}, describe = {}, close = {}}, status = {"done"}})
  elseif (_2_ == "clone") then
    local new_id = uuid.v4()
    sessions[new_id] = new_session()
    return reply({["new-session"] = new_id, status = {"done"}})
  elseif (_2_ == "eval") then
    local code = msg["code"]
    local sess
    if (session_id and sessions[session_id]) then
      sess = sessions[session_id]
    else
      sess = new_session()
      if session_id then
        sessions[session_id] = sess
      end
    end
    local repl_fn = sess.repl
    local result = repl_fn((code .. "\n"))
    local err = sess["last-error"].msg
    sess["last-error"].msg = nil
    if err then
      return reply({ex = err, err = err, status = {"done", "eval-error"}})
    else
      local result_str
      if (result and (#result > 0)) then
        result_str = str.join("\n", core.map(fennel.view, result))
      else
        result_str = "nil"
      end
      return reply({value = result_str, ns = "user", status = {"done"}})
    end
  elseif (_2_ == "close") then
    if session_id then
      sessions[session_id] = nil
    end
    return reply({status = {"done"}})
  else
    return reply({status = {"done", "unknown-op"}})
  end
end
local function on_connect(server)
  local client = uv.new_tcp()
  local sessions = {}
  local dec_state = bencode.new()
  server:accept(client)
  return client:read_start(function(err, chunk)
    if err then
      return client:close()
    elseif chunk then
      local msgs = bencode["decode-all"](dec_state, chunk)
      return vim.schedule(function()
        for _, msg in ipairs(msgs) do
          handle_msg(client, sessions, msg)
        end
      end)
    else
      return client:close()
    end
  end)
end
M.start = function()
  if not state.server then
    local server = uv.new_tcp()
    server:bind("127.0.0.1", 0)
    local addr = server:getsockname()
    server:listen(128, function()
      return on_connect(server)
    end)
    state.server = server
    write_port_file(addr.port)
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        delete_port_file()
        if state.server then
          state.server:close()
          state.server = nil
        end
      end,
      once = true,
    })
  end
end
M.stop = function()
  delete_port_file()
  if state.server then
    state.server:close()
    state.server = nil
  end
end
return M
