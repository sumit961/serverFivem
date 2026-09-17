local config = require('shared/config')

function debugPrint(msg)
    if config.debugPrint then
        lib.print.info(msg)
    end
end

function locale(key, ...)
    local playerLang = config.Locale or 'en'
    local langTable = Locales[playerLang] or Locales['en']

    local value = langTable[key]
    if not value then
        return key
    end

    if select('#', ...) > 0 then
        return string.format(value, ...)
    end

    return value
end
