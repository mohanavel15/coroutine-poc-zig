# Coroutine POC in Zing

>[!CAUTION]
> This isn't a library to be used somewhere. This is purely to get an understanding of single threaded asynchronous programming.

# Example

```zig
pub fn main() void {
    var coros: [10]Coroutine = .{.{}} ** 10;
    var manager = CoroutineManager{
        .coros = &coros,
        .len = 0,
        .curr = 0,
    };

    manager.Init();
    manager.create(counter);
    manager.create(counter);
    manager.run();
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
