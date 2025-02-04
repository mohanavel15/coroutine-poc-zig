const coroutine = @import("coroutine.zig");
const std = @import("std");

fn counter(len: usize) void {
    for (0..len) |i| {
        std.debug.print("{}\n", .{i});
        coroutine.yeild();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) {
            @panic("memory leak!");
        }
    }

    coroutine.init(gpa.allocator());
    defer coroutine.deinit();

    coroutine.create(struct {
        fn f() void {
            counter(10);
        }
    }.f);
    coroutine.create(struct {
        fn f() void {
            counter(6);
        }
    }.f);
    coroutine.create(struct {
        fn f() void {
            counter(12);
        }
    }.f);
    coroutine.run();
}
