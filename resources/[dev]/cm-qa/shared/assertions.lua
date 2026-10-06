CmQaAssertions = {}

function CmQaAssertions.ok(condition, message)
    return condition == true, message or (condition and 'ok' or 'assertion failed')
end
