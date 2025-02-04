const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const STACK_CAPACITY = 1024 * 4;

var alloc: Allocator = undefined;
var coros: ArrayList(*Context) = undefined;
var garbage: ArrayList(*Context) = undefined;
var curr: usize = 0;

const Context = struct {
    rsp: usize = 0,
    stack: []align(16) usize = undefined,

    const Self = @This();

    fn init(self: *Self, func: *fn () void) void {
        self.stack = alloc.alignedAlloc(usize, 16, STACK_CAPACITY / 8) catch unreachable;
        @memset(self.stack, 0);

        self.stack[self.stack.len - 1] = @intFromPtr(&finish);
        self.stack[self.stack.len - 7] = @intFromPtr(func);
        self.rsp = @intFromPtr(self.stack.ptr) + STACK_CAPACITY - (8 * 8);
    }
};

pub fn init(allocator: Allocator) void {
    alloc = allocator;
    coros = ArrayList(*Context).init(alloc);
    garbage = ArrayList(*Context).initCapacity(alloc, 10) catch unreachable;

    const ctx = alloc.create(Context) catch unreachable;
    coros.append(ctx) catch unreachable;
}

pub fn deinit() void {
    const main_ctx = coros.pop();
    alloc.destroy(main_ctx);
    coros.deinit();
    garbage.deinit();
}

pub fn create(func: fn () void) void {
    const ctx = alloc.create(Context) catch unreachable;
    ctx.init(@constCast(&func));
    coros.append(ctx) catch unreachable;
}

fn next() void {
    curr += 1;
    curr %= coros.items.len;
}

pub fn run() void {
    while (coros.items.len > 1) {
        yeild();
        while (garbage.items.len > 0) {
            const ctx = garbage.pop();
            alloc.free(ctx.stack);
            alloc.destroy(ctx);
        }
    }
}

pub inline fn yeild() void {
    asm volatile (
        \\ push %r12
        \\ push %r13
        \\ push %r14
        \\ push %r15
        \\ push %rbx
    );

    yeild_intern(false);
}

fn yeild_intern(only_restore: bool) void {
    if (!only_restore) {
        var ctx: *Context = coros.items[curr];
        ctx.rsp = asm volatile (""
            : [ret] "={rbp}" (-> usize),
        );

        next();
    }

    const ctx = coros.items[curr];

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
    const ctx = coros.orderedRemove(curr);
    garbage.append(ctx) catch unreachable;
    curr %= coros.items.len;
    yeild_intern(true);
}
