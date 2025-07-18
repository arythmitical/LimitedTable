--!strict
--!optimize 2

--[[
	Fairly simple interpreter that uses LimitedTable.
	Supports local scope for variables.
]]

local HttpService = game:GetService("HttpService") -- for the interpreter

local LimitedTable = require(game:GetService("ReplicatedStorage"):WaitForChild("LimitedTable"))

local Function = {}
Function.__index = Function

export type SetVar = { type: "SETVAR", variable: string, value: string }
export type Print = { type: "PRINT", message: string }
export type NewTable = { type: "NEWTABLE", variable: string }
export type SetEntry = { type: "SETENTRY", variable: string, key: string, value: string }
export type Wait = { type: "WAIT", time: string }
export type Operation = SetVar | Print | NewTable | SetEntry | Wait

export type Function = typeof(setmetatable(
	{} :: {
		code: { Operation },
		globalEnv: LimitedTable.LimitedTable,
		referencesCount: { [LimitedTable.LimitedTable]: number },
	},
	Function
))

--[[
	Creates a new Function object with the provided code
	which can then be ran multiple times.
]]
function Function.new(
	code: { Operation },
	globalEnv: LimitedTable.LimitedTable,
	referencesCount: { [LimitedTable.LimitedTable]: number }
): Function
	assert(LimitedTable.is(globalEnv), "expected global env to be LimitedTable")

	local self = setmetatable({}, Function)
	self.code = code
	self.globalEnv = globalEnv
	self.referencesCount = referencesCount

	return self
end

--[[
	Checks if the given object is a Function.
]]
function Function.is(object: any): boolean
	return typeof(object) == "table" and getmetatable(object) == Function
end

--[[
	Runs the Function.
	May yield depending on the code, so use Function:spawn() or a Promise.
]]
function Function.runAsync(self: Function): ()
	assert(Function.is(self), "invalid argument #1: expected Function")

	local referencesCount: { [LimitedTable.LimitedTable]: number } = self.referencesCount

	local globalEnv = self.globalEnv
	local localEnv = LimitedTable.new(globalEnv.maximumSize, { globalEnv })

	--[[
		Gets the scope that the variable is in
		based on whether the variable is prefixed with "l!" or not
	]]
	local function getVariableScope(variable: string): (string, LimitedTable.LimitedTable)
		local scope = string.sub(variable, 0, 2)

		if scope == "l!" then
			return string.sub(variable, 3, -1), localEnv
		else
			return variable, globalEnv
		end
	end

	--[[
		Wrapper around LimitedTable:destroy() that
		also destroys tables which have no references left.
	]]
	local function destroy(
		lt: LimitedTable.LimitedTable,
		visited: { LimitedTable.LimitedTable }
	): ()
		if table.find(visited, lt) then
			return
		end
		table.insert(visited, lt)

		for _, value in pairs(lt.contents) do
			if LimitedTable.is(value) and referencesCount[value] == 1 then
				destroy(lt, visited)
			end
		end
		referencesCount[lt] = nil
		lt:destroy()
	end

	--[[
		Wrapper around LimitedTable:set() that tracks
		LimitedTable references, required for getting rid of tables.
	]]
	local function set(lt: LimitedTable.LimitedTable, key, value): ()
		local oldVal = lt:set(key, value)
		if LimitedTable.is(oldVal) then
			referencesCount[oldVal] -= 1
			if referencesCount[oldVal] == 0 then
				destroy(oldVal, {})
			end
		end
		if LimitedTable.is(value) then
			referencesCount[value] += 1
		end
	end

	--[[
		Checks for a variable reference in a text field.
	]]
	local function parseTextField(text: string): any?
		if string.sub(text, 1, 1) == "{" and string.sub(text, -1, -1) == "}" then
			local variable, scope = getVariableScope(string.sub(text, 2, -2))
			local value = scope.contents[variable]

			return if value ~= nil then value else text
		else
			return text
		end
	end

	for _, operation: Operation in pairs(self.code) do
		if operation.type == "SETVAR" then
			local variable, scope = getVariableScope(operation.variable)
			set(scope, variable, parseTextField(operation.value))
		elseif operation.type == "PRINT" then
			local message = parseTextField(operation.message)

			if LimitedTable.is(message) then
				message = HttpService:JSONEncode(message.contents)
			end

			print(message)
		elseif operation.type == "NEWTABLE" then
			local variable, scope = getVariableScope(operation.variable)
			local new = LimitedTable.new(localEnv.maximumSize, { globalEnv })

			scope:set(variable, new)
			referencesCount[new] = 1
		elseif operation.type == "SETENTRY" then
			local variable, scope = getVariableScope(operation.variable)
			local data: any = scope.contents[variable]

			assert(LimitedTable.is(data), "expected #1 to be a table")
			set(
				data :: LimitedTable.LimitedTable,
				parseTextField(operation.key),
				parseTextField(operation.value)
			)
		elseif operation.type == "WAIT" then
			task.wait(tonumber(operation.time))
		end
	end

	destroy(localEnv, {})
end

--[[
	Spawns a new thread which runs the Function.
]]
function Function.spawn(self: Function): ()
	task.spawn(Function.runAsync, self)
end

-- running an imaginary script with 3 functions
do
	local globalEnv = LimitedTable.new(1024 * 1000)
	local referencesCount = {}

	Function.new({
		{ type = "SETVAR", variable = "l!local", value = "hello from the Function!" },
		{ type = "PRINT", message = "{l!local}" },
	}, globalEnv, referencesCount):spawn()

	Function.new({
		{ type = "NEWTABLE", variable = "l!table" },
		{ type = "SETENTRY", variable = "l!table", key = "key", value = "value" },
		{ type = "PRINT", message = "{l!table}" },
		{ type = "SETVAR", variable = "table", value = "{l!table}" },
	}, globalEnv, referencesCount):spawn()

	Function.new({
		{ type = "WAIT", time = "5" },
		{ type = "PRINT", message = "table:" },
		{ type = "PRINT", message = "{table}" },
	}, globalEnv, referencesCount):spawn()
end

return Function
