const COROUTINE_CAPACITY = 10;
const STACK_CAPACITY = 1024;

const CoroutineState = enum {
    New,
    Ready,
    Running,
    Paused,
    Terminated,
};

const Coroutine = struct {
    rip: usize = 0,
    rbp: usize = 0,
    rsp: usize = 0,
    stack: [STACK_CAPACITY]u8 = undefined,
    state: CoroutineState = .New,
    cm: *CoroutineManager = undefined,

    const Self = @This();

    fn init(self: *Self, cm: *CoroutineManager, func: *fn (*Coroutine) void) void {
        self.rsp = @intFromPtr(&self.stack) + STACK_CAPACITY - 1;
        self.rip = @intFromPtr(func);
        self.cm = cm;
        @memset(&self.stack, 0);
        self.state = .Ready;
    }

    pub fn Start(self: *Self) void {
        if (self.state != .Ready) {
            return;
        }

        self.state = .Running;

        asm volatile (
            \\ push %rsi
            \\ jmp *%rax
            :
            : [rsp] "{rsp}" (self.rsp),
              [rbp] "{rbp}" (self.rbp),
              [arg1] "{rdi}" (@intFromPtr(self)),
              [arg2] "{rsi}" (@intFromPtr(&Coroutine.Finish)),
              [rip] "{rax}" (self.rip),
        );
    }

    pub fn Pause(self: *Self) void {
        if (self.state != .Running) {
            return;
        }

        self.state = .Paused;

        // Why arbitary index into rbp?
        // rbp = callee' rsp with previous rbp pushed
        // simple saw the changes to stack
        // using binary ninja and calculated
        // the offsets.
        self.rsp = asm volatile (""
            : [ret] "={rbp}" (-> usize),
        ) - 16;

        self.rbp = asm volatile ("movq (%rbp), %rax"
            : [ret] "={rax}" (-> usize),
        );

        self.rip = asm volatile ("movq 8(%rbp), %rax"
            : [ret] "={rax}" (-> usize),
        );

        self.cm.yeild();
    }

    pub fn Resume(self: *Self) void {
        if (self.state != .Paused) {
            return;
        }

        self.state = .Running;

        asm volatile ("jmp *%rax"
            :
            : [rsp] "{rsp}" (self.rsp),
              [rbp] "{rbp}" (self.rbp),
              [arg1] "{rdi}" (@intFromPtr(self)),
              [rip] "{rax}" (self.rip),
        );
    }

    pub fn Finish(self: *Self) void {
        self.state = .Terminated;
        print(@constCast("Finished!\n"));
    }
};

const CoroutineManager = struct {
    coros: []Coroutine,
    len: usize,
    curr: usize,

    const Self = @This();

    fn create(self: *Self, func: fn (*Coroutine) void) void {
        if (self.len >= 10) {
            @panic("OVERFLOW");
        }

        const idx = self.len;
        self.len += 1;

        self.coros[idx].init(self, @constCast(&func));
    }

    fn next(self: *Self) usize {
        self.curr += 1;
        if (self.curr >= self.len) {
            self.curr = 0;
        }
        return self.curr;
    }

    fn run(self: *Self) void {
        const idx = self.curr;
        switch (self.coros[idx].state) {
            .Ready => {
                self.coros[idx].Start();
            },
            .Paused => {
                self.coros[idx].Resume();
            },
            else => {},
        }
    }

    fn yeild(self: *Self) void {
        print(@constCast("yeild\n"));
        const idx = self.next();
        switch (self.coros[idx].state) {
            .Ready => {
                self.coros[idx].Start();
            },
            .Paused => {
                self.coros[idx].Resume();
            },
            else => {},
        }
        self.coros[idx].Resume();
    }
};

fn print(arg: []u8) void {
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
        print(@constCast(&v));
        coro.Pause();
    }
}

pub fn main() void {
    var coros: [10]Coroutine = .{.{}} ** 10;
    var manager = CoroutineManager{
        .coros = &coros,
        .len = 0,
        .curr = 0,
    };

    manager.create(counter);
    manager.create(counter);
    manager.run();
}
