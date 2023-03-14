const std = @import("std");
const heap = std.heap;
const lua = @import("ziglua");
const xev = @import("xev");
const Lua = lua.Lua;

// library-wide globals and global resources shared across
pub const allocator = std.heap.c_allocator;
const BUFFER_SIZE = 4096;

pub var GLOBAL: *Self = undefined;

// types
//const Queue = std.TailQueue(Lua);
//pub const Node = Queue.Node;
const BufferPool = heap.MemoryPool([BUFFER_SIZE]u8);
const CompletionPool = heap.MemoryPool(xev.Completion);

const Self = @This();
loop: xev.Loop,
//queue: Queue,
buffer_pool: BufferPool,
completion_pool: CompletionPool,

pub fn init() !void {
    GLOBAL = try allocator.create(Self);
    GLOBAL.* = .{
        .loop = try xev.Loop.init(.{}),
        //.queue = .{},
        .buffer_pool = BufferPool.init(allocator),
        .completion_pool = CompletionPool.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.loop.deinit();
    self.buffer_pool.deinit();
    self.completion_pool.deinit();
}

/// Get the global xev event loop.
pub fn defaultLoop() *xev.Loop {
    return &GLOBAL.loop;
}

/// Create or reuse a xev.Completion from memory pool.
pub fn getCompletion() !*xev.Completion {
    return GLOBAL.completion_pool.create();
}

/// Destroy the specified xev.Completion, puts it back to the memory pool.
pub fn destroyCompletion(c: *xev.Completion) void {
    return GLOBAL.completion_pool.destroy(c);
}

pub fn getBuffer() !*align (BufferPool.item_alignment) [BUFFER_SIZE]u8 {
    return GLOBAL.buffer_pool.create();
}
