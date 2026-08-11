Sounds = {}

function Sounds.playSound(self, name, volume)
    SendNUIMessage({
        action = "playSound",
        data = {
            name = name,
            volume = volume or 0.5,
        },
    })
end
