QuestDialog = {}

QuestDialog.open    = false
QuestDialog.lines   = {}     -- list of {speaker, line}
QuestDialog.index   = 1
QuestDialog.callback = nil
QuestDialog.showTime = 0

function QuestDialog:Open(lines, onComplete)
  self.lines    = lines
  self.index    = 1
  self.open     = true
  self.callback = onComplete
  self.showTime = 0.4
  GameState     = 2   -- reuse existing dialog game state
  MessageQueue:Clear()
end

function QuestDialog:Close()
  self.open  = false
  self.lines = {}
  self.index = 1
  GameState  = 1
  if self.callback then
    local cb       = self.callback
    self.callback  = nil
    cb()
  end
end

function QuestDialog:Update(dt)
  if not self.open then return end
  if self.showTime > 0 then
    self.showTime = self.showTime - dt
  end
end

function QuestDialog:Advance()
  if not self.open then return end
  if self.showTime > 0 then return end
  if self.index < #self.lines then
    self.index    = self.index + 1
    self.showTime = 0.4
  else
    self:Close()
  end
end

function QuestDialog:IsOpen() return self.open end

function QuestDialog:Draw()
  if not self.open then return end
  local turn = self.lines[self.index]
  if turn == nil then return end

  -- resolve speaker
  local speaker = turn.speaker or "?"
  if speaker == "PLAYER" then
    speaker = "John"
  else
    local def = NPCDefinitions[speaker]
    if def and def.displayName then speaker = def.displayName end
  end

  -- prompt only after the brief lockout
  local prompt = nil
  if self.showTime <= 0 then
    prompt = (self.index < #self.lines)
      and "PRESS ENTER TO CONTINUE"
      or  "PRESS ENTER TO CLOSE"
  end

  MessageBox:Draw(speaker, turn.line or "", prompt)
end