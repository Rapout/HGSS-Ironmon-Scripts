local base_addr = 0x02111958 --0x02111938 pour la version US
local addr_offset = 0x1DE4

local domain = "ARM9 System Bus"

local no_encounter_value = 0x00

local encounters_enabled = true
local previous_rate = -1
local previous_rate_surf = -1

local last_up = false
local last_down = false

local rom_loaded = gameinfo.getromhash()

local save_gui_settings = require("utils/save_gui_settings")
local settings = save_gui_settings.load_settings("configs/gui_settings.cfg")

function reset()
    print("Reset...")
    encounters_enabled = true
    previous_rate = -1
	previous_rate_surf = -1
	last_up = false
	last_down = false
end

local function draw_overlay()
	-- A retirer/modifier si necessaire
    local text = encounters_enabled and "Sauvages : ON" or "Sauvages : OFF"
    local color = encounters_enabled and "green" or "red"
    gui.text(10 + settings.x_offset, 10 + settings.y_offset, text, color)
end


while true do

	local current_rom = gameinfo.getromhash()
    if current_rom ~= rom_loaded then
        print("🔄 Changement ou rechargement de ROM détecté")
        reset()
		rom_loaded = current_rom
    end

	if current_rom ~= "" then
		local input_state = joypad.get()
		local encounter_addr = memory.read_u32_le(base_addr, domain) + addr_offset
		local surf_encounter_addr = encounter_addr + 1
		
		-- A modifier pour changer les raccourcis
		local pressing_select = input_state["Select"] or false
		local pressing_up = input_state["Up"] or false
		local pressing_down = input_state["Down"] or false

		if pressing_select and pressing_up and not last_up then
			encounters_enabled = true
			print("✅ Sauvages ON")
		end

		if pressing_select and pressing_down and not last_down then
			encounters_enabled = false
			print("❌ Sauvages OFF")
		end

		local current_rate = memory.read_u8(encounter_addr, domain)
		local current_rate_surf = memory.read_u8(surf_encounter_addr, domain)
		
		if encounters_enabled then
			if current_rate ~= previous_rate and current_rate ~= no_encounter_value then
				previous_rate = current_rate -- sauvegarde le taux de sauvage de la zone
			end

			if current_rate_surf ~= previous_rate_surf and current_rate_surf ~= no_encounter_value then
				previous_rate_surf = current_rate_surf -- sauvegarde le taux de sauvage de la zone pour surf
			end

			memory.write_u8(encounter_addr, previous_rate, domain)
			memory.write_u8(surf_encounter_addr, previous_rate_surf, domain) 		
		else
			if current_rate ~= no_encounter_value then
				previous_rate = current_rate -- sauvegarde le taux de sauvage de la zone
			end
			
			if current_rate_surf ~= no_encounter_value then
				previous_rate_surf = current_rate_surf -- sauvegarde le taux de sauvage de la zone pour surf
			end
			memory.write_u8(encounter_addr, no_encounter_value, domain)
			memory.write_u8(surf_encounter_addr, no_encounter_value, domain) 		
		end

		draw_overlay() -- A retirer si necessaire

		last_up = pressing_select and pressing_up
		last_down = pressing_select and pressing_down
	end
	
    emu.frameadvance()
end
