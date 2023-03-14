const std = @import("std");
const lua = @import("ziglua");
const global = @import("global.zig");
const Lua = lua.Lua;

const Self = @This();

pub fn spawn(vm: *Lua) i32 {
    vm.checkType(1, .function);

    var co = vm.newThread();
    vm.pushValue(1);
    vm.xMove(co, 1);

    _ = co.resumeThread(0) catch {
        return 0;
    };

    return 0;
}

pub fn suspends(vm: *Lua) i32 {
    //global.push(vm.*) catch unreachable;
    return vm.yield(0);
}

// TODO: refactor runner
pub fn run(vm: *Lua) i32 {
    _ = vm;
    global.GLOBAL.loop.run(.until_done) catch std.debug.print("some error\n", .{});

    return 0;
}
