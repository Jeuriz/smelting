local QBCore = exports['qb-core']:GetCoreObject()
local smeltingProcesses = {}

-- Callback para obtener items del jugador
QBCore.Functions.CreateCallback('smelting:getPlayerItems', function(source, cb)
    local items = {}
    local fuel = {}
    
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

-- Callback para iniciar proceso de fundición
QBCore.Functions.CreateCallback('smelting:startProcess', function(source, cb, selectedItems, fuelAmount, fuelType)
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
    
    -- Guardar proceso para completar después
    smeltingProcesses[source] = {
        results = results,
        startTime = GetGameTimer()
    }
    
    cb(true, 'Proceso iniciado', totalTime)
end)

-- Event para completar proceso
RegisterNetEvent('smelting:completeProcess', function()
    local source = source
    
    if not smeltingProcesses[source] then return end
    
    local process = smeltingProcesses[source]
    
    -- Dar items resultantes usando tgiann-inventory exports
    for item, amount in pairs(process.results) do
        local success = exports['tgiann-inventory']:AddItem(source, item, amount)
        if success then
            TriggerClientEvent('tgiann-inventory:client:ItemBox', source, item, "add", amount)
        end
    end
    
    -- Limpiar proceso
    smeltingProcesses[source] = nil
    
    TriggerClientEvent('smelting:notify', source, Config.Texts['smelting_complete'], 'success')
end)

-- Event para cancelar proceso
RegisterNetEvent('smelting:cancelProcess', function()
    local source = source
    smeltingProcesses[source] = nil
end)
