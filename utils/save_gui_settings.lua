-- Usage: local save_gui_settings = require("utils/save_gui_settings")

local save_gui_settings = {}

local default_settings = {
    x_offset = 0,
    y_offset = 0
}


function save_gui_settings.save_settings(settings, filename)
    local file = io.open(filename, "w")
    if file then
        file:write("return " .. string.format("{ x_offset = %d, y_offset = %d }", settings.x_offset, settings.y_offset))
        file:close()
        return true
    else
        print("Warning: Could not save GUI settings to " .. filename)
        return false
    end
end

function save_gui_settings.load_settings(filename)
    local ok, settings = pcall(dofile, filename)

    if not ok or settings == nil then
        print("Warning: Failed to load settings, using default values.")
        settings = default_settings
    end
    
    return settings
end

return save_gui_settings