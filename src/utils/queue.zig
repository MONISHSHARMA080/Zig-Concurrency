const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ThreadSafeQueue(T: type, config: struct {
    /// size of the arrayList we do during each allocation
    listSize: u64 = 180,
}) type {
    return struct {
        allocator: std.mem.Allocator,
        nodeNumber: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        Queue: *node,
        ///  this is used for the poping as we will get the Fisrt element,
        ///  this one points to the element that you can get and not the empty reigon of memory, so after you get the element you have to either go to the next
        ///  node in queue or if it is not there then set it to null(and also return it too)
        ///  [queueEnd and queueStart can't point to same address , assert that ]
        queueStart: pointer,
        /// now the  thing is that when we append/add we need to do it to the curent ptr and move it to the next, i.e this one points to the empty region of the memory
        /// may be we should also make this the same as the one in the queueStart (i.e null in the start)
        ///  [queueEnd and queueStart can't point to same address , assert that ]
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
        const node = struct { list: []T, nextListPtr: ?*node, nodeId: u64 };
        const pointer = struct {
            nodePtr: *node,
            /// this one either contain the pointer to the item or (on it being null) the list is uninitialized i.e is allocated but none of the elements is used(garbage value)
            itemPtr: ?*T,
            /// should make this one null as the reader or writer could be on a node and not have used any index, or think
            itemIndex: u64,
            nodeIndex: u64,
            /// lock for reading or writing
            lock: std.Thread.Mutex,
        };

        fn getNewNode(self: *Self, allocator: Allocator) Allocator.Error!*node {
            const size = @sizeOf(node) + @sizeOf(T) * config.listSize;
            const mem = try allocator.alloc(u8, size);
            const Node: *node = @ptrCast(@alignCast(mem.ptr));
            const allocatedList: []T = @ptrCast(@alignCast(mem[@sizeOf(node)..]));
            Node.nextListPtr = null;
            Node.list = allocatedList;
            Node.nodeId = self.nodeNumber.fetchAdd(1, .monotonic);
            return Node;
        }

        /// appends to the list, this one will block (mutex)
        /// this fn gets the last value and also removes it from the list,
        /// **?T** cause if you try to get the element if no element is in the list then we can return null
        pub fn get(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();
            // now if this is null then we need to return null as there is nothing there, but if there is then return it and also increment the pointer to
            // next ?index
            switch (self.queueStart.itemPtr) {
                null => return null,
                else => {
                    // take the element to return and return it then increment the ptr to the next element
                    const elementToReturn = self.queueStart.itemPtr.?.*;

                    self.queueStart.nodePtr.list.len;
                    // now move the pointer to the next element to return or null
                    // we also need to check is the next element is uninitialized or not and we do that by seeing if the self.queueStart.itemPtr is ahead/infornt or
                    //
                    // not there, eg [0,1,2,3,4] all uninitialized, and we insert at 0, and after checking if the node.id is same we also set the self.queueStart to
                    // point to the first elements, and insert 1,2 and after that we increment the self.queueEnd.itemPtr and now if we get hit with get() we give the element at
                    // [0] and then we check if other elements are available in the array and if yes then set it there and if not then keep iterating till  we reach same number
                    // of node as in the self.queueEnd.node.id and if there is no left then we set it to null and when we get hit with the put call we will need to set it
                    // to other element again, how do we do that in a abstract way
                    //
                    //  ALT but better:
                    //       if this is complicated then we can keep the track of the array start and end via a storage in the node block like nodeID, woudl take slightly
                    //       more storage but will work, since the DS move in the right dir only, the remove the old node and keep it for tracking responsility is of get()
                    //       and putting it back is the responsility of put(),
                    //       now we do not need to keep waking/changing the self.queueStart index/ptr form the put fn
                    //
                    //
                    // ** hey we need to also tell the self.queueStart to be not null when we have our first element or in general when we have it to null , we do that in the put fn **
                    //  and also checking if we are at the end of the array so no outer bounds indexing
                },
            }
        }

        /// appends to the list, this one will block (mutex)
        /// **hey we need to also tell the self.queueStart to be not null when we have our first element , we do that in the here**
        pub fn put(self: *Self, value: T) !void {
            self.lock.lock();
            defer self.lock.unlock();
            // now since this is FIFO so we need to take the value add it in the queue
            _ = value;
        }

        pub fn init(allocator2: std.mem.Allocator) std.mem.Allocator.Error!Self {
            const Node = try getNewNode(Self);
            return Self{
                .lock = std.Thread.Mutex{},
                .Queue = Node,
                .allocator = allocator2,
                .queueStart = .{ .nodePtr = Node, .itemPtr = null, .itemIndex = 0 },
                .queueEnd = .{ .nodePtr = Node, .itemPtr = null, .itemIndex = 0 },
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
