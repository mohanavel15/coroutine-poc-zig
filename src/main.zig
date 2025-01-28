const COROUTINE_CAPACITY = 10;
const STACK_CAPACITY = 1024;

const Coroutine = struct {
    rsp: usize = 0,
    stack: [STACK_CAPACITY / 8]usize = undefined,
    cm: *CoroutineManager = undefined,

    const Self = @This();

    fn Init(self: *Self, cm: *CoroutineManager, func: *fn (*Coroutine) void) void {
        @memset(&self.stack, 0);

        self.stack[self.stack.len - 1] = @intFromPtr(&Coroutine.Finish);
        self.stack[self.stack.len - 2] = @intFromPtr(func);
        self.rsp = @intFromPtr(&self.stack) + STACK_CAPACITY - (8 * 3);

        self.cm = cm;
    }

    pub fn Pause(self: *Self) void {
        self.rsp = asm volatile (""
            : [ret] "={rbp}" (-> usize),
        );

        self.cm.yeild();
    }

    pub fn Resume(self: *Self) void {
        asm volatile (
            \\ popq %rbp
            \\ ret
            :
            : [rsp] "{rsp}" (self.rsp),
              [arg1] "{rdi}" (@intFromPtr(self)),
            : "rbp", "rsp", "memory"
        );
    }

    pub fn Finish(self: *Self) void {
        print("Finish #1.0\n");

        for (self.cm.curr..self.cm.len - 1) |idx| {
            const ctx = self.cm.coros[idx + 1];
            self.cm.coros[idx] = ctx;
        }
        self.cm.len -= 1;

        print("Finish #1.1\n");
        _ = self.cm.yeild();
    }
};

const CoroutineManager = struct {
    coros: []Coroutine,
    len: usize,
    curr: usize,

    const Self = @This();

    fn Init(self: *Self) void {
        self.len += 1;

        var ctx: *Coroutine = &self.coros[0];
        ctx.cm = self;
    }

    fn create(self: *Self, func: fn (*Coroutine) void) void {
        if (self.len >= 10) {
            @panic("OVERFLOW");
        }

        const idx = self.len;
        self.len += 1;

        self.coros[idx].Init(self, @constCast(&func));
    }

    fn next(self: *Self) usize {
        self.curr += 1;
        if (self.curr >= self.len) {
            self.curr = 0;
        }
        return self.curr;
    }

    fn run(self: *Self) void {
        while (self.len > 1) {
            self.coros[0].Pause();
        }
    }

    fn yeild(self: *Self) void {
        const idx = self.next();
        var ctx: *Coroutine = &self.coros[idx];
        ctx.Resume();
    }
};

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

fn counter(coro: *Coroutine) void {
    for (0..10) |i| {
        const v: [2]u8 = .{ @as(u8, @truncate(i + 48)), '\n' };
        print(&v);
        _ = coro.Pause();
    }
}

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
