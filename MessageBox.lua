-- Shared styled panel renderer for dialog turns, game messages,
-- and any future text-popup UI. Pure draw helper, no state.

MessageBox = {}

-- draws a panel anchored to the bottom of the screen.
-- params:
--   speaker: optional string (nil for plain messages)
--   text:    main body, may wrap
--   prompt:  optional string shown bottom-right (e.g. "PRESS ENTER")
--   width:   panel width (default 600)
function MessageBox:Draw(speaker, text, prompt, width)
  local panelW    = width or 600
  local sidePad   = 20
  local topPad    = 12
  local namePad   = 8
  local promptPad = 10
  local panelX    = (BASE_WIDTH / 2) - (panelW / 2)
  local textW     = panelW - (sidePad * 2)

  -- measure
  local nameH = speaker and myfont:getHeight() or 0
  local _, wrappedLines = myfont:getWrap(text or "", textW)
  local linesH = math.max(1, #wrappedLines) * myfont:getHeight()
  local promptH = prompt and myfont2:getHeight() or myfont2:getHeight()

  local panelH = topPad + nameH
  if speaker then panelH = panelH + namePad + promptPad + promptH end
  panelH = panelH + linesH
  --if prompt then panelH = panelH + promptPad + promptH end
  panelH = panelH + topPad

  local panelY = BASE_HEIGHT - panelH - 12

  -- panel background
  love.graphics.setColor(0.05, 0.05, 0.05, 0.92)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
  love.graphics.setColor(0.4, 0.4, 0.4)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

  local cursorY = panelY + topPad

  -- speaker
  if speaker then
    love.graphics.setFont(myfont)
    love.graphics.setColor(0.85, 0.7, 0.2)
    love.graphics.print(speaker, panelX + sidePad, cursorY)
    cursorY = cursorY + nameH + namePad
  end

  -- body text
  love.graphics.setFont(myfont)
  love.graphics.setColor(0.95, 0.95, 0.95)
  love.graphics.printf(text or "", panelX + sidePad, cursorY, textW, "left")

  -- prompt
  if prompt then
    love.graphics.setFont(myfont2)
    love.graphics.setColor(0.85, 0.3, 0.3)
    local promptW = myfont2:getWidth(prompt)
    love.graphics.print(prompt,
      panelX + panelW - promptW - sidePad,
      panelY + panelH - topPad - promptH)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end