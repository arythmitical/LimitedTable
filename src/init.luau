--!strict
--!native
--!optimize 2

local LimitedTable = {}
LimitedTable.__index = LimitedTable

-- in case developer was writing to table directly
local newIndexWarningShown: boolean = false

-- used for quickly referencing LimitedTable by its LimitedTable, without any complicated things
local objectsRegistry = setmetatable(
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
	calculates the size of "data", without recursion.
	not 100% accurate and never will. let's be honest about that.
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
		warn(`{type} is not supported`) -- should not occur
		return 0
	end
end

--[[
	attaches a metatable to the given table and calculates its initial size.
	if additional tables were found, does the same thing for them.
	
	returns the calculated size of table.
]]
local function transformTableRecursive(
	data: { [any]: any },
	object: LimitedTable,
	calculated: { { [any]: any } }
): number
	table.insert(calculated, data)

	local currentSize = 0 -- header is already included from calculateSize()

	setmetatable(data, tableMetatable)
	objectsRegistry[data] = object
	objectsReferences[data] = 1

	for key, value in pairs(data) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what

		if
			typeof(value) == "table"
			and objectsRegistry[value] == nil
			and table.find(calculated, value) == nil
		then
			currentSize += transformTableRecursive(value, object, calculated)
		end
	end

	return currentSize
end

--[[
	returns a deep copy of "target", with all
	LimitedTable tables replaced by normal tables.
]]
local function cloneTableRecursive<T>(
	target: LimitedTableTable,
	visited: { [LimitedTableTable]: T }
): T
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
	frees the table out of LimitedTable and its listeners,
	and returns the size it was taking.

	if additional tables were found and they don't have any
	references too, does the same thing for them.

	the table can then be attached to another LimitedTable
]]
local function freeTableSizeRecursive(
	target: LimitedTableTable,
	calculated: { LimitedTableTable }
): number
	table.insert(calculated, target)

	local currentSize = 0 -- header is already included from calculateSize()

	objectsRegistry[target] = nil
	objectsReferences[target] = nil

	for key, value in pairs(target) do
		currentSize += 16 + calculateSize(key) + calculateSize(value) -- each entry takes up 16 bytes no matter what

		if
			typeof(value) == "table"
			and objectsReferences[value] == 1
			and table.find(calculated, value) == nil
		then -- only if referenced here
			currentSize += freeTableSizeRecursive(value, calculated)
		end
	end

	return currentSize
end

--[[
	clears and resets LimitedTable table.
	if additional tables were found, does the same thing for them.
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
	DEPRECATED
	__newindex is not invoked for entries that already exist.
	
	listens to changes and adjusts _currentSize.
]]
function tableMetatable.__newindex(self: LimitedTableTable, key: any, value: any): ()
	if newIndexWarningShown == false then
		warn(
			"writing to table directly is not stable, use limitedTable:set() instead"
				.. debug.traceback("came from:", 2)
		)
		newIndexWarningShown = true
	end

	local object: LimitedTable? = objectsRegistry[self] -- reference to LimitedTable
	assert(object, "table does not belong to any LimitedTable")

	object:set(key, value, self)
end

--[[
	Creates a new LimitedTable object with given size limit of "maximumSize".
	When writing a value that exceeds total size, raises an error with "errorMessage".

	"errorMessage" defaults to "maximum size of %s bytes exceeded"
	
	For getting, use LimitedTable.table like a normal table.
	For setting, use LimitedTable:set(). Writing to LimitedTable.table is unstable.
	
	Example:
	```lua
	local lt = LimitedTable.new(512000)
	lt.maximumSize += 64000
	lt.sizeExceededMessage = "bum"
	```
]]
function LimitedTable.new(maximumSize: number, errorMessage: (string | () -> ())?): LimitedTable
	assert(typeof(maximumSize) == "number", "expected maximum size to be a number")
	assert(
		errorMessage == nil
			or typeof(errorMessage) == "string"
			or typeof(errorMessage) == "function",
		"expected error message to be a string or a function"
	)

	local self = {}
	self._currentSize = 0
	self.maximumSize = maximumSize
	self.sizeExceededMessage = errorMessage or "maximum size of %s bytes exceeded"

	local limitedTableTable = setmetatable({} :: { [any]: any }, tableMetatable)
	self.table = limitedTableTable

	setmetatable(self, LimitedTable) -- setting last because of LimitedTable.__newindex

	objectsRegistry[limitedTableTable] = self
	objectsReferences[limitedTableTable] = 0 -- only references coming from LimitedTableTable are counted

	return self
end

--[[
	Checks if the given object is a valid LimitedTable from this module.
	
	Example:
	```lua
	print(LimitedTable.isValid(LimitedTable.new(512000))) --> true

	print(LimitedTable.isValid({})) --> false
	```
]]
function LimitedTable.isValid(object: LimitedTable): boolean
	return typeof(object) == "table" and getmetatable(object :: any) == LimitedTable
end

--[[
	Checks if the given object is a valid LimitedTableTable by this module.
	
	Example:
	```lua
	print(LimitedTable.isTable(LimitedTable.new(512000).table)) --> true
	
	print(LimitedTable.isTable({})) --> false
	```
]]
function LimitedTable.isTable(table: LimitedTableTable): boolean
	return typeof(table) == "table" and getmetatable(table :: any) == tableMetatable
end

--[[
	Returns the LimitedTable that the table belongs to, or nil if not found.

	Example:
	```lua
	local lt = LimitedTable.new(512000)

	print(LimitedTable.getOwner(lt.table) == lt) --> true
	```
]]
function LimitedTable.getOwner(table: LimitedTableTable): LimitedTable?
	return objectsRegistry[table]
end

--[[
	Calculates and returns the size of given data.

	If "recursive" is true and the "data" is a table
	then it counts entries's size too.

	Example:
	```lua
	print(LimitedTable.sizeOf("hi!")) --> 3

	print(LimitedTable.sizeOf({ 1, 2, 3 })) --> 40
	print(LimitedTable.sizeOf({ 1, 2, 3 }, true)) --> 88
	```
]]
function LimitedTable.sizeOf(data: any, recursive: boolean?): number
	local size = calculateSize(data)

	if typeof(data) == "table" and recursive == true then
		for key, value in pairs(data) do
			size += LimitedTable.sizeOf(key, recursive) + LimitedTable.sizeOf(value, recursive)
		end
	end

	return size
end

--[[
	Sets "key" of given "table" to "value".
	"table" defaults to self.table
	
	Returns the size of the changes.

	If "apply" is set to false, then it only returns the
	size difference without making any changes to the table.
	
	Example:
	```lua
	local lt = LimitedTable.new(512000)

	lt:set("a", "hi")

	lt:set("myArray", {})
	lt:set(1, "lol", lt.table.myArray)
	
	lt:set("myArray", {
		"milk",
		"eggs",
		"cheese",
	})
	```
]]
function LimitedTable.set(
	self: LimitedTable,
	key: any,
	value: any,
	table: LimitedTableTable?,
	apply: boolean?
): number
	assert(LimitedTable.isValid(self), 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if table == nil then
		target = self.table
	else
		assert(objectsRegistry[table] == self, "table is not attached to any LimitedTable")
		target = table
	end

	local newSize: number = 0
	local oldValue: any = target[key]

	newSize += calculateSize(value) - calculateSize(oldValue) -- currentSize + delta

	-- entry does not exist if it is nil
	if oldValue == nil then
		newSize += calculateSize(key) + 16 -- 16 bytes overhead for each entry
	end

	if value == nil then
		newSize -= calculateSize(key) + 16 -- 16 bytes overhead for each entry
	end

	if typeof(value) == "table" then
		if objectsRegistry[value] == nil then
			newSize += transformTableRecursive(value, self, {})
		else
			objectsReferences[value] += 1
		end
	end

	if self._currentSize + newSize > self.maximumSize then
		-- changes must be reverted
		if typeof(value) == "table" then
			objectsReferences[value] -= 1
		end

		if typeof(self.sizeExceededMessage) == "function" then
			self.sizeExceededMessage(target)
		else
			error(string.format(self.sizeExceededMessage, self.maximumSize), 2)
		end
	end

	-- table must change only if the size does not exceed

	-- reducing size if the table is no longer referenced inside LimitedTable
	-- past limit check because subtraction will never exceed size limit
	if typeof(oldValue) == "table" then
		-- oldValue is LimitedTableTable
		objectsReferences[oldValue] -= 1

		if objectsReferences[oldValue] == 0 then
			newSize -= freeTableSizeRecursive(oldValue, {})
		end
	end

	if apply ~= false then
		self._currentSize += newSize
		rawset(target :: any, key, value) -- typecasted into any because rawset type definition is incorrect
	end

	return newSize
end

--[[
	Inserts "value" at given "position" of "array".

	"array" defaults to self.table
	"position" defaults to the end of the "array"

	Returns the size of the changes.

	If "apply" is set to false, then it only returns the size difference,
	without making any changes to the table.

	Example:
	```lua
	local lt = LimitedTable.new(512000)

	for i = 1, 10 do
		lt:insert("Hello, world!")
	end
	
	lt:set("reversed", {})
	for i = 10, 1, -1 do
		lt:insert(i, lt.table.reversed, 1)
	end
	```
]]
function LimitedTable.insert(
	self: LimitedTable,
	value: any,
	array: LimitedTableTable?,
	position: number?,
	apply: boolean?
): number
	assert(LimitedTable.isValid(self), 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if array == nil then
		target = self.table
	else
		assert(objectsRegistry[array] == self, "table is not attached to any LimitedTable")
		target = array
	end

	local newSize: number = 0
	if value ~= nil then -- inserting nil will only update keys, meaning there won't be size change
		newSize += calculateSize(value) + 24 -- value size + key internal + number size

		if typeof(value) == "table" then
			if objectsRegistry[value] == nil then
				newSize += transformTableRecursive(value, self, {})
			else
				objectsReferences[value] += 1
			end
		end

		if self._currentSize + newSize > self.maximumSize then
			if typeof(self.sizeExceededMessage) == "function" then
				self.sizeExceededMessage(target)
			else
				error(string.format(self.sizeExceededMessage, self.maximumSize), 2)
			end
		end
	end

	if apply ~= false then
		self._currentSize += newSize

		if position == nil then
			table.insert(target :: any, value) -- table.insert bypasses metatables
		else
			table.insert(target :: any, position :: any, value)
		end
	end

	return newSize
end

--[[
	Removes entry at given "position" from "array".

	"array" defaults to self.table
	"position" defaults to the end of the "array"

	Returns the size of the changes.

	If "apply" is set to false, then it only returns the size difference,
	without making any changes to the table.

	Example:
	```lua
	local lt = LimitedTable.new(512000)
	lt:set("myArray", {
		"milk",
		"eggs",
		"cheese",
	})

	lt:remove(lt.table.myArray)
	lt:remove(lt.table.myArray, 2)

	print(lt.table.myArray) --> { "cheese" }
	```
]]
function LimitedTable.remove(
	self: LimitedTable,
	array: LimitedTableTable?,
	position: number?,
	apply: boolean?
): number
	assert(LimitedTable.isValid(self), 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if array == nil then
		target = self.table
	else
		assert(objectsRegistry[array] == self, "table is not attached to any LimitedTable")
		target = array
	end

	local targetPos = position or #target
	local targetValue = target[targetPos]

	local newSize = 0
	if targetValue ~= nil then
		newSize -= calculateSize(targetValue) + 24 -- value size + key internal + number size

		-- reducing size if the table is no longer referenced inside LimitedTable
		if typeof(targetValue) == "table" then
			-- oldValue is LimitedTableTable
			objectsReferences[targetValue] -= 1

			if objectsReferences[targetValue] == 0 then
				newSize -= freeTableSizeRecursive(targetValue, {})
			end
		end

		-- size check is not performed because we are only subtracting current size
	end

	if apply ~= false then
		self._currentSize += newSize
		table.remove(target :: any, targetPos) -- table.remove bypasses metatables
	end

	return newSize
end

--[[
	Returns a deep copy of "table", with all
	limited tables replaced by normal ones.
	
	"table" defaults to self.table
	
	Example:
	```lua
	local lt = LimitedTable.new(512000)
	lt:set("t", { 1, 2, 3 })
	
	local raw = lt:cloneRaw(lt.table.t)
	print(raw) --> { 1, 2, 3 }
	print(raw == lt.table.t) --> false
	```
]]
function LimitedTable.cloneRaw(self: LimitedTable, table: LimitedTableTable?): { [any]: any }
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	local target: LimitedTableTable

	if table == nil then
		target = self.table
	else
		assert(
			objectsRegistry[table] == self,
			"table does not belong to LimitedTable, or is not a valid object at all"
		)
		target = table
	end

	return cloneTableRecursive(target, {})
end

--[[
	Destroy given LimitedTable
	Make sure to clear up ALL references!
	
	Example:
	```lua
	local lt = LimitedTable.new(512000)

	local references = setmetatable(
		{ lt, lt.table },
		{ __mode = "v" }
	)
	
	lt:destroy()
	lt = nil
	
	task.wait(5)
	print(`deleted: {#references == 0}!`) --> true (unless something stupid happened)
	```
]]
function LimitedTable.destroy(self: LimitedTable): ()
	assert(self, 'must be called via ":" not ".", or provide LimitedTable')

	wipeTableRecursive(self.table, {})

	setmetatable(self :: any, nil)
	table.clear(self :: any)

	-- references from objectsRegistry are auto-removed because it is a weak table
end

--[[
	protection against creating unknown properties
	in LimitedTable class (not lt.table)
]]
function LimitedTable.__newindex(_: LimitedTable, key: string): ()
	error(
		`attempt to set unknown key "{key}" of LimitedTable. did you mean to set key of LimitedTable.table?`,
		2
	)
end

export type LimitedTableTable = typeof(setmetatable({} :: { [any]: any }, tableMetatable))

export type LimitedTable = typeof(setmetatable(
	{} :: {
		table: LimitedTableTable,
		maximumSize: number,
		_currentSize: number,
		sizeExceededMessage: string | (table: LimitedTableTable) -> (),
	},
	LimitedTable
))

return table.freeze(LimitedTable)
