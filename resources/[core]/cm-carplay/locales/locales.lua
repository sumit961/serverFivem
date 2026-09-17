

Locales = {}

function _L(key)
    local lang = GetConvar("carplay:locale", "en")
    if not Locales[lang] then
        lang = "en"
    end
    local value = Locales[lang]
    for k in key:gmatch("[^.]+") do
        value = value[k]
        if not value then
            return key
        end
    end
    return value
end

-- Get the current locale table for sending to NUI
function GetLocaleTable()
    local lang = GetConvar("carplay:locale", "en")
    if not Locales[lang] then
        lang = "en"
    end
    return Locales[lang]
end

