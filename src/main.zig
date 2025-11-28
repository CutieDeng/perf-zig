const std = @import("std");
const perf_zig = @import("perf_zig");

pub fn main() !void {
    try perf_zig.doPerfCount(@bitCast(@as(i64, -1)), @bitCast(@as(i64, -1)), @bitCast(@as(i64, -1)), 0, 10, 1);
}
