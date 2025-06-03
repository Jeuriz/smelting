local QBCore = exports['qb-core']:GetCoreObject()
local smeltingProcesses = {}
local furnaceStorage = {} -- Almacenamiento temporal de items en el horno

-- Sistema de cache con ox_lib
local itemsCache = {}
local cacheTimeout = 5000 -- 5 segundos de cache

-- Función auxiliar para obtener la cantidad de un item con cache
local function GetItemCount(source, itemName)
    if not source or not itemName then return 0 end
    
    -- Verificar cache primero
    local cacheKey = string.format("%s_%s", source, itemName)
    local now = GetGameTimer()
    
    if itemsCache[cacheKey] and itemsCache[cacheKey].time and (now - itemsCache[cacheKey].time) < cacheTimeout then
        return itemsCache[cacheKey].count
    end
    
    -- Si no está en cache, obtener del inventario
    local count = 0
    
    -- Método 1: Intentar con tgiann-inventory
    local success, result = pcall(function()
        return exports['tgiann-inventory']:GetItemByName(source, itemName)
    end)
    
    if success and result then
        if type(result) == "table" then
            count = result.count or result.amount or 0
        elseif type(result) == "number" then
            count = result
        end
    else
        -- Método 2: Intentar con QBCore si falla el primero
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local item = Player.Functions.GetItemByName(itemName)
            if item and item.amount then
                count = item.amount
            end
        end
    end
    
    -- Guardar en cache
    itemsCache[cacheKey] = {
        count = count,
        time = now
    }
    
    return count
end

-- Limpiar cache periódicamente
CreateThread(function()
    while true do
        Wait(60000) -- Cada minuto
        local now = GetGameTimer()
        for key, data in pairs(itemsCache) do
            if data.time and (now - data.time) > 60000 then
                itemsCache[key] = nil
            end
        end
    end
end)

-- Cargar datos al iniciar el recurso
CreateThread(function()
    Wait(1000)
    
    -- Verificar procesos activos y reanudarlos si es necesario
    for playerId, process in pairs(smeltingProcesses) do
        if process and process.active and process.startTime and process.totalTime then
            local timeElapsed = (GetGameTimer() - process.startTime)
            local remainingTime = process.totalTime - timeElapsed
            
            if remainingTime <= 0 then
                CompleteSmeltingProcess(playerId)
            else
                print(string.format("^3[Smelting]^7 Reanudando proceso para jugador %s (%.1fs restantes)", tostring(playerId), remainingTime / 1000))
                ContinueSmeltingProcess(playerId, remainingTime)
            end
        end
    end
end)

-- Función para continuar un proceso después de reconexión
function ContinueSmeltingProcess(playerId, remainingTime)
    if not smeltingProcesses[tostring(playerId)] or remainingTime <= 0 then 
        return 
    end
    
    CreateThread(function()
        Wait(math.max(0, remainingTime))
        CompleteSmeltingProcess(tostring(playerId))
    end)
end

-- Función para completar proceso automáticamente
function CompleteSmeltingProcess(playerId)
    local playerIdStr = tostring(playerId)
    if not smeltingProcesses[playerIdStr] then 
        return 
    end
    
    local process = smeltingProcesses[playerIdStr]
    
    if process and process.results then
        -- Guardar items en el almacenamiento del horno
        if not furnaceStorage[playerIdStr] then
            furnaceStorage[playerIdStr] = {}
        end
        
        for item, amount in pairs(process.results) do
            if furnaceStorage[playerIdStr][item] then
                furnaceStorage[playerIdStr][item] = furnaceStorage[playerIdStr][item] + amount
            else
                furnaceStorage[playerIdStr][item] = amount
            end
        end
        
        -- Notificar si está conectado
        local playerSource = tonumber(playerId)
        if playerSource and QBCore.Functions.GetPlayer(playerSource) then
            TriggerClientEvent('smelting:notify', playerSource, Config.Texts['smelting_complete'] or 'Fundición completada', 'success')
            TriggerClientEvent('smelting:processCompleted', playerSource)
        end
        
        -- Limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    end
end

-- Callback con ox_lib para obtener items del jugador
lib.callback.register('smelting:getPlayerItems', function(source)
    local items = {}
    local fuel = {}
    local outputItems = {}
    
    if not source then
        return items, fuel, outputItems
    end
    
    local sourceStr = tostring(source)
    
    -- Obtener items fundibles
    if Config.SmeltingRules then
        for item, rule in pairs(Config.SmeltingRules) do
            local count = GetItemCount(source, item)
            if count > 0 then
                items[item] = count
            end
        end
    end
    
    -- Obtener combustibles
    if Config.FuelItems then
        for _, fuelItem in pairs(Config.FuelItems) do
            local count = GetItemCount(source, fuelItem)
            if count > 0 then
                fuel[fuelItem] = count
            end
        end
    end
    
    -- Obtener items ya procesados en el horno
    if furnaceStorage[sourceStr] then
        outputItems = furnaceStorage[sourceStr]
    end
    
    return items, fuel, outputItems
end)

-- Callback con ox_lib para iniciar proceso
lib.callback.register('smelting:startProcess', function(source, selectedItems, fuelAmount, fuelType)
    if not source then
        return false, "Error del sistema"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        return false, "Error del jugador"
    end
    
    -- Validar parámetros
    if not selectedItems or not fuelAmount or not fuelType then
        return false, "Parámetros inválidos"
    end
    
    fuelAmount = tonumber(fuelAmount) or 0
    if fuelAmount <= 0 then
        return false, "Cantidad de combustible inválida"
    end
    
    -- Verificar combustible
    local fuelCount = GetItemCount(source, fuelType)
    if fuelCount < fuelAmount then
        return false, Config.Texts['no_fuel'] or 'No tienes suficiente combustible'
    end
    
    -- Verificar materiales y calcular resultados
    local totalTime = 0
    local results = {}
    local totalFuelNeeded = 0
    
    for item, amount in pairs(selectedItems) do
        if item and amount and Config.SmeltingRules and Config.SmeltingRules[item] then
            amount = tonumber(amount) or 0
            if amount > 0 then
                local itemCount = GetItemCount(source, item)
                
                if itemCount < amount then
                    return false, Config.Texts['no_materials'] or 'No tienes los materiales necesarios'
                end
                
                local rule = Config.SmeltingRules[item]
                if rule and rule.time and rule.fuel_needed and rule.result and rule.amount then
                    totalTime = totalTime + (rule.time * amount)
                    totalFuelNeeded = totalFuelNeeded + (rule.fuel_needed * amount)
                    
                    local resultAmount = rule.amount * amount
                    if results[rule.result] then
                        results[rule.result] = results[rule.result] + resultAmount
                    else
                        results[rule.result] = resultAmount
                    end
                end
            end
        end
    end
    
    -- Verificar si tiene suficiente combustible
    if fuelAmount < totalFuelNeeded then
        return false, Config.Texts['insufficient_fuel'] or 'Necesitas más combustible para este proceso'
    end
    
    -- Limpiar cache
    for key, _ in pairs(itemsCache) do
        if string.find(key, tostring(source) .. "_") then
            itemsCache[key] = nil
        end
    end
    
    -- Remover items y combustible
    for item, amount in pairs(selectedItems) do
        if item and amount and tonumber(amount) and tonumber(amount) > 0 then
            local removeSuccess = exports['tgiann-inventory']:RemoveItem(source, item, tonumber(amount))
            if removeSuccess then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "remove", tonumber(amount))
            end
        end
    end
    
    local fuelSuccess = exports['tgiann-inventory']:RemoveItem(source, fuelType, totalFuelNeeded)
    if fuelSuccess then
        TriggerClientEvent('tgiann-inventory:client:ItemBox', source, fuelType, "remove", totalFuelNeeded)
    end
    
    -- Guardar proceso en memoria
    smeltingProcesses[tostring(source)] = {
        results = results,
        startTime = GetGameTimer(),
        totalTime = totalTime,
        citizenId = Player.PlayerData.citizenid,
        active = true
    }
    
    -- Iniciar timer
    CreateThread(function()
        if totalTime and totalTime > 0 then
            Wait(totalTime)
            CompleteSmeltingProcess(tostring(source))
        end
    end)
    
    return true, 'Proceso iniciado', totalTime
end)

-- Callback para tomar solo minerales procesados
lib.callback.register('smelting:takeOre', function(source)
    if not source then
        return false, "Error del sistema"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, "Error del jugador"
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, "No hay minerales procesados para recoger"
    end
    
    -- Dar solo los minerales procesados (no combustibles)
    local given = false
    for item, amount in pairs(furnaceStorage[sourceStr]) do
        -- Verificar que no sea combustible
        local isFuel = false
        for _, fuelItem in pairs(Config.FuelItems) do
            if item == fuelItem then
                isFuel = true
                break
            end
        end
        
        if not isFuel and amount > 0 then
            local success = exports['tgiann-inventory']:AddItem(source, item, amount)
            if success then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
                furnaceStorage[sourceStr][item] = nil
                given = true
            end
        end
    end
    
    -- Limpiar items vacíos
    for item, amount in pairs(furnaceStorage[sourceStr]) do
        if not amount or amount <= 0 then
            furnaceStorage[sourceStr][item] = nil
        end
    end
    
    return given, given and "Minerales recogidos" or "No se pudieron recoger los minerales"
end)

-- Callback para tomar todo
lib.callback.register('smelting:takeAll', function(source)
    if not source then
        return false, "Error del sistema"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, "Error del jugador"
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, "No hay items para recoger"
    end
    
    -- Dar todos los items
    local given = false
    for item, amount in pairs(furnaceStorage[sourceStr]) do
        if amount > 0 then
            local success = exports['tgiann-inventory']:AddItem(source, item, amount)
            if success then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
                given = true
            end
        end
    end
    
    -- Limpiar almacenamiento
    furnaceStorage[sourceStr] = {}
    
    return given, given and "Todos los items recogidos" or "No se pudieron recoger los items"
end)

-- Callback con ox_lib para obtener estado del proceso
lib.callback.register('smelting:getProcessStatus', function(source)
    if not source then
        return {active = false}
    end
    
    local process = smeltingProcesses[tostring(source)]
    if process and process.active and process.startTime and process.totalTime then
        local timeElapsed = GetGameTimer() - process.startTime
        local remainingTime = math.max(0, process.totalTime - timeElapsed)
        
        return {
            active = true,
            remainingTime = remainingTime,
            totalTime = process.totalTime,
            results = process.results or {}
        }
    else
        return {active = false}
    end
end)

-- Event para completar proceso manualmente
RegisterNetEvent('smelting:completeProcess', function()
    local source = source
    if source then
        CompleteSmeltingProcess(tostring(source))
    end
end)

-- Event para cancelar proceso
RegisterNetEvent('smelting:cancelProcess', function()
    local source = source
    if not source then return end
    
    local Player = QBCore.Functions.GetPlayer(source)
    local sourceStr = tostring(source)
    
    if smeltingProcesses[sourceStr] and Player then
        smeltingProcesses[sourceStr] = nil
    end
end)

-- Limpiar datos al desconectar
AddEventHandler('playerDropped', function(reason)
    local source = source
    if source then
        local sourceStr = tostring(source)
        -- Mantener el almacenamiento del horno pero limpiar procesos activos después de completarse
    end
end)

-- Comando de debug con ox_lib
lib.addCommand('smeltdebug', {
    help = 'Debug del sistema de fundición (solo admins)',
    restricted = 'group.admin'
}, function(source, args, raw)
    if source > 0 then
        print("^3[Smelting Debug]^7 === DEBUG INVENTARIO ===")
        
        -- Verificar items
        for item, _ in pairs(Config.SmeltingRules) do
            local count = GetItemCount(source, item)
            print("^2[Smelting Debug]^7 " .. item .. ": " .. count)
        end
        
        -- Verificar combustibles
        for _, fuel in pairs(Config.FuelItems) do
            local count = GetItemCount(source, fuel)
            print("^2[Smelting Debug]^7 " .. fuel .. ": " .. count)
        end
        
        -- Verificar almacenamiento del horno
        local sourceStr = tostring(source)
        if furnaceStorage[sourceStr] then
            print("^3[Smelting Debug]^7 === ALMACENAMIENTO DEL HORNO ===")
            for item, amount in pairs(furnaceStorage[sourceStr]) do
                print("^2[Smelting Debug]^7 " .. item .. ": " .. amount)
            end
        end
        
        TriggerClientEvent('smelting:notify', source, 'Revisa la consola del servidor para ver el debug', 'info')
    end
end)
