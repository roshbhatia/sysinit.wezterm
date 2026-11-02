local M = {}

local ADJECTIVES = {
  "amber",
  "brisk",
  "calm",
  "clever",
  "cobalt",
  "cool",
  "crisp",
  "curious",
  "daring",
  "eager",
  "even",
  "fierce",
  "gentle",
  "golden",
  "hidden",
  "keen",
  "lively",
  "lucid",
  "mellow",
  "nimble",
  "quiet",
  "ready",
  "resilient",
  "steady",
  "swift",
  "vivid",
  "warm",
  "wild",
  "wise",
  "zealous",
}

local NOUNS = {
  "anchor",
  "badger",
  "beacon",
  "branch",
  "canyon",
  "cedar",
  "circuit",
  "comet",
  "compass",
  "delta",
  "ember",
  "falcon",
  "forest",
  "harbor",
  "horizon",
  "island",
  "lantern",
  "meadow",
  "nebula",
  "orbit",
  "otter",
  "pebble",
  "phoenix",
  "river",
  "signal",
  "sparrow",
  "summit",
  "thicket",
  "willow",
  "zephyr",
}

local NAMES = {}
for _, adjective in ipairs(ADJECTIVES) do
  for _, noun in ipairs(NOUNS) do
    NAMES[#NAMES + 1] = adjective .. "-" .. noun
  end
end

function M.name(pane_id)
  local h = pane_id * 2654435761
  return NAMES[(h % #NAMES) + 1]
end

function M.color(pane_id, colors)
  local h = pane_id * 2654435761
  local slot = (h % 6) + 2
  if type(colors) == "table" then
    local a = colors.ansi or (colors.colors and colors.colors.ansi)
    if type(a) == "table" and a[slot] then
      return a[slot]
    end
    local b = colors.brights or colors
    if type(b) == "table" then
      return b[(h % 6) + 2]
    end
  end
  return nil
end

return M
