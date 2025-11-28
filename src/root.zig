const std = @import("std");
const linux = std.os.linux;

const perf_event_attr_def = @import("perf_event_attr.zig");
const PerfEventAttr = perf_event_attr_def.PerfEventAttr;

const perf_lib = @cImport({
    @cInclude("linux/perf_event.h");
    @cInclude("linux/hw_breakpoint.h");
    @cInclude("sys/syscall.h");
    @cInclude("unistd.h");
});

pub fn perfEventOpen(attr: *PerfEventAttr, pid: usize, cpu: usize, group_fd: usize, flags: usize) usize {
    const FLAGS_DEFAULT = perf_lib.PERF_FLAG_FD_CLOEXEC;
    return linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(attr), pid, cpu, group_fd, flags | FLAGS_DEFAULT);
}

pub fn doPerfCount(pid: usize, cpu: usize, group_fd: usize, flags: usize, cnt: usize, sec: usize) !void {
    const FLAGS_DEFAULT = perf_lib.PERF_FLAG_FD_CLOEXEC;
    var attr: PerfEventAttr = undefined;
    @memset(std.mem.asBytes(&attr), 0);
    attr.size = @sizeOf(PerfEventAttr);
    attr.@"type"= perf_lib.PERF_TYPE_HARDWARE;
    attr.config = perf_lib.PERF_COUNT_HW_INSTRUCTIONS;
    attr.disabled = 1;
    const fd_raw = linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(&attr), pid, cpu, group_fd, flags | FLAGS_DEFAULT);
    const fd_e = std.posix.errno(fd_raw);
    if (fd_e != .SUCCESS) { return std.posix.unexpectedErrno(fd_e); }
    const fd: std.posix.fd_t = @intCast(fd_raw);
    const ioc_e = std.posix.errno(linux.ioctl(fd, perf_lib.PERF_EVENT_IOC_ENABLE, 0));
    if (ioc_e != .SUCCESS) { return std.posix.unexpectedErrno(ioc_e); }
    var cur_cnt: usize = cnt;
    while (cur_cnt > 0) : (cur_cnt -= 1) {
        var ins: u64 = undefined;
        const sz = try std.posix.read(fd, std.mem.asBytes(&ins));
        if (sz != @sizeOf(@TypeOf(ins))) {
            std.log.warn("failed read instructions, only read {} bytes", .{ sz });
            std.posix.nanosleep(3, 0);
        } else {
            std.log.info("instructions={}", .{ ins });
            std.posix.nanosleep(sec, 0);
        }
    }
}
