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
        AddTextComponentString("Large Furnace")
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
           
            debug = true,
            options = {
                {
                    name = 'smelting_furnace_' .. k,
                    icon = 'fas fa-fire',
                    label = 'Use Large Furnace',
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
                    label = 'Check Process',
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
                    title = 'Large Furnace',
                    description = 'You have a smelting process in progress...',
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
    
    -- Mostrar barra de progreso con ox_lib
    if lib.progressBar({
        duration = totalTime,
        label = isResuming and 'Continuing smelting process...' or 'Smelting materials...',
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
            title = 'Large Furnace',
            description = 'Smelting process completed successfully!',
            type = 'success',
            duration = 4000
        })
        
    else
        -- Cancelado (aunque canCancel está en false, por si acaso)
        StopWorkingAnimation()
        TriggerServerEvent('smelting:cancelProcess')
    end
    
    progressActive = false
end

-- Función para abrir la UI mejorada
function OpenSmeltingUI()
    if activeProcess then
        lib.notify({
            title = 'Large Furnace',
            description = 'You already have an active smelting process',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    if progressActive then
        return
    end
    
    lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems)
        SetNuiFocus(true, true)
        isSmeltingOpen = true
        SendNUIMessage({
            action = "openSmelting",
            items = items,
            fuel = fuel,
            outputItems = outputItems,
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
    if activeProcess or progressActive then
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
                title = 'Large Furnace',
                description = 'Starting smelting process...',
                type = 'success',
                duration = 3000
            })
            
            -- Cerrar UI inmediatamente
            CloseSmeltingUI()
            
            -- Esperar un poco y iniciar progreso
            Wait(500)
            StartProgressUI(totalTime, false)
            
        else
            lib.notify({
                title = 'Large Furnace',
                description = message,
                type = 'error',
                duration = 4000
            })
        end
    end, selectedItems, fuelAmount, fuelType)
    
    cb('ok')
end)

-- Callbacks para Take Ore y Take All (eliminados - entrega automática)
-- Las funciones se mantienen para compatibilidad pero no se usan

RegisterNUICallback('takeOre', function(data, cb)
    -- Ya no se usa - entrega automática
    cb('ok')
end)

RegisterNUICallback('takeAll', function(data, cb)
    -- Ya no se usa - entrega automática  
    cb('ok')
end)

-- Función para refrescar la UI sin cerrarla
function RefreshSmeltingUI()
    if isSmeltingOpen then
        lib.callback('smelting:getPlayerItems', false, function(items, fuel, outputItems)
            SendNUIMessage({
                action = "updateSmelting",
                items = items,
                fuel = fuel,
                outputItems = outputItems,
                smeltingRules = Config.SmeltingRules
            })
        end)
    end
end

-- Event handlers
RegisterNetEvent('smelting:notify', function(message, type)
    lib.notify({
        title = 'Large Furnace',
        description = message,
        type = type,
        duration = 4000
    })
end)

RegisterNetEvent('smelting:processCompleted', function()
    activeProcess = false
    progressActive = false
    StopWorkingAnimation()
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

-- Limpiar cuando el jugador muere o se desconecta
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        if victim == PlayerPedId() and IsEntityDead(victim) then
            if isFrozen then
                StopWorkingAnimation()
            end
            progressActive = false
        end
    end
end)
