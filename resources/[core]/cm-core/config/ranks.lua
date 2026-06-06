CM.Ranks = {
    {id = 1, name = "Newbie", level = 1, min_xp = 0, max_xp = 499, daily_salary = 0, benefits = {shop_discount = 0, maxVehicles = 1, maxProperties = 0, jobAccess = {}, canCreateGang = false, canCreateFamily = false}, icon = "⭐"},
    {id = 2, name = "Citizen", level = 2, min_xp = 500, max_xp = 1499, daily_salary = 100, benefits = {shop_discount = 5, maxVehicles = 2, maxProperties = 1, jobAccess = {"trucker", "taxi", "delivery"}, canCreateGang = false, canCreateFamily = false}, icon = "⭐⭐"},
    {id = 3, name = "Resident", level = 3, min_xp = 1500, max_xp = 3999, daily_salary = 250, benefits = {shop_discount = 10, maxVehicles = 4, maxProperties = 2, jobAccess = {"trucker", "taxi", "delivery", "mechanic", "reporter"}, canCreateGang = false, canCreateFamily = true}, icon = "⭐⭐⭐"},
    {id = 4, name = "Established", level = 4, min_xp = 4000, max_xp = 7999, daily_salary = 500, benefits = {shop_discount = 15, maxVehicles = 6, maxProperties = 3, jobAccess = {"trucker", "taxi", "delivery", "mechanic", "reporter", "police", "ems"}, canCreateGang = true, canCreateFamily = true}, icon = "💎"},
    {id = 5, name = "Veteran", level = 5, min_xp = 8000, max_xp = 14999, daily_salary = 1000, benefits = {shop_discount = 20, maxVehicles = 10, maxProperties = 5, jobAccess = {"all"}, canCreateGang = true, canCreateFamily = true}, icon = "👑"},
    {id = 6, name = "Legend", level = 6, min_xp = 15000, max_xp = 999999, daily_salary = 2500, benefits = {shop_discount = 25, maxVehicles = 20, maxProperties = 10, jobAccess = {"all"}, canCreateGang = true, canCreateFamily = true, exclusiveFeatures = {"vip_chat", "custom_plate", "priority_queue"}}, icon = "🏆"}
}

return CM.Ranks