const std = @import("std");
const perf_zig = @import("perf_zig");

pub fn main() !void {
    // const gpa = std.testing.allocator;
    const fd = perf_zig.perf_event_open(undefined, 0, 0xffffffffffffffff, 0xffffffffffffffff, 0);
    const api_e = std.posix.errno(fd);
    std.log.info("perf: {}", .{ api_e });
}
