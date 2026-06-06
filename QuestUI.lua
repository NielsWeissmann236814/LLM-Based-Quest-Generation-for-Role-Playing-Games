QuestUI = {}

QuestUI.expanded = false

function QuestUI:Toggle() self.expanded = not self.expanded end

function QuestUI:Draw()
  -- show a "generating" indicator while the next chapter is being made
  if QuestSystem:IsGenerating() and not QuestRunner:IsActive() then
    self:DrawGeneratingIndicator()
    return
  end

  if not QuestRunner:IsActive() then return end
  if not QuestRunner.panelVisible then return end

  local goals  = QuestRunner:GetGoals()
  local active = QuestRunner:GetCurrentIndex()

  if self.expanded then
    self:DrawExpanded(goals, active)
  else
    self:DrawCompact(goals, active)
  end
end

function QuestUI:DrawCompact(goals, active)
  local goal = goals[active]
  if goal == nil then return end

  local panelW   = 280
  local panelX   = BASE_WIDTH - panelW - 12
  local panelY   = 12
  local textW    = panelW - 20
  local lineH    = myfont:getHeight()

  -- measure how many lines the description wraps to at our text width
  local _, wrappedLines = myfont:getWrap(goal.description, textW)
  local nLines          = math.max(1, #wrappedLines)

  -- panel height: header (22) + wrapped text + footer space (22)
  local panelH = 22 + (nLines * lineH) + 22

  love.graphics.setColor(0.05, 0.05, 0.05, 0.85)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 5, 5)
  love.graphics.setColor(0.7, 0.6, 0.1)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 5, 5)

  -- header
  love.graphics.setFont(myfont2)
  love.graphics.setColor(0.7, 0.6, 0.1)
  love.graphics.print("CURRENT GOAL", panelX + 10, panelY + 6)

  -- description (wrapped)
  love.graphics.setFont(myfont)
  love.graphics.setColor(0.95, 0.95, 0.95)
  love.graphics.printf(goal.description, panelX + 10, panelY + 22, textW, "left")

  -- footer hint
  love.graphics.setFont(myfont2)
  love.graphics.setColor(0.5, 0.5, 0.5)
  love.graphics.print("[Tab] expand", panelX + panelW - 80, panelY + panelH - 16)

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end

function QuestUI:DrawExpanded(goals, active)
  local panelW = 380
  local panelX = BASE_WIDTH - panelW - 12
  local panelY = 12
  local lineH  = 22

  -- group goals by quest
  local quests       = {}
  local questByTitle = {}
  for i, goal in ipairs(goals) do
    local title = goal.questTitle or "Quest"
    local q = questByTitle[title]
    if q == nil then
      q = { title = title, goals = {}, indices = {} }
      questByTitle[title] = q
      table.insert(quests, q)
    end
    table.insert(q.goals, goal)
    table.insert(q.indices, i)
  end

  -- classify each quest
  for _, q in ipairs(quests) do
    local first = q.indices[1]
    local last  = q.indices[#q.indices]
    if active > last then
      q.status = "completed"
    elseif active >= first and active <= last then
      q.status = "current"
    else
      q.status = "upcoming"
    end
  end

  -- compute panel height
  local contentLines = 0
  for _, q in ipairs(quests) do
    if q.status == "completed" then
      contentLines = contentLines + 1
    elseif q.status == "current" then
      -- title + (completed + current goals) + maybe a "..." line
      local visibleGoals = 0
      local hasMore      = false
      for _, idx in ipairs(q.indices) do
        if idx <= active then
          visibleGoals = visibleGoals + 1
        else
          hasMore = true
        end
      end
      contentLines = contentLines + 1 + visibleGoals + (hasMore and 1 or 0)
    end
    -- upcoming quests: 0 lines
  end
  local panelH = 50 + (contentLines * lineH) + 12

  love.graphics.setColor(0.05, 0.05, 0.05, 0.92)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 5, 5)
  love.graphics.setColor(0.7, 0.6, 0.1)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 5, 5)

  -- chapter title
  love.graphics.setFont(myfont)
  love.graphics.setColor(0.85, 0.75, 0.2)
  local title = QuestRunner.chapter and QuestRunner.chapter.chapter_title or "Chapter"
  love.graphics.printf(title, panelX + 10, panelY + 8, panelW - 100, "left")

  love.graphics.setFont(myfont2)
  love.graphics.setColor(0.5, 0.5, 0.5)
  love.graphics.print("[Tab] collapse", panelX + panelW - 90, panelY + 12)

  love.graphics.setFont(myfont2)
  local y = panelY + 50
  for _, q in ipairs(quests) do
    if q.status == "completed" then
      love.graphics.setColor(0.35, 0.55, 0.35)
      love.graphics.print("[v] " .. q.title, panelX + 10, y)
      y = y + lineH

    elseif q.status == "current" then
      love.graphics.setColor(0.85, 0.75, 0.2)
      love.graphics.print("> " .. q.title, panelX + 10, y)
      y = y + lineH

      -- visible goals: completed + current
      local hasMore = false
      for j, goal in ipairs(q.goals) do
        local goalIdx = q.indices[j]
        if goalIdx < active then
          love.graphics.setColor(0.35, 0.55, 0.35)
          love.graphics.print("[v] " .. goal.description, panelX + 30, y)
          y = y + lineH
        elseif goalIdx == active then
          love.graphics.setColor(1, 0.85, 0.2)
          love.graphics.print("> " .. goal.description, panelX + 30, y)
          y = y + lineH
        else
          hasMore = true   -- there are future goals; we'll add one ??? below
        end
      end

      -- single hint that more goals follow
      if hasMore then
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.print("  ...", panelX + 30, y)
        y = y + lineH
      end
    end
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end

function QuestUI:DrawGeneratingIndicator()
  local panelW = 280
  local panelX = BASE_WIDTH - panelW - 12
  local panelY = 12
  local panelH = 50

  love.graphics.setColor(0.05, 0.05, 0.05, 0.85)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 5, 5)
  love.graphics.setColor(0.4, 0.4, 0.4)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 5, 5)

  love.graphics.setFont(myfont2)
  love.graphics.setColor(0.6, 0.6, 0.6)
  love.graphics.print("PREPARING NEXT CHAPTER", panelX + 10, panelY + 6)

  -- small inline progress bar
  local barW = panelW - 20
  local barH = 4
  local barX = panelX + 10
  local barY = panelY + 30

  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)

  local cycle    = (love.timer.getTime() % 1.6) / 1.6
  local triangle = 1 - math.abs(cycle * 2 - 1)
  local chunkW   = 50
  local chunkX   = barX + (barW - chunkW) * triangle
  love.graphics.setColor(0.85, 0.75, 0.2)
  love.graphics.rectangle("fill", chunkX, barY, chunkW, barH, 2, 2)

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end