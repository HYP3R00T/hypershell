-- Match the window corners to the Carbon frame.
local active_border = "#666666"
local inactive_border = "#393939"
local colors = io.open(os.getenv("HOME") .. "/.local/state/omarchy/current/theme/colors.toml", "r")
if colors then
  for line in colors:lines() do
    local key, color = line:match('^%s*(hyprland_%a+_border)%s*=%s*"(#%x%x%x%x%x%x)"')
    if key == "hyprland_active_border" then
      active_border = color
    elseif key == "hyprland_inactive_border" then
      inactive_border = color
    end
  end
  colors:close()
end

hl.config({
  general = {
    gaps_in = 2,
    -- The sides include the 5 px bezel. The panels reserve the top and bottom.
    gaps_out = { top = 5, right = 10, bottom = 5, left = 10 },
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },
  decoration = { rounding = 8 },
  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },
})

-- Omarchy loads its no-gaps flag after the theme. Keep the bezel clear
-- when the flag removes all window gaps. The panels reserve top and bottom.
hl.on("config.reloaded", function()
  local no_gaps = io.open(os.getenv("HOME") .. "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua", "r")
  if not no_gaps then return end
  no_gaps:close()

  hl.config({
    general = {
      gaps_out = { top = 0, right = 5, bottom = 0, left = 5 },
    },
  })
end)

-- Remove the backdrop dim only while the Quake console is open.
local console = "special:qconsole"
local standard_dim = hl.get_config("decoration.dim_special")
local console_visible = false
local styled_agents = {}

local function update_console()
  local workspace = hl.get_workspace(console)
  local visible = workspace ~= nil and workspace.visible == true
  if visible ~= console_visible then
    hl.config({ decoration = { dim_special = visible and 0 or standard_dim } })
    console_visible = visible
  end

  local agents = {}
  if visible then
    for _, window in ipairs(hl.get_workspace_windows(console)) do
      if window.class == "org.omarchy.agent" and window.pid and window.pid > 0 then
        agents[window.pid] = true
      end
    end
  end

  local command = 'data="$HOME/.config/omarchy/themes/carbon/notch/notch-data.py"; '
    .. '[ -f "$data" ] || data="$HOME/.config/omarchy/themes/linear-carbon/notch/notch-data.py"; '
    .. 'python3 "$data" quake-color'
  local changed = false
  for pid in pairs(styled_agents) do
    if not agents[pid] then
      command = command .. " " .. pid
      changed = true
    end
  end
  for pid in pairs(agents) do
    if not styled_agents[pid] then
      command = command .. " " .. pid
      changed = true
    end
  end
  styled_agents = agents
  if changed then hl.exec_cmd(command) end
end

hl.on("workspace.special_active", update_console)
hl.on("window.open", update_console)
hl.on("window.move_to_workspace", update_console)
update_console()
