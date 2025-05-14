--!strict
--!native
--!optimize 2

--[[
	Example interpreter with usage of LimitedTable.
	Functionality is based on CatWeb's webrenderer.

	(yes i actually coded this for just an example)
]]

local LimitedTable = require(game:GetService("ReplicatedStorage"):WaitForChild("LimitedTable"))

local function parseVariableField(variable: string): string
	return string.gsub(variable, "[{}]", "")
end

local Closure = {}
Closure.__index = Closure

function Closure.new(bytecode: { { any } }, env: LimitedTable.LimitedTable): Closure
	assert(env, "no global env provided")
	assert(LimitedTable.isValid(env), "expected global env to be LimitedTable")

	local self = {}
	self.alive = true
	self.bytecode = bytecode
	self.env = env

	setmetatable(self, Closure)

	return self
end

function Closure.isValid(closure: Closure): boolean
	return typeof(closure) == "table" and getmetatable(closure) == Closure
end

function Closure.run(self: Closure): ()
	assert(Closure.isValid(self), "invalid argument #1: expected Closure")

	local action = 0 -- position of action in bytecode array
	local stack = {} -- for loops and conditions

	local bytecode = self.bytecode

	local globalEnv = self.env
	local globalTable = globalEnv.table

	local localEnv = LimitedTable.new(1024000)
	local localTable = localEnv.table

	local function setLocal(key: any, value: any, table: LimitedTable.LimitedTableTable?): ()
		local sizeDelta: number = localEnv:set(key, value, table, false)

		if globalEnv._currentSize + sizeDelta > globalEnv.maximumSize then
			local sizeExceededMessage = globalEnv.sizeExceededMessage

			if typeof(sizeExceededMessage) == "function" then
				sizeExceededMessage(globalEnv)
			else
				error(string.format(sizeExceededMessage, globalEnv.maximumSize))
			end
		end

		localEnv:set(key, value, table)
	end

	local function parseTextField(text: string): any?
		local parsed, replacecements = string.gsub(
			text,
			"{([^{}]+)}",
			function(variable: string): string
				local value = localTable[variable]
				if value == nil then
					value = globalTable[variable]
				end

				local valueType = typeof(value)

				if value == nil then
					return "{" .. variable .. "}"
				elseif valueType == "string" or valueType == "number" then
					return tostring(value)
				elseif valueType == "Instance" then
					return "<element>"
				else
					return "<" .. valueType .. ">"
				end
			end
		)

		if
			replacecements == 1
			and string.sub(text, 1, 1) == "{"
			and string.sub(text, -1, -1) == "}"
		then
			local variable = parseVariableField(text)

			local value = localTable[variable]
			if value == nil then
				value = globalTable[variable]
			end

			return if value ~= nil then value else text
		else
			return parsed
		end
	end

	local function findClosestLoop(): number?
		local containersIgnored = 0

		for i = action, 1, -1 do
			local actionInfo = bytecode[i]
			local operation = actionInfo[1]

			if operation == 4 then
				containersIgnored += 1
				continue
			end

			if operation == 3 or operation == 5 then
				if containersIgnored > 0 then
					containersIgnored -= 1
				elseif operation == 5 then
					return i
				end
			end
		end

		return nil
	end

	while self.alive == true do
		action += 1

		local actionInfo = bytecode[action]

		if actionInfo == nil then
			-- code finished

			globalEnv._currentSize -= localEnv._currentSize
			localEnv:destroy()

			break
		end

		local opcode: number = actionInfo[1]

		-- blocks
		if opcode == 1 then -- Set local <variable> to <any>
			local variable: string = parseVariableField(actionInfo[2])
			local value: any? = parseTextField(actionInfo[3])

			setLocal(variable, value)
		elseif opcode == 2 then -- Set <variable> to <any>
			local variable: string = parseVariableField(actionInfo[2])
			local value: any? = parseTextField(actionInfo[3])

			globalEnv:set(variable, value)
		elseif opcode == 3 then -- If <any> is equal to <any>
			if parseTextField(actionInfo[2]) ~= parseTextField(actionInfo[3]) then
				-- immediatly jumps to end block is not equal
				action = action + actionInfo[4] + 1
			end
		elseif opcode == 4 then -- [end container]
			local lastLoop = findClosestLoop()

			if lastLoop ~= nil then
				-- the loop decides if it should repeat
				action = lastLoop - 1
			end
		elseif opcode == 5 then -- Repeat <number> times (3rd parameter defines how many blocks are inside)
			local stackInfo = stack[action]

			if stackInfo == nil then
				local limit: number? = tonumber(parseTextField(actionInfo[2]))
				assert(limit ~= nil, 'no amount provided for "Repeat <number> times"')

				stackInfo = { 0, limit }
				stack[action] = stackInfo
			end

			stackInfo[1] += 1

			if stackInfo[1] > stackInfo[2] then
				stack[action] = nil
				action += actionInfo[3] + 1
			end
		elseif opcode == 6 then -- Break
			local lastLoop = findClosestLoop()

			if lastLoop ~= nil then
				local loopData = bytecode[lastLoop]
				local loopType = loopData[1]

				if loopType == 5 then
					action = lastLoop + loopData[3] + 1
				end
			end
		elseif opcode == 7 then -- Log <any>
			print(parseTextField(actionInfo[2]))
		else
			error(`unknown operation: {opcode}`)
		end
	end
end

export type Closure = typeof(setmetatable(
	{} :: {
		alive: boolean,
		bytecode: { { any } }, -- typechecking arrays with different types is hard!!!!
		env: LimitedTable.LimitedTable,
	},
	Closure
))

return Closure
