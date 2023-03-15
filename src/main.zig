const std = @import("std");
const lua = @import("ziglua");
const loop = @import("loop.zig");
const global = @import("global.zig");
const exportTcp = @import("wrap_tcp.zig").exportTcp;
const exportTcpMt = @import("wrap_tcp.zig").exportTcpMt;
const Lua = lua.Lua;

/// library entry point
export fn luaopen_oni(state: ?*lua.LuaState) c_int {
    global.init() catch {
        std.debug.print("globals not initialized\n", .{});
    };

    var vm = Lua{ .state = state.? };

    exportTcpMt(&vm);

    vm.createTable(0, 0);
    vm.pushString("spawn");
    vm.pushFunction(lua.wrap(loop.spawn));
    vm.rawSetTable(-3);
    vm.pushString("suspend");
    vm.pushFunction(lua.wrap(loop.suspends));
    vm.rawSetTable(-3);
    vm.pushString("run");
    vm.pushFunction(lua.wrap(loop.run));
    vm.rawSetTable(-3);
    vm.pushString("wait");
    vm.pushFunction(lua.wrap(loop.wait));
    vm.rawSetTable(-3);

    // expose TCP utilities
    exportTcp(&vm);

    return 1;
}
