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

-- Mensajes mejorados en español
Config.Texts = {
    ['open_smelting'] = 'Usar Horno Grande',
    ['check_process'] = 'Revisar Proceso de Fundición',
    ['no_fuel'] = 'No tienes suficiente combustible',
    ['no_materials'] = 'No tienes los materiales necesarios',
    ['smelting_started'] = 'Iniciando proceso de fundición...',
    ['smelting_complete'] = '¡Proceso de fundición completado con éxito!',
    ['invalid_items'] = 'Materiales inválidos para fundición',
    ['process_cancelled'] = 'Proceso de fundición cancelado',
    ['inventory_full'] = 'Inventario lleno, algunos objetos se dejaron en el suelo',
    ['insufficient_fuel'] = 'Combustible insuficiente para este proceso',
    ['process_in_progress'] = 'Tienes un proceso de fundición en progreso...',
    ['no_active_process'] = 'No tienes procesos de fundición activos',
    ['materials_collected'] = 'Recolectaste los materiales procesados',
    ['all_items_collected'] = 'Recolectaste todos los objetos del horno',
    ['no_items_to_collect'] = 'No hay objetos para recolectar',
    ['process_cooldown'] = 'Por favor espera antes de iniciar otro proceso',
    ['player_error'] = 'Jugador no encontrado',
    ['system_error'] = 'Error del sistema',
    
    -- Nuevos mensajes específicos
    ['need_fuel_selected'] = 'Debes seleccionar un combustible primero',
    ['need_materials_selected'] = 'Debes seleccionar materiales para fundir',
    ['fuel_not_enough'] = 'No tienes suficiente combustible. Necesitas %d unidades de %s',
    ['material_not_enough'] = 'No tienes suficiente %s. Necesitas %d unidades pero solo tienes %d',
    ['fuel_missing_inventory'] = 'El combustible %s ya no está en tu inventario',
    ['material_missing_inventory'] = 'El material %s ya no está en tu inventario',
    ['items_moved_during_process'] = 'Algunos objetos fueron movidos durante el proceso. Verifica tu inventario',
    ['skill_required'] = 'Necesitas la habilidad %s para usar este slot',
    ['max_slots_reached'] = 'Has alcanzado el máximo de slots disponibles (%d) con tus habilidades actuales',
    ['fuel_amount_invalid'] = 'Cantidad de combustible inválida',
    ['total_fuel_needed'] = 'Combustible total necesario: %d unidades',
    ['fuel_shortage'] = 'Te faltan %d unidades de combustible para este proceso',
    ['inventory_full_stored'] = 'Inventario lleno. Los objetos se almacenaron en el horno',
    ['process_auto_complete'] = 'Proceso completado automáticamente mientras estabas desconectado',
    ['anti_abuse_detected'] = 'Se detectó un intento de abuso. Proceso cancelado',
}
