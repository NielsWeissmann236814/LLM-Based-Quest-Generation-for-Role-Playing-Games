require "Debug"

print("[npc_worker] script starting")

local ok1, socket = pcall(require, "socket")
print("[npc_worker] require socket: " .. tostring(ok1))
if not ok1 then print("[npc_worker] error: " .. tostring(socket)); return end

local ok2, http = pcall(require, "socket.http")
print("[npc_worker] require socket.http: " .. tostring(ok2))
if not ok2 then print("[npc_worker] error: " .. tostring(http)); return end

local ok3, ltn12 = pcall(require, "ltn12")
print("[npc_worker] require ltn12: " .. tostring(ok3))
if not ok3 then print("[npc_worker] error: " .. tostring(ltn12)); return end

local ok4, json = pcall(require, "libs/dkjson")
print("[npc_worker] require dkjson: " .. tostring(ok4))
if not ok4 then print("[npc_worker] error: " .. tostring(json)); return end

print("[npc_worker] all modules loaded, entering job loop")

local jobs    = love.thread.getChannel("npc_jobs")
local results = love.thread.getChannel("npc_results")

while true do
  print("[npc_worker] waiting for job")
  local job = jobs:demand()
  print("[npc_worker] got job: " .. tostring(job))
  if job == "shutdown" then break end

  local ok, err = pcall(function()
    local jobID = job.jobID
    local url   = job.url
    local body  = job.body

    http.TIMEOUT = 350

    local chunks = {}
    local httpOk, code = http.request {
      url     = url,
      method  = "POST",
      headers = {
        ["Content-Type"]   = "application/json",
        ["Content-Length"] = tostring(#body)
      },
      source = ltn12.source.string(body),
      sink   = ltn12.sink.table(chunks)
    }

    local raw = table.concat(chunks)

    if not httpOk then
      results:push({ jobID = jobID, ok = false, error = "HTTP request failed: " .. tostring(code) })
    elseif code ~= 200 then
      results:push({ jobID = jobID, ok = false, error = "HTTP " .. tostring(code), response = raw })
    else
      local decoded, _, decodeErr = json.decode(raw)
      if decodeErr then
        results:push({ jobID = jobID, ok = false, error = "JSON decode failed: " .. decodeErr, raw = raw })
      else
        results:push({ jobID = jobID, ok = true, data = decoded })
      end
    end
  end)

  if not ok then
    results:push({ jobID = job.jobID or -1, ok = false, error = "worker exception: " .. tostring(err) })
  end
end

print("[npc_worker] exiting")