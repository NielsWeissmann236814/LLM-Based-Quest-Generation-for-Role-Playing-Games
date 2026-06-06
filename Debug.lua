-- Debug.lua
-- Replaces the global print() with a gated version. When DEBUG is false,
-- print() becomes a no-op. No code changes needed anywhere else.

DEBUG = false

local PrintDebug = print

function print(...)
  if DEBUG then
    PrintDebug(...)
  end
end