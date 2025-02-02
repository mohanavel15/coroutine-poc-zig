const coroutine = @import("coroutine.zig");
const std = @import("std");

fn print(arg: []const u8) void {
    const SYS_WRITE: usize = 1;
    const STDOUT_FILENO: usize = 1;

    _ = asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [SYS_WRITE] "{rax}" (SYS_WRITE),
          [STDOUT_FILENO] "{rdi}" (STDOUT_FILENO),
          [data] "{rsi}" (arg.ptr),
          [len] "{rdx}" (arg.len),
        : "rcx", "r11"
    );
}

fn counter(len: usize) void {
    for (0..len) |i| {
        const v: [2]u8 = .{ @as(u8, @truncate(i + 48)), '\n' };
        print(&v);
        coroutine.yeild();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) {
            @panic("memory");
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
