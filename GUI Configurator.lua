local save_gui_settings = require("utils/save_gui_settings")

local settings = save_gui_settings.load_settings("configs/gui_settings.cfg")
local save_message = ""
local save_message_timer = 0

while true do
    local keys = input.get()
    
    if keys.Up then
        settings.y_offset = settings.y_offset - 1
    elseif keys.Down then
        settings.y_offset = settings.y_offset + 1
    end
    if keys.Left then
        settings.x_offset = settings.x_offset - 1
    elseif keys.Right then
        settings.x_offset = settings.x_offset + 1
    end
    
    if keys.Enter then
        if save_gui_settings.save_settings(settings, "configs/gui_settings.cfg") then
            save_message = "Settings saved!"
            save_message_timer = 60  -- Show message for 60 frames
        else
            save_message = "Failed to save settings"
            save_message_timer = 60
        end
    end

    if save_message_timer > 0 then
        gui.text(10, 10, save_message, "yellow")
        save_message_timer = save_message_timer - 1
    end

    gui.text(10 + settings.x_offset, 10 + settings.y_offset, "Sauvages : ON", "green")
    gui.text(10 + settings.x_offset, 40 + settings.y_offset, "PV ", "white")
    gui.text(55 + settings.x_offset, 40 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 55 + settings.y_offset, "ATQ", "white")
    gui.text(55 + settings.x_offset, 55 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 70 + settings.y_offset, "DEF", "white")
    gui.text(55 + settings.x_offset, 70 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 85 + settings.y_offset, "A.SP", "white")
    gui.text(55 + settings.x_offset, 85 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 100 + settings.y_offset, "D.SP", "white")
    gui.text(55 + settings.x_offset, 100 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 115 + settings.y_offset, "VIT", "white")
    gui.text(55 + settings.x_offset, 115 + settings.y_offset, string.format("%2d", 31), "green")
    gui.text(10 + settings.x_offset, 130 + settings.y_offset, "Avg ", "white")
    gui.text(55 + settings.x_offset, 130 + settings.y_offset, string.format("%4.1f", 31), "green")

    gui.text(10 + settings.x_offset, 160 + settings.y_offset, "Puis. Cachee : 100 Electrik", "yellow")

    gui.text(10 + settings.x_offset, 190 + settings.y_offset, "Fleches directionnelles pour deplacer l'interface", "white")
    gui.text(10 + settings.x_offset, 205 + settings.y_offset, "Entree pour sauvegarder", "white")

    emu.frameadvance()
end