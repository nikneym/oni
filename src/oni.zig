const std = @import("std");
const lua = @import("ziglua");
const xev = @import("xev");
const global = @import("global.zig");
const Lua = lua.Lua;
const LuaState = lua.LuaState;

pub fn scheduleTimer(co: *Lua, ms: usize) !c_int {
    const timer = try xev.Timer.init();
    const c = try global.getCompletion();

    timer.run(
        global.defaultLoop(),
        c,
        ms,
        LuaState,
        co.state,
        onTimerFireDefaultFn,
    );

    return co.yield(0);
}

// this one just resumes the thread back
fn onTimerFireDefaultFn(
    state: ?*LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    res: xev.Timer.RunError!void,
) xev.CallbackAction {
    global.destroyCompletion(c);
    var co = Lua{ .state = state.? };

    res catch {
        @panic("timer error");
    };

    // give control back to coroutine
    _ = co.resumeThread(0) catch co.raiseError();
    return .disarm;
}
