local QBCore = exports['qb-core']:GetCoreObject()
local isSmeltingOpen = false

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
                QBCore.Functions.DrawText3D(v.x, v.y, v.z + 1, Config.Texts['open_smelting'])
                
                if IsControlJustPressed(0, 38) and not isSmeltingOpen then -- E key
                    OpenSmeltingUI()
                end
            end
        end
        
        Wait(wait)
    end
end)

-- Función para abrir la UI
function OpenSmeltingUI()
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
    local selectedItems = data.selectedItems
    local fuelAmount = data.fuelAmount
    local fuelType = data.fuelType
    
    QBCore.Functions.TriggerCallback('smelting:startProcess', function(success, message)
        if success then
            QBCore.Functions.Notify(Config.Texts['smelting_started'], 'success')
            CloseSmeltingUI()
            
            -- Crear progbar
            QBCore.Functions.Progressbar("smelting_process", "Fundiendo materiales...", data.totalTime, false, true, {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            }, {
                animDict = "mini@repair",
                anim = "fixing_a_player",
            }, {}, {}, function() -- Done
                TriggerServerEvent('smelting:completeProcess')
                QBCore.Functions.Notify(Config.Texts['smelting_complete'], 'success')
            end, function() -- Cancel
                TriggerServerEvent('smelting:cancelProcess')
                QBCore.Functions.Notify('Proceso cancelado', 'error')
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
