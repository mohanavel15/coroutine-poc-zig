const COROUTINE_CAPACITY = 10;
const STACK_CAPACITY = 1024;

var coros: [10]Context = .{.{}} ** 10;
var curr: usize = 0;
var len: usize = 1;

const Context = struct {
    rsp: usize = 0,
    stack: [STACK_CAPACITY / 8]usize = undefined,
    completed: bool = true,

    const Self = @This();

    fn init(self: *Self, func: *fn () void) void {
        @memset(&self.stack, 0);

        self.stack[self.stack.len - 1] = @intFromPtr(&finish);
        self.stack[self.stack.len - 2] = @intFromPtr(func);
        self.rsp = @intFromPtr(&self.stack) + STACK_CAPACITY - (8 * 3);
        self.completed = false;
    }
};

fn create(func: fn () void) void {
    const idx = len;
    len += 1;

    coros[idx].init(@constCast(&func));
}

fn next() usize {
    curr += 1;
    if (curr >= len) {
        curr = 0;
    }
    return curr;
}

fn run() void {
    while (coroutine_count() > 0) {
        yeild();
    }
}

fn yeild() void {
    var ctx: *Context = &coros[curr];

    ctx.rsp = asm volatile (""
        : [ret] "={rbp}" (-> usize),
    );

    const idx = next();

    ctx = &coros[idx];
    if (ctx.completed) {
        ctx = &coros[0];
    }

    asm volatile (
        \\ pop %rbp
        \\ ret
        :
        : [rsp] "{rsp}" (ctx.rsp),
        : "rbp", "rsp", "memory"
    );
}

fn finish() void {
    var ctx: *Context = &coros[curr];
    ctx.completed = true;
    yeild();
}

fn coroutine_count() usize {
    var count: usize = 0;
    for (0..len) |i| {
        if (!coros[i].completed) {
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

pub fn main() void {
    create(counter);
    create(counter);
    run();
}
