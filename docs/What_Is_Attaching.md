# What is Attaching

LimitedTable has a special feature called **attaching**, which
lets you attach a LimitedTable to *another* LimitedTable.

## How it works

Let's imagine that you have an environment system and a root table:

```lua
local root = LimitedTable.new(1024 * 1000) -- 1MB
```

To make this 1MB limit span across the entire environment, you need
to have all LimitedTables inside of `root` add to the `root`'s current size, and
one of the best ways to solve this is to create an *attached LimitedTable*:

```lua
root:set("child", LimitedTable.new(1024 * 1000, { root }))
-- now the root will include the child's current size!
```

Or, you can also attach an existing LimitedTable using
[**\:attachTo()**](../Api#attachTo):

```lua
local child = LimitedTable.new(1024 * 1000)
child:attachTo(root)
root:set("child", child)
```

We've attached table `child` to table `root`, and now `root` includes
the size of `child`, and `child` is now restricted by both its maximum size
and `root`'s maximum size.

You can also attach to multiple LimitedTables:

```lua
local child = LimitedTable.new(1024 * 1000, {
    root,
    anotherEnv,
})

-- or...
local child = LimitedTable.new(1024 * 1000)
child:attachTo(root)
child:attachTo(anotherEnv)
```

## Detaching

Now, what if the table `child` is no longer needed? You might have decided to
attach it to a different LimitedTable, or you need to get rid of the table `child`.

In this case, you call [**\:detachFrom()**](../Api#detachFrom):

```lua
root:set("child", nil)
child:detachFrom(root) -- removed from root completely!
```

If you attached a LimitedTable to multiple LimitedTables, you can call
[**\:detachFromAll()**](../Api#detachFromAll):

```lua
local child = LimitedTable.new(1024 * 1000, {
    LimitedTable.new(1024 * 1000),
    LimitedTable.new(1024 * 1000),
})
child:detachFromAll()
```

This method is also called whenever you [destroy](../Api#destroy) the LimitedTable:

```lua
local child = LimitedTable.new(1024 * 1000, {
    LimitedTable.new(1024 * 1000),
    LimitedTable.new(1024 * 1000),
})
child:destroy()
-- same thing except child is now unusable
child = nil
```

:::warning
LimitedTable does not know if it is used anywhere and when
is it going to be garbage collected, thus it can't detach automatically,
which can lead to incorrect size calculation.

Make sure to call [**\:detachFromAll()**](../Api#detachFromAll) or
[**\:destroy()**](../Api#destroy) on a LimitedTable when it is no longer used.
:::
