--!strict

--[[
	Example of using LimitedTable.
	The following code runs an interpreter which uses LimitedTable.
]]

local Closure = require(script:WaitForChild("Closure"))
local LimitedTable = require(game:GetService("ReplicatedStorage").LimitedTable)

local closure = Closure.new({
	-- Basic logging
	{ 7, "Hello, world!" }, -- Log <any>
	-- Global & Local scopes
	{ 2, "test", "I'm a global!" }, -- Set <variable> to <any>
	{ 7, "{test}" }, -- Log <any>
	{ 1, "test", "I'm a local!" }, -- Set local <variable> to <any>
	{ 7, "{test}" }, -- Log <any>
	-- Concatenating
	{ 2, "myGlobal", "foo" }, -- Set <variable> to <any>
	{ 1, "myLocal", "bar" }, -- Set local <variable> to <any>
	{ 7, "{myGlobal} {myLocal}" }, -- Log <any>
	-- If statements
	{ 1, "input", "1234" }, -- Set local <variable> to <any>
	{ 3, "{input}", "1234", 1 }, -- If <any> is equal to <any>
	{ 7, "Password is 1234!" }, -- Log <any>
	{ 4 },
	-- Loops
	{ 5, "2", 3 }, -- Repeat <number> times
	{ 7, "Repeat 2 times..." }, -- Log <any>
	{ 7, "Break!" }, -- Log <any>
	{ 6 }, -- Break
	{ 4 },
}, LimitedTable.new(512000))

closure:run()
