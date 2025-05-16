# LimitedTable

Constructor of [Luau](https://luau-lang.org) tables with size limits. Useful for interpreters, VMs and much more.

## Installation

### GitHub

Download the [latest .rbxm file](https://github.com/arythmitical/LimitedTable/releases/latest) from releases and insert it into Roblox Studio.

### Creator Marketplace

[Creator Marketplace Module](https://create.roblox.com/store/asset/103337933619557)

### **[Wally](https://github.com/UpliftGames/wally)**

1. Add LimitedTable to dependencies in `wally.toml` inside your project:

    ```toml
    limitedtable = "arythmitical/limitedtable@1.2.0"
    ```

2. Update dependencies using shell:

    ```bash
    wally install
    ```

## Usage

### Properties

#### .maximumSize

```lua
LimitedTable.maximumSize: number
```

Determines the maximum allowed size of data inside LimitedTable. This **must** be specified.

#### .table

```lua
LimitedTable.table: { [any]: any }
```

The real table with contents of LimitedTable *(aka LimitedTableTable)*. **Use only for getting values**.

#### .sizeExceededMessage

```lua
LimitedTable.sizeExceededMessage: string | (table: LimitedTableTable) -> (),
```

Determines the error message that will be raised when the maximum size is exceeded. Alternatively, it can be a **function** that will be invoked instead of raising an error.

Default: `maximum size of %s bytes exceeded`

### Functions

#### .new

```lua
function LimitedTable.new(
    maximumSize: number,
    errorMessage: (string | () -> ())?
): LimitedTable
```

Construct a new LimitedTable with given size limit of **`maximumSize`** bytes.

Writing a value that exceeds LimitedTable's size will raise an error with **`errorMessage`**. If the `errorMessage` is a function, then that function will be called instead.

Example:

```lua
local lt = LimitedTable.new(512000)

lt.maximumSize += 64000

lt.sizeExceededMessage = "bum"
lt.sizeExceededMessage = function()
    game.Players.LocalPlayer:Kick()
end
```

#### isValid

```lua
function LimitedTable.isValid(
    object: LimitedTable
): boolean
```

Checks if the given **`object`** is a valid LimitedTable from this module.

Example:

```lua
print(LimitedTable.isValid(LimitedTable.new(512000))) --> true
print(LimitedTable.isValid({})) --> false
```

#### isTable

```lua
function LimitedTable.isTable(
    object: LimitedTableTable
): boolean
```

Checks if the given **`object`** is a valid LimitedTableTable from this module.

Example:

```lua
print(LimitedTable.isTable(LimitedTable.new(512000).table)) --> true
print(LimitedTable.isTable({})) --> false
```

#### getOwner

```lua
function LimitedTable.getOwner(
    table: LimitedTableTable
): LimitedTable?
```

Returns the LimitedTable that the **`table`** belongs to, or nil if not found.

Example:

```lua
local lt = LimitedTable.new(512000)
print(LimitedTable.getOwner(lt.table) == lt) --> true

local another = LimitedTable.new(512000)
print(LimitedTable.getOwner(lt.table) == another) --> false
```

#### :set

```lua
function LimitedTable:set(
    key: any,
    value: any,
    table: LimitedTableTable?,
    apply: boolean?
): number
```

Sets **`key`** of given **`table`** to **`value`** and returns the size of the changes.

**`table`** defaults to `LimitedTable.table`. Optional parameter **`apply`** determines whether to apply given changes.

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

#### :insert

```lua
function LimitedTable:insert(
    value: any,
    array: LimitedTableTable?,
    position: number?,
    apply: boolean?
): number
```

Inserts **`value`** at given **`position`** of **`array`** and returns the size of the changes. If **`position`** is not provided, inserts to the end of the **`array`**.

**`array`** defaults to `LimitedTable.table`. Optional parameter **`apply`** determines whether to apply given changes.

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

#### :remove

```lua
function LimitedTable:remove(
    array: LimitedTableTable?,
    position: number?,
    apply: boolean?
): number
```

Removes element at given **`position`** from **`array`** and returns the size of the changes. If **`position`** is not provided, removes the last element from the **`array`**.

**`array`** defaults to `LimitedTable.table`. Optional parameter **`apply`** determines whether to apply given changes.

Example:

```lua
local lt = LimitedTable.new(512000)
lt:set("myArray", {
    "milk",
    "eggs",
    "cheese",
})

lt:remove(lt.table.myArray) -- remove last element
lt:remove(lt.table.myArray, 1)

print(lt.table.myArray) --> { "eggs" }
```

#### :cloneRaw

```lua
function LimitedTable:cloneRaw(
    table: LimitedTableTable?
): { [any]: any }
```

Returns a deep copy of **`table`**, with all LimitedTable tables replaced by normal ones.

**`table`** defaults to `LimitedTable.table`.

Example:

```lua
local lt = LimitedTable.new(512000)
lt:set("t", { 1, 2, 3 })

local raw = lt:cloneRaw(lt.table.t)
print(raw) --> { 1, 2, 3 }
print(raw == lt.table.t) --> false
```

#### :destroy

```lua
function LimitedTable:destroy(): ()
```

Destroys LimitedTable. Make sure to clear up **all** references!

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

## Example

Check out the example usage of LimitedTable! Clone the Git repo and build the example project:

```bash
rojo build --output LimitedTableExample.rbxl example.project.json
```
