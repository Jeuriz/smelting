local QBCore = exports['qb-core']:GetCoreObject()
local isSmeltingOpen = false
local activeProcess = false

-- Cache de ox_lib
local cache = {
    ped = cache.ped,
    coords = cache.coords,
    vehicle = cache.vehicle
}

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
    lib.callback('smelting:getProcessStatus', false, function(status)
        if status.active then
            activeProcess = true
            lib.notify({
                title = 'Fundición',
                description = 'Tienes un proceso de fundición en curso',
                type = 'info'
            })
            
            -- Mostrar progreso restante
            local remainingTime = status.remainingTime
            if remainingTime > 0 then
                lib.progressBar({
                    duration = remainingTime,
                    label = 'Continuando fundición...',
                    useWhileDead = false,
                    canCancel = false,
                    disable = {
                        car = false,
                        move = false,
                        combat = false
                    }
                })
                
                -- Esperar a que termine y completar
                SetTimeout(remainingTime, function()
                    TriggerServerEvent('smelting:completeProcess')
                    lib.notify({
                        title = 'Fundición',
                        description = Config.Texts['smelting_complete'],
                        type = 'success'
                    })
                    activeProcess = false
                end)
            else
                -- El proceso ya debería estar completo
                TriggerServerEvent('smelting:completeProcess')
                activeProcess = false
            end
        end
    end)
end

-- Función principal para manejar las ubicaciones con ox_lib
CreateThread(function()
    -- Crear puntos de interacción con ox_lib
    for k, v in pairs(Config.SmeltingLocations) do
        local point = lib.points.new({
            coords = vector3(v.x, v.y, v.z),
            distance = Config.SmeltingDistance,
            duiId = 'smelting_' .. k,
        })

        function point:onEnter()
            if activeProcess then
                lib.showTextUI('[E] Verificar Proceso', {
                    position = "top-center",
                    icon = 'fire',
                    style = {
                        borderRadius = 4,
                        backgroundColor = '#ff6b35',
                        color = 'white'
                    }
                })
            else
                lib.showTextUI(Config.Texts['open_smelting'], {
                    position = "top-center",
                    icon = 'fire',
                    style = {
                        borderRadius = 4,
                        backgroundColor = '#ff6b35',
                        color = 'white'
                    }
                })
            end
        end

        function point:onExit()
            lib.hideTextUI()
        end

        function point:nearby()
            if self.currentDistance < 2.0 then
                if IsControlJustPressed(0, 38) then -- E key
                    if activeProcess then
                        CheckActiveProcess()
                    elseif not isSmeltingOpen then
                        OpenSmeltingUI()
                    end
                end
            end
        end
    end
end)

-- Función para abrir la UI
function OpenSmeltingUI()
    if activeProcess then
        lib.notify({
            title = 'Fundición',
            description = 'Ya tienes un proceso de fundición activo',
            type = 'error'
        })
        return
    end
    
    lib.callback('smelting:getPlayerItems', false, function(items, fuel)
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
    
    lib.callback('smelting:startProcess', false, function(success, message, totalTime)
        if success then
            activeProcess = true
            lib.notify({
                title = 'Fundición',
                description = Config.Texts['smelting_started'],
                type = 'success'
            })
            CloseSmeltingUI()
            
            -- Crear progbar con ox_lib
            local progressSuccess = lib.progressBar({
                duration = totalTime,
                label = 'Fundiendo materiales... (Puedes desconectarte)',
                useWhileDead = false,
                canCancel = true,
                disable = {
                    car = false,
                    move = false,
                    combat = false
                },
                anim = {
                    dict = 'mini@repair',
                    clip = 'fixing_a_player'
                }
            })
            
            if progressSuccess then
                -- Completado
                TriggerServerEvent('smelting:completeProcess')
                lib.notify({
                    title = 'Fundición',
                    description = Config.Texts['smelting_complete'],
                    type = 'success'
                })
                activeProcess = false
            else
                -- Cancelado
                TriggerServerEvent('smelting:cancelProcess')
                lib.notify({
                    title = 'Fundición',
                    description = 'Proceso cancelado',
                    type = 'error'
                })
                activeProcess = false
            end
        else
            lib.notify({
                title = 'Fundición',
                description = message,
                type = 'error'
            })
        end
    end, selectedItems, fuelAmount, fuelType)
    
    cb('ok')
end)

-- Event handlers
RegisterNetEvent('smelting:notify', function(message, type)
    lib.notify({
        title = 'Fundición',
        description = message,
        type = type
    })
end)

RegisterNetEvent('smelting:processCompleted', function()
    activeProcess = false
end)

-- Comando para verificar proceso con ox_lib
lib.addCommand('checksmelt', {
    help = 'Verificar proceso de fundición activo',
    restricted = false
}, function(source, args, raw)
    if activeProcess then
        CheckActiveProcess()
    else
        lib.notify({
            title = 'Fundición',
            description = 'No tienes procesos activos',
            type = 'info'
        })
    end
end)

-- Limpiar al descargar el recurso
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        lib.hideTextUI()
        if isSmeltingOpen then
            CloseSmeltingUI()
        end
    end
end)
