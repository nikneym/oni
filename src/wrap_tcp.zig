const std = @import("std");
const mem = std.mem;
const lua = @import("ziglua");
const Tcp = @import("tcp.zig").Tcp;
const Lua = lua.Lua;

//*
//* net.TcpConnect(host: string, port: integer) -> [ TcpConnection, nil ], [ err, nil ]
//* 
// TODO: better error messages
fn wrap_TcpConnect(vm: *Lua) i32 {
    vm.checkType(1, .string);
    vm.checkType(2, .number);

    const host: []const u8 = mem.span(vm.toString(1) catch unreachable);
    const port: u16 = @intCast(u16, vm.toInteger(2));

    return Tcp.scheduleConnect(vm, host, port) catch {
        vm.pushNil();
        vm.pushString("failed scheduling a connect event");
        return 2;
    };
}

//*
//* tcp:read(length: number) -> [ string, nil ], [ err, nil ]
//* 
fn wrap_TcpRead(vm: *Lua) i32 {
    vm.checkType(1, .userdata);
    vm.checkType(2, .number);

    const tcp = vm.toUserdata(Tcp.Userdata, 1) catch unreachable;
    const len = @intCast(usize, vm.toInteger(2));

    return Tcp.scheduleRead(vm, tcp, len) catch {
        vm.pushNil();
        vm.pushString("failed scheduling a read event");
        return 2;
    };
}

//*
//* tcp:write(bytes: string) -> [ err, nil ]
//* 
// TODO: better error messages
fn wrap_TcpWrite(vm: *Lua) i32 {
    vm.checkType(1, .userdata);
    vm.checkType(2, .string);

    const tcp = vm.toUserdata(Tcp.Userdata, 1) catch unreachable;
    const bytes = vm.toBytes(2) catch unreachable;

    return Tcp.scheduleWrite(vm, tcp.fd, bytes) catch {
        vm.pushString("failed scheduling a write event");
        return 1;
    };
}

//*
//* tcp:close() -> [ err, nil ]
//* 
fn wrap_TcpClose(vm: *Lua) i32 {
    vm.checkType(1, .userdata);

    const tcp = vm.toUserdata(Tcp.Userdata, 1) catch unreachable;

    return Tcp.scheduleClose(vm, tcp) catch {
        vm.pushString("failed scheduling a close event");
        return 1;
    };
}

fn wrap_tostring(vm: *Lua) i32 {
    _ = vm.pushFString("<TcpConnection %p>", .{ vm.toPointer(1) catch null });
    return 1;
}

pub fn exportTcp(vm: *Lua) void {
    vm.pushString("net");
    vm.newTable();

    // TCP functions
    vm.pushString("TcpConnect");
    vm.pushFunction(lua.wrap(wrap_TcpConnect));
    vm.rawSetTable(-3);

    vm.rawSetTable(-3);
}

pub fn exportTcpMt(vm: *Lua) void {
    vm.newMetatable("tcp") catch unreachable;
    vm.newTable();
    vm.pushString("read");
    vm.pushFunction(lua.wrap(wrap_TcpRead));
    vm.rawSetTable(-3);
    vm.pushString("write");
    vm.pushFunction(lua.wrap(wrap_TcpWrite));
    vm.rawSetTable(-3);
    vm.pushString("close");
    vm.pushFunction(lua.wrap(wrap_TcpClose));
    vm.rawSetTable(-3);
    vm.setField(-2, "__index");
    vm.pushFunction(lua.wrap(wrap_tostring));
    vm.setField(-2, "__tostring");
}
