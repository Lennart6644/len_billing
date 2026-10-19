ESX = nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

Billing = {}

local function trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function resolveStyle(billType, jobName)
    if billType == 'private' then
        return Config.PrivateStyle
    end
    return Config.Jobs[jobName] or Config.DefaultJobStyle
end

function Billing.IsLeader(jobName, grade)
    local job = Config.Jobs[jobName]
    if not job or not job.leaderMinGrade then
        return false
    end
    return (tonumber(grade) or -1) >= job.leaderMinGrade
end

-- Befehl /createbill: Admin-Gruppe (ESX)
function Billing.HasAdminGroup(xPlayer)
    if not xPlayer or not xPlayer.getGroup then
        return false
    end
    local group = xPlayer.getGroup()
    for _, name in ipairs(Config.AdminGroups or {}) do
        if group == name then
            return true
        end
    end
    return false
end

-- Item "bill": Job admin
function Billing.IsAdmin(xPlayer)
    return xPlayer ~= nil and xPlayer.job ~= nil and xPlayer.job.name == Config.AdminJob
end

-- Entscheidet, ob im Dropdown beliebige Jobs gewählt werden dürfen
function Billing.CanIssueAs(xPlayer, viaCommand)
    if viaCommand then
        return Billing.HasAdminGroup(xPlayer)
    end
    return Billing.IsAdmin(xPlayer)
end

local function toTimestamp(value)
    if type(value) == 'number' then
        return math.floor(value / 1000)
    end
    local y, mo, d, h, mi, s = tostring(value):match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
    if not y then
        return os.time()
    end
    return os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    })
end

local function calcLateFee(total, createdAt)
    local dueTimestamp = toTimestamp(createdAt) + Config.DueDays * 86400
    if os.time() > dueTimestamp then
        return math.floor(total * Config.LateFeePercent / 100)
    end
    return 0
end

local function attachItems(rows)
    if #rows == 0 then
        return rows
    end
    local ids, placeholders = {}, {}
    for i, row in ipairs(rows) do
        ids[i] = row.id
        placeholders[i] = '?'
    end
    local items = MySQL.query.await(
        ('SELECT invoice_id, description, quantity, unit_price, line_total FROM %s WHERE invoice_id IN (%s) ORDER BY id ASC'):format(Config.Tables.items, table.concat(placeholders, ',')),
        ids
    ) or {}
    local grouped = {}
    for _, item in ipairs(items) do
        grouped[item.invoice_id] = grouped[item.invoice_id] or {}
        table.insert(grouped[item.invoice_id], item)
    end
    for _, row in ipairs(rows) do
        row.items = grouped[row.id] or {}
    end
    return rows
end

local function formatInvoice(row, reveal)
    local style = resolveStyle(row.bill_type, row.job_name)
    local createdTimestamp = toTimestamp(row.created_at)
    local dueTimestamp = createdTimestamp + Config.DueDays * 86400
    local lateFee = 0
    if row.status == 'paid' then
        lateFee = row.late_fee or 0
    elseif row.status == 'unpaid' then
        lateFee = calcLateFee(row.total, row.created_at)
    end
    local hideIssuer = row.bill_type == 'job' and not reveal
    local items = {}
    for _, item in ipairs(row.items or {}) do
        items[#items + 1] = {
            description = item.description,
            quantity = item.quantity,
            unitPrice = item.unit_price,
            lineTotal = item.line_total,
        }
    end
    return {
        id = row.id,
        number = ('%s-%06d'):format(row.number_prefix, row.id),
        billType = row.bill_type,
        jobLabel = row.job_label,
        label = row.bill_type == 'job' and row.job_label or style.label,
        short = style.short,
        color = style.color,
        icon = style.icon,
        issuer = (not hideIssuer) and row.issuer_name or nil,
        target = row.target_name,
        reason = row.reason,
        subtotal = row.subtotal,
        tax = row.tax,
        total = row.total,
        lateFee = lateFee,
        payable = row.total + lateFee,
        overdue = row.status == 'unpaid' and lateFee > 0,
        paidText = row.paid_at and os.date('%d.%m.%Y %H:%M', toTimestamp(row.paid_at)) or nil,
        noProfit = row.no_profit == 1,
        status = row.status,
        dateText = os.date('%d.%m.%Y', createdTimestamp),
        timeText = os.date('%H:%M', createdTimestamp),
        dueText = os.date('%d.%m.%Y', dueTimestamp),
        items = items,
    }
end

local function formatList(rows, reveal)
    local list = {}
    for _, row in ipairs(attachItems(rows)) do
        list[#list + 1] = formatInvoice(row, reveal)
    end
    return list
end

function Billing.GetInvoice(id, reveal)
    id = tonumber(id)
    if not id then
        return nil
    end
    local row = MySQL.single.await(('SELECT * FROM %s WHERE id = ?'):format(Config.Tables.invoices), { id })
    if not row then
        return nil
    end
    return formatInvoice(attachItems({ row })[1], reveal)
end

function Billing.GetUnpaidInvoices(targetIdentifier)
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE target_identifier = ? AND status = ? ORDER BY id DESC LIMIT 100'):format(Config.Tables.invoices),
        { targetIdentifier, 'unpaid' }
    ) or {}
    return formatList(rows, false)
end

function Billing.GetJobInvoices(jobName)
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE bill_type = ? AND job_name = ? AND status = ? ORDER BY id DESC LIMIT 100'):format(Config.Tables.invoices),
        { 'job', jobName, 'unpaid' }
    ) or {}
    return formatList(rows, true)
end

local function sanitizeItems(items)
    if type(items) ~= 'table' or #items < 1 or #items > Config.MaxItems then
        return nil, L('err_items', Config.MaxItems)
    end
    local clean, subtotal = {}, 0
    for _, item in ipairs(items) do
        if type(item) ~= 'table' then
            return nil, L('err_item_desc')
        end
        local description = trim(item.description)
        local quantity = math.floor(tonumber(item.quantity) or 0)
        local unitPrice = math.floor(tonumber(item.unitPrice) or -1)
        if description == '' or #description > Config.MaxDescriptionLength then
            return nil, L('err_item_desc')
        end
        if quantity < 1 or quantity > Config.MaxQuantity then
            return nil, L('err_item_quantity', Config.MaxQuantity)
        end
        if unitPrice < 0 or unitPrice > Config.MaxUnitPrice then
            return nil, L('err_item_price', Config.MaxUnitPrice)
        end
        local lineTotal = quantity * unitPrice
        subtotal = subtotal + lineTotal
        clean[#clean + 1] = {
            description = description,
            quantity = quantity,
            unitPrice = unitPrice,
            lineTotal = lineTotal,
        }
    end
    return clean, subtotal
end

local function sendPrinted(targetSource, invoice)
    local ok, err = pcall(function()
        exports.ox_inventory:AddItem(targetSource, Config.PrintedItem, 1, invoice)
    end)
    if not ok then
        print(('[len_billing] Konnte gedruckte Rechnung nicht ausgeben: %s'):format(err))
    end
end

local function addSocietyMoney(jobName, amount)
    TriggerEvent('esx_addonaccount:getSharedAccount', Config.SocietyPrefix .. jobName, function(account)
        if account then
            account.addMoney(amount)
        end
    end)
end

local function findPayableAccount(xPlayer, amount)
    for _, name in ipairs(Config.PayAccounts) do
        local account = xPlayer.getAccount(name)
        if account and account.money >= amount then
            return name
        end
    end
    return nil
end

function Billing.CreateInvoice(data, ignoreLimits)
    if type(data) ~= 'table' then
        return false, L('err_invalid_data')
    end

    local billType = data.billType == 'job' and 'job' or 'private'

    local targetSource = tonumber(data.targetSource)
    local targetPlayer = targetSource and ESX.GetPlayerFromId(targetSource)
    if not targetPlayer then
        return false, L('err_target')
    end

    local issuerIdentifier = trim(data.issuerIdentifier)
    local issuerName = trim(data.issuerName)
    if issuerIdentifier == '' then
        return false, L('err_invalid_data')
    end

    local jobName = billType == 'job' and trim(data.jobName) or ''
    if billType == 'job' and jobName == '' then
        return false, L('err_job')
    end

    local style = resolveStyle(billType, jobName)
    local jobLabel = billType == 'job' and trim(data.jobLabel) or ''
    if billType == 'job' and jobLabel == '' then
        jobLabel = style.label or jobName
    end

    local reason = trim(data.reason)
    if reason == '' then
        reason = L(style.defaultReason or (billType == 'job' and 'reason_job' or 'reason_private'))
    end
    if #reason > Config.MaxReasonLength then
        return false, L('err_reason')
    end

    local items, subtotalOrError = sanitizeItems(data.items)
    if not items then
        return false, subtotalOrError
    end
    local subtotal = subtotalOrError
    local tax = math.floor(subtotal * Config.TaxPercent / 100)
    local total = subtotal + tax

    if total < 1 then
        return false, 'Eine Rechnung muss mindestens 1$ betragen.'
    end

    if not ignoreLimits then
        if billType == 'private' and total > Config.MaxPrivateTotal then
            return false, L('err_limit_private', Config.Currency .. Config.MaxPrivateTotal)
        end
        if billType == 'job' and style.limit and total > style.limit then
            return false, L('err_limit_job', Config.Currency .. style.limit)
        end
    end

    local noProfit = billType == 'job' and data.noProfit == true

    local invoiceId = MySQL.insert.await(
        ('INSERT INTO %s (bill_type, job_name, job_label, number_prefix, issuer_identifier, issuer_name, target_identifier, target_name, reason, subtotal, tax, total, no_profit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(Config.Tables.invoices),
        {
            billType, jobName, jobLabel, style.short or 'JOB',
            issuerIdentifier, issuerName,
            targetPlayer.identifier, targetPlayer.getName(),
            reason, subtotal, tax, total, noProfit and 1 or 0,
        }
    )
    if not invoiceId or invoiceId == 0 then
        return false, L('err_db')
    end

    for _, item in ipairs(items) do
        MySQL.insert.await(
            ('INSERT INTO %s (invoice_id, description, quantity, unit_price, line_total) VALUES (?, ?, ?, ?, ?)'):format(Config.Tables.items),
            { invoiceId, item.description, item.quantity, item.unitPrice, item.lineTotal }
        )
    end

    if data.createDoc == true then
        local invoice = Billing.GetInvoice(invoiceId, false)
        if invoice then
            sendPrinted(targetPlayer.source, invoice)
        end
    end
    TriggerClientEvent('esx:showAdvancedNotification', targetPlayer.source, L('notify_bank'), L('notify_received_title'), L('notify_received', Config.Currency .. total), 'CHAR_BANK_MAZE', 1)

    return true, invoiceId
end

function Billing.PayInvoice(source, invoiceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    invoiceId = tonumber(invoiceId)
    if not xPlayer or not invoiceId then
        return false, L('err_not_found')
    end

    local row = MySQL.single.await(
        ('SELECT id, bill_type, job_name, target_identifier, total, created_at, status FROM %s WHERE id = ?'):format(Config.Tables.invoices),
        { invoiceId }
    )
    if not row then
        return false, L('err_not_found')
    end
    if row.target_identifier ~= xPlayer.identifier then
        return false, L('err_not_target')
    end
    if row.status ~= 'unpaid' then
        return false, L('err_not_open')
    end

    local lateFee = calcLateFee(row.total, row.created_at)
    local payable = row.total + lateFee

    local account = findPayableAccount(xPlayer, payable)
    if not account then
        return false, L('err_funds')
    end

    local updated = MySQL.update.await(
        ('UPDATE %s SET status = ?, paid_by = ?, paid_at = NOW(), late_fee = ? WHERE id = ? AND status = ?'):format(Config.Tables.invoices),
        { 'paid', xPlayer.identifier, lateFee, row.id, 'unpaid' }
    )
    if not updated or updated == 0 then
        return false, L('err_not_open')
    end

    xPlayer.removeAccountMoney(account, payable)
    if row.bill_type == 'job' then
        addSocietyMoney(row.job_name, payable)
    end

    return true, L('ok_paid', Config.Currency .. payable)
end

function Billing.CancelInvoice(source, invoiceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    invoiceId = tonumber(invoiceId)
    if not xPlayer or not invoiceId then
        return false, L('err_not_found')
    end

    local row = MySQL.single.await(
        ('SELECT id, bill_type, job_name, issuer_identifier, status FROM %s WHERE id = ?'):format(Config.Tables.invoices),
        { invoiceId }
    )
    if not row then
        return false, L('err_not_found')
    end
    if row.bill_type == 'private' then
        if row.issuer_identifier ~= xPlayer.identifier then
            return false, L('err_not_leader')
        end
    elseif row.bill_type == 'job' then
        if not Billing.IsAdmin(xPlayer) and (xPlayer.job.name ~= row.job_name or not Billing.IsLeader(xPlayer.job.name, xPlayer.job.grade)) then
            return false, L('err_not_leader')
        end
    else
        return false, L('err_not_found')
    end
    if row.status ~= 'unpaid' then
        return false, L('err_not_open')
    end

    local updated = MySQL.update.await(
        ('UPDATE %s SET status = ? WHERE id = ? AND status = ?'):format(Config.Tables.invoices),
        { 'cancelled', row.id, 'unpaid' }
    )
    if not updated or updated == 0 then
        return false, L('err_not_open')
    end

    return true, L('ok_cancelled')
end

function Billing.GetInvoicesForTarget(targetIdentifier, billType)
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE target_identifier = ? AND bill_type = ? ORDER BY id DESC LIMIT 200'):format(Config.Tables.invoices),
        { targetIdentifier, billType }
    ) or {}
    return formatList(rows, false)
end

function Billing.GetPrivateIssued(issuerIdentifier)
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE issuer_identifier = ? AND bill_type = ? ORDER BY id DESC LIMIT 200'):format(Config.Tables.invoices),
        { issuerIdentifier, 'private' }
    ) or {}
    return formatList(rows, true)
end

function Billing.GetJobInvoicesAll(jobName)
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE bill_type = ? AND job_name = ? ORDER BY id DESC LIMIT 200'):format(Config.Tables.invoices),
        { 'job', jobName }
    ) or {}
    return formatList(rows, true)
end


local function ownsCategory(jobName, categoryId)
    return MySQL.scalar.await(
        ('SELECT id FROM %s WHERE id = ? AND job_name = ?'):format(Config.Tables.priceCategories),
        { categoryId, jobName }
    ) ~= nil
end

local function ownsItem(jobName, itemId)
    return MySQL.scalar.await(
        ('SELECT i.id FROM %s i JOIN %s c ON c.id = i.category_id WHERE i.id = ? AND c.job_name = ?'):format(Config.Tables.priceItems, Config.Tables.priceCategories),
        { itemId, jobName }
    ) ~= nil
end

function Billing.GetPriceCategories(jobName)
    local categories = MySQL.query.await(
        ('SELECT id, name FROM %s WHERE job_name = ? ORDER BY sort_order, id'):format(Config.Tables.priceCategories),
        { jobName }
    ) or {}
    local items = MySQL.query.await(
        ('SELECT i.id, i.category_id, i.label, i.short, i.price FROM %s i JOIN %s c ON c.id = i.category_id WHERE c.job_name = ? ORDER BY i.sort_order, i.id'):format(Config.Tables.priceItems, Config.Tables.priceCategories),
        { jobName }
    ) or {}
    local grouped = {}
    for _, item in ipairs(items) do
        grouped[item.category_id] = grouped[item.category_id] or {}
        table.insert(grouped[item.category_id], { id = item.id, label = item.label, short = item.short, price = item.price })
    end
    local list = {}
    for _, category in ipairs(categories) do
        list[#list + 1] = { id = category.id, name = category.name, items = grouped[category.id] or {} }
    end
    return list
end

function Billing.GetPriceList(jobName)
    local list = {}
    for _, category in ipairs(Billing.GetPriceCategories(jobName)) do
        for _, item in ipairs(category.items) do
            list[#list + 1] = { category = category.name, label = item.label, short = item.short, price = item.price }
        end
    end
    return list
end

function Billing.SaveCategory(jobName, data)
    if type(data) ~= 'table' then
        return false, L('err_invalid_data')
    end
    local name = trim(data.name)
    if name == '' or #name > 80 then
        return false, L('err_category_name')
    end
    local categoryId = tonumber(data.id)
    if categoryId then
        if not ownsCategory(jobName, categoryId) then
            return false, L('err_not_found')
        end
        MySQL.update.await(
            ('UPDATE %s SET name = ? WHERE id = ?'):format(Config.Tables.priceCategories),
            { name, categoryId }
        )
    else
        local sortOrder = MySQL.scalar.await(
            ('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM %s WHERE job_name = ?'):format(Config.Tables.priceCategories),
            { jobName }
        ) or 1
        MySQL.insert.await(
            ('INSERT INTO %s (job_name, name, sort_order) VALUES (?, ?, ?)'):format(Config.Tables.priceCategories),
            { jobName, name, sortOrder }
        )
    end
    return true, L('ok_saved')
end

function Billing.DeleteCategory(jobName, data)
    local categoryId = type(data) == 'table' and tonumber(data.id) or nil
    if not categoryId or not ownsCategory(jobName, categoryId) then
        return false, L('err_not_found')
    end
    MySQL.update.await(
        ('DELETE FROM %s WHERE id = ?'):format(Config.Tables.priceCategories),
        { categoryId }
    )
    return true, L('ok_deleted')
end

function Billing.SaveItem(jobName, data)
    if type(data) ~= 'table' then
        return false, L('err_invalid_data')
    end
    local label = trim(data.label)
    if label == '' or #label > 120 then
        return false, L('err_item_label')
    end
    local short = trim(data.short)
    if #short > 40 then
        return false, L('err_invalid_data')
    end
    local price = math.floor(tonumber(data.price) or -1)
    if price < 0 or price > Config.MaxUnitPrice then
        return false, L('err_item_price', Config.MaxUnitPrice)
    end
    local categoryId = tonumber(data.categoryId)
    if not categoryId or not ownsCategory(jobName, categoryId) then
        return false, L('err_not_found')
    end
    local itemId = tonumber(data.id)
    if itemId then
        if not ownsItem(jobName, itemId) then
            return false, L('err_not_found')
        end
        MySQL.update.await(
            ('UPDATE %s SET category_id = ?, label = ?, short = ?, price = ? WHERE id = ?'):format(Config.Tables.priceItems),
            { categoryId, label, short, price, itemId }
        )
    else
        local sortOrder = MySQL.scalar.await(
            ('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM %s WHERE category_id = ?'):format(Config.Tables.priceItems),
            { categoryId }
        ) or 1
        MySQL.insert.await(
            ('INSERT INTO %s (category_id, label, short, price, sort_order) VALUES (?, ?, ?, ?, ?)'):format(Config.Tables.priceItems),
            { categoryId, label, short, price, sortOrder }
        )
    end
    return true, L('ok_saved')
end

function Billing.DeleteItem(jobName, data)
    local itemId = type(data) == 'table' and tonumber(data.id) or nil
    if not itemId or not ownsItem(jobName, itemId) then
        return false, L('err_not_found')
    end
    MySQL.update.await(
        ('DELETE FROM %s WHERE id = ?'):format(Config.Tables.priceItems),
        { itemId }
    )
    return true, L('ok_deleted')
end