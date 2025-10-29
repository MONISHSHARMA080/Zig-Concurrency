const std = @import("std");
const assert = @import("./assert.zig").assertWithMessage;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub fn isTypeCompatible(comptime T1: type, comptime T2: type) bool {
    const info1 = @typeInfo(T1);
    const info2 = @typeInfo(T2);

    // If types are identical, they're compatible
    if (T1 == T2) return true;

    // If type categories don't match, they're not compatible
    if (@intFromEnum(info1) != @intFromEnum(info2)) return false;

    return switch (info1) {
        .@"struct" => |s1| blk: {
            const s2 = @typeInfo(T2).@"struct";
            if (s1.fields.len != s2.fields.len) break :blk false;
            if (s1.is_tuple != s2.is_tuple) break :blk false;

            for (s1.fields, s2.fields) |f1, f2| {
                if (!std.mem.eql(u8, f1.name, f2.name)) break :blk false;
                if (!isTypeCompatible(f1.type, f2.type)) break :blk false;
            }
            break :blk true;
        },
        .@"enum" => |e1| blk: {
            const e2 = @typeInfo(T2).@"enum";
            if (e1.fields.len != e2.fields.len) break :blk false;

            for (e1.fields, e2.fields) |f1, f2| {
                if (!std.mem.eql(u8, f1.name, f2.name)) break :blk false;
                if (f1.value != f2.value) break :blk false;
            }
            break :blk true;
        },
        .array => |a1| blk: {
            const a2 = @typeInfo(T2).array;
            if (a1.len != a2.len) break :blk false;
            break :blk isTypeCompatible(a1.child, a2.child);
        },
        .pointer => |p1| blk: {
            const p2 = @typeInfo(T2).pointer;
            if (p1.size != p2.size) break :blk false;
            if (p1.is_const != p2.is_const) break :blk false;
            if (p1.is_volatile != p2.is_volatile) break :blk false;
            break :blk isTypeCompatible(p1.child, p2.child);
        },
        .optional => |o1| blk: {
            const o2 = @typeInfo(T2).optional;
            break :blk isTypeCompatible(o1.child, o2.child);
        },
        else => T1 == T2,
    };
}
pub fn validateArgsMatchFunction(comptime Fn: anytype, comptime ArgsType: anytype, typeToSkipChecking: ?[]const type) bool {
    const fnTypeInfo = @typeInfo(@TypeOf(Fn));
    const fn_info = switch (fnTypeInfo) {
        .@"fn" => fnTypeInfo,
        .pointer => |ptr_info| blk: {
            const child_info = @typeInfo(ptr_info.child);
            if (child_info != .@"fn") return false;
            break :blk child_info;
        },
        else => return false,
    };

    if (fn_info != .@"fn") return false;

    const Fnparams = fn_info.@"fn".params;
    const args_info = @typeInfo(@TypeOf(ArgsType));

    if (args_info != .@"struct") return false;
    const fields = args_info.@"struct".fields;

    const arrayLen = if (typeToSkipChecking != null) typeToSkipChecking.?.len else 0;
    var haveWeCheckedThisType: [arrayLen]bool = [_]bool{false} ** arrayLen;

    if (typeToSkipChecking) |skipTypes| {
        assert(skipTypes.len > fields.len, std.fmt.comptimePrint(" there are more types to skip {d} than there are param for the fn('s args {d})  \n", .{ skipTypes.len, fields.len }));

        if (Fnparams.len - skipTypes.len != fields.len) return false;
    } else {
        if (Fnparams.len != fields.len) return false;
    }

    // var z = 0;
    inline for (fields, 0..) |field, i| {
        if (Fnparams[i].type) |param_type| {
            if (typeToSkipChecking) |skiptTheTypes| {
                const shouldWeSkip = shouldWeSkip: {
                    inline for (skiptTheTypes, 0..) |a, index| {
                        // if the type has already been checked then we will not check it again
                        if (isTypeCompatible(a, param_type)) {
                            // check in the array if the types are alrrady checked if it is then skip it
                            if (haveWeCheckedThisType[index] == true) {
                                break :shouldWeSkip false; // as this type is already checked
                            } else {
                                haveWeCheckedThisType[index] = true;
                                break :shouldWeSkip true;
                            }
                        }
                    }
                };
                if (shouldWeSkip == true) {
                    // continue;
                    @compileError(std.fmt.comptimePrint("got told to continue and the index is {} \n", .{skiptTheTypes}));
                }
            }
            if (!isTypeCompatible(field.type, param_type)) {
                // @compileError("Type mismatch at argument " ++ std.fmt.comptimePrint("{d}", .{i}));
                return false;
            }
        }
    }
    return true;
}

fn basicFn(a: u32, b: bool) void {
    _ = a;
    _ = b;
}
const ArgsBasic = struct { a: u32, b: bool };
fn arrayFn(arr: [4]i32) void {
    _ = arr;
}
const Inner = struct { x: u8 };
fn structFn(s: Inner) void {
    _ = s;
}
test "check if the validateArgsMatchFunction is working with various types" {
    comptime {
        // --- Primitives and Simple Types ---

        // 1. Basic Match
        try expect(validateArgsMatchFunction(basicFn, ArgsBasic));

        // 2. Basic Mismatch (different primitive type)
        const ArgsMismatch = struct { a: u16, b: bool };
        try expect(!validateArgsMatchFunction(basicFn, ArgsMismatch));

        // 3. Argument Count Mismatch (fewer args)
        const ArgsFewer = struct { a: u32 };
        try expect(!validateArgsMatchFunction(basicFn, ArgsFewer));

        // 4. Argument Count Mismatch (more args)
        const ArgsMore = struct { a: u32, b: bool, c: f32 };
        try expect(!validateArgsMatchFunction(basicFn, ArgsMore));

        // --- Complex Type Tests ---

        // Define Custom Types
        const SameInner = struct { x: u8 }; // Should be compatible
        const DiffInner = struct { y: u8 }; // Should be incompatible (field name mismatch)

        // const EnumType = enum { A, B };
        // const SameEnum = enum { A, B }; // Should be compatible
        // const DiffEnumVal = enum { A, B }; // Should be incompatible (value mismatch)
        // const DiffEnumName = enum { A, C }; // Should be incompatible (field name mismatch)

        // 5. Array Match
        const ArgsArray = struct { arr: [4]i32 };
        try expect(validateArgsMatchFunction(arrayFn, ArgsArray));

        // 6. Array Mismatch (length)
        const ArgsArrayLenMismatch = struct { arr: [3]i32 };
        try expect(!validateArgsMatchFunction(arrayFn, ArgsArrayLenMismatch));

        // 7. Array Mismatch (child type)
        const ArgsArrayChildMismatch = struct { arr: [4]u32 };
        try expect(!validateArgsMatchFunction(arrayFn, ArgsArrayChildMismatch));

        // 8. Struct Match
        const ArgsStructMatch = struct { s: SameInner };
        try expect(validateArgsMatchFunction(structFn, ArgsStructMatch));

        // 9. Struct Mismatch (field name)
        const ArgsStructMismatch = struct { s: DiffInner };
        try expect(!validateArgsMatchFunction(structFn, ArgsStructMismatch));

        // 10. Enum Match
        // fn enumFn(e: EnumType) void{};
        // const ArgsEnumMatch = struct { e: SameEnum };
        // try expect(validateArgsMatchFunction(enumFn, ArgsEnumMatch));
        //
        // // 11. Enum Mismatch (value)
        // const ArgsEnumValMismatch = struct { e: DiffEnumVal };
        // try expect(!validateArgsMatchFunction(enumFn, ArgsEnumValMismatch));
        //
        // // 12. Pointer Match (mutable)
        // fn ptrFn(p: *u32) void{};
        // const ArgsPtrMatch = struct { p: *u32 };
        // try expect(validateArgsMatchFunction(ptrFn, ArgsPtrMatch));
        //
        // // 13. Pointer Match (const)
        // fn constPtrFn(p: *const u32) void{};
        // const ArgsConstPtrMatch = struct { p: *const u32 };
        // try expect(validateArgsMatchFunction(constPtrFn, ArgsConstPtrMatch));
        //
        // // 14. Pointer Mismatch (constness: expected non-const, got const)
        // const ArgsConstForMut = struct { p: *const u32 };
        // try expect(!validateArgsMatchFunction(ptrFn, ArgsConstForMut)); // Ptr is *u32, Arg is *const u32
        //
        // // 15. Optional Match
        // fn optionalFn(o: ?f32) void{};
        // const ArgsOptionalMatch = struct { o: ?f32 };
        // try expect(validateArgsMatchFunction(optionalFn, ArgsOptionalMatch));
        //
        // // 16. Optional Mismatch (child type)
        // const ArgsOptionalMismatch = struct { o: ?u32 };
        // try expect(!validateArgsMatchFunction(optionalFn, ArgsOptionalMismatch));
        //
        // // 17. Not-a-Function Test
        // const NotFn = 1;
        // try expect(!validateArgsMatchFunction(NotFn, ArgsBasic));
    }
}
