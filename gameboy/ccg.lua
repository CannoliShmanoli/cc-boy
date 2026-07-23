-- ccg.lua - .ccg loader module
-- Usage: local img = require("ccg").load("path.ccg")

local ccg = {}

function ccg.load(path)
    local f = fs.open(path, "rb")
    if not f then error("Cannot open " .. path) end
    local data = f.readAll()
    f.close()

    local w = data:byte(1) + data:byte(2) * 256
    local h = data:byte(3) + data:byte(4) * 256
    local img = {}

    for y = 0, h - 1 do
        local row = {}
        for x = 0, w - 1 do
            local off = 5 + (y * w + x) * 3
            row[x + 1] = {data:byte(off), data:byte(off + 1), data:byte(off + 2)}
        end
        img[y + 1] = row
    end

    return { w = w, h = h, data = img }
end

function ccg.draw(path, x, y)
    local img = ccg.load(path)
    term.drawPixels(x or 0, y or 0, img.data)
end

return ccg
