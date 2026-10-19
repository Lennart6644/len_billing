ESX = nil

Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Citizen.Wait(100)
    end
end)

local isOpen = false

local allowedRequests = {
    getContext = true,
    getPlayers = true,
    getInbox = true,
    getPrivateIssued = true,
    getPriceList = true,
    getJobInvoices = true,
    issue = true,
    pay = true,
    cancel = true,
    getPrices = true,
    saveCategory = true,
    deleteCategory = true,
    saveItem = true,
    deleteItem = true,
}

local function baseMessage(action)
    return {
        action = action,
        locale = Locales[Config.Locale] or Locales.de,
        config = {
            currency = Config.Currency,
            taxPercent = Config.TaxPercent,
            dueDays = Config.DueDays,
            lateFeePercent = Config.LateFeePercent,
            city = Config.DefaultCity,
            paper = Config.Paper,
            maxReason = Config.MaxReasonLength,
            maxDescription = Config.MaxDescriptionLength,
            maxQuantity = Config.MaxQuantity,
            maxUnitPrice = Config.MaxUnitPrice,
            maxItems = Config.MaxItems,
        },
    }
end

local function setOpen(state)
    isOpen = state
    SetNuiFocus(state, state)
    if not state then
        ClearPedTasks(PlayerPedId())
    end
end

local function openTerminal(mode, admin)
    if isOpen then
        return
    end
    ESX.TriggerServerCallback('billing:getContext', function(context)
        setOpen(true)
        TaskStartScenarioInPlace(PlayerPedId(), 'WORLD_HUMAN_CLIPBOARD', 0, true)
        local message = baseMessage('open')
        message.mode = mode
        message.admin = admin == true
        message.context = context
        SendNUIMessage(message)
    end, admin == true)
end

RegisterCommand(Config.Command, function()
    openTerminal('bills')
end, false)

RegisterNetEvent('billing:open', function()
    openTerminal('issue')
end)

RegisterNetEvent('billing:showPrinted', function(invoice)
    setOpen(true)
    local message = baseMessage('printed')
    message.invoice = invoice
    SendNUIMessage(message)
end)

RegisterNUICallback('request', function(payload, cb)
    if type(payload) ~= 'table' or not allowedRequests[payload.name] then
        return cb({ success = false })
    end
    ESX.TriggerServerCallback('billing:' .. payload.name, function(result)
        cb(result or {})
    end, payload.data)
end)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb('ok')
end)

RegisterNetEvent('billing:openAdmin', function()
    openTerminal('issue', true)
end)
