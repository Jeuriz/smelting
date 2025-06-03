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
            
            -- Mostrar UI con progreso
            local remainingTime = status.remainingTime
            if remainingTime > 0 then
                SendNUIMessage({
                    action = "showProgress",
                    totalTime = remainingTime
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
    
    lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems)
        SetNuiFocus(true, true)
        isSmeltingOpen = true
        SendNUIMessage({
            action = "openSmelting",
            items = items,
            fuel = fuel,
            outputItems = outputItems, -- Items ya procesados
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
            
            -- El progreso se maneja en la UI
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

-- Callbacks para Take Ore y Take All
RegisterNUICallback('takeOre', function(data, cb)
    lib.callback('smelting:takeOre', false, function(success, message)
        if success then
            lib.notify({
                title = 'Fundición',
                description = 'Has recogido los minerales procesados',
                type = 'success'
            })
            CloseSmeltingUI()
        else
            lib.notify({
                title = 'Fundición',
                description = message or 'No hay minerales para recoger',
                type = 'error'
            })
        end
    end)
    cb('ok')
end)

RegisterNUICallback('takeAll', function(data, cb)
    lib.callback('smelting:takeAll', false, function(success, message)
        if success then
            lib.notify({
                title = 'Fundición',
                description = 'Has recogido todo el contenido',
                type = 'success'
            })
            CloseSmeltingUI()
        else
            lib.notify({
                title = 'Fundición',
                description = message or 'No hay items para recoger',
                type = 'error'
            })
        end
    end)
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
