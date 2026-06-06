module ( "astar", package.seeall )

----------------------------------------------------------------
-- local variables
----------------------------------------------------------------

local INF = 1/0
local cachedPaths = nil

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------

-- Encode a tile (x, y) as a single integer key. Map sizes are well under
-- 10000 tiles per axis, so x * 10000 + y gives a unique key with no
-- string allocation. This replaces NodeToString and is used for all
-- per-node hash table lookups (g_score, f_score, came_from, closedset).
local function key(x, y)
  return x * 10000 + y
end

-- Manhattan distance: admissible and exact for 4-connected grids without
-- diagonals. Matches actual step cost (1 per move), so A* will expand the
-- minimum possible number of nodes for an optimal path.
local function heuristic(x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1
  if dx < 0 then dx = -dx end
  if dy < 0 then dy = -dy end
  return dx + dy
end

----------------------------------------------------------------
-- binary min-heap keyed on f_score
-- Stores { x, y, f } triples. Pop returns the lowest-f node.
----------------------------------------------------------------

local function heap_push(heap, x, y, f)
  local i = #heap + 1
  heap[i] = { x = x, y = y, f = f }
  -- sift up
  while i > 1 do
    local parent = math.floor(i / 2)
    if heap[parent].f > heap[i].f then
      heap[parent], heap[i] = heap[i], heap[parent]
      i = parent
    else
      break
    end
  end
end

local function heap_pop(heap)
  local n = #heap
  if n == 0 then return nil end
  local top = heap[1]
  if n == 1 then
    heap[1] = nil
    return top
  end
  heap[1] = heap[n]
  heap[n] = nil
  n = n - 1
  -- sift down
  local i = 1
  while true do
    local l = i * 2
    local r = l + 1
    local smallest = i
    if l <= n and heap[l].f < heap[smallest].f then smallest = l end
    if r <= n and heap[r].f < heap[smallest].f then smallest = r end
    if smallest == i then break end
    heap[i], heap[smallest] = heap[smallest], heap[i]
    i = smallest
  end
  return top
end

----------------------------------------------------------------
-- neighbor expansion
----------------------------------------------------------------

-- Returns up to 4 walkable neighbors. Writes into the provided buffer
-- (an array reused across calls) to avoid per-expansion allocation.
-- Returns the count of neighbors written.
local function neighbors(nodes, x, y, buf)
  local n = 0
  local t

  t = nodes:GetTile(x + 1, y)
  if t ~= nil and t.properties.obstacle == nil then
    n = n + 1
    buf[n] = buf[n] or {}
    buf[n].x = x + 1
    buf[n].y = y
  end

  t = nodes:GetTile(x - 1, y)
  if t ~= nil and t.properties.obstacle == nil then
    n = n + 1
    buf[n] = buf[n] or {}
    buf[n].x = x - 1
    buf[n].y = y
  end

  t = nodes:GetTile(x, y + 1)
  if t ~= nil and t.properties.obstacle == nil then
    n = n + 1
    buf[n] = buf[n] or {}
    buf[n].x = x
    buf[n].y = y + 1
  end

  t = nodes:GetTile(x, y - 1)
  if t ~= nil and t.properties.obstacle == nil then
    n = n + 1
    buf[n] = buf[n] or {}
    buf[n].x = x
    buf[n].y = y - 1
  end

  return n
end

----------------------------------------------------------------
-- A*
----------------------------------------------------------------

-- Reused neighbor buffer. A* is single-threaded and never recurses, so
-- one shared buffer across calls is fine and saves allocations.
local neighborBuf = { {}, {}, {}, {} }

local function a_star(start, goal, nodes)
  local sx, sy = start.x, start.y
  local gx, gy = goal.x,  goal.y

  -- early out: start == goal
  if sx == gx and sy == gy then
    return { { x = sx, y = sy } }
  end

  local openHeap   = {}
  local g_score    = {}
  local came_from  = {}
  local closedset  = {}
  -- track which nodes are currently in the open heap so we can skip
  -- stale entries when popped (lazy deletion instead of decrease-key)
  local openMember = {}

  local startKey = key(sx, sy)
  g_score[startKey] = 0
  heap_push(openHeap, sx, sy, heuristic(sx, sy, gx, gy))
  openMember[startKey] = true

  while #openHeap > 0 do
    local current = heap_pop(openHeap)
    local cx, cy  = current.x, current.y
    local cKey    = key(cx, cy)

    -- a node may appear in the heap multiple times if we found a better
    -- path to it after pushing the first entry. Skip stale entries.
    if not closedset[cKey] then
      if cx == gx and cy == gy then
        -- reconstruct path
        local path = {}
        local k = cKey
        local nx, ny = cx, cy
        while k ~= nil do
          table.insert(path, 1, { x = nx, y = ny })
          local prev = came_from[k]
          if prev == nil then break end
          nx, ny = prev.x, prev.y
          k = key(nx, ny)
          if k == startKey then
            table.insert(path, 1, { x = nx, y = ny })
            break
          end
        end
        return path
      end

      closedset[cKey] = true
      openMember[cKey] = nil

      local count = neighbors(nodes, cx, cy, neighborBuf)
      local cg = g_score[cKey]
      for i = 1, count do
        local nb  = neighborBuf[i]
        local nx  = nb.x
        local ny  = nb.y
        local nKey = key(nx, ny)

        if not closedset[nKey] then
          local tentative_g = cg + 1   -- 4-connected, uniform step cost
          local existing_g  = g_score[nKey]
          if existing_g == nil or tentative_g < existing_g then
            came_from[nKey] = { x = cx, y = cy }
            g_score[nKey]   = tentative_g
            local f = tentative_g + heuristic(nx, ny, gx, gy)
            heap_push(openHeap, nx, ny, f)
            openMember[nKey] = true
          end
        end
      end
    end
  end

  return nil
end

----------------------------------------------------------------
-- exposed functions (unchanged API)
----------------------------------------------------------------

function clear_cached_paths ()
  cachedPaths = nil
end

function distance ( x1, y1, x2, y2 )
  -- preserved for any external caller; uses the original Euclidean form
  return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
end

function path ( start, goal, nodes, ignore_cache)
  if not cachedPaths then cachedPaths = {} end
  local sk = key(start.x, start.y)
  local gk = key(goal.x,  goal.y)
  if not cachedPaths[sk] then
    cachedPaths[sk] = {}
  elseif cachedPaths[sk][gk] and not ignore_cache then
    return cachedPaths[sk][gk]
  end
  return a_star(start, goal, nodes)
end