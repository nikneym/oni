const std = @import("std");
const lua = @import("ziglua");
const xev = @import("xev");
const global = @import("global.zig");
const Lua = lua.Lua;
const LuaState = lua.LuaState;

// Schedules a new timer event
pub fn scheduleTimer(co: *Lua, ms: usize) !c_int {
    const timer = try xev.Timer.init();
    const c = try global.getCompletion();

    // schedule a timer
    timer.run(
        global.defaultLoop(),
        c,
        ms,
        LuaState,
        co.state,
        onTimerFireDefaultFn,
    );

    // push the timer to onFireFn
    //const ptr = co.newUserdata(*const xev.Timer);
    //ptr.* = &timer;
    return co.yield(0);
}

// this timerFn just resumes the thread back
fn onTimerFireDefaultFn(
    state: ?*LuaState,
    _: *xev.Loop,
    c: *xev.Completion,
    res: xev.Timer.RunError!void,
) xev.CallbackAction {
    global.destroyCompletion(c);
    var co = Lua{ .state = state.? };
    //const timer = co.toUserdata(*xev.Timer, 1) catch @panic("unable to receive timer from event");
    //timer.*.deinit();

    // TODO: proper error
    res catch |e| {
        co.pushString(@errorName(e));
        _ = co.resumeThread(1) catch co.raiseError();
        return .disarm;
    };

    // give control back to coroutine
    _ = co.resumeThread(0) catch co.raiseError();
    return .disarm;
}
