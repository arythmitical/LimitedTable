--[[
	Constructor of tables with size limits.
	Useful for interpreters, VMs and much more.
	
	Current limitations:
		1. Improper handling of tables with metatables, leading to
		2. LimitedTable inside another LimitedTable is not properly handled.
	
	Short documentation (also see individual function docs):
		LimitedTable.new(maxSize: number): LimitedTable - returns a new LimitedTable object.
			LimitedTable.table - table with size limit (has a metatable, see cloneRaw)
			LimitedTable:set(key, value, table?): () - table defaults to LimitedTable.table
			LimitedTable:cloneRaw(table?): table - removes all metatables
			
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

--!strict
--!optimize 2
-- @native function attribute is used instead of --!native


-- used by methods in metatables for referencing LimitedTable by their environments
local objectsDictionary = setmetatable({} :: {
	[LimitedTableTable]: LimitedTable?,
}, {
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
local function transformTableRecursive(object: LimitedTable, data: { [any]: any }): number
	local currentSize = 40 -- header + memory address 
	for key, value in pairs(data) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what
		
		if typeof(value) == "table" and objectsDictionary[value] == nil then
			currentSize += transformTableRecursive(object, value)
		end
	end
	
	setmetatable(data, tableMetatable)
	objectsDictionary[data] = object
	
	return currentSize
end

--[[
	Returns a deep copy of "target", with all limited tables replaced by normal ones.
]]
@native
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
@native
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
]]
@native
function tableMetatable.__newindex(self: LimitedTableTable, key: string, value: any): ()
	-- code is mostly synced with LimitedTable:set()
	
	local object: LimitedTable? = objectsDictionary[self] -- reference to LimitedTable
	assert(object, "die idiot") -- SHOULD never happen
	
	local currentSize: number = object._currentSize
	local oldValue: any = self[key]
	
	currentSize -= calculateSize(oldValue) -- old size
	
	-- new size
	if oldValue == nil then
		currentSize += calculateSize(key)
	end
	currentSize += calculateSize(value)
	
	if typeof(value) == "table" and objectsDictionary[value] == nil then
		currentSize += transformTableRecursive(object, value)
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
	When writing a value that exceeds total size, raises an error.
	
	For getting, use LimitedTable.table like a normal table.
	For setting, use LimitedTable:set(). Writing to LimitedTable.table is less performant.
	
	Example:
		local env = LimitedTable.new(512000)
		env.table:set("test", "Hi")
		env.table.slow = "brrrrrr"
]]
@native
function LimitedTable.new(maximumSize: number)
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
@native
function LimitedTable.isValid(object: LimitedTable): boolean
	assert(object, "object not provided")
	
	if typeof(object) ~= "table" then
		return false
	end
	
	-- typecasted into any because fuck getmetatable type definition
	local metatable = getmetatable(object :: any)
	
	if metatable == nil then
		return false
	end
	
	return metatable.__index == LimitedTable
end

--[[
	Sets "key" of given "table" to "value".
	"table" defaults to self.table
	
	Recommended to be used over limitedTable.table[key] = value, as it is much faster than __newindex call.
	
	You can also do LimitedTable.set(obj, ...) to increase speed in repetitive use cases.
	
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
@native
function LimitedTable:set(key: any, value: any, table: LimitedTableTable?): ()
	-- i have chosen to not write as module:namecall() because i define properties
	
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')
	
	local target: LimitedTableTable;
	
	if table ~= nil then
		assert(objectsDictionary[table] == self, "table does not belong to LimitedTable")
		target = table
	else
		target = self.table
	end

	local currentSize: number = self._currentSize
	local oldValue: any = self[key]

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
	rawset(target :: any, key, value) -- typecasted into any because fuck rawset type definition
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
@native
function LimitedTable:cloneRaw(table: LimitedTableTable?): { [any]: any }
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')
	
	local target: LimitedTableTable;

	if table ~= nil then
		assert(objectsDictionary[table] == self, "table does not belong to LimitedTable")
		target = table
	else
		target = self.table
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
function LimitedTable:destroy(): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	-- i could go through objectsDictionary and use table.clear() but
	-- it will get slower and slower the bigger objectsDictionary becomes

	clearTableRecursive(self)

	-- references from objectsDictionary are auto-removed becase it is a weak table
end

table.freeze(LimitedTable)

-- types are defined down here because of typeof() resolvers
export type LimitedTable = typeof(LimitedTable.new(0)) -- solely to get the type
type LimitedTableTable = typeof(setmetatable({} :: { [any]: any }, tableMetatable))

return LimitedTable
