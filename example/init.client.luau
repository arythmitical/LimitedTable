--!nonstrict
--!optimize 2
--!native
-- # selene: allow(empty_if)

--[[
	basic interpreter simillar to catweb, but has different loops logic
	
	container and its finisher are a pair and are referencing each
	other's positions
	
	1. loop, 3 -- finisher position
	2. ...
	3. end, 1 -- start position
]]

-- each operation has an id, and the rest of its data varies
local BYTECODE = {
	{ 22, "1", 3 }, -- Repeat times, 1 (amount), finisher position in array
	{ 24, 3 }, -- break, finisher position in array
	{ 25, 1 }, -- finish container, container position in array

	{ 23, 6 }, -- Repeat forever, finisher position in array
	{ 24, 6 }, -- break, finisher position in array
	{ 25, 4 }, -- finish container, container position in array

	{ 54, "myTable" }, -- Create table myTable
	{ 55, "2", "myTable", "yo" }, -- Set 2 of myTable to yo
	{ 55, "3", "myTable", "hey" }, -- Set 3 of myTable to hey
	{ 55, "1", "myTable", "hi" }, -- Set 1 of myTable to hi
	{ 61, "myTable", "myIndex", "myValue", 15 }, -- Iterate through myTable, finisher position in array
	{ 18, "{myValue}", "yo", 14 }, -- If {myValue} is equal to yo, finisher position in array
	{ 24, 15 }, -- break, finisher position in array
	{ 25, 12 }, -- finish container, container position in array
	{ 25, 11 }, -- finish container, container position in array

	{
		62,
		"myTable",
		nil,
		nil,
		20,
	}, -- Iterate through array myTable, finisher position in array
	{ 18, "{value}", "yo", 19 }, -- If {value} is equal to yo, finisher position in array
	{ 24, 20 }, -- break, finisher position in array
	{ 25, 17 }, -- finish container, container position in array
	{ 25, 16 }, -- finish container, container position in array
}

-- idek what this line could possibly reference to
local LimitedTable = require(game:GetService("ReplicatedStorage"):WaitForChild("LimitedTable"))

local function create(bytecode: typeof(BYTECODE)): ()
	local alive = true

	local function close()
		alive = false
	end

	local function run(varsObj: LimitedTable.LimitedTable): ()
		local vars = varsObj.table

		local function parseField(text: string): any
			if string.sub(text, 1, 1) == "{" and string.sub(text, #text, #text) == "}" then
				-- string.sub is faster than (""):sub() btw
				-- (if u use --!optimize 2 just like in this script)
				return vars[string.sub(text, 2, #text - 1)]
			else
				-- no variables in text for you!
				return text
			end
		end

		local action = 0 -- position of action in bytecode array

		local stack = {}

		while alive do
			action += 1

			local actionInfo = bytecode[action]

			if actionInfo == nil then
				break -- code finished
			end

			local operation = actionInfo[1]

			if operation == 18 then -- If <any> is equal to <any>
				-- jumps to end block if not equal, otherwise goes normally
				if parseField(actionInfo[2]) ~= parseField(actionInfo[3]) then
					action = actionInfo[4] -- + 1 on next iter
				end
			elseif operation == 22 then -- Repeat <number> times
				local stackInfo = stack[action]

				if stackInfo == nil then
					-- step, limit
					stackInfo = {
						0,
						tonumber(
							parseField(
								assert(
									actionInfo[2],
									'no amount provided for "Repeat <number> times"'
								)
							)
						),
					}
					stack[action] = stackInfo
				end

				stackInfo[1] += 1

				if stackInfo[1] > stackInfo[2] then
					stack[action] = nil
					action = actionInfo[3] -- loop finishes
				end
			elseif operation == 23 then -- Repeat forever
				-- runs code under itself unconditionally
			elseif operation == 24 then -- Break
				action = actionInfo[2] -- will skip finish container after action increases by 1
			elseif operation == 25 then -- [finish container]
				-- does nothing if the container is not a loop

				local opcode = bytecode[actionInfo[2]][1]

				if opcode == 22 or opcode == 23 or opcode == 61 then
					action = actionInfo[2] - 1 -- back into the loop
				end
			elseif operation == 54 then -- Create table <table>
				varsObj:set(
					string.gsub(
						string.gsub(
							assert(actionInfo[2], 'no name provided for "Create table <table>"'),
							"{",
							""
						),
						"}",
						""
					),
					{}
				)
			elseif operation == 55 then -- Set <entry> of <table> to <any>
				assert(actionInfo[3], "table name not provided")

				local key = parseField(
					assert(
						actionInfo[2],
						'no <entry> provided for "Set <entry> of <table> to <any>"'
					)
				)
				key = tonumber(key) or key

				varsObj:set(
					key,
					parseField(actionInfo[4]),
					assert(
						vars[string.gsub(
							string.gsub(
								assert(
									actionInfo[3],
									"no <table> provided for Set <entry> of <table> to <any>"
								),
								"{",
								""
							),
							"}",
							""
						)],
						"no <table> provided for Set <entry> of <table> to <any>"
					)
				)
			elseif operation == 61 then -- Iterate through <table> -> <index?>, <value?>
				local stackInfo = stack[action]

				if stackInfo == nil then
					-- table, next
					stackInfo = {
						assert(
							vars[string.gsub(
								string.gsub(
									assert(
										actionInfo[2],
										'no <table> provided for "Iterate through <table> -> <index?>, <value?>"'
									),
									"{",
									""
								),
								"}",
								""
							)],
							'no <table> provided for "Iterate through <table> -> <index?>, <value?>"'
						),
						nil,
					}
					stack[action] = stackInfo
				end

				stackInfo[2] = next(stackInfo[1], stackInfo[2])

				if stackInfo[2] == nil then
					stack[action] = nil
					action = actionInfo[5] -- loop finishes
				else
					-- key
					varsObj:set(
						string.gsub(string.gsub(actionInfo[3] or "index", "{", ""), "}", ""),
						stackInfo[2]
					)
					-- value
					varsObj:set(
						string.gsub(string.gsub(actionInfo[4] or "value", "{", ""), "}", ""),
						stackInfo[1][stackInfo[2]]
					)
				end
			elseif operation == 62 then -- Iterate through <array> -> <pos?>, <value?> :O
				local stackInfo = stack[action]

				if stackInfo == nil then
					-- table, next
					stackInfo = {
						assert(
							vars[string.gsub(
								string.gsub(
									assert(
										actionInfo[2],
										'no <table> provided for "Iterate through <array> -> <pos?>, <value?>"'
									),
									"{",
									""
								),
								"}",
								""
							)],
							'no <table> provided for "Iterate through <array> -> <pos?>, <value?>"'
						),
						0,
					}
					stack[action] = stackInfo
				end

				stackInfo[2] += 1

				local value = stackInfo[1][stackInfo[2]]

				if value == nil then
					stack[action] = nil
					action = actionInfo[5] -- loop finishes
				else
					-- key
					varsObj:set(
						string.gsub(string.gsub(actionInfo[3] or "index", "{", ""), "}", ""),
						stackInfo[2]
					)
					-- value
					varsObj:set(
						string.gsub(string.gsub(actionInfo[4] or "value", "{", ""), "}", ""),
						value
					)
				end
			else
				error(`unknown opcode {operation}`)
			end
		end
	end

	return run, close
end

-- vrooom vroooom
({ create(BYTECODE) })[1](LimitedTable.new(512000))
