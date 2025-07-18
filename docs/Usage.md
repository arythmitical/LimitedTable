# Usage Guide

## How does it work?

All changes in LimitedTable are made through custom methods, such as
[**:set()**](../Api/LimitedTable#set),
[**:insert()**](../Api/LimitedTable#insert), or
[**:remove()**](../Api/LimitedTable#remove) —
these are *the basic* operations that the developer usually does with
a normal table. *(although there are more than 3 methods in the module)*

LimitedTable always keeps track of its current size, and only updates it
when a change is made. There are **no recalculations**, only the size
of the change is calculated, which allows LimitedTable to
**error before actually changing anything** and be super fast.

## Syntax

The syntax for LimitedTable is *as simple* as the syntax for table! Just look:

Creating a table:

```lua
local default = {}
local limited = LimitedTable.new(1024 * 1000) -- 1MB
```

Modifying a table:

```lua
-- set
default.entry = "hi"
limited:set("entry", "hi")

-- insert
table.insert(default, "hi")
limited:insert("hi")

-- remove
table.remove(default, 1)
limited:remove(1)

-- clear
table.clear(default)
limited:clear()
```

Reading a table:

```lua
print(default.entry)
print(limited.contents.entry) -- just like the default table!

-- all functions for reading are also usable with LimitedTable
print(table.find(default, "hi"))
print(table.find(limited.contents, "hi"))
```

## Example

Check out [this](https://github.com/arythmitical/LimitedTable/blob/main/example/init.client.luau) example of using LimitedTable! It's a simple code
interpreter that uses LimitedTable to limit memory usage of its scripts.
