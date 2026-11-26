-- Match the window corners to the Linear Carbon frame.
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
