local QBCore = exports['qb-core']:GetCoreObject()
local isSmeltingOpen = false
local activeProcess = false
local isFrozen = false
local progressActive = false

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
        AddTextComponentString("Horno Grande")
        EndTextCommandSetBlipName(blip)
    end
end)

-- Configurar ox_target para las ubicaciones
CreateThread(function()
    Wait(1000) -- Esperar a que ox_target esté listo
    
    for k, v in pairs(Config.SmeltingLocations) do
        -- Crear el target zone
        exports.ox_target:addBoxZone({
            coords = vector3(v.x, v.y, v.z),
            size = vector3(2.0, 2.0, 2.0),
            rotation = 0,
           
            debug = false ,
            options = {
                {
                    name = 'smelting_furnace_' .. k,
                    icon = 'fas fa-fire',
                    label = Config.Texts['open_smelting'],
                    distance = 1,
                    canInteract = function()
                        return not progressActive
                    end,
                    onSelect = function()
                        if activeProcess and not isSmeltingOpen then
                            CheckActiveProcess()
                        elseif not isSmeltingOpen and not progressActive then
                            OpenSmeltingUI()
                        end
                    end
                },
                {
                    name = 'check_process_' .. k,
                    icon = 'fas fa-clock',
                    label = Config.Texts['check_process'],
                    canInteract = function()
                        return activeProcess and not isSmeltingOpen and not progressActive
                    end,
                    onSelect = function()
                        CheckActiveProcess()
                    end
                }
            }
        })
    end
end)

-- Verificar procesos activos al spawnearse
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000) -- Esperar a que todo se cargue
    CheckActiveProcess()
end)

-- Función para verificar si hay un proceso activo
function CheckActiveProcess()
    if progressActive then return end
    
    lib.callback('smelting:getProcessStatus', false, function(status)
        if status.active then
            activeProcess = true
            
            local remainingTime = status.remainingTime
            if remainingTime > 1000 then -- Solo si queda más de 1 segundo
                lib.notify({
                    title = 'Horno Grande',
                    description = Config.Texts['process_in_progress'],
                    type = 'info',
                    duration = 3000
                })
                
                -- Mostrar progreso en UI
                StartProgressUI(remainingTime, true)
                
            else
                -- El proceso ya debería estar completo
                TriggerServerEvent('smelting:completeProcess')
                activeProcess = false
            end
        else
            activeProcess = false
        end
    end)
end

-- Función para iniciar animación de trabajo
function StartWorkingAnimation()
    local ped = PlayerPedId()
    
    -- Cargar animación
    local animDict = "amb@prop_human_bbq@male@base"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end
    
    -- Iniciar animación
    TaskPlayAnim(ped, animDict, "base", 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Freezar al jugador
    FreezeEntityPosition(ped, true)
    isFrozen = true
end

-- Función para detener animación y desfreezar
function StopWorkingAnimation()
    local ped = PlayerPedId()
    
    -- Detener animación
    StopAnimTask(ped, "amb@prop_human_bbq@male@base", "base", 1.0)
    
    -- Desfreezar jugador
    FreezeEntityPosition(ped, false)
    isFrozen = false
end

-- Función para mostrar progreso mejorado
function StartProgressUI(totalTime, isResuming)
    if progressActive then return end
    
    progressActive = true
    
    -- Cerrar UI de fundición si está abierta
    if isSmeltingOpen then
        CloseSmeltingUI()
    end
    
    -- Iniciar animación
    StartWorkingAnimation()
    
    -- Determinar el mensaje de progreso
    local progressLabel = isResuming and 'Continuando proceso de fundición...' or 'Fundiendo materiales...'
    
    -- Mostrar barra de progreso con ox_lib
    if lib.progressBar({
        duration = totalTime,
        label = progressLabel,
        useWhileDead = false,
        canCancel = false,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = 'amb@prop_human_bbq@male@base',
            clip = 'base'
        },
    }) then
        -- Completado exitosamente
        StopWorkingAnimation()
        
        -- Esperar un poco antes de completar
        Wait(500)
        
        if isResuming then
            -- Si estaba reanudando, el servidor ya manejará la finalización
            activeProcess = false
        else
            -- Si era un proceso nuevo, triggear completion
            TriggerServerEvent('smelting:completeProcess')
        end
        
        lib.notify({
            title = 'Horno Grande',
            description = Config.Texts['smelting_complete'],
            type = 'success',
            duration = 4000
        })
        
    else
        -- Cancelado (aunque canCancel está en false, por si acaso)
        StopWorkingAnimation()
        TriggerServerEvent('smelting:cancelProcess')
        
        lib.notify({
            title = 'Horno Grande',
            description = Config.Texts['process_cancelled'],
            type = 'warning',
            duration = 3000
        })
    end
    
    progressActive = false
end

-- Función para abrir la UI mejorada con validaciones de inventario
function OpenSmeltingUI()
    if activeProcess then
        lib.notify({
            title = 'Horno Grande',
            description = Config.Texts['process_in_progress'],
            type = 'error',
            duration = 3000
        })
        return
    end
    
    if progressActive then
        return
    end
    
    -- -- Mostrar notificación de carga
    -- lib.notify({
    --     title = 'Horno Grande',
    --     description = 'Cargando inventario...',
    --     type = 'info',
    --     duration = 2000
    -- })
    
    lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems, playerSkills, skillLabels)
        -- -- Verificar si el jugador tiene items para fundir
        -- if not items or not next(items) then
        --     lib.notify({
        --         title = 'Horno Grande',
        --         description = 'No tienes materiales para fundir',
        --         type = 'error',
        --         duration = 4000
        --     })
        --     return
        -- end
        
        -- -- Verificar si el jugador tiene combustible
        -- if not fuel or not next(fuel) then
        --     lib.notify({
        --         title = 'Horno Grande',
        --         description = 'No tienes combustible para el horno',
        --         type = 'error',
        --         duration = 4000
        --     })
        --     return
        -- end
        
        -- Abrir la UI solo si tiene materiales y combustible
        SetNuiFocus(true, true)
        isSmeltingOpen = true
        SendNUIMessage({
            action = "openSmelting",
            items = items,
            fuel = fuel,
            outputItems = outputItems,
            smeltingRules = Config.SmeltingRules,
            playerSkills = playerSkills or {},
            skillLabels = skillLabels or {},
            slotSkills = Config.SlotSkills
        })
        
        -- Notificación de ayuda
        -- lib.notify({
        --     title = 'Horno Grande',
        --     description = 'Selecciona combustible y materiales para empezar',
        --     type = 'info',
        --     duration = 5000
        -- })
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
    if activeProcess or progressActive then
        lib.notify({
            title = 'Horno Grande',
            description = Config.Texts['process_in_progress'],
            type = 'error',
            duration = 3000
        })
        cb('error')
        return
    end
    
    local selectedItems = data.selectedItems
    local fuelAmount = data.fuelAmount
    local fuelType = data.fuelType
    
    -- Validaciones del lado cliente ANTES de enviar al servidor
    if not selectedItems or not next(selectedItems) then
        lib.notify({
            title = 'Horno Grande',
            description = 'Debes seleccionar materiales para fundir',
            type = 'error',
            duration = 4000
        })
        cb('error')
        return
    end
    
    if not fuelType or fuelType == "" then
        lib.notify({
            title = 'Horno Grande',
            description = 'Debes seleccionar un combustible',
            type = 'error',
            duration = 4000
        })
        cb('error')
        return
    end
    
    if not fuelAmount or tonumber(fuelAmount) <= 0 then
        lib.notify({
            title = 'Horno Grande',
            description = 'Cantidad de combustible inválida',
            type = 'error',
            duration = 4000
        })
        cb('error')
        return
    end
    
    -- Calcular combustible necesario para mostrar información
    local totalFuelNeeded = 0
    for item, amount in pairs(selectedItems) do
        if Config.SmeltingRules[item] then
            totalFuelNeeded = totalFuelNeeded + (Config.SmeltingRules[item].fuel_needed * amount)
        end
    end
    
    if tonumber(fuelAmount) < totalFuelNeeded then
        lib.notify({
            title = 'Horno Grande',
            description = string.format('Necesitas %d unidades de combustible para este proceso', totalFuelNeeded),
            type = 'error',
            duration = 5000
        })
        cb('error')
        return
    end
    
    -- Mostrar notificación de validación
    lib.notify({
        title = 'Horno Grande',
        description = 'Validando materiales y combustible...',
        type = 'info',
        duration = 2000
    })
    
    lib.callback('smelting:startProcess', false, function(success, message, totalTime)
        if success then
            activeProcess = true
            
            lib.notify({
                title = 'Horno Grande',
                description = Config.Texts['smelting_started'],
                type = 'success',
                duration = 3000
            })
            
            -- Cerrar UI inmediatamente
            CloseSmeltingUI()
            
            -- Esperar un poco y iniciar progreso
            Wait(500)
            StartProgressUI(totalTime, false)
            
        else
            -- El servidor envió un error específico
            lib.notify({
                title = 'Horno Grande',
                description = message or 'Error desconocido',
                type = 'error',
                duration = 6000
            })
        end
    end, selectedItems, fuelAmount, fuelType)
    
    cb('ok')
end)

-- Callbacks para Take Ore y Take All (eliminados - entrega automática)
RegisterNUICallback('takeOre', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('takeAll', function(data, cb)
    cb('ok')
end)

-- Callback NUI para refrescar UI (ACTUALIZADO CON SKILL LABELS)
RegisterNUICallback('refreshUI', function(data, cb)
    if isSmeltingOpen then
        -- Mostrar notificación de actualización
        -- lib.notify({
        --     title = 'Horno Grande',
        --     description = 'Actualizando inventario...',
        --     type = 'info',
        --     duration = 2000
        -- })
        
        -- Solicitar datos actualizados del servidor incluyendo skills y labels
        lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems, playerSkills, skillLabels)
            -- Verificar si el jugador perdió sus materiales o combustible
            local hasItems = items and next(items)
            local hasFuel = fuel and next(fuel)
            
            if not hasItems and not hasFuel then
                lib.notify({
                    title = 'Horno Grande',
                    description = 'No tienes materiales ni combustible',
                    type = 'warning',
                    duration = 4000
                })
                CloseSmeltingUI()
                cb('ok')
                return
            elseif not hasItems then
                lib.notify({
                    title = 'Horno Grande',
                    description = 'No tienes materiales para fundir',
                    type = 'warning',
                    duration = 4000
                })
            elseif not hasFuel then
                lib.notify({
                    title = 'Horno Grande',
                    description = 'No tienes combustible',
                    type = 'warning',
                    duration = 4000
                })
            end
            
            -- Enviar datos actualizados a la UI con la acción correcta
            SendNUIMessage({
                action = "refreshComplete",
                items = items,
                fuel = fuel,
                outputItems = outputItems,
                smeltingRules = Config.SmeltingRules,
                playerSkills = playerSkills or {},
                skillLabels = skillLabels or {},
                slotSkills = Config.SlotSkills
            })
        end)
    end
    cb('ok')
end)

-- Event handlers
RegisterNetEvent('smelting:notify', function(message, type)
    lib.notify({
        title = 'Horno Grande',
        description = message,
        type = type or 'info',
        duration = type == 'error' and 6000 or 4000
    })
end)

RegisterNetEvent('smelting:processCompleted', function()
    activeProcess = false
    progressActive = false
    StopWorkingAnimation()
    
    -- Notificación adicional de finalización
    lib.notify({
        title = 'Horno Grande',
        description = 'El proceso de fundición ha finalizado',
        type = 'success',
        duration = 4000
    })
end)

-- Event handler para datos de refresh (ACTUALIZADO CON SKILL LABELS)
RegisterNetEvent('smelting:refreshUIData', function(data)
    if isSmeltingOpen then
        SendNUIMessage({
            action = "refreshComplete",
            items = data.items,
            fuel = data.fuel,
            outputItems = data.outputItems,
            smeltingRules = data.smeltingRules,
            playerSkills = data.playerSkills or {},
            skillLabels = data.skillLabels or {},
            slotSkills = data.slotSkills or Config.SlotSkills
        })
    end
end)

-- Event handler para auto-completar procesos
RegisterNetEvent('smelting:autoCompleteProcess', function()
    if not progressActive then
        lib.notify({
            title = 'Horno Grande',
            description = Config.Texts['process_auto_complete'],
            type = 'success',
            duration = 5000
        })
        activeProcess = false
    end
end)



-- Limpiar al descargar el recurso
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if isFrozen then
            StopWorkingAnimation()
        end
        if isSmeltingOpen then
            CloseSmeltingUI()
        end
        progressActive = false
    end
end)

-- Limpiar cuando el jugador muere
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        if victim == PlayerPedId() and IsEntityDead(victim) then
            if isFrozen then
                StopWorkingAnimation()
            end
            if isSmeltingOpen then
                CloseSmeltingUI()
            end
            progressActive = false
            
            -- Notificar sobre proceso interrumpido
            if activeProcess then
                lib.notify({
                    title = 'Horno Grande',
                    description = 'El proceso fue interrumpido por la muerte',
                    type = 'warning',
                    duration = 4000
                })
            end
        end
    end
end)

-- Event handler para errores de inventario
RegisterNetEvent('smelting:inventoryError', function(errorType, itemName, amount)
    local message = ""
    
    if errorType == "insufficient_fuel" then
        message = string.format("Combustible insuficiente: %s", itemName or "desconocido")
    elseif errorType == "insufficient_material" then
        message = string.format("Material insuficiente: %s (necesitas %d)", itemName or "desconocido", amount or 0)
    elseif errorType == "item_missing" then
        message = string.format("El objeto %s ya no está en tu inventario", itemName or "desconocido")
    else
        message = "Error de inventario desconocido"
    end
    
    lib.notify({
        title = 'Error de Inventario',
        description = message,
        type = 'error',
        duration = 5000
    })
end)
