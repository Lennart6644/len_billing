exports('CreateInvoice', function(data)
    return Billing.CreateInvoice(data, type(data) == 'table' and data.ignoreLimits == true)
end)

exports('GetInvoice', function(id)
    return Billing.GetInvoice(id, true)
end)

exports('GetUnpaidInvoices', function(targetIdentifier)
    return Billing.GetUnpaidInvoices(targetIdentifier)
end)

exports('GetJobInvoices', function(jobName)
    return Billing.GetJobInvoices(jobName)
end)

exports('PayInvoice', function(source, invoiceId)
    return Billing.PayInvoice(source, invoiceId)
end)

exports('CancelInvoice', function(source, invoiceId)
    return Billing.CancelInvoice(source, invoiceId)
end)
