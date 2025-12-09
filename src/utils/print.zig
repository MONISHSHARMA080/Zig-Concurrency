const std = @import("std");
const lockStderrWriter = std.debug.lockStderrWriter;
const unlockStderrWriter = std.debug.unlockStderrWriter;

// pub fn KeepPrinting() type {
//     return struct {
//         buff: [64 * 32]u8 = undefined,
//         bw: *std.Io.Writer,
//         const Self = @This();
//         pub fn init() Self {
//             const a: [64 * 32]u8 = undefined;
//             return KeepPrinting{
//                 .buff = undefined,
//                 .bw = lockStderrWriter(&a),
//             };
//         }
//         pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
//             const buffer: [64 * 32]u8 = undefined;
//             self.bw = lockStderrWriter(&self.bw);
//             nosuspend self.bw.print(fmt, args) catch return;
//             _ = buffer;
//         }
//         pub fn destroy(self: *Self) void {
//             _ = self;
//             defer unlockStderrWriter();
//         }
//     };
// }
pub fn KeepPrinting() type {
    return struct {
        buff: [64 * 32]u8,
        writer: *std.io.Writer,

        const Self = @This();

        pub fn init() Self {
            var instance = Self{
                .buff = undefined,
                .writer = undefined,
            };
            instance.writer = std.debug.lockStderrWriter(&instance.buff);
            return instance;
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            nosuspend self.writer.print(fmt, args) catch return;
        }

        pub fn destroy(self: *Self) void {
            _ = self;
            std.debug.unlockStderrWriter();
        }
    };
}

// pub const KeepPrinting = struct {
//     buff: [64 * 32]u8 = undefined,
//     bw: *std.Io.Writer,
//     pub fn init() KeepPrinting {
//         const a: [64 * 32]u8 = undefined;
//         return KeepPrinting{
//             .buff = undefined,
//             .bw = lockStderrWriter(&a),
//         };
//     }
//     pub fn print(self: *KeepPrinting, comptime fmt: []const u8, args: anytype) void {
//         const buffer: [64 * 32]u8 = undefined;
//         self.bw = lockStderrWriter(&self.bw);
//         // const bw = std.debug.lockStderrWriter(&buffer);
//         // defer unlockStderrWriter();
//         nosuspend self.bw.print(fmt, args) catch return;
//         _ = buffer;
//     }
//     pub fn destroy() void {
//         defer unlockStderrWriter();
//     }
// };
//

