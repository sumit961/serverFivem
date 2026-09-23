AddEventHandler('playerDropped', function()
    local player = source
	for k, v in pairs(trunks) do
		if v == player then
			trunks[k] = nil
		end
    end
	GlobalState.hideintrunk = trunks
end)