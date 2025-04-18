--[[
	Constructor of tables with size limits.
	Useful for interpreters, VMs and much more.
	
	For usage docs and license, visit:
	https://github.com/arythmitical/LimitedTable
]]

--!strict
--!native
--!optimize 2

local LimitedTable = {}
LimitedTable.__index = LimitedTable

-- in case developer was writing to table directly
local newIndexWarningShown: boolean = false

-- used for quickly referencing LimitedTable by its LimitedTable, without any complicated things
local objectsDictionary = setmetatable(
	{} :: {
		[LimitedTableTable]: LimitedTable?,
	},
	{
		__mode = "kv", -- when objects are not referenced anywhere, they should get obliterated by GC
	}
)

-- used for checking reference amount to LimitedTableTable
local objectsReferences = setmetatable(
	{} :: {
		[LimitedTableTable]: number,
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
local function transformTableRecursive(
	data: { [any]: any },
	object: LimitedTable,
	calculated: { { [any]: any } }
): number
	table.insert(calculated, data)

	local currentSize = 0 -- header is already included from calculateSize()

	setmetatable(data, tableMetatable)
	objectsDictionary[data] = object
	objectsReferences[data] = 0

	for key, value in pairs(data) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what

		if typeof(value) == "table" and objectsDictionary[value] == nil and table.find(calculated, value) == nil then
			currentSize += transformTableRecursive(value, object, calculated)
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
	Frees the table out of LimitedTable and its listeners, and returns the size it was taking.
	If additional tables were found and they don't have any references too, does the same thing for them.
]]
local function freeTableSizeRecursive(target: LimitedTableTable, calculated: { LimitedTableTable }): number
	table.insert(calculated, target)

	local currentSize = 0 -- header is already included from calculateSize()

	setmetatable(target :: any, nil)

	objectsDictionary[target] = nil
	objectsReferences[target] = nil

	for key, value in pairs(target) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what

		if typeof(value) == "table" and objectsReferences[value] == 1 and table.find(calculated, value) == nil then -- only if referenced here
			currentSize += freeTableSizeRecursive(value, calculated)
		end
	end

	return currentSize
end

--[[
	Traverses over a table, wiping out everything possible.
	If additional tables were found, does the same thing for them.
]]
local function wipeTableRecursive(target: LimitedTableTable, visited: { LimitedTableTable }): ()
	if table.find(visited, target) == nil then
		table.insert(visited, target)

		setmetatable(target :: any, nil)

		for key: any, value: any in pairs(target) do
			if typeof(value) == "table" and getmetatable(value) == tableMetatable then
				wipeTableRecursive(value, visited)
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
	if newIndexWarningShown == false then
		warn("writing to table directly is not stable, use limitedTable:set() instead")
		newIndexWarningShown = true
	end

	local object: LimitedTable? = objectsDictionary[self] -- reference to LimitedTable
	assert(object, "table does not belong to any LimitedTable")

	object:set(key, value, self)
end

--[[
	Create a new LimitedTable object with given size limit of "maximumSize".
	When writing a value that exceeds total size, raises an error with "errorMessage".

	"errorMessage" defaults to "maximum size of %s bytes exceeded"
	
	For getting, use LimitedTable.table like a normal table.
	For setting, use LimitedTable:set(). Writing to LimitedTable.table is unstable.
	
	Example:
		local env = LimitedTable.new(512000)
		env.table:set("test", "Hi")
		env.table.slow = "brrrrrr"
]]
function LimitedTable.new(maximumSize: number, errorMessage: string?): LimitedTable
	assert(typeof(maximumSize) == "number", "expected maximumSize to be a number")

	local object = setmetatable({}, LimitedTable)
	object._currentSize = 0
	object.maximumSize = maximumSize
	object.sizeExceededMessage = errorMessage or "maximum size of %s bytes exceeded"

	local limitedTableTable = setmetatable({} :: { [any]: any }, tableMetatable)
	object.table = limitedTableTable
	objectsDictionary[limitedTableTable] = object
	objectsReferences[limitedTableTable] = 0 -- only references coming from LimitedTableTable are counted

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

	if typeof(value) == "table" then
		if objectsDictionary[value] == nil then
			currentSize += transformTableRecursive(value, self, {})
		end

		objectsReferences[value] += 1
	end

	if currentSize > self.maximumSize then
		-- changes must be reverted
		if typeof(value) == "table" then
			objectsReferences[value] -= 1
		end

		error(string.format(self.sizeExceededMessage, self.maximumSize), 2)
	end

	-- table must change only if the size does not exceed

	-- reducing size if the table is no longer referenced inside LimitedTable
	-- past limit check because subtraction will never exceed size limit
	if typeof(oldValue) == "table" then
		-- oldValue is LimitedTableTable
		objectsReferences[oldValue] -= 1

		if objectsReferences[oldValue] == 0 then
			currentSize -= freeTableSizeRecursive(oldValue, {})
		end
	end

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
		currentSize += transformTableRecursive(value, self, {})
	end

	if currentSize > self.maximumSize then
		error(string.format(self.sizeExceededMessage, self.maximumSize), 2)
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
		local newSize = self._currentSize

		newSize -= calculateSize(targetValue) + 24 -- value size + key internal + number size

		-- reducing size if the table is no longer referenced inside LimitedTable
		if typeof(targetValue) == "table" then
			-- oldValue is LimitedTableTable
			objectsReferences[targetValue] -= 1

			if objectsReferences[targetValue] == 0 then
				newSize -= freeTableSizeRecursive(targetValue, {})
			end
		end

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

	wipeTableRecursive(self.table, {})

	setmetatable(self :: any, nil)
	table.clear(self :: any)

	-- references from objectsDictionary are auto-removed because it is a weak table
end

type LimitedTableTable = typeof(setmetatable({} :: { [any]: any }, tableMetatable))

export type LimitedTable = typeof(setmetatable(
	{} :: {
		table: LimitedTableTable,
		maximumSize: number,
		_currentSize: number,
		sizeExceededMessage: string,
	},
	LimitedTable
))

return table.freeze(LimitedTable)
