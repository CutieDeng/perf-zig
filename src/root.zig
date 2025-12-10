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

pub fn calculateIPC(pid: usize, cpu: usize, group_fd: usize, flags: usize, sec: usize) !f64 {
    const FLAGS_DEFAULT = perf_lib.PERF_FLAG_FD_CLOEXEC;
    
    // Create perf event for instructions
    var attr_ins: PerfEventAttr = undefined;
    @memset(std.mem.asBytes(&attr_ins), 0);
    attr_ins.size = @sizeOf(PerfEventAttr);
    attr_ins.@"type" = perf_lib.PERF_TYPE_HARDWARE;
    attr_ins.config = perf_lib.PERF_COUNT_HW_INSTRUCTIONS;
    attr_ins.disabled = 1;
    
    const fd_ins_raw = linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(&attr_ins), pid, cpu, group_fd, flags | FLAGS_DEFAULT);
    const fd_ins_e = std.posix.errno(fd_ins_raw);
    if (fd_ins_e != .SUCCESS) { return std.posix.unexpectedErrno(fd_ins_e); }
    const fd_ins: std.posix.fd_t = @intCast(fd_ins_raw);
    
    // Create perf event for cycles (group leader)
    var attr_cyc: PerfEventAttr = undefined;
    @memset(std.mem.asBytes(&attr_cyc), 0);
    attr_cyc.size = @sizeOf(PerfEventAttr);
    attr_cyc.@"type" = perf_lib.PERF_TYPE_HARDWARE;
    attr_cyc.config = perf_lib.PERF_COUNT_HW_CPU_CYCLES;
    attr_cyc.disabled = 1;
    
    const fd_cyc_raw = linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(&attr_cyc), pid, cpu, @as(usize, @bitCast(@as(i64, -1))), flags | FLAGS_DEFAULT);
    const fd_cyc_e = std.posix.errno(fd_cyc_raw);
    if (fd_cyc_e != .SUCCESS) { return std.posix.unexpectedErrno(fd_cyc_e); }
    const fd_cyc: std.posix.fd_t = @intCast(fd_cyc_raw);
    
    // Enable both events
    const ioc_ins_e = std.posix.errno(linux.ioctl(fd_ins, perf_lib.PERF_EVENT_IOC_ENABLE, 0));
    if (ioc_ins_e != .SUCCESS) { return std.posix.unexpectedErrno(ioc_ins_e); }
    
    const ioc_cyc_e = std.posix.errno(linux.ioctl(fd_cyc, perf_lib.PERF_EVENT_IOC_ENABLE, 0));
    if (ioc_cyc_e != .SUCCESS) { return std.posix.unexpectedErrno(ioc_cyc_e); }
    
    // Sleep for the specified duration
    std.posix.nanosleep(sec, 0);
    
    // Disable both events
    _ = linux.ioctl(fd_ins, perf_lib.PERF_EVENT_IOC_DISABLE, 0);
    _ = linux.ioctl(fd_cyc, perf_lib.PERF_EVENT_IOC_DISABLE, 0);
    
    // Read instruction count
    var ins: u64 = undefined;
    const sz_ins = try std.posix.read(fd_ins, std.mem.asBytes(&ins));
    if (sz_ins != @sizeOf(@TypeOf(ins))) {
        std.log.warn("failed read instructions, only read {} bytes", .{sz_ins});
        return 0.0;
    }
    
    // Read cycle count
    var cyc: u64 = undefined;
    const sz_cyc = try std.posix.read(fd_cyc, std.mem.asBytes(&cyc));
    if (sz_cyc != @sizeOf(@TypeOf(cyc))) {
        std.log.warn("failed read cycles, only read {} bytes", .{sz_cyc});
        return 0.0;
    }
    
    // Close file descriptors
    std.posix.close(fd_ins);
    std.posix.close(fd_cyc);
    
    // Calculate IPC
    const ipc = if (cyc > 0) @as(f64, @floatFromInt(ins)) / @as(f64, @floatFromInt(cyc)) else 0.0;
    
    std.log.info("instructions={}, cycles={}, IPC={d:.4}", .{ ins, cyc, ipc });
    
    return ipc;
}
