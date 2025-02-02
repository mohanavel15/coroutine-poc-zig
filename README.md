# Coroutine POC in Zig

>[!CAUTION]
> This is purely to get an understanding of single threaded asynchronous programming. This introduces Undefined behaviors in a lot cases.

# Example

```zig
const coroutine = @import("coroutine.zig");

pub fn main() void {
    coroutine.init(std.heap.page_allocator); 
    defer coroutine.deinit();

    coroutine.create(counter);
    coroutine.create(counter);

    coroutine.run();
}
```
### Output
```
0
0
1
1
2
2
3
3
4
4
5
5

... so on
```

# Reference

http://6.s081.scripts.mit.edu/sp18/x86-64-architecture-guide.html
