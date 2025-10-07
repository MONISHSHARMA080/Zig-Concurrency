const std = @import("std");
const builtin = @import("builtin");
const errors = @import("./coroutine.zig").Error;

const ArchInfo = struct {
    num_registers: usize,
    jump_idx: usize,
    assembly: []const u8,
};

const archInfo: ArchInfo = switch (builtin.cpu.arch) {
    .aarch64 => .{
        .num_registers = 20,
        .jump_idx = 19,
        .assembly = @embedFile("../asm/aarch64.s"),
    },
    .x86_64 => switch (builtin.os.tag) {
        .windows => .{
            .num_registers = 32,
            .jump_idx = 30,
            .assembly = @embedFile("../asm/x86_64_windows.s"),
        },
        else => .{
            .num_registers = 8,
            .jump_idx = 6,
            .assembly = @embedFile("../asm/x86_64.s"),
        },
    },
    .riscv64 => .{
        .num_registers = 25,
        .jump_idx = 24,
        .assembly = @embedFile("../asm/riscv64.s"),
    },
    else => {
        @compileError("Unsupported cpu architecture");
    },
};

comptime {
    asm (archInfo.assembly);
}

extern fn ziro_stack_swap(current: *anyopaque, target: *anyopaque) void;

pub const stackAlignment = 16;

pub const CoroutineState = enum { Waiting, Finished, Running, Completed, WaitingForChannel };

pub const CoroutineBase = packed struct {
    stack_pointer: [*]u8,
    const Func = *const fn (
        from: *CoroutineBase,
        self: *CoroutineBase,
    ) callconv(.c) noreturn;

    pub const coroutineState: CoroutineState = .Running;

    pub fn init(func: Func, stack: []align(stackAlignment) u8) errors!CoroutineBase {
        if (@sizeOf(usize) != 8) @compileError("usize expected to take 8 bytes");
        if (@sizeOf(*Func) != 8) @compileError("function pointer expected to take 8 bytes");
        const register_bytes = archInfo.num_registers * 8;
        if (register_bytes > stack.len) return errors.StackTooSmall;
        const register_space = stack[stack.len - register_bytes ..];
        const jump_ptr: *Func = @ptrCast(@alignCast(&register_space[archInfo.jump_idx * 8]));
        jump_ptr.* = func;
        return .{ .stack_pointer = register_space.ptr };
    }
    pub inline fn resumeFrom(self: *CoroutineBase, from: *CoroutineBase) void {
        return ziro_stack_swap(from, self);
    }
    pub fn yield(self: *@This(), target: *CoroutineBase) void {
        ziro_stack_swap(self, target);
        // When this returns, someone has resumed us
        // Execution continues from here with all registers restored
    }
};

//
// this lib will provide(not this , I am talking about the lib as a whole), 2 fn go(Fn) and goRunCoro(Fn)- the go is like
// the golang one while the goRunCoro will take in a fn and that fn should take in the argument Corotine type as I want to allow
// the fn to pasue or resume later
//
// now the thing is that we have too keep track of the state so as we do not want to call the resume on it
// 1) we can make the fn explicitly handle the state management
// 2) we can take in the fn and then put it in another fn and when the fn(original) is over then we can in the end put the
//  state to be done (enum)
//
//
//  tuesday:7th Oct
//  -- coroutine impl
//  * implement coroBase : asm for both fn and also
//  * the the yield mechanism , how to mark it's state to be ended when the
//
//  --- next is the scheduler --
//
//
//

////
