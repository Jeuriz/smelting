local QBCore = exports['qb-core']:GetCoreObject()
local smeltingProcesses = {}

-- Sistema de persistencia de datos
local function SaveSmeltingData()
    local success, data = pcall(json.encode, smeltingProcesses)
    if success and data then
        SaveResourceFile(GetCurrentResourceName(), "data/smelting_processes.json", data, -1)
    else
        print("^1[Smelting]^7 Error al guardar datos de fundición")
    end
end

local function LoadSmeltingData()
    local data = LoadResourceFile(GetCurrentResourceName(), "data/smelting_processes.json")
    if data and data ~= "" then
        local success, decoded = pcall(json.decode, data)
        if success and decoded and type(decoded) == "table" then
            smeltingProcesses = decoded
            print("^2[Smelting]^7 Datos de fundición cargados correctamente")
        else
            print("^1[Smelting]^7 Error al decodificar datos de fundición")
            smeltingProcesses = {}
        end
    else
        print("^3[Smelting]^7 No se encontraron datos previos de fundición")
        smeltingProcesses = {}
    end
end

-- Cargar datos al iniciar el recurso
CreateThread(function()
    Wait(1000) -- Esperar a que QBCore se inicialice
    LoadSmeltingData()
    
    -- Verificar procesos activos y reanudarlos si es necesario
    for playerId, process in pairs(smeltingProcesses) do
        if process and process.active and process.startTime and process.totalTime then
            local timeElapsed = (GetGameTimer() - process.startTime)
            local remainingTime = process.totalTime - timeElapsed
            
            if remainingTime <= 0 then
                -- El proceso ya debería haber terminado
                CompleteSmeltingProcess(playerId)
            else
                -- Continuar el proceso
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
    
    -- Verificar si el jugador está conectado
    local playerSource = tonumber(playerId)
    local player = nil
    
    if playerSource then
        player = QBCore.Functions.GetPlayer(playerSource)
    end
    
    if player and process.results then
        -- Dar items resultantes usando tgiann-inventory exports
        for item, amount in pairs(process.results) do
            if item and amount and amount > 0 then
                local success = exports['tgiann-inventory']:AddItem(playerSource, item, amount)
                if success then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, item, "add", amount)
                end
            end
        end
        
        TriggerClientEvent('smelting:notify', playerSource, Config.Texts['smelting_complete'] or 'Fundición completada', 'success')
        TriggerClientEvent('smelting:processCompleted', playerSource)
        
        -- Limpiar proceso completado
        smeltingProcesses[playerIdStr] = nil
    else
        -- Jugador desconectado, marcar items como pendientes
        if process then
            process.completed = true
            process.active = false
            process.completedTime = os.time()
        end
        print(string.format("^3[Smelting]^7 Proceso completado para jugador desconectado %s", playerIdStr))
    end
    
    SaveSmeltingData()
end

-- Callback para obtener items del jugador
QBCore.Functions.CreateCallback('smelting:getPlayerItems', function(source, cb)
    local items = {}
    local fuel = {}
    
    if not source or not cb then
        return
    end
    
    -- Verificar si hay procesos pendientes al conectarse
    CheckPendingProcesses(source)
    
    -- Obtener items fundibles usando tgiann-inventory exports
    if Config.SmeltingRules then
        for item, _ in pairs(Config.SmeltingRules) do
            if item then
                local success, itemCount = pcall(exports['tgiann-inventory'].GetItemByName, exports['tgiann-inventory'], source, item)
                if success and itemCount and itemCount.count and itemCount.count > 0 then
                    items[item] = itemCount.count
                end
            end
        end
    end
    
    -- Obtener combustibles
    if Config.FuelItems then
        for _, fuelItem in pairs(Config.FuelItems) do
            if fuelItem then
                local success, itemCount = pcall(exports['tgiann-inventory'].GetItemByName, exports['tgiann-inventory'], source, fuelItem)
                if success and itemCount and itemCount.count and itemCount.count > 0 then
                    fuel[fuelItem] = itemCount.count
                end
            end
        end
    end
    
    cb(items, fuel)
end)

-- Función para verificar procesos pendientes
function CheckPendingProcesses(source)
    if not source then return end
    
    local player = QBCore.Functions.GetPlayer(source)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        return
    end
    
    local citizenId = player.PlayerData.citizenid
    
    for playerId, process in pairs(smeltingProcesses) do
        if process and process.citizenId == citizenId and process.completed and not process.delivered and process.results then
            -- Entregar items pendientes
            for item, amount in pairs(process.results) do
                if item and amount and amount > 0 then
                    local success = exports['tgiann-inventory']:AddItem(source, item, amount)
                    if success then
                        TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
                    end
                end
            end
            
            TriggerClientEvent('smelting:notify', source, 'Proceso de fundición completado mientras estabas desconectado', 'success')
            
            -- Marcar como entregado
            smeltingProcesses[playerId] = nil
        end
    end
    SaveSmeltingData()
end

-- Callback para iniciar proceso de fundición
QBCore.Functions.CreateCallback('smelting:startProcess', function(source, cb, selectedItems, fuelAmount, fuelType)
    if not source or not cb then
        return
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        return cb(false, "Error del jugador") 
    end
    
    -- Validar parámetros
    if not selectedItems or not fuelAmount or not fuelType then
        return cb(false, "Parámetros inválidos")
    end
    
    fuelAmount = tonumber(fuelAmount) or 0
    if fuelAmount <= 0 then
        return cb(false, "Cantidad de combustible inválida")
    end
    
    -- Verificar combustible usando tgiann-inventory
    local success, fuelItem = pcall(exports['tgiann-inventory'].GetItemByName, exports['tgiann-inventory'], source, fuelType)
    if not success or not fuelItem or not fuelItem.count or fuelItem.count < fuelAmount then
        return cb(false, Config.Texts['no_fuel'] or 'No tienes suficiente combustible')
    end
    
    -- Verificar materiales y calcular resultados
    local totalTime = 0
    local results = {}
    local totalFuelNeeded = 0
    
    for item, amount in pairs(selectedItems) do
        if item and amount and Config.SmeltingRules and Config.SmeltingRules[item] then
            amount = tonumber(amount) or 0
            if amount > 0 then
                local itemSuccess, itemData = pcall(exports['tgiann-inventory'].GetItemByName, exports['tgiann-inventory'], source, item)
                if not itemSuccess or not itemData or not itemData.count or itemData.count < amount then
                    return cb(false, Config.Texts['no_materials'] or 'No tienes los materiales necesarios')
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
        return cb(false, 'Necesitas más combustible para este proceso')
    end
    
    -- Remover items y combustible usando tgiann-inventory exports
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
    
    -- Guardar proceso con datos persistentes
    smeltingProcesses[tostring(source)] = {
        results = results,
        startTime = GetGameTimer(),
        totalTime = totalTime,
        citizenId = Player.PlayerData.citizenid,
        active = true,
        completed = false,
        delivered = false,
        timestamp = os.time()
    }
    
    -- Guardar datos
    SaveSmeltingData()
    
    -- Iniciar timer para completar automáticamente
    CreateThread(function()
        if totalTime and totalTime > 0 then
            Wait(totalTime)
            CompleteSmeltingProcess(tostring(source))
        end
    end)
    
    cb(true, 'Proceso iniciado', totalTime)
end)

-- Event para completar proceso manualmente (cuando el jugador está presente)
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
        local process = smeltingProcesses[sourceStr]
        
        -- Devolver materiales si el proceso se cancela
        if process and process.active and not process.completed then
            -- Aquí podrías implementar lógica para devolver algunos materiales
            -- Por ejemplo, devolver el 50% de los materiales
        end
        
        smeltingProcesses[sourceStr] = nil
        SaveSmeltingData()
    end
end)

-- Callback para obtener estado del proceso
QBCore.Functions.CreateCallback('smelting:getProcessStatus', function(source, cb)
    if not source or not cb then
        return
    end
    
    local process = smeltingProcesses[tostring(source)]
    if process and process.active and process.startTime and process.totalTime then
        local timeElapsed = GetGameTimer() - process.startTime
        local remainingTime = math.max(0, process.totalTime - timeElapsed)
        
        cb({
            active = true,
            remainingTime = remainingTime,
            totalTime = process.totalTime,
            results = process.results or {}
        })
    else
        cb({active = false})
    end
end)

-- Limpiar procesos antiguos periódicamente (más de 7 días)
CreateThread(function()
    while true do
        Wait(300000) -- Cada 5 minutos
        
        local currentTime = os.time()
        local toRemove = {}
        
        for playerId, process in pairs(smeltingProcesses) do
            if process then
                -- Remover procesos completados y entregados después de 24 horas
                if process.completed and process.delivered and 
                   process.completedTime and (currentTime - process.completedTime) > 86400 then
                    table.insert(toRemove, playerId)
                end
                
                -- Remover procesos muy antiguos (más de 7 días)
                if process.timestamp and (currentTime - process.timestamp) > 604800 then
                    table.insert(toRemove, playerId)
                end
            end
        end
        
        if #toRemove > 0 then
            for _, playerId in pairs(toRemove) do
                smeltingProcesses[playerId] = nil
            end
            SaveSmeltingData()
            print(string.format("^3[Smelting]^7 Limpiados %d procesos antiguos", #toRemove))
        end
    end
end)

-- Guardar datos cuando el recurso se detiene
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SaveSmeltingData()
        print("^2[Smelting]^7 Datos guardados al detener el recurso")
    end
end)
