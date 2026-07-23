local function scan_dir(dir)
    local games = {}
    if not fs.isDir(dir) then return games end
    for _, name in ipairs(fs.list(dir)) do
        local path = fs.combine(dir, name)
        if not fs.isDir(path) then
            local ext = name:sub(-3):lower()
            if ext == ".gb" or ext == "gbc" then
                games[#games+1] = {name = name, path = path}
            end
        end
    end
    return games
end

local games = scan_dir(".")
for _, v in ipairs(scan_dir("gameboy")) do games[#games+1] = v end
for _, v in ipairs(scan_dir("roms")) do games[#games+1] = v end
table.sort(games, function(a,b) return a.name:lower() < b.name:lower() end)

if #games == 0 then print("No .gb files found.") return end

-- Shared settings
local settings_path = "ccboy_settings.txt"
local settings = {}
if fs.exists(settings_path) then
    local f = fs.open(settings_path, "r")
    local ok, d = pcall(textutils.unserialize, f.readAll())
    f.close()
    if ok and type(d) == "table" then settings = d end
end
if settings.cgb_bypass == nil then settings.cgb_bypass = false end

local function save_settings()
    local f = fs.open(settings_path, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

local function show_settings_menu()
    local sel = 1
    local cols, rows = term.getSize()

    local function draw()
        term.setBackgroundColor(colors.black)
        term.clear()
        local cgb = settings.cgb_bypass and "ON " or "OFF"
        local items = {"CGB Bypass  [" .. cgb .. "]", "Back"}
        local cx = math.floor((cols - 20) / 2) + 1
        local cy = math.floor((rows - #items - 1) / 2)

        term.setCursorPos(cx, cy)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
        term.write(" " .. " Launcher Settings  ")

        for i = 1, #items do
            term.setCursorPos(cx, cy + i)
            if i == sel then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            term.write(" " .. items[i] .. string.rep(" ", 19 - #items[i]) .. " ")
        end

        term.setBackgroundColor(colors.black)
        term.setCursorPos(1, rows)
        term.setTextColor(colors.gray)
        term.write("  Arrow:nav  Enter:toggle/select  ESC:back")
    end

    draw()
    while true do
        local _, k = os.pullEvent("key")
        if k == keys.up and sel > 1 then sel = sel - 1; draw()
        elseif k == keys.down and sel < 2 then sel = sel + 1; draw()
        elseif k == keys.enter then
            if sel == 1 then
                settings.cgb_bypass = not settings.cgb_bypass
                save_settings()
                draw()
            else
                term.setBackgroundColor(colors.black)
                term.clear()
                return
            end
        elseif k == keys.escape then
            term.setBackgroundColor(colors.black)
            term.clear()
            return
        end
    end
end

local selected, scroll, cols, rows = 1, 0, term.getSize()

local function draw()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    term.write("  Game Boy Launcher")
    term.setCursorPos(1, 2)
    term.setTextColor(colors.gray)
    term.write(string.rep("-", cols))

    local max_vis = math.min(rows - 4, #games)
    if selected > scroll + max_vis then scroll = selected - max_vis
    elseif selected <= scroll then scroll = selected - 1 end

    for i = 1, max_vis do
        local idx = scroll + i
        if idx > #games then break end
        term.setCursorPos(1, 2 + i)
        local g = games[idx]
        if idx == selected then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.write("  " .. g.name .. string.rep(" ", math.max(0, cols - #g.name - 3)))
        else
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.lightGray)
            term.write("  " .. g.name)
        end
    end

    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, rows)
    term.setTextColor(colors.gray)
    term.write("  Arrow:nav  Enter:launch  S:settings  Q:quit")
end

draw()
while true do
    local _, key = os.pullEvent("key")
    if key == keys.up and selected > 1 then selected = selected - 1
    elseif key == keys.down and selected < #games then selected = selected + 1
    elseif key == keys.enter then break
    elseif key == keys.s then
        show_settings_menu()
        draw()
    elseif key == keys.q or key == keys.escape then
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        return
    end
    draw()
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
local game_path = games[selected].path
print("Launching " .. games[selected].name .. "...")

if not shell.run("ccboy", game_path) then
    shell.run("gameboy/ccboy", game_path)
end
term.setGraphicsMode(0)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
