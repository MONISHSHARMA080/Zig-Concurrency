const std = @import("std");

pub const Scheduler = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    schedulerInstanceOnThread: SchedulerInstanceOnThread,
    const FnToExecute = *const fn (userData: anyopaque) void;

    pub fn go(fnToExecute: FnToExecute) void {
        // the fn to execute
        fnToExecute();
        return;
    }
    pub fn yield() void {
        // now to yield back to the Scheduler make a coroutine in the loop that is undefined and start from there
    }
};

const SchedulerInstanceOnThread = struct {
    // this is the global Scheduler that will be there, now what the fn executing could have is the instance to the
    allocator: std.mem.Allocator,
    const FnToExecute = *const fn (userData: anyopaque) void;

    pub fn go(fnToExecute: FnToExecute) void {
        fnToExecute();
        return;
    }
    pub fn yield() void {
        // now to yield back to the Scheduler make a coroutine in the loop that is undefined and start from there
    }
};

//
//
// ok like this is how I will use it, Scheduler{} and then a fn work(scheduler:Scheduler){
//  a();
//  b(); // now I want to yield
//  scheduler.yield();
// }
// now the thing is that if the fn is running then I can't call the yield via scheduler, instead I need to expose the coroutine struct and then allow it to call yield;
// or we can use some fn magic(ziro_stack_swap) to do this too, prefer the 2nd option
//
//
