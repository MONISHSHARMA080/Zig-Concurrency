const std = @import("std");
const Allocator = std.mem.Allocator;
const allocOutOfMemError = Allocator.Error;
const assert = std.debug.assert;
const asserts = @import("./assert.zig");
const assertWithMessage = asserts.assertWithMessage;
const cmpPrint = std.fmt.comptimePrint;

/// FIFO queue
pub fn ThreadSafeQueue(T: type) type {
    return struct {
        listSize: u64,
        allocator: std.mem.Allocator,
        nodeNumber: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        ///  this is used for the poping as we will get the Fisrt element,
        ///  this one points to the element that you can get and not the empty reigon of memory, so after you get the element you have to either go to the next
        ///  node in queue or if it is not there then set it to null(and also return it too)
        ///  [queueEnd and queueStart can't point to same address , assert that ]
        queueStart: nodePointer,
        /// now the  thing is that when we append/add we need to do it to the curent ptr and move it to the next, i.e this one points to the empty region of the memory
        /// may be we should also make this the same as the one in the queueStart (i.e null in the start)
        ///  [queueEnd and queueStart can't point to same address , assert that ]
        queueEnd: nodePointer,

        // ok tell me how am I suppose to impl FIFO in the array type manner like if I have a array of 10 elements like [ | | | | | |....] and if i inserted first 5
        // then I have 5 slots used, now if I remove the one it will be the first one  now I have slots 2..5 used and the first and the 6..10 empty now if I get the
        // insert request then what am I suppose to do do I insert it to the first one or the 6th and if it is 6th for the FIFO then there is a empty space now what
        // we are wasting space??
        //
        // ans: so heere is what we will do we will keep doing it but when by popping we get the head out of this then we instead of deleating the list we will just store it
        // like a Linked list and also when we need extra list just add it there, ptr swapping no alloc calls

        // we also need a lock on this or not, we can access the put via the list, but when there is a delete operation going on then the delete one has already
        // accquired the lock so no need here
        freedList: ?*Node = null,
        // allocationsFailedForFutureNode: bool = false,
        /// this one tells us that in out last allocation we were returned full by the allocator and can't do one more allocation
        cantAllocateAfterThis: bool = false,

        const Self = @This();
        const Node = struct {
            list: []T,
            nextListPtr: ?*Node,
            nodeId: u64,
            /// lock for reading or writing
            lock: std.Thread.Mutex,
            /// this is for the pop() , seeing if the node is empty or not
            indexFilled: u64 = 0,
        };
        const nodePointer = struct {
            nodePtr: *Node,
            // this one either contain the pointer to the item or (on it being null) the list is uninitialized i.e is allocated but none of the elements is used(garbage value)
            // itemPtr: ?*T,

            /// [appending]:where to append, move it for next item when you have added a value for the next time use
            /// [popping]:which index to remove, move it forward when you have removed a value for the next time use
            itemIndex: u64 = 0,
            // nodeIndex: u64,
        };

        pub fn destroy(self: *Self) void {
            var currentNode: ?Node = self.queueStart.nodePtr;
            while (currentNode) |node| {
                currentNode = node.nextListPtr;
                const size = @sizeOf(Node) + @sizeOf(T) * self.listSize;
                const mem: []u8 = @as([*]u8, @ptrCast(node))[0..size];
                self.allocator.free(mem);
            }
            currentNode = self.freedList;
            while (currentNode) |node| {
                currentNode = node.nextListPtr;
                const size = @sizeOf(Node) + @sizeOf(T) * self.listSize;
                const mem: []u8 = @as([*]u8, @ptrCast(node))[0..size];
                self.allocator.free(mem);
            }
        }

        pub fn putNTimes(self: *Self, elementsToPut: []T) allocOutOfMemError!void {
            // take in a array and use put() to add n time
            for (elementsToPut) |value| {
                try self.put(value);
            }
            return;
        }

        pub fn popNTimesOrLess(self: *Self, comptime option: struct { numberOfCoroToGet: u32 = 10, arrayToReturn: ?[]T = null }) ?[]T {
            switch (option.arrayToReturn) {
                null => {
                    var arrayToReturn: [option.numberOfCoroToGet]T = undefined;
                    for (0..option.numberOfCoroToGet) |i| {
                        if (self.pop()) |val| {
                            assert(i < arrayToReturn.len);
                            arrayToReturn[i] = val;
                        } else {
                            if (i == 0) return null;
                            return arrayToReturn[0..i];
                        }
                    }
                    return arrayToReturn;
                },
                else => {
                    for (0..option.numberOfCoroToGet) |i| {
                        if (self.pop()) |val| {
                            assert(i < option.arrayToReturn.?.len);
                            option.arrayToReturn[i] = val;
                        } else {
                            if (i == 0) return null;
                            return option.arrayToReturn[0..i];
                        }
                    }
                    return option.arrayToReturn.?;
                },
            }
        }

        /// *NOTE* *:* this keeps the nodeId/nodeNumber same and perform no operations on it
        fn allocateNewNode(param: union(enum) { self: *Self, new: struct { allocator: Allocator, listSize: u64 } }) Allocator.Error!*Node {
            const allocator = switch (param) {
                .new => |v| v.allocator,
                .self => |b| b.allocator,
            };
            const listSize = switch (param) {
                .new => |v| v.listSize,
                .self => |b| b.listSize,
            };
            const size = @sizeOf(Node) + @sizeOf(T) * listSize;

            const mem = try allocator.alloc(u8, size);
            const node: *Node = @ptrCast(@alignCast(mem.ptr));
            const allocatedList: []T = @ptrCast(@alignCast(mem[@sizeOf(Node)..]));
            node.nextListPtr = null;
            node.list = allocatedList;
            node.*.lock = std.Thread.Mutex{};
            node.indexFilled = 0;
            return node;
        }

        /// appends to the list, this one will block (mutex)
        ///  (FIFO) will return the **?node** and also remove the value
        /// **?T** cause if you try to get the element if no element is in the list then we can return null
        pub fn pop(self: *Self) ?T {
            const nodeToOprUpon = self.queueStart.nodePtr;
            nodeToOprUpon.lock.lock();
            defer nodeToOprUpon.lock.unlock();
            // now if this is null then we need to return null as there is nothing there, but if there is then return it and also increment the pointer to
            // next ?index
            switch (self.queueStart.nodePtr.indexFilled) {
                0 => return null,
                else => {
                    // take the element to return and return it then increment the ptr to the next element
                    // const elementToReturn = self.queueStart.itemPtr.?.*;
                    asserts.assertWithMessageFmtRuntime(self.queueStart.itemIndex <= self.listSize, "the itemIndex to remove the element {d} from node {d} is not <= size of the list {d} ", .{ self.queueStart.itemIndex, self.queueStart.nodePtr.nodeId, self.listSize });
                    //TODO: you can't do that first check if we can remove the eleements or not , remove thsi
                    // const elementToReturn = self.queueStart.nodePtr.list[self.queueStart.itemIndex];
                    //
                    const elementToReturn: ?T = val: {
                        if (self.queueStart.nodePtr.nodeId == self.queueStart.nodePtr.nodeId) { // same nodes
                            // check if we have no items left to pop
                            if (self.queueStart.nodePtr.indexFilled == self.queueEnd.itemIndex and self.queueStart.itemIndex == self.queueEnd.nodePtr.indexFilled) {
                                std.debug.print("we have reached the cond where the pop can't remove element as the put has not written ahead in this node \n", .{});
                                // break :val null;
                                return null; // as no more incrementation
                            } else break :val self.queueStart.nodePtr.list[self.queueStart.itemIndex];
                        } else {
                            assert(self.queueStart.nodePtr.nodeId < self.queueEnd.nodePtr.nodeId);
                            break :val self.queueStart.nodePtr.list[self.queueStart.itemIndex];
                        }
                    };

                    // if we are at the end of the queue and can't remove more items

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
                    //       and putting it back is the responsility of put()(if needed before allocation),
                    //       now we do not need to keep waking/changing the self.queueStart index/ptr form the put fn
                    //
                    //
                    // ** hey we need to also tell the self.queueStart to be not null when we have our first element or in general when we have it to null , we do that in the put fn **
                    //  and also checking if we are at the end of the array so no outer bounds indexing

                    // now increment the node and handeling deletion
                    const indexWeAreInTheNode = self.queueStart.itemIndex;
                    if (indexWeAreInTheNode + 1 >= self.queueStart.nodePtr.list.len) {
                        // here if we are in same node and it has on same index in reading and writign, i.e then in the if block in the if statement above( to get return element )
                        // should return null, and hence here we have a next node if not this has a assert that will crash it
                        self.deleteUsedNodeAndGoToNextOne();
                    } else {
                        // same node go forward
                        self.queueStart.itemIndex += 1;
                    }
                    return elementToReturn;
                },
            }
        }

        /// deletes the node in the queueStart and moves it to the next node, and also asserts that there is a next node to go to, if not then crash
        fn deleteUsedNodeAndGoToNextOne(self: *Self) void {
            const nodeToDelete = self.queueStart.nodePtr;
            asserts.assertWithMessageFmtRuntime(nodeToDelete.nextListPtr != null, "expected the next node ptr to not be null when deleting the node (ID:{d}) ", .{nodeToDelete.nodeId});
            self.queueStart.nodePtr = nodeToDelete.nextListPtr.?;
            self.queueStart.itemIndex = 0;
            if (self.freedList) |freedList| {
                nodeToDelete.nextListPtr = freedList;
                self.freedList = nodeToDelete;
            } else {
                self.freedList = nodeToDelete;
            }
        }

        /// goes through the freedList and then allocator for new node, if not in any then null
        fn getNewNodeEitherThroughAllocOrFreedList(self: *Self) ?*Node {
            // first check the freedList
            const newNode = node: {
                if (self.freedList) |startNode| {
                    self.freedList = startNode.nextListPtr;
                    startNode.nextListPtr = null;
                    startNode.indexFilled = 0;
                    const currentNodeId = self.nodeNumber.fetchAdd(1, .monotonic);
                    startNode.nodeId = currentNodeId;
                    std.debug.print("got a node via freedList\n", .{});
                    break :node startNode;
                } else {
                    // through the alloc
                    const allocatedNode = allocateNewNode(.{ .allocator = self.allocator }) catch return null;
                    allocatedNode.nextListPtr = null;
                    allocatedNode.indexFilled = 0;
                    const currentNodeId = self.nodeNumber.fetchAdd(1, .monotonic);
                    allocatedNode.nodeId = currentNodeId;
                    std.debug.print("got a node via alloc\n", .{});
                    break :node allocatedNode;
                }
            };
            return newNode;
        }

        /// takes a newly allocated node and moves the self.queueEnd ptr to it
        /// [NoAbleToGetNewNode] - we can't get a new node from the freedList or from the allocator
        fn getNewNodeAndIncrementQueueEndPointerToThat(self: *Self) error{NoAbleToGetNewNode}!void {
            const newNode = self.getNewNodeEitherThroughAllocOrFreedList();
            if (newNode) |node| {
                const currentNodeId = self.queueEnd.nodePtr.nodeId;
                std.debug.print(" the newNode's id is {d} and currentNodeId is {d} \n", .{ node.nodeId, currentNodeId });
                std.debug.print(" the node.nextListPtr of the new node is {any} \n", .{self.queueEnd.nodePtr.nextListPtr});
                if (self.queueEnd.nodePtr.nextListPtr) |nn| {
                    std.debug.print("and the new node is there and it's id is {d} \n", .{nn.nodeId});
                }
                asserts.assertWithMessageFmtRuntime(self.queueEnd.nodePtr.nextListPtr == null, "the node at queueEnd:{d} contains a next node, it should have been null\n", .{self.queueEnd.nodePtr.nodeId});
                self.queueEnd.nodePtr.nextListPtr = node;
                node.nextListPtr = null;
                node.indexFilled = 0;
                self.queueEnd.itemIndex = 0;
                self.queueEnd.nodePtr = node;
                std.debug.print("the queueEnd.nodePtr.nodeId is {d}\n", .{self.queueEnd.nodePtr.nodeId});
            } else return error.NoAbleToGetNewNode;
        }

        /// appends to the list, this one will block (mutex)
        /// errors if we don't have space and can't allocate new node
        pub fn put(self: *Self, value: T) Allocator.Error!void {
            self.queueStart.nodePtr.*.lock.lock();
            defer self.queueStart.nodePtr.*.lock.unlock();
            // now since this is FIFO so we need to take the value add it in the queue

            // first we need to insert it in the place of the index and if we have a problem in allocating that is a problem of the next put btw, so a bool flag to check it
            // or we can make it size - 1 as future problem can be forced to dealt with today
            //
            // increment the node's indexFilled field

            if (self.cantAllocateAfterThis) {
                self.getNewNodeAndIncrementQueueEndPointerToThat() catch return Allocator.Error.OutOfMemory;
            }

            // now if we were out of mem we got a new node and if not then then put already have a index
            // now insert
            // std.debug.print("\n;) the cantAllocateAfterThis is {any}\n", .{self.cantAllocateAfterThis});
            std.debug.print(" at node:{d} , we are at {d} \n", .{ self.queueEnd.nodePtr.nodeId, self.queueEnd.itemIndex });
            asserts.assertWithMessageFmtRuntime(self.queueEnd.itemIndex < self.listSize, "we are outside the array bounds, the array len([0..len-1]) is {d} and we are at {d} \n", .{ self.listSize, self.queueEnd.itemIndex });
            self.queueEnd.nodePtr.list[self.queueEnd.itemIndex] = value;
            self.queueEnd.nodePtr.indexFilled += 1;
            if (self.cantAllocateAfterThis) {
                // if we alllocated after a failed attempt and also inserted it in then the array index is at 0 index in that one
                assert(self.queueEnd.itemIndex + 1 <= self.listSize);
                self.queueEnd.itemIndex += 1;
                self.cantAllocateAfterThis = false;
            }
            // increment the ptr to the next node if it is at the end then allocate a new node if not able to then set the self.cantAllocateAfterThis to true
            if (self.queueEnd.itemIndex + 1 >= self.listSize) {
                // new node
                std.debug.print("the current node's next node ptr is {any} \n and also current node is {} \n", .{ self.queueEnd.nodePtr.nextListPtr, self.queueEnd.nodePtr.* });

                self.getNewNodeAndIncrementQueueEndPointerToThat() catch {
                    self.cantAllocateAfterThis = true;
                    // now don't return a error as we are able to put it in and not able to go to/get the next node
                    // return Allocator.Error;
                    return;
                };
                return;
            } else {
                self.queueEnd.itemIndex += 1;
                return;
            }
        }

        pub fn init(allocator2: std.mem.Allocator, comptime config: struct {
            /// size of the arrayList we do during each allocation
            listSize: u64 = 180,
        }) std.mem.Allocator.Error!Self {
            assertWithMessage(config.listSize > 0, "the listSize should be greater than 0\n");
            var node: *Node = try allocateNewNode(.{ .allocator = allocator2 });

            var self = Self{
                .listSize = config.listSize,
                .allocator = allocator2,
                .queueStart = .{ .nodePtr = node, .itemIndex = 0 },
                .queueEnd = .{ .nodePtr = node, .itemIndex = 0 },
                .freedList = null,
                .cantAllocateAfterThis = false,
                .nodeNumber = std.atomic.Value(u64).init(0),
            };
            node.nodeId = self.nodeNumber.fetchAdd(1, .monotonic);
            return self;
        }
    };
}
