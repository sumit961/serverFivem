# bcrypt for CitizenFX

local hash = exports['bcrypt']:GetPasswordHash("password")

local valid = exports['bcrypt']:VerifyPasswordHash("password", hash)