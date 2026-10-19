Config = {}

Config.Locale = 'en'
Config.Currency = '$'
Config.Command = 'bills'
Config.AdminCommand = 'createbill'
Config.AdminGroups = { 'admin' }
Config.AdminJob = 'admin'
Config.BillItem = 'bill'
Config.PrintedItem = 'printed_bill'
Config.Tables = {
    invoices = 'billing_invoices',
    items = 'billing_invoice_items',
    priceCategories = 'billing_price_categories',
    priceItems = 'billing_price_items',
}
Config.SocietyPrefix = 'society_'
Config.PayAccounts = { 'bank', 'money' }
Config.DueDays = 7
Config.LateFeePercent = 20
Config.TaxPercent = 0
Config.MaxItems = 10
Config.MaxQuantity = 999
Config.MaxUnitPrice = 1000000
Config.MaxPrivateTotal = 250000
Config.MaxReasonLength = 120
Config.MaxDescriptionLength = 120
Config.DefaultCity = 'Los Santos'

Config.Paper = {
    background = '#f4f7fb',
    text = '#0b1324',
    muted = '#64748b',
    line = '#d5dde8',
}

Config.PrivateStyle = {
    label = 'Private',
    short = 'PRIV',
    color = '#0b1324',
    icon = 'fa-user',
}

Config.DefaultJobStyle = {
    label = 'Department',
    short = 'JOB',
    color = '#1e293b',
    icon = 'fa-building-columns',
}

Config.Jobs = {
    police = { label = 'Los Santos Police Department', short = 'LSPD', color = '#1d4ed8', icon = 'fa-shield-halved', limit = 60000, defaultReason = 'reason_fine', leaderMinGrade = 4 },
    ambulance = { label = 'Emergency Medical Services', short = 'EMS', color = '#dc2626', icon = 'fa-truck-medical', limit = 25000, leaderMinGrade = 4, defaultReason = "Treatment costs" },
    fire = { label = 'Fire Department', short = 'LSFD', color = '#ea580c', icon = 'fa-fire-extinguisher', limit = 25000, leaderMinGrade = 4 },
    mechanic = { label = 'Mechanik-Werkstatt', short = 'MECH', color = '#ca8a04', icon = 'fa-wrench', limit = 120000, defaultReason = 'reason_repair', leaderMinGrade = 4 },
    admin = { label = 'Administration', short = 'ADMIN', color = '#0f172a', icon = 'fa-gavel', limit = 9999999999, leaderMinGrade = 4 },
    taxi = { label = 'Taxi Cab', short = 'TAXI', color = '#eab308', icon = 'fa-taxi', limit = 20000, leaderMinGrade = 4, defaultReason = "Taxi ride" },
}

function L(key, ...)
    local set = Locales[Config.Locale] or Locales.de
    local text = set[key] or Locales.de[key] or key
    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end
