local bit32 = require("bit32")

local Palette = {}

function Palette.new(graphics, modules)
  local io = modules.io
  local ports = io.ports

  local palette = {}

  local dmg_colors = {}
  dmg_colors[0] = {255,255,255}
  dmg_colors[1] = {192, 192, 192}
  dmg_colors[2] = {128, 128, 128}
  dmg_colors[3] = {0, 0,0}
  palette.dmg_colors = dmg_colors

  palette.set_dmg_colors = function(pal_0, pal_1, pal_2, pal_3)
    dmg_colors[0] = pal_0
    dmg_colors[1] = pal_1
    dmg_colors[2] = pal_2
    dmg_colors[3] = pal_3
  end

  palette.bg =   {}
  palette.obj0 = {}
  palette.obj1 = {}

  palette.color_bg = {}
  palette.color_obj = {}
  palette.color_bg_raw = {}
  palette.color_obj_raw = {}

  local function copy_color(color)
    return {color[1], color[2], color[3]}
  end

  local getColorFromIndex = function(index, palette)
    palette = palette or 0xE4
    while index > 0 do
      palette = bit32.rshift(palette, 2)
      index = index - 1
    end
    return dmg_colors[bit32.band(palette, 0x3)]
  end

  palette.reset = function()
    local bgp = io.ram[ports.BGP] or 0xFC
    local obp0 = io.ram[ports.OBP0] or 0xFF
    local obp1 = io.ram[ports.OBP1] or 0xFF
    for i = 1, 4 do
      palette.bg[i] = getColorFromIndex(i - 1, bgp)
      palette.obj0[i] = getColorFromIndex(i - 1, obp0)
      palette.obj1[i] = getColorFromIndex(i - 1, obp1)
    end

    local bg_defaults = {}
    local obj_defaults = {}
    for i = 1, 4 do
      bg_defaults[i] = getColorFromIndex(i - 1, bgp)
      obj_defaults[i] = getColorFromIndex(i - 1, obp0)
    end

    for p = 0, 7 do
      palette.color_bg[p] = palette.color_bg[p] or {}
      palette.color_obj[p] = palette.color_obj[p] or {}
      for i = 1, 4 do
        palette.color_bg[p][i] = copy_color(bg_defaults[i])
        palette.color_obj[p][i] = copy_color(obj_defaults[i])
      end
    end

    for i = 0, 63 do
      palette.color_bg_raw[i] = 0
      palette.color_obj_raw[i] = 0
    end
  end

  palette.reset()

  -- DMG palettes
  io.write_logic[ports.BGP] = function(byte)
    io.ram[ports.BGP] = byte
    for i = 1, 4 do
      palette.bg[i] = getColorFromIndex(i - 1, byte)
    end
    graphics.update()
  end

  io.write_logic[ports.OBP0] = function(byte)
    io.ram[ports.OBP0] = byte
    for i = 1, 4 do
      palette.obj0[i] = getColorFromIndex(i - 1, byte)
    end
    graphics.update()
  end

  io.write_logic[ports.OBP1] = function(byte)
    io.ram[ports.OBP1] = byte
    for i = 1, 4 do
      palette.obj1[i] = getColorFromIndex(i - 1, byte)
    end
    graphics.update()
  end

  palette.color_bg_index = 0
  palette.color_bg_auto_increment = false
  palette.color_obj_index = 0
  palette.color_obj_auto_increment = false

  -- Color Palettes
  io.write_logic[0x68] = function(byte)
    io.ram[0x68] = byte
    palette.color_bg_index = bit32.band(byte, 0x3F)
    palette.color_bg_auto_increment = bit32.band(byte, 0x80) ~= 0
  end

  io.write_logic[0x69] = function(byte)
    palette.color_bg_raw[palette.color_bg_index] = byte

    -- Update the palette cache for this byte pair
    local low_byte = palette.color_bg_raw[bit32.band(palette.color_bg_index, 0xFE)]
    local high_byte = palette.color_bg_raw[bit32.band(palette.color_bg_index, 0xFE) + 1]
    local rgb5_color = bit32.lshift(high_byte, 8) + low_byte
    local r = bit32.band(rgb5_color, 0x001F) * 8
    local g = bit32.rshift(bit32.band(rgb5_color, 0x03E0), 5) * 8
    local b = bit32.rshift(bit32.band(rgb5_color, 0x7C00), 10) * 8
    local palette_index = math.floor(palette.color_bg_index / 8)
    local color_index = math.floor((palette.color_bg_index % 8) / 2) + 1
    palette.color_bg[palette_index][color_index] = {r, g, b}

    if palette.color_bg_auto_increment then
      palette.color_bg_index = palette.color_bg_index + 1
      if palette.color_bg_index > 63 then
        palette.color_bg_index = 0
      end
    end
  end

  io.read_logic[0x69] = function()
    return palette.color_bg_raw[palette.color_bg_index]
  end

  io.write_logic[0x6A] = function(byte)
    io.ram[0x6A] = byte
    palette.color_obj_index = bit32.band(byte, 0x3F)
    palette.color_obj_auto_increment = bit32.band(byte, 0x80) ~= 0
  end

  io.write_logic[0x6B] = function(byte)
    palette.color_obj_raw[palette.color_obj_index] = byte

    -- Update the palette cache for this byte pair
    local low_byte = palette.color_obj_raw[bit32.band(palette.color_obj_index, 0xFE)]
    local high_byte = palette.color_obj_raw[bit32.band(palette.color_obj_index, 0xFE) + 1]
    local rgb5_color = bit32.lshift(high_byte, 8) + low_byte
    local r = bit32.band(rgb5_color, 0x001F) * 8
    local g = bit32.rshift(bit32.band(rgb5_color, 0x03E0), 5) * 8
    local b = bit32.rshift(bit32.band(rgb5_color, 0x7C00), 10) * 8
    local palette_index = math.floor(palette.color_obj_index / 8)
    local color_index = math.floor((palette.color_obj_index % 8) / 2) + 1
    palette.color_obj[palette_index][color_index] = {r, g, b}

    if palette.color_obj_auto_increment then
      palette.color_obj_index = palette.color_obj_index + 1
      if palette.color_obj_index > 63 then
        palette.color_obj_index = 0
      end
    end
  end

  io.read_logic[0x6B] = function()
    return palette.color_obj_raw[palette.color_obj_index]
  end

  return palette
end

return Palette
