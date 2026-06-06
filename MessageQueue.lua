-- Centralized queue for player-facing messages. Replaces direct writes to
-- GameMessage / GameMessageTime so messages from different systems queue
-- behind each other instead of overwriting.

MessageQueue = {}

MessageQueue.queue = {}
MessageQueue.timer = 0   -- countdown until next message can show

-- push a message onto the queue. plays after any pending messages.
--   text:     string to display
--   duration: how long to display it (default 3)
--   delay:    extra gap after this message before the next (default 0)
function MessageQueue:Push(text, duration, delay, onShow)
  table.insert(self.queue, {
    text     = text,
    duration = duration or 3,
    delay    = delay    or 0,
    onShow   = onShow
  })
end

-- show a message immediately, clearing any queued messages.
-- use sparingly — only for things that genuinely supersede everything else
-- (game over, critical errors).
function MessageQueue:Replace(text, duration)
  self.queue = {}
  GameMessage     = text
  GameMessageTime = duration or 3
  self.timer      = duration or 3
end

function MessageQueue:Clear()
  self.queue      = {}
  GameMessage     = ""
  GameMessageTime = 0
  self.timer      = 0
end

function MessageQueue:Update(dt)
  if self.timer > 0 then
    self.timer = self.timer - dt
    return
  end
  if GameMessageTime > 0 then return end
  if #self.queue == 0 then return end

  local msg = table.remove(self.queue, 1)
  GameMessage     = msg.text
  GameMessageTime = msg.duration
  self.timer      = msg.duration + msg.delay

  if msg.onShow then msg.onShow() end
end