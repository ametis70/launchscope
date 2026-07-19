-- HTTP client for the launchscoped API.
-- All calls are synchronous. Localhost requests bypass API key auth.
--
-- The UI reads its own config (font, scale, background, mode) from disk
-- via lib/uiconfig.lua. This client only talks to the daemon (launchscoped)
-- for runtime operations: apps, launch/stop, audio, power.
--
-- Environment variables:
--   LAUNCHSCOPE_PORT=N     Server port (default 8765)

local http = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")
local json = require("lib.json")

local M = {}

local PORT = tonumber(os.getenv("LAUNCHSCOPE_PORT")) or 8765
local BASE = "http://127.0.0.1:" .. PORT

-- Short timeout so a down server doesn't freeze the UI thread.
http.TIMEOUT = 2

-- ── HTTP helpers ─────────────────────────────────────────────────────── --

local function request(method, path, payload)
	local body = payload and json.encode(payload) or ""
	local resp = {}
	local _, code = http.request({
		url = BASE .. path,
		method = method,
		headers = {
			["Content-Type"] = "application/json",
			["Content-Length"] = tostring(#body),
		},
		source = ltn12.source.string(body),
		sink = ltn12.sink.table(resp),
	})
	return table.concat(resp), code
end

function M.get(path)
	local body, code = request("GET", path)
	if code ~= 200 then
		return nil, ("GET " .. path .. " → " .. tostring(code))
	end
	local ok, result = pcall(json.decode, body)
	if not ok then
		return nil, ("JSON decode error: " .. tostring(result))
	end
	return result, nil
end

function M.post(path, payload)
	local body, code = request("POST", path, payload)
	if code == 200 or code == 202 then
		if #body > 0 then
			local ok, result = pcall(json.decode, body)
			if ok then
				return result, code
			end
		end
		return nil, code
	end
	return nil, code
end

-- ── Named shortcuts ───────────────────────────────────────────────────── --

function M.getApps()
	return M.get("/api/apps")
end
function M.getStatus()
	return M.get("/api/status")
end
function M.getConfig()
	return M.get("/api/config")
end

function M.launch(id)
	return M.post("/api/launch/" .. id)
end
function M.stop()
	return M.post("/api/stop")
end
function M.setVolume(delta)
	return M.post("/api/audio/volume", { delta = delta })
end
function M.setMute(toggle)
	return M.post("/api/audio/mute", { toggle = toggle })
end
function M.cecStandby()
	return M.post("/api/cec/standby")
end
function M.cecActivate()
	return M.post("/api/cec/activate")
end
function M.power(action)
	return M.post("/api/system/power", { action = action })
end

return M
