Config = {}

-- Ubicaciones de los hornos de fundición
Config.SmeltingLocations = {
    {x = 2920.90, y = 2653.55, z = 43.18}, -- Puerto de Los Santos
    -- Agrega más ubicaciones aquí
}

-- Configuración de slots con skills requeridas
Config.SlotSkills = {
    [1] = nil,                    -- Slot 1: Sin skill requerida (siempre disponible)
    [2] = "fun_2",     -- Slot 2: Metalurgia básica
    [3] = "fun_3",  -- Slot 3: Metalurgia avanzada 
    [4] = "fun_4",         -- Slot 4: Maestría del fuego
    [5] = "fun_5"   -- Slot 5: Fundición industrial
}

-- Labels amigables para las skills
Config.SkillLabels = {
    ["fun_2"] = "Espacio Fundir 2",
    ["fun_3"] = "Espacio Fundir 3", 
    ["fun_4"] = "Espacio Fundir 4",
    ["fun_5"] = "Espacio Fundir 5"
}

-- Configuración de fundición
Config.SmeltingRules = {
    ['mena_aluminio'] = {
        result = 'mena_esmeralda',
        amount = 1, -- Cantidad que se obtiene por cada mineral
        time = 200, -- Tiempo en ms (5 segundos)
        fuel_needed = 1 -- Combustible necesario por mineral
    },
    ['mena_azufre'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_cobre'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_diamante'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_esmeralda'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_estano'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_hierro'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_plomo'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_rubi'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
    ['mena_topacio'] = {
        result = 'mena_hierro',
        amount = 1,
       time = 200, -- 4 segundos
        fuel_needed = 1
    },
}

-- Combustibles aceptados (en orden de eficiencia)
Config.FuelItems = {
    'wood',      -- Menos eficiente
    'mena_carbon',      -- Más eficiente
}

-- Mensajes mejorados
Config.Texts = {
    ['open_smelting'] = 'Use Large Furnace',
    ['check_process'] = 'Check Smelting Process',
    ['no_fuel'] = 'You don\'t have enough fuel',
    ['no_materials'] = 'You don\'t have the necessary materials',
    ['smelting_started'] = 'Starting smelting process...',
    ['smelting_complete'] = 'Smelting process completed successfully!',
    ['invalid_items'] = 'Invalid materials for smelting',
    ['process_cancelled'] = 'Smelting process cancelled',
    ['inventory_full'] = 'Inventory full, some items were dropped on the ground',
    ['insufficient_fuel'] = 'Insufficient fuel for this process',
    ['process_in_progress'] = 'You have a smelting process in progress...',
    ['no_active_process'] = 'You have no active smelting processes',
    ['materials_collected'] = 'You collected the processed materials',
    ['all_items_collected'] = 'You collected all items from the furnace',
    ['no_items_to_collect'] = 'No items to collect',
    ['process_cooldown'] = 'Please wait before starting another process',
    ['player_error'] = 'Player not found',
    ['system_error'] = 'System error occurred'
}
