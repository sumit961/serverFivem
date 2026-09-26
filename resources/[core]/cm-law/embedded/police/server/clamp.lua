-- Compatibility callback retained for existing Police clients. The shared
-- Law handler owns all authorization and target validation.
lib.callback.register('cm-police:server:toggleClamp', function(src, netId)
    if type(LawToggleClamp) ~= 'function' then return false, 'Clamp service is unavailable.' end
    return LawToggleClamp(src, netId)
end)
