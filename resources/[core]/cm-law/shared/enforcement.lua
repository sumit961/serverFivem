-- Shared plate normalization for client/server Law enforcement paths.
-- Rendered registration text is lookup/display data; persistent vehicle
-- identity remains cm-vehicles' vehicle_id.
function LawNormalizePlate(value)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    local plate = tostring(value):upper():gsub('%s+', '')
    if plate == '' or plate == 'NULL' or plate == 'NONE' or plate == 'UNKNOWN'
        or plate == 'NO PLATE' or plate == '--------' then return nil end
    if #plate > 16 or plate:find('[^%w%-]') then return nil end
    return plate
end
