local billItemSession = {}
local SESSION_TIMEOUT = 300 -- Sekunden

AddEventHandler('playerDropped', function()
    billItemSession[source] = nil
end)

ESX.RegisterServerCallback('billing:getContext', function(source, cb, isCommand)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return cb({})
    end
    local isAdmin = Billing.CanIssueAs(xPlayer, isCommand == true)
    local job = Config.Jobs[xPlayer.job.name]
    local allJobs = {}
    if isAdmin then
        for name, j in pairs(Config.Jobs) do
            allJobs[#allJobs + 1] = {
                name = name, label = j.label, short = j.short, color = j.color, icon = j.icon,
                defaultReason = L(j.defaultReason or 'reason_job'),
            }
        end
        table.sort(allJobs, function(a, b) return a.label < b.label end)
    end
    cb({
        name = xPlayer.getName(),
        isAdmin = isAdmin,
        allJobs = allJobs,
        canBillJob = job ~= nil or isAdmin,
        isLeader = job ~= nil and Billing.IsLeader(xPlayer.job.name, xPlayer.job.grade),
        jobLabel = job and job.label or nil,
        jobLimit = job and job.limit or nil,
        privateLimit = Config.MaxPrivateTotal,
        privateStyle = Config.PrivateStyle,
        jobStyle = job and { label = job.label, short = job.short, color = job.color, icon = job.icon } or nil,
        priceList = Billing.GetPriceList(xPlayer.job.name),
        taxPercent = Config.TaxPercent,
        defaultReasonPrivate = L('reason_private'),
        defaultReasonJob = L(job and job.defaultReason or 'reason_job'),
    })
end)

ESX.RegisterServerCallback('billing:getPlayers', function(source, cb)
    local players = {}
    for _, xPlayer in ipairs(ESX.GetExtendedPlayers()) do
        players[#players + 1] = { id = xPlayer.source, name = xPlayer.getName() }
    end
    cb(players)
end)

ESX.RegisterServerCallback('billing:getInbox', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    local billType = type(data) == 'table' and data.billType == 'job' and 'job' or 'private'
    cb(xPlayer and Billing.GetInvoicesForTarget(xPlayer.identifier, billType) or {})
end)

ESX.RegisterServerCallback('billing:getPrivateIssued', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    cb(xPlayer and Billing.GetPrivateIssued(xPlayer.identifier) or {})
end)

ESX.RegisterServerCallback('billing:getJobInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Billing.IsLeader(xPlayer.job.name, xPlayer.job.grade) then
        return cb({})
    end
    cb(Billing.GetJobInvoicesAll(xPlayer.job.name))
end)

ESX.RegisterServerCallback('billing:issue', function(source, cb, form)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or type(form) ~= 'table' then
        return cb({ success = false, message = L('err_invalid_data') })
    end

    -- Dokument nur, wenn die Rechnung über das Item "bill" gestartet wurde (und nicht zu alt ist)
    local startedAt = billItemSession[source]
    local fromItem = startedAt ~= nil and (os.time() - startedAt) <= SESSION_TIMEOUT
    billItemSession[source] = nil

    local billType = form.billType == 'job' and 'job' or 'private'
    local jobName = xPlayer.job.name
    local asAdmin = false
    if billType == 'job' then
        if form.asAdmin == true and Billing.CanIssueAs(xPlayer, form.viaCommand == true) then
            if type(form.jobName) ~= 'string' or not Config.Jobs[form.jobName] then
                return cb({ success = false, message = L('err_job') })
            end
            jobName = form.jobName
            asAdmin = true
        elseif not Config.Jobs[xPlayer.job.name] then
            return cb({ success = false, message = L('err_no_job') })
        end
    end

    local ok, result = Billing.CreateInvoice({
        billType = billType,
        targetSource = form.targetSource,
        jobName = jobName,
        issuerIdentifier = xPlayer.identifier,
        issuerName = xPlayer.getName(),
        reason = form.reason,
        noProfit = form.noProfit,
        items = form.items,
        createDoc = fromItem,
    }, asAdmin)

    if ok then
        cb({ success = true, message = L('ok_issued'), id = result })
    else
        cb({ success = false, message = result })
    end
end)

ESX.RegisterServerCallback('billing:pay', function(source, cb, invoiceId)
    local ok, message = Billing.PayInvoice(source, invoiceId)
    cb({ success = ok, message = message })
end)

ESX.RegisterServerCallback('billing:cancel', function(source, cb, invoiceId)
    local ok, message = Billing.CancelInvoice(source, invoiceId)
    cb({ success = ok, message = message })
end)

ESX.RegisterUsableItem(Config.BillItem, function(source)
    billItemSession[source] = os.time()
    TriggerClientEvent('billing:open', source)
end)

ESX.RegisterUsableItem(Config.PrintedItem, function(source, _, itemData)
    if itemData and itemData.metadata then
        TriggerClientEvent('billing:showPrinted', source, itemData.metadata)
    end
end)

ESX.RegisterCommand(Config.AdminCommand, 'admin', function(xPlayer)
    if not xPlayer then
        print('[len_billing] Der Befehl ist nur im Spiel nutzbar.')
        return
    end
    if not Billing.HasAdminGroup(xPlayer) then
        return xPlayer.showNotification(L('err_not_leader'))
    end
    billItemSession[xPlayer.source] = nil
    TriggerClientEvent('billing:openAdmin', xPlayer.source)
end, false, {
    help = 'Admin: Rechnung im Namen eines Jobs ausstellen (ohne Limits)',
})

local function leaderJob(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Billing.IsLeader(xPlayer.job.name, xPlayer.job.grade) then
        return nil
    end
    return xPlayer.job.name
end

ESX.RegisterServerCallback('billing:getPrices', function(source, cb)
    local job = leaderJob(source)
    cb(job and Billing.GetPriceCategories(job) or {})
end)

ESX.RegisterServerCallback('billing:saveCategory', function(source, cb, data)
    local job = leaderJob(source)
    if not job then
        return cb({ success = false, message = L('err_not_leader') })
    end
    local ok, message = Billing.SaveCategory(job, data)
    cb({ success = ok, message = message })
end)

ESX.RegisterServerCallback('billing:deleteCategory', function(source, cb, data)
    local job = leaderJob(source)
    if not job then
        return cb({ success = false, message = L('err_not_leader') })
    end
    local ok, message = Billing.DeleteCategory(job, data)
    cb({ success = ok, message = message })
end)

ESX.RegisterServerCallback('billing:saveItem', function(source, cb, data)
    local job = leaderJob(source)
    if not job then
        return cb({ success = false, message = L('err_not_leader') })
    end
    local ok, message = Billing.SaveItem(job, data)
    cb({ success = ok, message = message })
end)

ESX.RegisterServerCallback('billing:deleteItem', function(source, cb, data)
    local job = leaderJob(source)
    if not job then
        return cb({ success = false, message = L('err_not_leader') })
    end
    local ok, message = Billing.DeleteItem(job, data)
    cb({ success = ok, message = message })
end)

ESX.RegisterServerCallback('billing:getPriceList', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return cb({})
    end
    local jobName = xPlayer.job.name
    if type(data) == 'table' and Config.Jobs[data.jobName] and Billing.CanIssueAs(xPlayer, data.viaCommand == true) then
        jobName = data.jobName
    end
    cb(Billing.GetPriceList(jobName))
end)