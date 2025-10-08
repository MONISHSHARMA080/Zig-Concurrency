const std = @import("std");
const builtin = @import("builtin");
const errors = @import("./coroutine.zig").Error;
const assert = @import("../utils/assert.zig");

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

pub const CoroutineState = enum { NotRunning, Waiting, Finished, Running, Completed, WaitingForChannel };

pub const CoroutineBase = struct {
    stack_pointer: [*]u8,

    coroutineState: CoroutineState = .NotRunning,
    targetCoroutineToYieldTo: ?*CoroutineBase = null,

    user_func_ptr: ?*const anyopaque = null,
    user_args_ptr: ?*anyopaque = null,
    // caller_fn: ?*const fn (*const anyopaque, ?*anyopaque) void = null,
    caller_fn: ?*const fn (*anyopaque) void = null,
    args_storage: [256]u8 align(8) = undefined,

    // var nameOfTheFnToExecute: *const [:0]u8 = "";

    const Func = *const fn (
        from: *CoroutineBase,
        self: *CoroutineBase,
    ) callconv(.c) noreturn;

    /// note the coroutines are cold, you need to run it
    pub fn init(func: anytype, stack: []align(stackAlignment) u8) errors!CoroutineBase {
        if (@sizeOf(usize) != 8) @compileError("usize expected to take 8 bytes");
        if (@sizeOf(*Func) != 8) @compileError("function pointer expected to take 8 bytes");
        const register_bytes = archInfo.num_registers * 8;
        if (register_bytes > stack.len) return errors.StackTooSmall;
        const register_space = stack[stack.len - register_bytes ..];
        const jump_ptr: *Func = @ptrCast(@alignCast(&register_space[archInfo.jump_idx * 8]));
        jump_ptr.* = func;
        return .{
            .stack_pointer = register_space.ptr,
            .targetCoroutineToYieldTo = null,
        };
    }

    // This is the actual wrapper that gets put on the stack
    fn coroutineWrapper(from: *CoroutineBase, self: *CoroutineBase) callconv(.c) noreturn {
        // Mark as running
        self.coroutineState = .Running;
        if (self.caller_fn) |caller| {
            caller(&self.args_storage);
        }

        self.coroutineState = .Finished;
        // Yield back to the caller (scheduler/parent coroutine)
        // Never returns from here
        ziro_stack_swap(self, from);
        unreachable;
    }

    pub fn initWithFunc(comptime user_func: anytype, args: anytype, stack: []align(stackAlignment) u8) errors!CoroutineBase {
        if (@sizeOf(usize) != 8) @compileError("usize expected to take 8 bytes");
        if (@sizeOf(*Func) != 8) @compileError("function pointer expected to take 8 bytes");

        // c       nameOfTheFnToExecute = @typeName(user_func);

        const ArgsType = @TypeOf(args);
        if (@sizeOf(ArgsType) > 256) {
            @compileError("Args too large, increase args_storage size");
        }
        //                          To Do
        // =======================================================================
        //   now get your comptime interface lib and check to see if
        //   user_func's param's type match the one in the args/params
        // =======================================================================
        // 2) now how does the fn that was called gets to yield,
        //    I think the initWithFunc is better but we need to check the arg type
        //    and the we need to asure that it has the param of CoroutineBase to
        //    yield and the fn where we should yield to should be in the coroutine
        //    or in the fn too
        // =======================================================================

        const register_bytes = archInfo.num_registers * 8;
        if (register_bytes > stack.len) return errors.StackTooSmall;

        const register_space = stack[stack.len - register_bytes ..];

        // Put the WRAPPER function on the stack, not the user function
        const jump_ptr: *Func = @ptrCast(@alignCast(&register_space[archInfo.jump_idx * 8]));
        jump_ptr.* = coroutineWrapper;
        const Caller = struct {
            fn call(args_ptr: *anyopaque) void {
                const typed_args = @as(*ArgsType, @ptrCast(@alignCast(args_ptr)));
                _ = @call(.auto, user_func, typed_args.*);
            }
        };

        var result = CoroutineBase{
            .stack_pointer = register_space.ptr,
            .caller_fn = Caller.call,
        };
        // Copy args into the struct's storage
        const args_bytes = std.mem.asBytes(&args);
        @memcpy(result.args_storage[0..args_bytes.len], args_bytes);
        return result;
    }

    pub inline fn resumeFrom(self: *CoroutineBase, from: *CoroutineBase) void {
        return ziro_stack_swap(from, self);
    }
    pub fn yield(self: *@This(), targetCoroutineToYieldTo: *CoroutineBase) void {
        // assert.assertWithMessage(self.targetCoroutineToYieldTo != null, "the fn/coroutine to yield is not there(null)");
        ziro_stack_swap(self, targetCoroutineToYieldTo);
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
// you know instead of making a seperate yield and resume we can, just keep it and in the scheduler we can
// call other if it is not there then go to main
//
//

////
