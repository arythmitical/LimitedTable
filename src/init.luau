--[[
	Constructor of tables with size limits.
	Useful for interpreters, VMs and much more.
	
	API summary:
		LimitedTable.new(maxSize: number): LimitedTable
			obj.table -- to get values
			obj:set(key, value, table?): () - table defaults to obj.table
			obj:cloneRaw(table?): table -- get normal table
			
			obj.maximumSize = 1024000
			obj:destroy()
		LimitedTable.isValid(obj)
	
	Current limitations:
		1. table.key = value is not checking limits when value is already set,
		   use object:set("key", value) instead
		2. Improper handling of tables with metatables, leading to
		3. LimitedTable inside another LimitedTable is not properly handled.
	
	Examples:
		creating new object
			local variablesObject = module.new(512000)
			local variables = variablesObject.table

		interacting with table like a normal one
			variables.myVariable = "Hello, world!"
			variables.numbers = 12345678
			variables.groceries = {
				"milk",
				"eggs",
				"cheese",
			}
			variables.recursiveData = {}
			variables.recursiveData.reference = variables.recursiveData

		interacting with table in a super optimized way
			variablesObject:set("myVariable", "Hello, world!")
			variablesObject:set("numbers", "12345678")
			variablesObject:set("groceries", {
				"milk",
				"eggs",
				"cheese",
			})
			variablesObject:set("recursiveData", {})
			variablesObject:set("reference", variables.recursiveData, variables.recursiveData)

		destroying object
			variablesObject:destroy()
			variablesObject = nil
			variables = nil

	Copyright (c) 2025 @arythmitic4l

	Permission is hereby granted, free of charge, to any person obtaining a copy of
	this software and associated documentation files (the "Software"), to deal in the
	Software without restriction, including without limitation the rights to use, copy,
	modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
	and to permit persons to whom the Software is furnished to do so, subject to the
	following conditions:

	The above copyright notice and this permission notice shall be included in all copies
	or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
	INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
	PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
	LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
	USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

--!strict
--!native
--!optimize 2

-- used by methods in metatables for referencing LimitedTable by their environments
local objectsDictionary = setmetatable(
	{} :: {
		[LimitedTableTable]: LimitedTable?,
	},
	{
		__mode = "kv", -- when objects are not referenced anywhere, they should get obliterated by GC
	}
)

-- metatable for LimitedTable.table and tables inside it
local tableMetatable = {}

--[[
	Calculates the size of "data", without recursing.
	Reference sizes are calculated correctly.
	
	Handles probably all concrete and builtin types.
	Not 100% accurate and never will. Lets be honest about that.
]]
local function calculateSize(data: any): number
	local type = type(data)

	if type == "nil" then
		return 0 -- does not exist at all
	elseif type == "string" then
		return string.len(data)
	elseif type == "number" then
		return 8 -- 64-bit double-precision floating-point number
	elseif type == "boolean" then
		return 1 -- true/false
	elseif type == "table" then
		return 40 -- reference size + headers
	elseif type == "function" then
		return 8 -- memory address
	elseif type == "userdata" then
		return 16 -- engine reference size, nothing else can be measured
	elseif type == "vector" then
		return 24 -- 3 numbers
	elseif type == "buffer" then
		return buffer.len(data)
	else
		warn(`{type} is not supported`) -- shouldn't occur
		return 0
	end
end

--[[
	Attaches a counting metatable to the given table and calculates its initial size.
	If additional tables were found, does the same thing for them.
	
	Returns the calculated size of table.
]]
local function transformTableRecursive(object: LimitedTable, data: { [any]: any }): number
	local currentSize = 0 -- header is already included from calculateSize()

	setmetatable(data, tableMetatable)
	objectsDictionary[data] = object

	for key, value in pairs(data) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what

		if typeof(value) == "table" and objectsDictionary[value] == nil then
			currentSize += transformTableRecursive(object, value)
		end
	end

	return currentSize
end

--[[
	Returns a deep copy of "target", with all limited tables replaced by normal ones.
]]
local function cloneTableRecursive<T>(target: LimitedTableTable, visited: { [LimitedTableTable]: T }): T
	local cached: T? = visited[target]

	if cached == nil then
		type RawCloned = typeof(setmetatable(target :: any, nil)) -- typecast into any: deleting metatable
		local clone: RawCloned = {}

		visited[target] = clone

		for key: any, value: any in pairs(target) do
			if typeof(value) == "table" and getmetatable(value) == tableMetatable then
				-- we remove only OUR size listeners
				clone[key] = cloneTableRecursive(value, visited)
			else
				clone[key] = value
			end
		end

		return clone
	else
		return cached
	end
end

--[[
	Traverses over a table, wiping out everything possible.
]]
local function clearTableRecursive(target: LimitedTable, visited: { LimitedTableTable }?): ()
	-- objects are END OF LIFE: everything is turned into nil no matter what
	-- (this is the reason why i'm typecasting into nil here)

	local visited = visited or {}

	if table.find(visited, target) == nil then
		table.insert(visited, target)

		setmetatable(target :: any, nil)

		for key: any, value: any in pairs(target) do
			if typeof(value) == "table" then
				clearTableRecursive(value, visited)
			end
			target[key] = nil
		end
	end
end

--[[
	Adjusts _currentSize upon changes.
	
	Not stable because __newindex does not fire for entries that already exist.
]]
function tableMetatable.__newindex(self: LimitedTableTable, key: any, value: any): ()
	warn(`table.key = value is not stable, use inbuilt methods instead`)

	-- code is mostly synced with LimitedTable:set()

	local object: LimitedTable? = objectsDictionary[self] -- reference to LimitedTable
	assert(object) -- here for typechecking issues, could be in a line above

	local currentSize: number = object._currentSize
	local oldValue: any = self[key]

	currentSize += calculateSize(value) - calculateSize(oldValue) -- currentSize + delta

	-- entry does not exist if it is nil
	if oldValue == nil then
		currentSize += calculateSize(key) + 16 -- 16 bytes overhead for each entry
	elseif value == nil then
		currentSize -= calculateSize(key) + 16 -- 16 bytes overhead for each entry
	end

	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += transformTableRecursive(object, value)
	end

	if currentSize > object.maximumSize then
		-- not using assert for speed and stack level "2"
		error(`maximum size of {object.maximumSize} bytes reached`, 2)
	end

	-- table should change only if the size does not exceed

	object._currentSize = currentSize
	rawset(self :: any, key, value) -- typecasted into any because rawset type definition is incorrect
end

local LimitedTable = {}
LimitedTable.__index = LimitedTable

--[[
	Create a new LimitedTable object with given size limit of "maximumSize".
	When writing a value that exceeds total size, raises an error.
	
	For getting, use LimitedTable.table like a normal table.
	For setting, use LimitedTable:set(). Writing to LimitedTable.table is unstable.
	
	Example:
		local env = LimitedTable.new(512000)
		env.table:set("test", "Hi")
		env.table.slow = "brrrrrr"
]]
function LimitedTable.new(maximumSize: number): LimitedTable
	assert(typeof(maximumSize) == "number", "expected maximumSize to be a number")
	-- hiding metatable use haha very funny
	local object = setmetatable({}, LimitedTable)
	object._currentSize = 0
	object.maximumSize = maximumSize
	object.table = setmetatable({} :: { [any]: any }, tableMetatable)

	objectsDictionary[object.table] = object

	return object
end

--[[
	Checks if LimitedTable was created by this module (aka a "valid" one)
	
	Example:
		print(LimitedTable.isValid(LimitedTable.new(512000))) -- "true"
		print(LimitedTable.isValid({})) -- "false"
]]
function LimitedTable.isValid(object: LimitedTable): boolean
	assert(object, "object not provided")

	if typeof(object) ~= "table" then
		return false
	end

	-- typecasted into any because getmetatable type definition is incorrect
	local metatable = getmetatable(object :: any)

	if metatable == nil then
		return false
	end

	return metatable.__index == LimitedTable
end

--[[
	Sets "key" of given "table" to "value".
	"table" defaults to self.table
	
	Use over limitedTable.table[key] = value, as the latter is unstable.
	
	Example:
		obj:set("a", "hi")
		obj:set("myArray", {})
		obj:set(1, "lol", lt.table.myArray)
		obj:set("myArray", {
		    "milk",
		    "cheese",
		    "pizza",
		})
]]
function LimitedTable.set(self: LimitedTable, key: any, value: any, table: LimitedTableTable?): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if table == nil then
		target = self.table
	else
		assert(
			objectsDictionary[table] == self,
			"table does not belong to LimitedTable, or is not a valid object at all"
		)
		target = table
	end

	local currentSize: number = self._currentSize
	local oldValue: any = target[key]

	currentSize += calculateSize(value) - calculateSize(oldValue) -- currentSize + delta

	-- entry does not exist if it is nil
	if oldValue == nil then
		currentSize += calculateSize(key) + 16 -- 16 bytes overhead for each entry
	elseif value == nil then
		currentSize -= calculateSize(key) + 16 -- 16 bytes overhead for each entry
	end

	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += transformTableRecursive(self, value)
	end

	if currentSize > self.maximumSize then
		error(`maximum size of {self.maximumSize} bytes reached`, 2)
	end

	-- table should change only if the size does not exceed

	self._currentSize = currentSize
	rawset(target :: any, key, value) -- typecasted into any because rawset type definition is incorrect
end

--[[
	Inserts "value" at given "position" of "array".
	
	"array" defaults to self.table
	"position" defaults to the end of the "array"
	
	Example:
		for i = 1, 10 do
			obj:insert("Hello, world!", "myArray")
		end
]]
function LimitedTable.insert(self: LimitedTable, value: any, array: LimitedTableTable?, position: number?): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if array == nil then
		target = self.table
	else
		assert(
			objectsDictionary[array] == self,
			"table does not belong to LimitedTable, or is not a valid object at all"
		)
		target = array
	end

	local currentSize: number = self._currentSize

	currentSize += calculateSize(value) + 24 -- value size + key internal + number size

	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += transformTableRecursive(self, value)
	end

	if currentSize > self.maximumSize then
		error(`maximum size of {self.maximumSize} bytes reached`, 2)
	end

	-- array should change only if the size does not exceed

	self._currentSize = currentSize

	if not position then
		table.insert(target :: any, value) -- table.insert bypasses metatables
	else
		table.insert(target :: any, position :: any, value)
	end
end

--[[
	Remove entry at given "position" of "array".
	
	"array" defaults to self.table
	"position" defaults to the end of the "array"
	
	Example:
		obj:remove("myArray")
		obj:remove("myArray, 2")
]]
function LimitedTable.remove(self: LimitedTable, array: LimitedTableTable?, position: number?): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if array == nil then
		target = self.table
	else
		assert(
			objectsDictionary[array] == self,
			"table does not belong to LimitedTable, or is not a valid object at all"
		)
		target = array
	end

	local targetPos = position or #target
	local targetValue = target[targetPos]

	if targetValue ~= nil then
		self._currentSize -= calculateSize(targetValue) + 24 -- value size + key internal + number size

		-- size checks are not performed because we are only subtracting current size,
		-- should not be a problem but if you experience something weird, be aware

		table.remove(target :: any, targetPos) -- table.remove bypasses metatables
	end
end

--[[
	Returns a deep copy of given "table", with all limited tables replaced by normal ones.
	"table" must belong to LimitedTable. set to LimitedTable.table by default.
	
	You can do LimitedTable.cloneRaw(obj, ...) to increase speed in repetitive use cases.
	
	Example:
		-- example data
		obj:set("a", 1)
		obj:set("t", {
		    a = "b",
		    z = "4",
		}
		obj:set("r", {})
		obj:set(1, obj.table.r, obj.table.r)
		obj:set(2, obj.table, obj.table.r)
		
		print(obj:cloneRaw())
		print(obj:cloneRaw(obj.table.t))
		print(obj:cloneRaw(obj.table.r))
]]
function LimitedTable.cloneRaw(self: LimitedTable, table: LimitedTableTable?): { [any]: any }
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if table == nil then
		target = self.table
	else
		assert(
			objectsDictionary[table] == self,
			"table does not belong to LimitedTable, or is not a valid object at all"
		)
		target = table
	end

	return cloneTableRecursive(target, {})
end

--[[
	Destroy given LimitedTable. Make sure to clear up references!
	
	Example:
		local object = module.new(512000)
		local table = nil
		
		local references = setmetatable(
		    { object, table },
		    { __mode = "v" }
		)
		
		object:destroy()
		object = nil
		table = nil
		
		task.wait(2)
		print(`destroyed: {#references == 0}!`)
]]
function LimitedTable.destroy(self: LimitedTable): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	-- i could go through objectsDictionary and use table.clear() but
	-- it will get slower and slower the bigger objectsDictionary becomes

	clearTableRecursive(self)

	-- references from objectsDictionary are auto-removed becase it is a weak table
end

export type LimitedTable = typeof(setmetatable(
	{} :: {
		maximumSize: number,
		_currentSize: number,
		table: LimitedTableTable,
	},
	LimitedTable
))

type LimitedTableTable = typeof(setmetatable({} :: { [any]: any }, tableMetatable))

return table.freeze(LimitedTable)
