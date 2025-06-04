local QBCore = exports['qb-core']:GetCoreObject()
local smeltingProcesses = {}
local furnaceStorage = {}
local playerCooldowns = {} -- Para prevenir spam de procesos

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
        
        -- Limpiar cooldowns expirados
        for playerId, cooldownTime in pairs(playerCooldowns) do
            if (now - cooldownTime) > 10000 then -- 10 segundos de cooldown
                playerCooldowns[playerId] = nil
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
                print(string.format("^3[Smelting]^7 Resuming process for player %s (%.1fs remaining)", tostring(playerId), remainingTime / 1000))
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

-- Función para completar proceso automáticamente (mejorada)
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
                TriggerClientEvent('smelting:notify', playerSource, 'Insufficient fuel to complete the process', 'error')
                smeltingProcesses[playerIdStr] = nil
                -- Notificar al cliente que el proceso terminó
                TriggerClientEvent('smelting:processCompleted', playerSource)
                return
            end
            
            if not hasAllItems then
                -- El jugador no tiene los items necesarios (posible intento de abuso)
                local missingText = "Missing items: "
                for item, amount in pairs(missingItems) do
                    missingText = missingText .. item .. " x" .. amount .. ", "
                end
                
                TriggerClientEvent('smelting:notify', playerSource, 'Process cancelled. ' .. missingText, 'error')
                TriggerClientEvent('smelting:processCompleted', playerSource)
                
                -- Log para administradores
                print(string.format("^1[Smelting Anti-Abuse]^7 Player %s (%s) tried to complete process without necessary items", 
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
                    print(string.format("^1[Smelting]^7 Error removing %s x%d from player %s", item, amount, playerSource))
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
                TriggerClientEvent('smelting:notify', playerSource, 'Error processing some items', 'error')
                smeltingProcesses[playerIdStr] = nil
                TriggerClientEvent('smelting:processCompleted', playerSource)
                return
            end
            
            -- Dar items directamente al inventario automáticamente
            local itemsGiven = false
            for item, amount in pairs(process.results) do
                local success = exports['tgiann-inventory']:AddItem(playerSource, item, amount)
                if success then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, item, "add", amount)
                    itemsGiven = true
                else
                    -- Si no se puede dar al inventario, guardar en almacenamiento del horno
                    if not furnaceStorage[playerIdStr] then
                        furnaceStorage[playerIdStr] = {}
                    end
                    
                    if furnaceStorage[playerIdStr][item] then
                        furnaceStorage[playerIdStr][item] = furnaceStorage[playerIdStr][item] + amount
                    else
                        furnaceStorage[playerIdStr][item] = amount
                    end
                end
            end
            
            if itemsGiven then
                TriggerClientEvent('smelting:notify', playerSource, 'Items automatically added to your inventory!', 'success')
            else
                -- Guardar en almacenamiento del horno si el inventario está lleno
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
                
                TriggerClientEvent('smelting:notify', playerSource, 'Inventory full! Items stored in furnace.', 'warning')
            end
            
            TriggerClientEvent('smelting:notify', playerSource, 'Smelting process completed successfully!', 'success')
            TriggerClientEvent('smelting:processCompleted', playerSource)
            
            -- Log exitoso
            print(string.format("^2[Smelting]^7 Player %s (%s) completed smelting process successfully", 
                Player.PlayerData.name, Player.PlayerData.citizenid))
                
        else
            -- Jugador desconectado, cancelar proceso sin dar items
            print(string.format("^3[Smelting]^7 Process cancelled for disconnected player %s", playerIdStr))
        end
        
        -- Limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    else
        -- Jugador no está conectado, limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    end
end

-- Callback con ox_lib para obtener items del jugador
-- Callback para obtener items del jugador (actualizado para mostrar solo items en almacenamiento)
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
    
    -- Solo mostrar items almacenados en el horno si el inventario estaba lleno
    if furnaceStorage[sourceStr] and next(furnaceStorage[sourceStr]) then
        outputItems = furnaceStorage[sourceStr]
    end
    
    return items, fuel, outputItems
end)

-- Callbacks simplificados para take (solo para casos especiales donde el inventario estaba lleno)
lib.callback.register('smelting:takeStoredItems', function(source)
    if not source then
        return false, "System error"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, "Player error"
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, "No stored items to collect"
    end
    
    -- Intentar dar todos los items almacenados
    local itemsGiven = {}
    local itemsRemaining = {}
    
    for item, amount in pairs(furnaceStorage[sourceStr]) do
        if amount > 0 then
            local success = exports['tgiann-inventory']:AddItem(source, item, amount)
            if success then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
                itemsGiven[item] = amount
            else
                itemsRemaining[item] = amount
            end
        end
    end
    
    -- Actualizar almacenamiento con items que no se pudieron dar
    furnaceStorage[sourceStr] = itemsRemaining
    
    local given = next(itemsGiven) ~= nil
    local remaining = next(itemsRemaining) ~= nil
    
    if given and not remaining then
        return true, "All stored items collected"
    elseif given and remaining then
        return true, "Some items collected, inventory still full"
    else
        return false, "Inventory full, could not collect items"
    end
end)

-- Callback con ox_lib para iniciar proceso (mejorado)
lib.callback.register('smelting:startProcess', function(source, selectedItems, fuelAmount, fuelType)
    if not source then
        return false, "System error"
    end
    
    local sourceStr = tostring(source)
    local now = GetGameTimer()
    
    -- Verificar cooldown para prevenir spam
    if playerCooldowns[sourceStr] and (now - playerCooldowns[sourceStr]) < 3000 then
        return false, "Please wait before starting another process"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        return false, "Player error"
    end
    
    -- Verificar si ya tiene un proceso activo
    if smeltingProcesses[sourceStr] and smeltingProcesses[sourceStr].active then
        return false, "You already have an active smelting process"
    end
    
    -- Validar parámetros
    if not selectedItems or not fuelAmount or not fuelType then
        return false, "Invalid parameters"
    end
    
    fuelAmount = tonumber(fuelAmount) or 0
    if fuelAmount <= 0 then
        return false, "Invalid fuel amount"
    end
    
    -- Limpiar cache antes de verificar
    for key, _ in pairs(itemsCache) do
        if string.find(key, tostring(source) .. "_") then
            itemsCache[key] = nil
        end
    end
    
    -- Verificar combustible
    local fuelCount = GetItemCount(source, fuelType)
    if fuelCount < fuelAmount then
        return false, 'Insufficient fuel'
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
                    return false, 'Insufficient materials: ' .. item
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
        return false, string.format('Need %d more fuel for this process', totalFuelNeeded - fuelAmount)
    end
    
    -- Establecer cooldown
    playerCooldowns[sourceStr] = now
    
    -- Guardar proceso en memoria SIN REMOVER ITEMS AÚN
    smeltingProcesses[sourceStr] = {
        results = results,
        startTime = now,
        totalTime = totalTime,
        citizenId = Player.PlayerData.citizenid,
        active = true,
        itemsToProcess = itemsToProcess, -- Items a procesar
        fuelType = fuelType,
        fuelNeeded = totalFuelNeeded
    }
    
    -- Log de inicio de proceso
    print(string.format("^2[Smelting]^7 Player %s (%s) started smelting process (%.1fs)", 
        Player.PlayerData.name, Player.PlayerData.citizenid, totalTime / 1000))
    
    -- Iniciar timer
    CreateThread(function()
        if totalTime and totalTime > 0 then
            Wait(totalTime)
            CompleteSmeltingProcess(sourceStr)
        end
    end)
    
    return true, 'Process started', totalTime
end)

-- Callback para tomar solo minerales procesados
lib.callback.register('smelting:takeOre', function(source)
    if not source then
        return false, "System error"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, "Player error"
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, "No processed materials to collect"
    end
    
    -- Dar solo los minerales procesados (no combustibles)
    local given = false
    local itemsToRemove = {}
    
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
                itemsToRemove[item] = true
                given = true
            end
        end
    end
    
    -- Remover items dados del almacenamiento
    for item, _ in pairs(itemsToRemove) do
        furnaceStorage[sourceStr][item] = nil
    end
    
    -- Limpiar items vacíos
    for item, amount in pairs(furnaceStorage[sourceStr]) do
        if not amount or amount <= 0 then
            furnaceStorage[sourceStr][item] = nil
        end
    end
    
    return given, given and "Materials collected" or "Could not collect materials"
end)

-- Callback para tomar todo
lib.callback.register('smelting:takeAll', function(source)
    if not source then
        return false, "System error"
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, "Player error"
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, "No items to collect"
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
    
    -- Limpiar almacenamiento solo si se dieron items
    if given then
        furnaceStorage[sourceStr] = {}
    end
    
    return given, given and "All items collected" or "Could not collect items"
end)

-- Callback con ox_lib para obtener estado del proceso (mejorado)
lib.callback.register('smelting:getProcessStatus', function(source)
    if not source then
        return {active = false}
    end
    
    local sourceStr = tostring(source)
    local process = smeltingProcesses[sourceStr]
    
    if process and process.active and process.startTime and process.totalTime then
        local timeElapsed = GetGameTimer() - process.startTime
        local remainingTime = math.max(0, process.totalTime - timeElapsed)
        
        -- Si el tiempo ya expiró, completar automáticamente
        if remainingTime <= 0 then
            CreateThread(function()
                Wait(100)
                CompleteSmeltingProcess(sourceStr)
            end)
            return {active = false}
        end
        
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
        TriggerClientEvent('smelting:notify', source, 'Smelting process cancelled', 'info')
        TriggerClientEvent('smelting:processCompleted', source)
        
        -- Log de cancelación
        print(string.format("^3[Smelting]^7 Player %s cancelled smelting process", Player.PlayerData.name))
        
        smeltingProcesses[sourceStr] = nil
    end
end)

-- Limpiar datos al desconectar
AddEventHandler('playerDropped', function(reason)
    local source = source
    if source then
        local sourceStr = tostring(source)
        local Player = QBCore.Functions.GetPlayer(source)
        
        if Player and smeltingProcesses[sourceStr] then
            print(string.format("^3[Smelting]^7 Player %s disconnected with active process, maintaining state", Player.PlayerData.name))
        end
        
        -- Mantener el almacenamiento del horno y procesos activos para cuando regrese
        -- Solo limpiar cooldowns
        playerCooldowns[sourceStr] = nil
    end
end)

-- Comando de debug con ox_lib
lib.addCommand('smeltdebug', {
    help = 'Debug smelting system (admin only)',
    restricted = 'group.admin'
}, function(source, args, raw)
    if source > 0 then
        print("^3[Smelting Debug]^7 === INVENTORY DEBUG ===")
        
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
            print("^3[Smelting Debug]^7 === FURNACE STORAGE ===")
            for item, amount in pairs(furnaceStorage[sourceStr]) do
                print("^2[Smelting Debug]^7 " .. item .. ": " .. amount)
            end
        end
        
        -- Verificar proceso activo
        if smeltingProcesses[sourceStr] then
            local process = smeltingProcesses[sourceStr]
            print("^3[Smelting Debug]^7 === ACTIVE PROCESS ===")
            print("^2[Smelting Debug]^7 Active: " .. tostring(process.active))
            if process.startTime and process.totalTime then
                local elapsed = GetGameTimer() - process.startTime
                local remaining = math.max(0, process.totalTime - elapsed)
                print("^2[Smelting Debug]^7 Remaining time: " .. math.floor(remaining / 1000) .. "s")
            end
        end
        
        TriggerClientEvent('smelting:notify', source, 'Check server console for debug info', 'info')
    end
end)

-- -- Comando para limpiar datos de un jugador (admin)
-- lib.addCommand('smeltclear', {
--     help = 'Clear smelting data for a player (admin only)',
--     restricted = 'group.admin',
--     params = {
--         {
--             name = 'target',
--             type = 'playerId',
--             help = 'Target player ID'
--         }
--     }
-- }, function(source, args, raw)
--     local targetId = args.target
--     local targetIdStr = tostring(targetId)
    
--     if smeltingProcesses[targetIdStr] then
--         smeltingProcesses[targetIdStr] = nil
--         print("^3[Smelting]^7 Cleared active process for player " .. targetId)
--     end
    
--     if furnaceStorage[targetIdStr] then
--         furnaceStorage[targetIdStr] = nil
--         print("^3[Smelting]^7 Cleared furnace storage for player " .. targetId)
--     end
    
--     if playerCooldowns[targetIdStr] then
--         playerCooldowns[targetIdStr] = nil
--         print("^3[Smelting]^7 Cleared cooldown for player " .. targetId)
--     end
    
--     -- Limpiar cache del jugador
--     for key, _ in pairs(itemsCache) do
--         if string.find(key, targetId .. "_") then
--             itemsCache[key] = nil
--         end
--     end
    
--     TriggerClientEvent('smelting:notify', source, 'Cleared smelting data for player ' .. targetId, 'success')
    
--     -- Notificar al jugador objetivo si está conectado
--     if GetPlayerName(targetId) then
--         TriggerClientEvent('smelting:notify', targetId, 'Your smelting data has been cleared by an admin', 'info')
--         TriggerClientEvent('smelting:processCompleted', targetId)
--     end
-- end)
