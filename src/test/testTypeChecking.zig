// const std = @import("std");
// const expect = std.testing.expect;
// const expectEqual = std.testing.expectEqual;
//
// const validateArgsMatchFunction = @import("../utils/typeChecking.zig").validateArgsMatchFunction;
//
// fn basicFn(a: u32, b: bool) void {
//     _ = a;
//     _ = b;
// }
// const ArgsBasic = struct { a: u32, b: bool };
// fn arrayFn(arr: [4]i32) void {
//     _ = arr;
// }
// const Inner = struct { x: u8 };
// fn structFn(s: Inner) void {
//     _ = s;
// }
// test "check if the validateArgsMatchFunction is working with various types" {
//     comptime {
//         // --- Primitives and Simple Types ---
//
//         // 1. Basic Match
//         try expect(validateArgsMatchFunction(basicFn, ArgsBasic));
//
//         // 2. Basic Mismatch (different primitive type)
//         const ArgsMismatch = struct { a: u16, b: bool };
//         try expect(!validateArgsMatchFunction(basicFn, ArgsMismatch));
//
//         // 3. Argument Count Mismatch (fewer args)
//         const ArgsFewer = struct { a: u32 };
//         try expect(!validateArgsMatchFunction(basicFn, ArgsFewer));
//
//         // 4. Argument Count Mismatch (more args)
//         const ArgsMore = struct { a: u32, b: bool, c: f32 };
//         try expect(!validateArgsMatchFunction(basicFn, ArgsMore));
//
//         // --- Complex Type Tests ---
//
//         // Define Custom Types
//         const SameInner = struct { x: u8 }; // Should be compatible
//         const DiffInner = struct { y: u8 }; // Should be incompatible (field name mismatch)
//
//         // const EnumType = enum { A, B };
//         // const SameEnum = enum { A, B }; // Should be compatible
//         // const DiffEnumVal = enum { A, B }; // Should be incompatible (value mismatch)
//         // const DiffEnumName = enum { A, C }; // Should be incompatible (field name mismatch)
//
//         // 5. Array Match
//         const ArgsArray = struct { arr: [4]i32 };
//         try expect(validateArgsMatchFunction(arrayFn, ArgsArray));
//
//         // 6. Array Mismatch (length)
//         const ArgsArrayLenMismatch = struct { arr: [3]i32 };
//         try expect(!validateArgsMatchFunction(arrayFn, ArgsArrayLenMismatch));
//
//         // 7. Array Mismatch (child type)
//         const ArgsArrayChildMismatch = struct { arr: [4]u32 };
//         try expect(!validateArgsMatchFunction(arrayFn, ArgsArrayChildMismatch));
//
//         // 8. Struct Match
//         const ArgsStructMatch = struct { s: SameInner };
//         try expect(validateArgsMatchFunction(structFn, ArgsStructMatch));
//
//         // 9. Struct Mismatch (field name)
//         const ArgsStructMismatch = struct { s: DiffInner };
//         try expect(!validateArgsMatchFunction(structFn, ArgsStructMismatch));
//
//         // 10. Enum Match
//         // fn enumFn(e: EnumType) void{};
//         // const ArgsEnumMatch = struct { e: SameEnum };
//         // try expect(validateArgsMatchFunction(enumFn, ArgsEnumMatch));
//         //
//         // // 11. Enum Mismatch (value)
//         // const ArgsEnumValMismatch = struct { e: DiffEnumVal };
//         // try expect(!validateArgsMatchFunction(enumFn, ArgsEnumValMismatch));
//         //
//         // // 12. Pointer Match (mutable)
//         // fn ptrFn(p: *u32) void{};
//         // const ArgsPtrMatch = struct { p: *u32 };
//         // try expect(validateArgsMatchFunction(ptrFn, ArgsPtrMatch));
//         //
//         // // 13. Pointer Match (const)
//         // fn constPtrFn(p: *const u32) void{};
//         // const ArgsConstPtrMatch = struct { p: *const u32 };
//         // try expect(validateArgsMatchFunction(constPtrFn, ArgsConstPtrMatch));
//         //
//         // // 14. Pointer Mismatch (constness: expected non-const, got const)
//         // const ArgsConstForMut = struct { p: *const u32 };
//         // try expect(!validateArgsMatchFunction(ptrFn, ArgsConstForMut)); // Ptr is *u32, Arg is *const u32
//         //
//         // // 15. Optional Match
//         // fn optionalFn(o: ?f32) void{};
//         // const ArgsOptionalMatch = struct { o: ?f32 };
//         // try expect(validateArgsMatchFunction(optionalFn, ArgsOptionalMatch));
//         //
//         // // 16. Optional Mismatch (child type)
//         // const ArgsOptionalMismatch = struct { o: ?u32 };
//         // try expect(!validateArgsMatchFunction(optionalFn, ArgsOptionalMismatch));
//         //
//         // // 17. Not-a-Function Test
//         // const NotFn = 1;
//         // try expect(!validateArgsMatchFunction(NotFn, ArgsBasic));
//     }
// }
