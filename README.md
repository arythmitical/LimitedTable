# LimitedTable

Constructor of tables with size limits. Useful for interpreters, VMs and much more.

## Installation

### Using [Wally](https://github.com/UpliftGames/wally)

Add LimitedTable to your dependencies in `wally.toml` file:

```toml
limitedtable = "arythmitical/limitedtable@1.1.1"
```

In shell, run:

```bash
wally install
```

### Using Creator Marketplace

[Creator Marketplace Module](https://create.roblox.com/store/asset/103337933619557)

### Using .rbxm from GitHub

Download the [latest release file](https://github.com/arythmitical/LimitedTable/releases/latest) from releases and add it into your project.

## Example

To see an example of what can be done using LimitedTable, open `LimitedTable.rbxlx` in Roblox Studio and start the [Rojo](https://rojo.space/) server:

```bash
rojo serve example.project.json
```

## Usage

Docs are not available, however the interface is pretty intuitive. Here are some examples:

### Constructing and modifying new LimitedTable

```lua
local limitedTable = LimitedTable.new(512000)

limitedTable.sizeExceededMessage = "maximum size of a gazillion bytes reached" -- u can also do LimitedTable.new(512000, "my error message!")

limitedTable.maximumSize = 512001 -- be careful when reducing maximum size

print(limitedTable._currentSize)
print(LimitedTable.isValid(limitedTable)) -- true
```

### Accessing and editing table

```lua
local realTable = limitedTable.table -- use this for ONLY GETTING values!

limitedTable:set("myEntry", "Hello, world!")
print(realTable.myEntry) -- "Hello, world!"

limitedTable:set("anotherTable", {})
limitedTable:set("entry", 1234, "anotherTable")

limitedTable:set(
    "tableTemplate",
    table.clone({ -- pasted tables are being internally modified, be aware!
        a = "b",
        foo = "bar",
    }
))
```

### Working with arrays

```lua
limitedTable:set("myArray", {})

for i = 1, 10 do
    limitedTable:insert("hey", "myArray")
end
print(#realTable.myArray) -- 10

-- inserting at specific position
limitedTable:insert("lol", "myArray", 1)
print(#realTable.myArray) -- 11

limitedTable:remove("myArray") -- remove last element
print(#realTable.myArray) -- 10

-- table.find and other simillar functions can be used as long as the don't modify the table
print(table.find(realTable.myArray, "lol")) -- 1
limitedTable:remove("myArray", 1)
print(table.find(realTable.myArray, "lol")) -- nil
```

### Getting raw tables

```lua
local rawTable = limitedTable:cloneRaw()

print(realTable == rawTable) -- false

local anotherClone = limitedTable:cloneRaw(realTable.myArray)
```

### Disposing of the LimitedTable

```lua
limitedTable:destroy()
realTable = nil
limitedTable = nil
```

Setting to `nil` is neccessary to ensure the object was fully cleared from memory. Make sure **all** references are removed!
