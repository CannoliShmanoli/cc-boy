local Gameboy = require("init")
local gb = Gameboy.new()
local bit32 = require("bit32")
local band = bit32.band

-- Settings
local settings_path = "ccboy_settings.txt"
local settings = {}
if fs.exists(settings_path) then
    local f = fs.open(settings_path, "r")
    local ok, data = pcall(textutils.unserialize, f.readAll())
    f.close()
    if ok and type(data) == "table" then settings = data end
end

if settings.cgb_bypass == nil then settings.cgb_bypass = false end
if settings.jit_enabled == nil then settings.jit_enabled = false end

if settings.frame_skip == nil then settings.frame_skip = 0 end
if settings.speed_limit == nil then settings.speed_limit = 100 end
if settings.render_mode == nil then settings.render_mode = "graphics" end
if settings.render_mode ~= "graphics" and settings.render_mode ~= "pixelbox" then
    settings.render_mode = "graphics"
end
if not settings.keys then
    settings.keys = {
        up = keys.up, down = keys.down, left = keys.left, right = keys.right,
        b = keys.z, a = keys.x, start = keys.enter, select = keys.leftShift,
    }
end

local function save_settings()
    local f = fs.open(settings_path, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

local use_pixelbox = settings.render_mode == "pixelbox"
local pixelbox_box
if use_pixelbox then
    local ok, pixelbox = pcall(require, "pixelbox_lite")
    if ok then
        pixelbox_box = pixelbox.new(term, colors.black)
    else
        use_pixelbox = false
        settings.render_mode = "graphics"
        save_settings()
    end
end
if not use_pixelbox then
    term.setGraphicsMode(2)
end

-- Center the 160x144 game screen
local cols, rows = term.getSize()
local screen_w = use_pixelbox and cols * 2 or cols * 6
local screen_h = use_pixelbox and rows * 3 or rows * 9
local default_ox = math.max(0, math.floor((screen_w - 160) / 2))
local default_oy = math.max(0, math.floor((screen_h - 144) / 2))
local ox = default_ox
local oy = default_oy
term.setBackgroundColor(colors.black)
term.clear()

-- Load border overlay from .ccg
local border
local border_pixels
local border_paths = {"assets/border.ccg", "gameboy/assets/border.ccg"}
if shell and shell.getRunningProgram then
    local dir = shell.getRunningProgram():match("^(.*/)" ) or ""
    table.insert(border_paths, 1, fs.combine(dir, "assets/border.ccg"))
end
local function find_border()
    for _, p in ipairs(border_paths) do
        if fs.exists(p) then return p end
    end
end
local function load_border()
    local bp = find_border()
    if not bp then return end
    local f = fs.open(bp, "rb")
    local data = f.readAll()
    f.close()
    local bw = data:byte(1) + data:byte(2) * 256
    local bh = data:byte(3) + data:byte(4) * 256
    local bdata = {}
    for y = 0, bh - 1 do
        bdata[y + 1] = {}
        for x = 0, bw - 1 do
            local off = 5 + (y * bw + x) * 3
            bdata[y + 1][x + 1] = {data:byte(off), data:byte(off + 1), data:byte(off + 2)}
        end
    end
    border = {w = bw, h = bh}
    border_pixels = bdata
end
load_border()

local palette_map = {}
local palette_cc_map = {}
local palette_next = 1
local max_index = 255
local cc_palette = {
    {colors.white, 255, 255, 255},
    {colors.orange, 240, 127, 51},
    {colors.magenta, 229, 127, 216},
    {colors.lightBlue, 153, 178, 242},
    {colors.yellow, 222, 222, 108},
    {colors.lime, 127, 204, 25},
    {colors.pink, 242, 178, 204},
    {colors.gray, 76, 76, 76},
    {colors.lightGray, 153, 153, 153},
    {colors.cyan, 76, 153, 178},
    {colors.purple, 178, 102, 229},
    {colors.blue, 51, 102, 204},
    {colors.brown, 127, 102, 76},
    {colors.green, 87, 166, 78},
    {colors.red, 204, 76, 76},
    {colors.black, 17, 17, 17},
}

local function nearest_cc_color(r, g, b)
    local best = colors.black
    local best_distance = math.huge
    for i = 1, #cc_palette do
        local c = cc_palette[i]
        local dr, dg, db = r - c[2], g - c[3], b - c[4]
        local distance = dr * dr + dg * dg + db * db
        if distance < best_distance then
            best = c[1]
            best_distance = distance
        end
    end
    return best
end

local function color_index_for_key(key, r, g, b)
    local index = palette_map[key]
    if not index then
        if palette_next > max_index then
            return 254
        end
        index = palette_next
        palette_map[key] = index
        palette_cc_map[index] = nearest_cc_color(r, g, b)
        if not use_pixelbox then
            term.setPaletteColor(index, r/255, g/255, b/255)
        end
        palette_next = palette_next + 1
    end
    return index
end

local function draw_indexed_pixels(px, py, pixels)
    if not use_pixelbox then
        term.drawPixels(px, py, pixels)
        return
    end

    local canvas = pixelbox_box.canvas
    local max_w = pixelbox_box.width
    local max_h = pixelbox_box.height
    local src_h = #pixels
    local src_w = #(pixels[1] or {})
    local scale = math.min(max_w / src_w, max_h / src_h)
    local dw = math.floor(src_w * scale)
    local dh = math.floor(src_h * scale)
    local off_x = math.floor((max_w - dw) / 2)
    local off_y = math.floor((max_h - dh) / 2)

    for dy = 0, dh - 1 do
        local sy = math.floor(dy / scale)
        local src_row = pixels[sy + 1]
        local dest_y = off_y + dy + 1
        if dest_y >= 1 and dest_y <= max_h then
            local dest_row = canvas[dest_y]
            for dx = 0, dw - 1 do
                local sx = math.floor(dx / scale)
                local dest_x = off_x + dx + 1
                if dest_x >= 1 and dest_x <= max_w then
                    dest_row[dest_x] = palette_cc_map[src_row[sx + 1]] or colors.black
                end
            end
        end
    end
    pixelbox_box:render()
end

local function enter_menu_display()
    if not use_pixelbox then term.setGraphicsMode(0) end
end

local function enter_game_display()
    if use_pixelbox then
        pixelbox_box:clear(colors.black)
    else
        term.setGraphicsMode(2)
    end
end

local function color_index_for_rgb(rgb)
    local key = rgb._ccboy_key
    if not key then
        key = rgb[1]*65536 + rgb[2]*256 + rgb[3]
        rgb._ccboy_key = key
    end
    return color_index_for_key(key, rgb[1], rgb[2], rgb[3])
end

local border_indexed
local border_ox, border_oy
local function build_border_indexed()
    if not border then return end
    border_indexed = {}
    for y = 1, border.h do
        border_indexed[y] = {}
        for x = 1, border.w do
            local p = border_pixels[y][x]
            border_indexed[y][x] = color_index_for_rgb(p)
        end
    end
    border_ox = math.max(0, math.floor((screen_w - border.w) / 2))
    border_oy = math.max(0, oy - border.h)
end
build_border_indexed()

local pixels_indexed = {}
local pixel_keys = {}
for y = 1, 144 do
    pixels_indexed[y] = {}
    pixel_keys[y] = {}
    for x = 1, 160 do
        pixels_indexed[y][x] = 0
        pixel_keys[y][x] = -1
    end
end

local function draw_game_screen()
    if not gb.graphics.game_screen then return end
    if use_pixelbox then pixelbox_box:clear(colors.black) end
    local screen = gb.graphics.game_screen
    for y = 0, 143 do
        local row = pixels_indexed[y+1]
        local key_row = pixel_keys[y+1]
        local screen_row = screen[y]
        for x = 0, 159 do
            local pixel = screen_row[x]
            local key = pixel[1]*65536 + pixel[2]*256 + pixel[3]
            local column = x + 1
            if key_row[column] ~= key then
                key_row[column] = key
                row[column] = color_index_for_key(key, pixel[1], pixel[2], pixel[3])
            end
        end
    end
    draw_indexed_pixels(ox, oy, pixels_indexed)
end

local function draw_border()
    ox = default_ox
    oy = default_oy
    if not border then return end
    draw_indexed_pixels(border_ox, border_oy, border_indexed)
end

draw_border()

local path = arg[1]
if not path or not fs.exists(path) then
    error("Usage: ccboy <rom.gb>")
end

local file = fs.open(path, "rb")
local rom_str = file.readAll()
file.close()
gb.cartridge.load(rom_str, #rom_str)
if settings.cgb_bypass then
    gb.cartridge.gameboy.type = gb.cartridge.gameboy.types.color
end

-- Battery ram and emulator state use separate files.
local save_path = path:sub(1, -4) .. ".sav"
local state_path = path:sub(1, -4) .. ".state"

if fs.exists(save_path) then
    local f = fs.open(save_path, "rb")
    local data = f.readAll()
    f.close()
    if not (data:sub(1, 1) == "{" and data:find("processor")) then
        gb.cartridge.load_external_ram(data)
    end
end

local function save_battery()
    if not gb.cartridge.external_ram.dirty then return true end
    local f = fs.open(save_path, "wb")
    f.write(gb.cartridge.dump_external_ram())
    f.close()
    return true
end

-- Find speaker once at startup
local speaker
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "speaker" then speaker = peripheral.wrap(name); break end
end

-- Audio callback: resample 32768→48000 Hz, send raw PCM
local audio_out = {}
local audio_resample_step = 256 / 375
gb.audio.on_buffer_full(function(buffer)
    if not speaker then return end
    local buf = audio_out
    for j = 0, 749 do
        local pos = j * audio_resample_step
        local idx = math.floor(pos)
        local frac = pos - idx
        local m0 = (buffer[idx*2] + buffer[idx*2+1]) / 2
        local sample
        if idx + 1 < 512 then
            local m1 = (buffer[(idx+1)*2] + buffer[(idx+1)*2+1]) / 2
            sample = m0 * (1 - frac) + m1 * frac
        else
            sample = m0
        end
        local pcm8 = math.floor(sample * 128)
        if pcm8 > 127 then pcm8 = 127 elseif pcm8 < -128 then pcm8 = -128 end
        buf[j+1] = pcm8
    end
    speaker.playAudio(buf)
end)

-- Key name lookup
local key_names = {
    [keys.up]="UP", [keys.down]="DOWN", [keys.left]="LEFT", [keys.right]="RIGHT",
    [keys.z]="Z", [keys.x]="X", [keys.enter]="ENTER",
    [keys.leftShift]="L-SHIFT", [keys.rightShift]="R-SHIFT",
    [keys.space]="SPACE", [keys.tab]="TAB",
    [keys.a]="A", [keys.b]="B", [keys.c]="C", [keys.d]="D", [keys.e]="E",
    [keys.f]="F", [keys.g]="G", [keys.h]="H", [keys.i]="I", [keys.j]="J",
    [keys.k]="K", [keys.l]="L", [keys.m]="M", [keys.n]="N", [keys.o]="O",
    [keys.p]="P", [keys.q]="Q", [keys.r]="R", [keys.s]="S", [keys.t]="T",
    [keys.u]="U", [keys.v]="V", [keys.w]="W", [keys.x]="X", [keys.y]="Y",
    [keys.z]="Z",
    [keys.one]="1", [keys.two]="2", [keys.three]="3", [keys.four]="4",
    [keys.five]="5", [keys.six]="6", [keys.seven]="7", [keys.eight]="8",
    [keys.nine]="9", [keys.zero]="0",
    [keys.f1]="F1", [keys.f2]="F2", [keys.f3]="F3", [keys.f4]="F4",
    [keys.f5]="F5", [keys.f6]="F6", [keys.f7]="F7", [keys.f8]="F8",
}
local function key_name(k) return key_names[k] or "KEY" end

local gb_buttons = {"up","down","left","right","b","a","start","select"}
local gb_labels  = {"UP","DOWN","LEFT","RIGHT","B","A","START","SELECT"}

local function show_bios_menu(title, items_fn, handler)
    enter_menu_display()
    local sel, msg, num_items = 1, "", 0
    local mcols, mrows = term.getSize()
    local bw = 20
    local mx = math.floor((mcols - bw) / 2) + 1

    local function get_items()
        if type(items_fn) == "function" then return items_fn() end
        return items_fn
    end

    local function draw()
        local items = get_items()
        num_items = #items
        local my = math.floor((mrows - num_items - 2) / 2)

        term.setBackgroundColor(colors.black)
        term.clear()

        -- Title bar
        term.setCursorPos(mx, my)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
        term.write(" " .. title .. string.rep(" ", bw - #title - 1) .. " ")

        -- Items
        for i = 1, num_items do
            term.setCursorPos(mx, my + i)
            if i == sel then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            term.write(" " .. items[i] .. string.rep(" ", bw - #items[i] - 1) .. " ")
        end

        term.setBackgroundColor(colors.black)

        if #msg > 0 then
            term.setCursorPos(mx, my + num_items + 1)
            term.setTextColor(colors.gray)
            term.write(" " .. msg .. " ")
        end

        term.setCursorPos(1, mrows)
        term.setTextColor(colors.gray)
        term.write("  Arrow:nav  Enter:select  ESC:back")
    end

    draw()
    while true do
        local _, k = os.pullEvent("key")
        if k == keys.up and sel > 1 then sel = sel - 1; msg = ""; draw()
        elseif k == keys.down and sel < num_items then sel = sel + 1; msg = ""; draw()
        elseif k == keys.enter then
            local action = handler(sel)
            if action == "back" then
                term.setBackgroundColor(colors.black)
                term.clear()
                return
            elseif action then msg = action; draw() end
        elseif k == keys.escape or k == keys.f2 then
            term.setBackgroundColor(colors.black)
            term.clear()
            return
        end
    end
end

local function show_keybinds()
    show_bios_menu(" Button Mapping ", function()
        local items = {}
        for i = 1, #gb_buttons do
            items[i] = gb_labels[i] .. "  [" .. key_name(settings.keys[gb_buttons[i]]) .. "]"
        end
        items[#items+1] = "Back"
        return items
    end, function(sel)
        if sel > #gb_buttons then return "back" end
        local btn = gb_buttons[sel]

        -- Wait for key press
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        term.write("  Press new key for " .. gb_labels[sel] .. "...")
        term.setTextColor(colors.gray)
        term.write("  (ESC to cancel)")

        while true do
            local _, k = os.pullEvent("key")
            if k == keys.escape then return "Cancelled" end
            -- Check for conflicts
            for _, v in pairs(settings.keys) do
                if v == k then return "Key already in use" end
            end
            settings.keys[btn] = k
            save_settings()
            return gb_labels[sel] .. " set to " .. key_name(k)
        end
    end)
end

local speed_options = {100, 200, 400, 0} -- 0 = Max

local function show_performance()
    show_bios_menu(" Performance ", function()
        local fast_s = settings.jit_enabled and "ON " or "OFF"
        local fps_s = tostring(settings.frame_skip)
        local spd_s = settings.speed_limit == 0 and "MAX" or (settings.speed_limit .. "%")
        return {"Fast Mode [" .. fast_s .. "]", "Frame Skip [" .. fps_s .. "]",
                "Speed Limit [" .. spd_s .. "]", "Back"}
    end, function(sel)
        if sel == 1 then
            settings.jit_enabled = not settings.jit_enabled
            save_settings()
        elseif sel == 2 then
            settings.frame_skip = (settings.frame_skip + 1) % 6
            if settings.frame_skip == 4 then settings.frame_skip = 5 end
            save_settings()
        elseif sel == 3 then
            for i, v in ipairs(speed_options) do
                if v == settings.speed_limit then
                    settings.speed_limit = speed_options[(i % #speed_options) + 1]
                    break
                end
            end
            save_settings()
        elseif sel == 4 then return "back" end
    end)
end

local function show_settings()
    show_bios_menu(" Settings ", function()
        local cgb = settings.cgb_bypass and "ON " or "OFF"
        return {"Button Mapping", "CGB Bypass [" .. cgb .. "]", "Performance", "Back"}
    end, function(sel)
        if sel == 1 then show_keybinds()
        elseif sel == 2 then
            settings.cgb_bypass = not settings.cgb_bypass
            save_settings()
        elseif sel == 3 then
            show_performance()
            return "back"
        elseif sel == 4 then return "back" end
    end)
end

local CYCLES_PER_FRAME = 69905
local frame_cycle_target = CYCLES_PER_FRAME
local last_vblank = 0
local frame_count = 0
local audio_frame_count = 0
local battery_frame_count = 0

local menu_items = {" Settings   ", " Quit Game  "}

local function show_menu()
    enter_menu_display()
    local sel, msg, msg_color = 1, "", colors.white
    local mcols, mrows = term.getSize()
    local bw, bh = 16, #menu_items
    local mx = math.floor((mcols - bw) / 2) + 1
    local my = math.floor((mrows - bh - 2) / 2)

    local function draw()
        term.setBackgroundColor(colors.black)
        term.clear()
        for i = 1, #menu_items do
            term.setCursorPos(mx, my + i)
            if i == sel then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            term.write("  " .. menu_items[i] .. "  ")
        end
        term.setBackgroundColor(colors.black)
        if #msg > 0 then
            term.setCursorPos(mx, my + bh + 1)
            term.setTextColor(msg_color)
            term.write("  " .. msg .. "  ")
        end
        term.setCursorPos(1, mrows)
        term.setTextColor(colors.gray)
        term.write("  Arrow:nav  Enter:select  ESC:back")
    end

    draw()
    while true do
        local _, k = os.pullEvent("key")
        if k == keys.up and sel > 1 then sel = sel - 1; msg = ""; draw()
        elseif k == keys.down and sel < #menu_items then sel = sel + 1; msg = ""; draw()
        elseif k == keys.enter then
            if sel == 1 then
                show_settings()
                term.setBackgroundColor(colors.black)
                term.clear()
                enter_game_display()
                draw_border()
                draw_game_screen()
                return "close"
            elseif sel == 2 then
                save_battery()
                term.setBackgroundColor(colors.black)
                term.clear()
                enter_game_display()
                return "quit"
            end
            elseif k == keys.escape or k == keys.f2 then
            term.setBackgroundColor(colors.black)
            term.clear()
            enter_game_display()
            draw_border()
            draw_game_screen()
            return "close"
        end
    end
    return nil
end

-- Input handler (F2 triggers menu)
-- Returns "quit", "close", or nil
local function handleKey(key, pressed)
    if pressed and key == keys.f2 then
        save_battery()
        return show_menu()
    end
    local val = pressed and 1 or 0
    local k = settings.keys
    if key == k.up then gb.input.keys.Up = val
    elseif key == k.down then gb.input.keys.Down = val
    elseif key == k.left then gb.input.keys.Left = val
    elseif key == k.right then gb.input.keys.Right = val
    elseif key == k.b then gb.input.keys.B = val
    elseif key == k.a then gb.input.keys.A = val
    elseif key == k.start then gb.input.keys.Start = val
    elseif key == k.select then gb.input.keys.Select = val
    else return end
    gb.input.update()
end

local frame_start = os.clock()

-- Localize hot-path tables for speed
local timers = gb.timers
local graphics = gb.graphics
local rp = gb.processor
local reg = rp.registers
local opcodes = rp.opcodes
local opcode_cycles = rp.opcode_cycles
local block_map = gb.memory.block_map

while true do
    local fast_mode = settings.jit_enabled
    local batch = fast_mode and 64 or 16
    while timers.system_clock < frame_cycle_target do
        timers:update()
        if timers.system_clock > graphics.next_edge then
            graphics.update()
        end
        if rp.halted == 0 then
            for _ = 1, batch do
                local addr = reg.pc
                local opcode = block_map[band(addr, 0xFF00)][addr]
                reg.pc = (addr + 1) % 65536
                opcodes[opcode]()
                timers.system_clock = timers.system_clock + (opcode_cycles[opcode] or 4)
            end
        else
            timers.system_clock = timers.system_clock + batch * 4
        end
        if graphics.vblank_count ~= last_vblank then
            last_vblank = graphics.vblank_count
            frame_count = frame_count + 1
            if frame_count > settings.frame_skip then
                draw_game_screen()
                frame_count = 0
            end
        end
    end
    frame_cycle_target = frame_cycle_target + CYCLES_PER_FRAME
    battery_frame_count = battery_frame_count + 1
    if battery_frame_count >= 120 then
        save_battery()
        battery_frame_count = 0
    end
    audio_frame_count = audio_frame_count + 1
    if not fast_mode or audio_frame_count >= 2 then
        gb.audio.update()
        audio_frame_count = 0
    end
    local elapsed = os.clock() - frame_start
    local speed = settings.speed_limit
    local target_time = speed > 0 and (1/60) * (100 / speed) or 0
    local wait = target_time - elapsed
    os.startTimer(wait > 0 and wait or 0)
    while true do
        local event, arg1 = os.pullEventRaw()
        if event == "timer" then break end
        if event == "key" then
            local r = handleKey(arg1, true)
            if r == "quit" then save_battery(); return
            elseif r == "close" then break end
        end
        if event == "key_up" then handleKey(arg1, false) end
        if event == "terminate" then save_battery(); error("Terminated", 0) end
    end
    frame_start = os.clock()
end
