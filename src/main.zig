const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const COROUTINE_CAPACITY = 10;
const STACK_CAPACITY = 1024;

var coros: ArrayList(Context) = undefined;
var curr: usize = 0;

const Context = struct {
    rsp: usize = 0,
    stack: [STACK_CAPACITY / 8]usize = undefined,
    completed: bool = true,

    const Self = @This();

    fn init(self: *Self, func: *fn () void) void {
        @memset(&self.stack, 0);

        self.stack[self.stack.len - 1] = @intFromPtr(&finish);
        self.stack[self.stack.len - 7] = @intFromPtr(func);
        self.rsp = @intFromPtr(&self.stack) + STACK_CAPACITY - (8 * 8);
        self.completed = false;
    }
};

fn init(allocator: Allocator) !void {
    coros = ArrayList(Context).init(allocator);
    try coros.append(.{});
}

fn deinit() void {
    coros.deinit();
}

fn create(func: fn () void) !void {
    try coros.append(.{});
    coros.items[coros.items.len - 1].init(@constCast(&func));
}

fn next() usize {
    curr += 1;
    if (curr >= coros.items.len) {
        curr = 0;
    }
    return curr;
}

fn run() void {
    while (coroutine_count() > 0) {
        yeild();
    }
}

inline fn yeild() void {
    _ = asm volatile (
        \\ push %r12
        \\ push %r13
        \\ push %r14
        \\ push %r15
        \\ push %rbx
    );

    restore();
}

fn restore() void {
    var ctx: *Context = &coros.items[curr];
    ctx.rsp = asm volatile (""
        : [ret] "={rbp}" (-> usize),
    );

    const idx = next();
    ctx = &coros.items[idx];
    if (ctx.completed) {
        ctx = &coros.items[0];
    }

    asm volatile (
        \\ pop %rbp
        \\ pop %r10
        \\ pop %rbx
        \\ pop %r15
        \\ pop %r14
        \\ pop %r13
        \\ pop %r12
        \\ push %r10
        \\ ret
        :
        : [rsp] "{rsp}" (ctx.rsp),
    );
}

fn finish() void {
    var ctx: *Context = &coros.items[curr];
    ctx.completed = true;
    yeild();
}

fn coroutine_count() usize {
    var count: usize = 0;
    for (0..coros.items.len) |i| {
        if (!coros.items[i].completed) {
            count += 1;
        }
    }

    return count;
}

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

fn counter() void {
    for (0..10) |i| {
        const v: [2]u8 = .{ @as(u8, @truncate(i + 48)), '\n' };
        print(&v);
        yeild();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const allocator = gpa.allocator();

    try init(allocator);
    try create(counter);
    try create(counter);
    run();
    deinit();
}
