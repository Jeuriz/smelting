local QBCore = exports['qb-core']:GetCoreObject()
local smeltingProcesses = {}

-- Sistema de persistencia de datos
local function SaveSmeltingData()
    local data = json.encode(smeltingProcesses)
    SaveResourceFile(GetCurrentResourceName(), "data/smelting_processes.json", data, -1)
end

local function LoadSmeltingData()
    local data = LoadResourceFile(GetCurrentResourceName(), "data/smelting_processes.json")
    if data then
        local success, decoded = pcall(json.decode, data)
        if success and decoded then
            smeltingProcesses = decoded
            print("^2[Smelting]^7 Datos de fundición cargados correctamente")
        else
            print("^1[Smelting]^7 Error al decodificar datos de fundición")
        end
    else
        print("^3[Smelting]^7 No se encontraron datos previos de fundición")
    end
end

-- Cargar datos al iniciar el recurso
CreateThread(function()
    Wait(1000) -- Esperar a que QBCore se inicialice
    LoadSmeltingData()
    
    -- Verificar procesos activos y reanudarlos si es necesario
    for playerId, process in pairs(smeltingProcesses) do
        if process.active then
            local timeElapsed = (GetGameTimer() - process.startTime)
            local remainingTime = process.totalTime - timeElapsed
            
            if remainingTime <= 0 then
                -- El proceso ya debería haber terminado
                CompleteSmeltingProcess(playerId)
            else
                -- Continuar el proceso
                print(string.format("^3[Smelting]^7 Reanudando proceso para jugador %s (%.1fs restantes)", playerId, remainingTime / 1000))
                ContinueSmeltingProcess(playerId, remainingTime)
            end
        end
    end
end)

-- Función para continuar un proceso después de reconexión
function ContinueSmeltingProcess(playerId, remainingTime)
    if not smeltingProcesses[playerId] then return end
    
    CreateThread(function()
        Wait(remainingTime)
        CompleteSmeltingProcess(playerId)
    end)
end

-- Función para completar proceso automáticamente
function CompleteSmeltingProcess(playerId)
    if not smeltingProcesses[playerId] then return end
    
    local process = smeltingProcesses[playerId]
    
    -- Verificar si el jugador está conectado
    local player = QBCore.Functions.GetPlayer(tonumber(playerId))
    if player then
        -- Dar items resultantes usando tgiann-inventory exports
        for item, amount in pairs(process.results) do
            local success = exports['tgiann-inventory']:AddItem(tonumber(playerId), item, amount)
            if success then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', tonumber(playerId), item, "add", amount)
            end
        end
        
        TriggerClientEvent('smelting:notify', tonumber(playerId), Config.Texts['smelting_complete'], 'success')
        TriggerClientEvent('smelting:processCompleted', tonumber(playerId))
    else
        -- Jugador desconectado, marcar items como pendientes
        process.completed = true
        process.active = false
        process.completedTime = os.time()
        SaveSmeltingData()
        print(string.format("^3[Smelting]^7 Proceso completado para jugador desconectado %s", playerId))
        return
    end
    
    -- Limpiar proceso completado
    smeltingProcesses[tostring(playerId)] = nil
    SaveSmeltingData()
end

-- Callback para obtener items del jugador
QBCore.Functions.CreateCallback('smelting:getPlayerItems', function(source, cb)
    local items = {}
    local fuel = {}
    
    -- Verificar si hay procesos pendientes al conectarse
    CheckPendingProcesses(source)
    
    -- Obtener items fundibles usando tgiann-inventory exports
    for item, _ in pairs(Config.SmeltingRules) do
        local itemCount = exports['tgiann-inventory']:GetItemByName(source, item)
        if itemCount and itemCount.count > 0 then
            items[item] = itemCount.count
        end
    end
    
    -- Obtener combustibles
    for _, fuelItem in pairs(Config.FuelItems) do
        local itemCount = exports['tgiann-inventory']:GetItemByName(source, fuelItem)
        if itemCount and itemCount.count > 0 then
            fuel[fuelItem] = itemCount.count
        end
    end
    
    cb(items, fuel)
end)

-- Función para verificar procesos pendientes
function CheckPendingProcesses(source)
    local citizenId = QBCore.Functions.GetPlayer(source).PlayerData.citizenid
    
    for playerId, process in pairs(smeltingProcesses) do
        if process.citizenId == citizenId and process.completed and not process.delivered then
            -- Entregar items pendientes
            for item, amount in pairs(process.results) do
                local success = exports['tgiann-inventory']:AddItem(source, item, amount)
                if success then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
                end
            end
            
            TriggerClientEvent('smelting:notify', source, 'Proceso de fundición completado mientras estabas desconectado', 'success')
            
            -- Marcar como entregado
            process.delivered = true
            smeltingProcesses[playerId] = nil
            SaveSmeltingData()
        end
    end
end

-- Callback para iniciar proceso de fundición
QBCore.Functions.CreateCallback('smelting:startProcess', function(source, cb, selectedItems, fuelAmount, fuelType)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, "Error del jugador") end
    
    -- Verificar combustible usando tgiann-inventory
    local fuelItem = exports['tgiann-inventory']:GetItemByName(source, fuelType)
    if not fuelItem or fuelItem.count < fuelAmount then
        return cb(false, Config.Texts['no_fuel'])
    end
    
    -- Verificar materiales y calcular resultados
    local totalTime = 0
    local results = {}
    local totalFuelNeeded = 0
    
    for item, amount in pairs(selectedItems) do
        if Config.SmeltingRules[item] then
            local itemData = exports['tgiann-inventory']:GetItemByName(source, item)
            if not itemData or itemData.count < amount then
                return cb(false, Config.Texts['no_materials'])
            end
            
            local rule = Config.SmeltingRules[item]
            totalTime = totalTime + (rule.time * amount)
            totalFuelNeeded = totalFuelNeeded + (rule.fuel_needed * amount)
            
            if results[rule.result] then
                results[rule.result] = results[rule.result] + (rule.amount * amount)
            else
                results[rule.result] = rule.amount * amount
            end
        end
    end
    
    -- Verificar si tiene suficiente combustible
    if fuelAmount < totalFuelNeeded then
        return cb(false, 'Necesitas más combustible para este proceso')
    end
    
    -- Remover items y combustible usando tgiann-inventory exports
    for item, amount in pairs(selectedItems) do
        local success = exports['tgiann-inventory']:RemoveItem(source, item, amount)
        if success then
            TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "remove", amount)
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
        Wait(totalTime)
        CompleteSmeltingProcess(tostring(source))
    end)
    
    cb(true, 'Proceso iniciado', totalTime)
end)

-- Event para completar proceso manualmente (cuando el jugador está presente)
RegisterNetEvent('smelting:completeProcess', function()
    local source = source
    CompleteSmeltingProcess(tostring(source))
end)

-- Event para cancelar proceso
RegisterNetEvent('smelting:cancelProcess', function()
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    
    if smeltingProcesses[tostring(source)] and Player then
        local process = smeltingProcesses[tostring(source)]
        
        -- Devolver materiales si el proceso se cancela
        if process.active and not process.completed then
            -- Aquí podrías implementar lógica para devolver algunos materiales
            -- Por ejemplo, devolver el 50% de los materiales
        end
        
        smeltingProcesses[tostring(source)] = nil
        SaveSmeltingData()
    end
end)

-- Callback para obtener estado del proceso
QBCore.Functions.CreateCallback('smelting:getProcessStatus', function(source, cb)
    local process = smeltingProcesses[tostring(source)]
    if process and process.active then
        local timeElapsed = GetGameTimer() - process.startTime
        local remainingTime = math.max(0, process.totalTime - timeElapsed)
        
        cb({
            active = true,
            remainingTime = remainingTime,
            totalTime = process.totalTime,
            results = process.results
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
