local QBCore = exports['qb-core']:GetCoreObject()
local isSmeltingOpen = false
local activeProcess = false

-- Función para crear blips
CreateThread(function()
    for k, v in pairs(Config.SmeltingLocations) do
        local blip = AddBlipForCoord(v.x, v.y, v.z)
        SetBlipSprite(blip, 436)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 17)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Fundición")
        EndTextCommandSetBlipName(blip)
    end
end)

-- Verificar procesos activos al spawnearse
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000) -- Esperar a que todo se cargue
    CheckActiveProcess()
end)

-- Función para verificar si hay un proceso activo
function CheckActiveProcess()
    QBCore.Functions.TriggerCallback('smelting:getProcessStatus', function(status)
        if status.active then
            activeProcess = true
            QBCore.Functions.Notify('Tienes un proceso de fundición en curso', 'info')
            
            -- Mostrar progreso restante
            local remainingTime = status.remainingTime
            if remainingTime > 0 then
                QBCore.Functions.Progressbar("smelting_process_resume", "Continuando fundición...", remainingTime, false, true, {
                    disableMovement = false,
                    disableCarMovement = false,
                    disableMouse = false,
                    disableCombat = false,
                }, {}, {}, {}, function() -- Done
                    TriggerServerEvent('smelting:completeProcess')
                    QBCore.Functions.Notify(Config.Texts['smelting_complete'], 'success')
                    activeProcess = false
                end, function() -- Cancel
                    -- No permitir cancelar procesos reanudados
                    QBCore.Functions.Notify('No puedes cancelar un proceso reanudado', 'error')
                end)
            else
                -- El proceso ya debería estar completo
                TriggerServerEvent('smelting:completeProcess')
                activeProcess = false
            end
        end
    end)
end

-- Función principal para manejar las ubicaciones
CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        
        for k, v in pairs(Config.SmeltingLocations) do
            local dist = #(pos - vector3(v.x, v.y, v.z))
            
            if dist < Config.SmeltingDistance then
                wait = 0
                
                if activeProcess then
                    QBCore.Functions.DrawText3D(v.x, v.y, v.z + 1, '[E] Verificar Proceso')
                    if IsControlJustPressed(0, 38) then -- E key
                        CheckActiveProcess()
                    end
                else
                    QBCore.Functions.DrawText3D(v.x, v.y, v.z + 1, Config.Texts['open_smelting'])
                    if IsControlJustPressed(0, 38) and not isSmeltingOpen then -- E key
                        OpenSmeltingUI()
                    end
                end
            end
        end
        
        Wait(wait)
    end
end)

-- Función para abrir la UI
function OpenSmeltingUI()
    if activeProcess then
        QBCore.Functions.Notify('Ya tienes un proceso de fundición activo', 'error')
        return
    end
    
    QBCore.Functions.TriggerCallback('smelting:getPlayerItems', function(items, fuel)
        SetNuiFocus(true, true)
        isSmeltingOpen = true
        SendNUIMessage({
            action = "openSmelting",
            items = items,
            fuel = fuel,
            smeltingRules = Config.SmeltingRules
        })
    end)
end

-- Función para cerrar la UI
function CloseSmeltingUI()
    SetNuiFocus(false, false)
    isSmeltingOpen = false
    SendNUIMessage({
        action = "closeSmelting"
    })
end

-- Callbacks NUI
RegisterNUICallback('closeSmelting', function(data, cb)
    CloseSmeltingUI()
    cb('ok')
end)

RegisterNUICallback('startSmelting', function(data, cb)
    if activeProcess then
        cb('error')
        return
    end
    
    local selectedItems = data.selectedItems
    local fuelAmount = data.fuelAmount
    local fuelType = data.fuelType
    
    QBCore.Functions.TriggerCallback('smelting:startProcess', function(success, message)
        if success then
            activeProcess = true
            QBCore.Functions.Notify(Config.Texts['smelting_started'], 'success')
            CloseSmeltingUI()
            
            -- Crear progbar con opción de salir (el proceso continuará en background)
            QBCore.Functions.Progressbar("smelting_process", "Fundiendo materiales... (Puedes desconectarte)", data.totalTime, false, false, {
                disableMovement = false,
                disableCarMovement = false,
                disableMouse = false,
                disableCombat = false,
            }, {
                animDict = "mini@repair",
                anim = "fixing_a_player",
            }, {}, {}, function() -- Done
                TriggerServerEvent('smelting:completeProcess')
                QBCore.Functions.Notify(Config.Texts['smelting_complete'], 'success')
                activeProcess = false
            end, function() -- Cancel
                -- Permitir cancelar solo si no ha pasado mucho tiempo
                TriggerServerEvent('smelting:cancelProcess')
                QBCore.Functions.Notify('Proceso cancelado', 'error')
                activeProcess = false
            end)
        else
            QBCore.Functions.Notify(message, 'error')
        end
    end, selectedItems, fuelAmount, fuelType)
    
    cb('ok')
end)

-- Event handlers
RegisterNetEvent('smelting:notify', function(message, type)
    QBCore.Functions.Notify(message, type)
end)

RegisterNetEvent('smelting:processCompleted', function()
    activeProcess = false
end)

-- Comando para verificar proceso (opcional)
RegisterCommand('checksmelt', function()
    if activeProcess then
        CheckActiveProcess()
    else
        QBCore.Functions.Notify('No tienes procesos activos', 'info')
    end
end)
