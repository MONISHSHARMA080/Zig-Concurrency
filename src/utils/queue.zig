const std = @import("std");

pub fn ThreadSafeQueue(T: type, config: struct {
    /// size of the arrayList we do during each allocation
    listSize: u64 = 180,
}) type {
    return struct {
        allocator: std.mem.Allocator,
        lock: std.Thread.Mutex,
        Queue: *node,
        /// NOOO- this is used for the poping as we will get the Fisrt element
        queueStart: pointer,
        /// now the  thing is that when we append/add we need to do it to the curent ptr and move it to the next, i.e this one points to the empty region of the memory
        queueEnd: pointer,

        // ok tell me how am I suppose to impl FIFO in the array type manner like if I have a array of 10 elements like [ | | | | | |....] and if i inserted first 5
        // then I have 5 slots used, now if I remove the one it will be the first one  now I have slots 2..5 used and the first and the 6..10 empty now if I get the
        // insert request then what am I suppose to do do I insert it to the first one or the 6th and if it is 6th for the FIFO then there is a empty space now what
        // we are wasting space??
        //
        // ans: so heere is what we will do we will keep doing it but when by popping we get the head out of this then we instead of deleating the list we will just store it
        // like a Linked list and also when we need extra list just add it there, ptr swapping no alloc calls

        freedList: ?node = null,

        const Self = @This();
        const node = struct { list: []T, nextListPtr: ?*node };
        const pointer = struct {
            nodePtr: *node,
            /// this one either contain the pointer to the item or (on it being null) the list is uninitialized i.e is allocated but none of the elements is used(garbage value)
            itemPtr: ?*T,
        };

        /// appends to the list, this one will block (mutex)
        /// this fn gets the last value and also removes it from the list,
        /// **?T** cause if you try to get the element if no element is in the list then we can return null
        pub fn get(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();
            // get the value from the queue start and
            // we need to make sure that we do not get the empty element as it will have the garbage data
            // sol one we can make the pointer.itemPtr null to make sure that we are pointing towards a element and not the empty data

            // now if this is null then we need to return null as there is nothing there, but if there is then return it and also increment the pointer to
            // next ?index
            switch (self.queueStart.itemPtr) {
                null => {
                    return null;
                },
                else => {
                    // take the element to return and return it then increment the ptr to the next element
                },
            }
        }

        /// appends to the list, this one will block (mutex)
        pub fn put(self: *Self, value: T) !void {
            self.lock.lock();
            defer self.lock.unlock();
            // now since this is FIFO so we need to take the value add it in the queue
            _ = value;
        }

        pub fn init(allocator2: std.mem.Allocator) std.mem.Allocator.Error!Self {
            const size = @sizeOf(node) + @sizeOf(T) * config.listSize;
            const mem = try allocator2.alloc(u8, size);
            const Node: *node = @ptrCast(@alignCast(mem.ptr));
            const allocatedList: []T = @ptrCast(@alignCast(mem[@sizeOf(node)..]));
            Node.nextListPtr = null;
            Node.list = allocatedList;

            return Self{
                .lock = std.Thread.Mutex{},
                .Queue = Node,
                .allocator = allocator2,
                .queueStart = .{ .nodePtr = Node, .itemPtr = &Node.list[0] },
                .queueEnd = .{ .nodePtr = Node, .itemPtr = &Node.list[0] },
                .freedList = null,
            };
        }

        pub fn appendNonBlocking(self: *Self, value: T, options: struct { tryForTimes: u16 = 5 }) !void {
            // self.Queue.append()
            // now since this is FIFO so we need to take the
            _ = options;
            _ = self;
            _ = value;
        }
    };
}
