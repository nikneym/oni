const std = @import("std");
const mem = std.mem;
const lua = @import("ziglua");
const tcp = @import("tcp.zig");
const Lua = lua.Lua;
const xev = @import("xev");

//*
//* net.TcpConnect(host: string, port: integer) -> [ TcpConnection, nil ], [ err, nil ]
//*
// TODO: better error messages
fn wrap_TcpStream(vm: *Lua) i32 {
    vm.checkType(1, .string);
    vm.checkType(2, .number);

    const host: []const u8 = mem.span(vm.toString(1) catch unreachable);
    const port: u16 = @intCast(u16, vm.toInteger(2));

    return tcp.connect(vm, host, port) catch {
        vm.pushNil();
        vm.pushString("failed scheduling a connect event");
        return 2;
    };
}

//*
//* net.TcpListener(host: string, port: integer) -> [ TcpListener, nil ], [ err, nil ]
//*
fn wrap_TcpListener(vm: *Lua) i32 {
    const host = mem.span(vm.checkString(1));
    const port = @intCast(u16, vm.checkInteger(2));

    return tcp.listen(vm, host, port) catch {
        vm.pushNil();
        vm.pushString("unable to create a TCP listener");
        return 2;
    };
}

//*
//* tcp:accept() -> [ TcpConnection, nil ], [ err, nil ]
//*
fn wrap_TcpAccept(vm: *Lua) i32 {
    vm.checkType(1, .userdata);

    const ptr = vm.toUserdata(xev.TCP, 1) catch unreachable;

    return tcp.accept(vm, ptr.*) catch {
        vm.pushNil();
        vm.pushString("failed scheduling accept event");
        return 2;
    };
}

//*
//* tcp:read(length: number) -> [ string, nil ], [ err, nil ]
//*
fn wrap_TcpRead(vm: *Lua) i32 {
    vm.checkType(1, .userdata);
    vm.checkType(2, .number);

    const ptr = vm.toUserdata(xev.TCP, 1) catch unreachable;
    const len = @intCast(usize, vm.toInteger(2));

    return tcp.read(vm, ptr.*, len) catch {
        vm.pushNil();
        vm.pushString("failed scheduling a read event");
        return 2;
    };
}

//*
//* tcp:write(bytes: string) -> [len, nil], [ err, nil ]
//*
// TODO: better error messages
fn wrap_TcpWrite(vm: *Lua) i32 {
    vm.checkType(1, .userdata);
    vm.checkType(2, .string);

    const ptr = vm.toUserdata(xev.TCP, 1) catch unreachable;
    const bytes = vm.toBytes(2) catch unreachable;

    return tcp.write(vm, ptr.*, bytes) catch {
        vm.pushNil();
        vm.pushString("failed scheduling a write event");
        return 2;
    };
}

//*
//* tcp:close() -> [ err, nil ]
//*
fn wrap_TcpClose(vm: *Lua) i32 {
    vm.checkType(1, .userdata);

    const ptr = vm.toUserdata(xev.TCP, 1) catch unreachable;

    return tcp.close(vm, ptr.*) catch {
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
    vm.pushString("TcpStream");
    vm.pushFunction(lua.wrap(wrap_TcpStream));
    vm.rawSetTable(-3);

    vm.pushString("TcpListener");
    vm.pushFunction(lua.wrap(wrap_TcpListener));
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
    vm.pushString("accept");
    vm.pushFunction(lua.wrap(wrap_TcpAccept));
    vm.rawSetTable(-3);
    vm.setField(-2, "__index");
    vm.pushFunction(lua.wrap(wrap_tostring));
    vm.setField(-2, "__tostring");
}
