--!strict
--!optimize 2

--[[
	Constructor of tables with size limits.
	Useful for interpreters, VMs and much more.
	
	Usage:
		LimitedTable.new(maxSize: number): LimitedTable - returns a new LimitedTable object.
			LimitedTable.table - table with size limit
			LimitedTable:set(key, value, table?) - table defaults to LimitedTable.table
			
			LimitedTable.maximumSize - can be adjusted dynamically, but be careful.
			LimitedTable:destroy() - destroys everything possible. make sure to clear up references.
	
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
]]
--[[
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


-- used by methods in metatables for referencing LimitedTable by their environments
local objectsDictionary = setmetatable({} :: LimitedEnvCache, {
	__mode = "kv" -- when objects are not referenced anywhere, they should get obliterated by GC
})

-- metatable for LimitedTable.table and tables inside it
local tableMetatable = {}

--[[
	Calculates the size of "data", without recursing.
	Reference sizes are calculated correctly.
	
	Handles probably all concrete and builtin types.
	Not 100% accurate and never will. Lets be honest about that.
]]
@native
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
@native
local function insertTableRecursive(object: LimitedTableLocal, data: { [any]: any }): number
	local currentSize = 40 -- header + memory address 
	for key, value in pairs(data) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what
		
		if typeof(value) == "table" and objectsDictionary[value] == nil then
			currentSize += insertTableRecursive(object, value)
		end
	end
	
	setmetatable(data, tableMetatable)
	objectsDictionary[data] = object
	
	return currentSize
end

--[[
	Traverses over a LimitedEnv table, wiping out everything possible.
]]
@native
local function clearTableRecursive(target: LimitedTableTable, visited: { LimitedTableTable }?): ()
	local visited = visited or {}
	
	if table.find(visited, target) ~= nil then
		table.insert(visited, target)
		
		setmetatable(target :: any, nil)
		
		for key, value in pairs(target) do
			if typeof(value) == "table" then
				clearTableRecursive(value, visited)
			end
			target[key] = nil
		end
	end
end

--[[
	Adjusts _currentSize upon changes.
]]
@native
function tableMetatable.__newindex(self: LimitedTableTable, key: string, value: any): ()
	-- code is mostly synced with LimitedEnv:set()
	
	local object = objectsDictionary[self] -- reference to LimitedTable
	
	local currentSize = object._currentSize
	local oldValue = self[key]
	
	currentSize -= calculateSize(oldValue) -- old size
	
	-- new size
	if oldValue == nil then
		currentSize += calculateSize(key)
	end
	currentSize += calculateSize(value)
	
	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += insertTableRecursive(object, value)
	end
	
	if currentSize > object.maximumSize then
		error(`maximum size of {object.maximumSize} bytes reached`, 2)
	end
	
	-- table should change only if the size does not exceed
	
	object._currentSize = currentSize
	rawset(self :: any, key, value) -- typecasted into any because fuck rawset type definition
end


local LimitedTable = {}
LimitedTable.__index = LimitedTable

--[[
	Create a new LimitedTable object with given size limit of "maximumSize".
	When limit is reached, errors.
	
	Example:
		local lt = module.new(512000)
]]
function LimitedTable.new(maximumSize: number): LimitedTable
	assert(typeof(maximumSize) == "number", "expected maximumSize to be a number")
	
	-- hiding metatable use haha very funny
	local obj: LimitedTableLocal = setmetatable({}, LimitedTable) :: any
	obj._currentSize = 0
	obj.maximumSize = maximumSize
	obj.table = setmetatable({}, tableMetatable)
	
	objectsDictionary[obj.table] = obj
	
	return obj :: any -- LimitedTableLocal -> LimitedTable
end

--[[
	Checks if LimitedTable was created by this module.
]]
function LimitedTable.isValid(object: LimitedTable): boolean
	assert(object, "object not provided")
	
	if typeof(object) ~= "table" then
		return false
	end
	
	-- typecasted into any because fuck getmetatable type definition
	if getmetatable(object :: any) == nil then
		return false
	end
	
	return getmetatable(object :: any).__index == LimitedTable
end

--[[
	Sets "key" of given "table" to "value".
	"table" defaults to self.table
	
	Recommended to be used over limitedTable.table[key] = value, as it is much faster than __newindex call.
	
	You can also do LimitedTable.set(obj, ...) to increase speed in repetitive cases.
	
	Examples:
		lt:set("a", "hi")
		lt:set(1, "lol", lt.table.myArray)
]]
@native
function LimitedTable.set(self: LimitedTable, key: any, value: any, table: LimitedTableTable?): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')
	local self: LimitedTableLocal = self :: any -- _currentSize access to autocomplete

	local currentSize = self._currentSize
	local oldValue = self[key]

	currentSize -= calculateSize(oldValue) -- old size

	-- new size
	if oldValue == nil then
		currentSize += calculateSize(key)
	end
	currentSize += calculateSize(value)

	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += insertTableRecursive(self, value)
	end

	if currentSize > self.maximumSize then
		error(`maximum size of {self.maximumSize} bytes reached`, 2)
	end

	-- table should change only if the size does not exceed

	self._currentSize = currentSize
	rawset(self :: any, key, value) -- typecasted into any because fuck rawset type definition
end

--[[
	Destroy given LimitedTable. Make sure to clear up references!
	
	Example:
		local lt = module.new(512000)
		lt:destroy()
		lt = nil
]]
function LimitedTable:destroy(): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	-- i could go through objectsDictionary and use table.clear() but
	-- it will get slower and slower the bigger objectsDictionary becomes
	clearTableRecursive(self)

	-- references from objectsDictionary are auto-removed becase it is a weak table
end

table.freeze(LimitedTable)

-- types are defined down here because of typeof() uses

export type LimitedTable = {
	table: { [any]: any },
	maximumSize: number,
	set: typeof(LimitedTable.set),
	destroy: typeof(LimitedTable.destroy),
}

-- same as LimitedTable, except with private fields. used only in this script
type LimitedTableLocal = {
	table: LimitedTableTable,
	_currentSize: number, -- _currentSize must not be modified by other scripts!
	maximumSize: number,
	set: typeof(LimitedTable.set),
	destroy: typeof(LimitedTable.destroy),
}

type LimitedTableTable = typeof(setmetatable({}, tableMetatable))

-- used for "objects" at the very top, for proper type definition
type LimitedEnvCache = {
	[LimitedTableTable]: LimitedTableLocal,
}

return LimitedTable
