Config = {}

-- Ubicaciones de los hornos de fundición
Config.SmeltingLocations = {
    {x = 1109.73, y = -2008.92, z = 31.08}, -- Ejemplo: Puerto de Los Santos
    {x = 2341.21, y = 3049.33, z = 47.15}, -- Sandy Shores
    {x = -1420.89, y = -2789.51, z = 13.84}, -- Aeropuerto
    -- Agrega más ubicaciones aquí
}

Config.SmeltingDistance = 2.0 -- Distancia para interactuar

-- Configuración de fundición
Config.SmeltingRules = {
    ['mena_aluminio'] = {
        result = 'mena_azufre',
        amount = 2, -- Cantidad que se obtiene por cada mineral
        time = 5000, -- Tiempo en ms
        fuel_needed = 1 -- Combustible necesario por mineral
    },
    ['mena_bauxite'] = {
        result = 'mena_azufre',
        amount = 2,
        time = 4000,
        fuel_needed = 1
    },
}

-- Combustibles aceptados (en orden de eficiencia)
Config.FuelItems = {
    'wood'      -- Menos eficiente
}

-- Configuración del inventario tgiann-inventory
Config.InventorySettings = {
    use_itembox = true, -- Mostrar notificaciones de items
    drop_on_full = true -- Si el inventario está lleno, tirar al suelo
}

-- Mensajes
Config.Texts = {
    ['open_smelting'] = '[E] Abrir Fundición',
    ['no_fuel'] = 'No tienes suficiente combustible',
    ['no_materials'] = 'No tienes los materiales necesarios',
    ['smelting_started'] = 'Comenzando proceso de fundición...',
    ['smelting_complete'] = 'Fundición completada exitosamente',
    ['invalid_items'] = 'Materiales no válidos para fundición',
    ['process_cancelled'] = 'Proceso de fundición cancelado',
    ['inventory_full'] = 'Inventario lleno, algunos items se tiraron al suelo',
    ['insufficient_fuel'] = 'Combustible insuficiente para este proceso'
}

-- Configuración de ox_lib
Config.UseOxLibNotifications = true -- Usar notificaciones de ox_lib
Config.UseOxLibProgress = true -- Usar barra de progreso de ox_lib
Config.UseOxLibTextUI = true -- Usar TextUI de ox_lib

-- Configuración de cache
Config.CacheTimeout = 5000 -- Tiempo en ms para mantener el cache de items
Config.CacheCleanupTime = 60000 -- Tiempo en ms para limpiar cache antiguo
