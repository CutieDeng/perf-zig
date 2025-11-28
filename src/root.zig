const std = @import("std");
const linux = std.os.linux;

const perf_lib = @cImport({
    @cInclude("linux/perf_event.h");
    @cInclude("linux/hw_breakpoint.h");
    @cInclude("sys/syscall.h");
    @cInclude("unistd.h");
});

pub fn fizz() !void {
    
}

pub fn perf_event_open(attr: *perf_lib.perf_event_attr, pid: usize, cpu: usize, group_fd: usize, flags: usize) usize {
    const FLAGS_DEFAULT = perf_lib.PERF_FLAG_FD_CLOEXEC;
    return linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(attr), pid, cpu, group_fd, flags | FLAGS_DEFAULT);
}
