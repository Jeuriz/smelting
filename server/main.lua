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

-- Función para formatear nombres de items
local function FormatItemName(itemName)
    if not itemName then return "Item desconocido" end
    return itemName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest) 
        return first:upper()..rest:lower() 
    end)
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
                TriggerClientEvent('smelting:notify', playerSource, 
                    string.format(Config.Texts['fuel_not_enough'], process.fuelNeeded, FormatItemName(process.fuelType)), 'error')
                smeltingProcesses[playerIdStr] = nil
                TriggerClientEvent('smelting:processCompleted', playerSource)
                return
            end
            
            if not hasAllItems then
                -- El jugador no tiene los items necesarios
                local missingText = "Faltan materiales: "
                for item, amount in pairs(missingItems) do
                    missingText = missingText .. FormatItemName(item) .. " x" .. amount .. ", "
                end
                
                TriggerClientEvent('smelting:notify', playerSource, 
                    Config.Texts['items_moved_during_process'], 'error')
                TriggerClientEvent('smelting:notify', playerSource, 
                    missingText:sub(1, -3), 'error')
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
            local removedItems = {}
            
            -- Remover items
            for item, amount in pairs(process.itemsToProcess) do
                local removeSuccess = exports['tgiann-inventory']:RemoveItem(playerSource, item, amount)
                if removeSuccess then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, item, "remove", amount)
                    removedItems[item] = amount
                else
                    allRemoved = false
                    TriggerClientEvent('smelting:notify', playerSource, 
                        string.format(Config.Texts['material_missing_inventory'], FormatItemName(item)), 'error')
                    print(string.format("^1[Smelting]^7 Error removing %s x%d from player %s", item, amount, playerSource))
                end
            end
            
            -- Remover combustible
            local fuelSuccess = exports['tgiann-inventory']:RemoveItem(playerSource, process.fuelType, process.fuelNeeded)
            if fuelSuccess then
                TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, process.fuelType, "remove", process.fuelNeeded)
            else
                allRemoved = false
                TriggerClientEvent('smelting:notify', playerSource, 
                    string.format(Config.Texts['fuel_missing_inventory'], FormatItemName(process.fuelType)), 'error')
            end
            
            if not allRemoved then
                TriggerClientEvent('smelting:notify', playerSource, 
                    Config.Texts['system_error'], 'error')
                smeltingProcesses[playerIdStr] = nil
                TriggerClientEvent('smelting:processCompleted', playerSource)
                return
            end
            
            -- Dar items directamente al inventario automáticamente
            local itemsGiven = false
            local itemsToStore = {}
            
            for item, amount in pairs(process.results) do
                local success = exports['tgiann-inventory']:AddItem(playerSource, item, amount)
                if success then
                    TriggerClientEvent('tgiann-inventory:client:ItemBox', playerSource, item, "add", amount)
                    itemsGiven = true
                else
                    -- Si no se puede dar al inventario, guardar para almacenar en horno
                    itemsToStore[item] = amount
                end
            end
            
            -- Almacenar items que no se pudieron dar
            if next(itemsToStore) then
                if not furnaceStorage[playerIdStr] then
                    furnaceStorage[playerIdStr] = {}
                end
                
                for item, amount in pairs(itemsToStore) do
                    if furnaceStorage[playerIdStr][item] then
                        furnaceStorage[playerIdStr][item] = furnaceStorage[playerIdStr][item] + amount
                    else
                        furnaceStorage[playerIdStr][item] = amount
                    end
                end
                
                TriggerClientEvent('smelting:notify', playerSource, 
                    Config.Texts['inventory_full_stored'], 'warning')
            end
            
            if itemsGiven then
                TriggerClientEvent('smelting:notify', playerSource, 
                    Config.Texts['smelting_complete'], 'success')
            end
            
            TriggerClientEvent('smelting:processCompleted', playerSource)
            
            -- Log exitoso
            print(string.format("^2[Smelting]^7 Player %s (%s) completed smelting process successfully", 
                Player.PlayerData.name, Player.PlayerData.citizenid))
                
        else
            -- Jugador desconectado, marcar para auto-completar cuando regrese
            if process.results then
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
            end
            
            print(string.format("^3[Smelting]^7 Process completed for disconnected player %s, items stored", playerIdStr))
        end
        
        -- Limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    else
        -- Jugador no está conectado, limpiar proceso
        smeltingProcesses[playerIdStr] = nil
    end
end

-- Función para verificar skills del jugador
local function GetPlayerSkills(source)
    local skills = {}
    
    -- Verificar cada skill requerida para los slots
    for slot, skillName in pairs(Config.SlotSkills) do
        if skillName then
            -- Usar el sistema de devhub_skillTree para verificar si la skill está desbloqueada
            local success, result = pcall(function()
                return exports['devhub_skillTree']:hasUnlockedSkill('personal', skillName, source)
            end)
            
            if success then
                skills[skillName] = result or false
            else
                -- Si hay error, asumir que no tiene la skill
                skills[skillName] = false
                print(string.format("^1[Smelting]^7 Error checking skill %s for player %s: %s", skillName, source, result or "unknown"))
            end
        end
    end
    
    return skills
end

-- Función para verificar si un jugador puede usar un slot específico
local function CanUseSlot(source, slotNumber)
    local requiredSkill = Config.SlotSkills[slotNumber]
    
    -- Si no requiere skill, siempre puede usarlo
    if not requiredSkill then
        return true
    end
    
    -- Verificar si tiene la skill
    local success, hasSkill = pcall(function()
        return exports['devhub_skillTree']:hasUnlockedSkill('personal', requiredSkill, source)
    end)
    
    if success then
        return hasSkill or false
    else
        print(string.format("^1[Smelting]^7 Error checking skill %s for player %s", requiredSkill, source))
        return false
    end
end

-- Función para validar que los items seleccionados respeten las skills
local function ValidateSelectedItems(source, selectedItems)
    local availableSlots = 0
    
    -- Contar slots disponibles basado en skills
    for slot = 1, 5 do
        if CanUseSlot(source, slot) then
            availableSlots = availableSlots + 1
        end
    end
    
    -- Verificar que no se excedan los slots disponibles
    local selectedCount = 0
    for item, amount in pairs(selectedItems) do
        if amount > 0 then
            selectedCount = selectedCount + 1
        end
    end
    
    if selectedCount > availableSlots then
        return false, string.format(Config.Texts['max_slots_reached'], availableSlots)
    end
    
    return true, nil
end

-- Callback con ox_lib para obtener items del jugador (ACTUALIZADO CON SKILL LABELS)
lib.callback.register('smelting:getPlayerItems', function(source)
    local items = {}
    local fuel = {}
    local outputItems = {}
    local playerSkills = {}
    local skillLabels = {}
    
    if not source then
        return items, fuel, outputItems, playerSkills, skillLabels
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
    
    -- Obtener skills del jugador
    playerSkills = GetPlayerSkills(source)
    
    -- Enviar labels de skills
    skillLabels = Config.SkillLabels or {}
    
    return items, fuel, outputItems, playerSkills, skillLabels
end)

-- Callbacks simplificados para take (solo para casos especiales donde el inventario estaba lleno)
lib.callback.register('smelting:takeStoredItems', function(source)
    if not source then
        return false, Config.Texts['system_error']
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, Config.Texts['player_error']
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, Config.Texts['no_items_to_collect']
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
        return true, Config.Texts['all_items_collected']
    elseif given and remaining then
        return true, "Algunos objetos recolectados, inventario aún lleno"
    else
        return false, "Inventario lleno, no se pudieron recolectar objetos"
    end
end)

-- Callback con ox_lib para iniciar proceso (MEJORADO CON VALIDACIONES DETALLADAS)
lib.callback.register('smelting:startProcess', function(source, selectedItems, fuelAmount, fuelType)
    if not source then
        return false, Config.Texts['system_error']
    end
    
    local sourceStr = tostring(source)
    local now = GetGameTimer()
    
    -- Verificar cooldown para prevenir spam
    if playerCooldowns[sourceStr] and (now - playerCooldowns[sourceStr]) < 3000 then
        return false, Config.Texts['process_cooldown']
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then 
        return false, Config.Texts['player_error']
    end
    
    -- Verificar si ya tiene un proceso activo
    if smeltingProcesses[sourceStr] and smeltingProcesses[sourceStr].active then
        return false, Config.Texts['process_in_progress']
    end
    
    -- Validar parámetros básicos
    if not selectedItems or type(selectedItems) ~= "table" or not next(selectedItems) then
        return false, Config.Texts['need_materials_selected']
    end
    
    if not fuelType or fuelType == "" then
        return false, Config.Texts['need_fuel_selected']
    end
    
    fuelAmount = tonumber(fuelAmount) or 0
    if fuelAmount <= 0 then
        return false, Config.Texts['fuel_amount_invalid']
    end
    
    -- Limpiar cache antes de verificar
    for key, _ in pairs(itemsCache) do
        if string.find(key, tostring(source) .. "_") then
            itemsCache[key] = nil
        end
    end
    
    -- Verificar combustible PRIMERO
    local fuelCount = GetItemCount(source, fuelType)
    if fuelCount <= 0 then
        return false, string.format(Config.Texts['fuel_missing_inventory'], FormatItemName(fuelType))
    end
    
    if fuelCount < fuelAmount then
        return false, string.format(Config.Texts['fuel_not_enough'], fuelAmount, FormatItemName(fuelType))
    end
    
    -- Validar items seleccionados respecto a skills
    local skillValidation, skillError = ValidateSelectedItems(source, selectedItems)
    if not skillValidation then
        return false, skillError
    end
    
    -- Verificar materiales DETALLADAMENTE y calcular resultados
    local totalTime = 0
    local results = {}
    local totalFuelNeeded = 0
    local itemsToProcess = {} -- Guardar items para verificar al final
    local materialErrors = {}
    
    for item, amount in pairs(selectedItems) do
        if item and amount and Config.SmeltingRules and Config.SmeltingRules[item] then
            amount = tonumber(amount) or 0
            if amount > 0 then
                local itemCount = GetItemCount(source, item)
                
                -- Verificar si tiene el item
                if itemCount <= 0 then
                    materialErrors[#materialErrors + 1] = string.format(
                        Config.Texts['material_missing_inventory'], FormatItemName(item)
                    )
                elseif itemCount < amount then
                    materialErrors[#materialErrors + 1] = string.format(
                        Config.Texts['material_not_enough'], FormatItemName(item), amount, itemCount
                    )
                else
                    -- Material válido, procesar
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
    end
    
    -- Si hay errores de materiales, reportarlos
    if #materialErrors > 0 then
        for _, error in ipairs(materialErrors) do
            TriggerClientEvent('smelting:notify', source, error, 'error')
        end
        return false, "Revisa los materiales necesarios"
    end
    
    -- Verificar si no hay items válidos para procesar
    if next(itemsToProcess) == nil then
        return false, Config.Texts['no_materials']
    end
    
    -- Verificar si tiene suficiente combustible para TODO el proceso
    if fuelAmount < totalFuelNeeded then
        local shortage = totalFuelNeeded - fuelAmount
        TriggerClientEvent('smelting:notify', source, 
            string.format(Config.Texts['total_fuel_needed'], totalFuelNeeded), 'info')
        TriggerClientEvent('smelting:notify', source, 
            string.format(Config.Texts['fuel_shortage'], shortage), 'error')
        return false, string.format(Config.Texts['fuel_shortage'], shortage)
    end
    
    -- Verificar disponibilidad final de combustible
    if fuelCount < totalFuelNeeded then
        return false, string.format(Config.Texts['fuel_not_enough'], totalFuelNeeded, FormatItemName(fuelType))
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
    print(string.format("^2[Smelting]^7 Player %s (%s) started smelting process (%.1fs, %d fuel needed)", 
        Player.PlayerData.name, Player.PlayerData.citizenid, totalTime / 1000, totalFuelNeeded))
    
    -- Notificar al jugador sobre el combustible que se usará
    TriggerClientEvent('smelting:notify', source, 
        string.format("Combustible a usar: %d unidades de %s", totalFuelNeeded, FormatItemName(fuelType)), 'info')
    
    -- Iniciar timer
    CreateThread(function()
        if totalTime and totalTime > 0 then
            Wait(totalTime)
            CompleteSmeltingProcess(sourceStr)
        end
    end)
    
    return true, Config.Texts['smelting_started'], totalTime
end)

-- Callback para tomar solo minerales procesados
lib.callback.register('smelting:takeOre', function(source)
    if not source then
        return false, Config.Texts['system_error']
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, Config.Texts['player_error']
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, Config.Texts['no_items_to_collect']
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
    
    return given, given and Config.Texts['materials_collected'] or "No se pudieron recolectar materiales"
end)

-- Callback para tomar todo
lib.callback.register('smelting:takeAll', function(source)
    if not source then
        return false, Config.Texts['system_error']
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        return false, Config.Texts['player_error']
    end
    
    local sourceStr = tostring(source)
    
    if not furnaceStorage[sourceStr] or next(furnaceStorage[sourceStr]) == nil then
        return false, Config.Texts['no_items_to_collect']
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
    
    return given, given and Config.Texts['all_items_collected'] or "No se pudieron recolectar objetos"
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
        TriggerClientEvent('smelting:notify', source, Config.Texts['process_cancelled'], 'info')
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
        
        -- Verificar skills del jugador
        local playerSkills = GetPlayerSkills(source)
        print("^3[Smelting Debug]^7 === PLAYER SKILLS ===")
        for skill, unlocked in pairs(playerSkills) do
            local label = Config.SkillLabels[skill] or skill
            print("^2[Smelting Debug]^7 " .. label .. " (" .. skill .. "): " .. tostring(unlocked))
        end
        
        TriggerClientEvent('smelting:notify', source, 'Revisa la consola del servidor para información de debug', 'info')
    end
end)

-- Callback NUI para refrescar la UI
RegisterNetEvent('__cfx_nui:refreshUI', function()
    local source = source
    if not source then return end
    
    -- Obtener datos actualizados del jugador con skill labels
    lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems, playerSkills, skillLabels)
        -- Enviar datos actualizados a la UI
        TriggerClientEvent('smelting:refreshUIData', source, {
            items = items,
            fuel = fuel,
            outputItems = outputItems,
            smeltingRules = Config.SmeltingRules,
            playerSkills = playerSkills,
            skillLabels = skillLabels,
            slotSkills = Config.SlotSkills
        })
    end, source)
end)

-- Event para enviar datos de refresh al cliente
RegisterNetEvent('smelting:refreshUIData', function(data)
    -- Este evento se enviará desde el servidor al cliente
    -- No necesita código aquí, solo está registrado para el cliente
end)
