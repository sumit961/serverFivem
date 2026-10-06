-- Public server contracts (see docs/CONTRACTS.md). Caller identity is ALWAYS GetInvokingResource(); a resource that is
-- not an enabled provider in Config.Providers is rejected. There is deliberately no network event for creating invoices.
local S = CMBilling.Server

-- CreateInvoice(data) -> ok, { reference, id, existing? } | false, reason
exports('CreateInvoice', function(data)
    return S.CreateInvoice(GetInvokingResource(), data)
end)

-- VoidInvoice(reference, reason) -> ok | false, reason. Only the issuing provider, only while pending.
exports('VoidInvoice', function(reference, reason)
    return S.VoidInvoice(GetInvokingResource(), reference, reason)
end)

-- GetInvoice(reference) -> view | nil, reason. Only invoices issued by the calling provider.
exports('GetInvoice', function(reference)
    return S.GetIssuedInvoice(GetInvokingResource(), reference)
end)

-- GetInvoiceStatus(reference) -> 'pending'|'processing'|'paid'|'voided'|'expired' | nil
exports('GetInvoiceStatus', function(reference)
    local view = S.GetIssuedInvoice(GetInvokingResource(), reference)
    return view and view.status or nil
end)

-- GetProviderPolicy() -> { provider, maxInvoiceAmount, platformMaxAmount, canRefund, canVoid, allowOffline, issuerTypes, destinations } | nil, reason.
-- Read-only view of the CALLING provider's own creation policy, so a provider can show a meaningful limit without duplicating the number.
exports('GetProviderPolicy', function()
    return S.GetProviderPolicy(GetInvokingResource())
end)

-- GetPendingInvoices(characterId) -> { view... } | nil, reason. Only invoices issued by the calling provider.
exports('GetPendingInvoices', function(characterId)
    return S.GetIssuedPending(GetInvokingResource(), characterId)
end)

-- ---------------------------------------------------------------------------
-- Refunds (see docs/CONTRACTS.md). Provider must be enabled with canRefund = true and may only refund invoices it issued.
-- There is deliberately no client/net event for refunds: a customer-facing request must go through the owning provider workflow.
-- ---------------------------------------------------------------------------

-- RequestRefund(invoiceReference, refundReference, amount|nil, reason) -> true, view | false, reason
exports('RequestRefund', function(invoiceReference, refundReference, amount, reason)
    return S.RequestRefund(GetInvokingResource(), invoiceReference, refundReference, amount, reason)
end)

-- GetRefundStatus(refundReference) -> view | nil, reason
exports('GetRefundStatus', function(refundReference)
    return S.GetRefundStatus(GetInvokingResource(), refundReference)
end)

-- GetInvoiceRefundState(invoiceReference) -> { refundState, paidAmount, refundedAmount, inFlightAmount, refundableAmount, netPaidAmount } | nil, reason
exports('GetInvoiceRefundState', function(invoiceReference)
    return S.GetInvoiceRefundState(GetInvokingResource(), invoiceReference)
end)

-- RetryRefund(refundReference) -> true, view | false, reason. Continues the provider's own refund forward; never alters the request.
exports('RetryRefund', function(refundReference)
    return S.RetryRefund(GetInvokingResource(), refundReference)
end)

-- Admin observability / reconcile: callable only by Config.Refund.AdminResources (cm-admin must authorise the human first).
exports('AdminListStuckRefunds', function(limit) return S.AdminListStuckRefunds(GetInvokingResource(), limit) end)
exports('AdminInspectRefund', function(refundReference, provider) return S.AdminInspectRefund(GetInvokingResource(), refundReference, provider) end)
exports('AdminReconcileRefund', function(refundReference, provider) return S.AdminReconcileRefund(GetInvokingResource(), refundReference, provider) end)
exports('AdminAbandonRefund', function(refundReference, provider, note) return S.AdminAbandonRefund(GetInvokingResource(), refundReference, provider, note) end)
