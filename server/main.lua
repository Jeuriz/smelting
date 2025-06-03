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
    local playerSource = tonumber(playerId)
    
    -- Verificar si el jugador está conectado
    if playerSource then
        local Player = QBCore.Functions.GetPlayer(playerSource)
        
        if Player and process.results and process.itemsToProcess then
            -- VERIFICAR NUEVAMENTE que el jugador tenga los items antes de procesarlos
            local hasAllItems = true
            local missingItems = {}
            
            -- Limpiar cache antes de verificar
            for key, _ in pairs(itemsCache) do
                if string.find(key, tostring(playerSource) .. "_") then
                    itemsCache[key] = nil
                end
            end
            
            -- Verificar cada item
            for item, amount in pairs(process.itemsToProcess) do
                local currentCount = GetItemCount(playerSource, item)
                if currentCount < amount then
                    hasAllItems = false
                    missingItems[item] = amount - currentCount
                end
            end
            
            -- Verificar combustible
            local fuelCount = GetItemCount(playerSource, process.fuelType)
            if fuelCount < process.fuelNeeded then
                hasAllItems = false
                TriggerClientEvent('smelting:notify', playerSource, 'No tienes suficiente combustible para completar el proceso', 'error')
                smeltingProcesses[playerIdStr] = nil
                return
            end
            
            if not hasAllItems then
                -- El jugador no tiene los items necesarios (posible intento de abuso)
                local missingText = "Faltan items: "
                for item, amount in pairs(missingItems) do
                    missingText = missingText .. item .. " x" .. amount .. ", "
                end
                
                TriggerClientEvent('smelting:notify', playerSource, 'Proceso cancelado. ' .. missingText, 'error')
                TriggerClientEvent('smelting:processCompleted', playerSource)
                
                -- Log para administradores
                print(string.format("^1[Smelting Anti-Abuse]^7 Jugador %s (%s) intentó completar proceso sin items necesarios", 
                    Player.PlayerData.name, Player.PlayerData.citizenid))
                
                -- Limpiar proceso
                smeltingProcesses[playerIdStr] = nil
                return
            end
            
            -- Si tiene todos los items, proceder a removerlos
            local allRemoved = true
            
            -- Remover items
            for item, amount in pairs(process.itemsToProcess) do
                local removeSuccess = exports['tgiann-inventory']:RemoveItem(playerSource, item, amount)
                if removeSuccess then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, item, "remove", amount)
                else
                    allRemoved = false
                    print(string.format("^1[Smelting]^7 Error al remover %s x%d del jugador %s", item, amount, playerSource))
                end
            end
            
            -- Remover combustible
            local fuelSuccess = exports['tgiann-inventory']:RemoveItem(playerSource, process.fuelType, process.fuelNeeded)
            if fuelSuccess then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, process.fuelType, "remove", process.fuelNeeded)
            else
                allRemoved = false
            end
            
            if not allRemoved then
                TriggerClientEvent('smelting:notify', playerSource, 'Error al procesar algunos items', 'error')
                smeltingProcesses[playerIdStr] = nil
                return
            end
            
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
            
            TriggerClientEvent('smelting:notify', playerSource, Config.Texts['smelting_complete'] or 'Fundición completada', 'success')
            TriggerClientEvent('smelting:processCompleted', playerSource)
        else
            -- Jugador desconectado, cancelar proceso sin dar items
            print(string.format("^3[Smelting]^7 Proceso cancelado para jugador desconectado %s", playerIdStr))
        end
        
        -- Limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    else
        -- Jugador no está conectado, limpiar proceso
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
    
    -- Verificar si ya tiene un proceso activo
    if smeltingProcesses[tostring(source)] and smeltingProcesses[tostring(source)].active then
        return false, "Ya tienes un proceso de fundición activo"
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
    local itemsToProcess = {} -- Guardar items para verificar al final
    
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
                    
                    -- Guardar para verificar al final
                    itemsToProcess[item] = amount
                end
            end
        end
    end
    
    -- Verificar si tiene suficiente combustible
    if fuelAmount < totalFuelNeeded then
        return false, Config.Texts['insufficient_fuel'] or 'Necesitas más combustible para este proceso'
    end
    
    -- Guardar proceso en memoria SIN REMOVER ITEMS AÚN
    smeltingProcesses[tostring(source)] = {
        results = results,
        startTime = GetGameTimer(),
        totalTime = totalTime,
        citizenId = Player.PlayerData.citizenid,
        active = true,
        itemsToProcess = itemsToProcess, -- Items a procesar
        fuelType = fuelType,
        fuelNeeded = totalFuelNeeded
    }
    
    -- Log de inicio de proceso
    print(string.format("^2[Smelting]^7 Jugador %s (%s) inició proceso de fundición", 
        Player.PlayerData.name, Player.PlayerData.citizenid))
    
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
        -- No devolver nada ya que no se removieron items al inicio
        TriggerClientEvent('smelting:notify', source, 'Proceso de fundición cancelado', 'info')
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
