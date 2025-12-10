const std = @import("std");
const perf_zig = @import("perf_zig");

pub fn main() !void {
    std.debug.print("Calculating IPC (Instructions Per Cycle)...\n", .{});
    const ipc = try perf_zig.calculateIPC(@bitCast(@as(i64, -1)), @bitCast(@as(i64, -1)), @bitCast(@as(i64, -1)), 0, 1);
    std.debug.print("Final IPC: {d:.4}\n", .{ipc});
}
