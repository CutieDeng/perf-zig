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

const c = @cImport({
    @cInclude("unistd.h");
});

/// 查询在线 CPU 数量
pub fn getCpuCount() !usize {
    const cpu_count = c.sysconf(c._SC_NPROCESSORS_ONLN);
    if (cpu_count < 0) return error.SysconfFailed;
    return @intCast(cpu_count);
}

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

/// 使用 perf group 原子读取的方式，统计“所有进程、所有 CPU”一段时间内的 IPC。
/// - 对每个 CPU 创建一个 group leader（cycles）和一个 follower（instructions）
/// - 同时启停（PERF_IOC_FLAG_GROUP）避免时间偏移
/// - 一次对 group leader 读出包含 time_enabled/time_running 的原子结果
pub fn calculateIPCAllCpusGrouped(sec: usize) !f64 {
    const pid_all = @as(usize, @bitCast(@as(i64, -1))); // pid = -1 表示所有进程
    const cpu_count = try getCpuCount();
    if (cpu_count == 0) return error.NoCpuDetected;

    const allocator = std.heap.c_allocator;
    // 为每个 CPU 保存 leader/follower fd
    var fds = try allocator.alloc(std.posix.fd_t, cpu_count * 2);
    defer allocator.free(fds);
    var fd_count: usize = 0;

    // 预设 attr：leader 用 PERF_FORMAT_GROUP + 时间字段；follower 不需要 read_format
    const read_fmt_group = perf_lib.PERF_FORMAT_GROUP | perf_lib.PERF_FORMAT_TOTAL_TIME_ENABLED | perf_lib.PERF_FORMAT_TOTAL_TIME_RUNNING;

    var cpu: usize = 0;
    while (cpu < cpu_count) : (cpu += 1) {
        // leader: cycles
        var attr_cyc: PerfEventAttr = undefined;
        @memset(std.mem.asBytes(&attr_cyc), 0);
        attr_cyc.size = @sizeOf(PerfEventAttr);
        attr_cyc.@"type" = perf_lib.PERF_TYPE_HARDWARE;
        attr_cyc.config = perf_lib.PERF_COUNT_HW_CPU_CYCLES;
        attr_cyc.disabled = 1;
        attr_cyc.read_format = read_fmt_group;

        const fd_leader_raw = linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(&attr_cyc), pid_all, cpu, @as(usize, @bitCast(@as(i64, -1))), perf_lib.PERF_FLAG_FD_CLOEXEC);
        const fd_leader_e = std.posix.errno(fd_leader_raw);
        if (fd_leader_e != .SUCCESS) {
            return std.posix.unexpectedErrno(fd_leader_e);
        }
        const fd_leader: std.posix.fd_t = @intCast(fd_leader_raw);
        fds[fd_count] = fd_leader;
        fd_count += 1;

        // follower: instructions
        var attr_ins: PerfEventAttr = undefined;
        @memset(std.mem.asBytes(&attr_ins), 0);
        attr_ins.size = @sizeOf(PerfEventAttr);
        attr_ins.@"type" = perf_lib.PERF_TYPE_HARDWARE;
        attr_ins.config = perf_lib.PERF_COUNT_HW_INSTRUCTIONS;
        attr_ins.disabled = 1;
        attr_ins.read_format = 0; // follower 读 leader

        const fd_ins_raw = linux.syscall5(linux.SYS.perf_event_open, @intFromPtr(&attr_ins), pid_all, cpu, @as(usize, fd_leader), perf_lib.PERF_FLAG_FD_CLOEXEC);
        const fd_ins_e = std.posix.errno(fd_ins_raw);
        if (fd_ins_e != .SUCCESS) {
            return std.posix.unexpectedErrno(fd_ins_e);
        }
        const fd_ins: std.posix.fd_t = @intCast(fd_ins_raw);
        fds[fd_count] = fd_ins;
        fd_count += 1;
    }

    // 启用（对 leader 使用 GROUP 标志，保证组内同时启用）
    var i: usize = 0;
    while (i < fd_count) : (i += 2) {
        const fd_leader = fds[i];
        const ioc_e = std.posix.errno(linux.ioctl(fd_leader, perf_lib.PERF_EVENT_IOC_ENABLE, perf_lib.PERF_IOC_FLAG_GROUP));
        if (ioc_e != .SUCCESS) return std.posix.unexpectedErrno(ioc_e);
    }

    std.posix.nanosleep(sec, 0);

    // 停用
    i = 0;
    while (i < fd_count) : (i += 2) {
        const fd_leader = fds[i];
        _ = linux.ioctl(fd_leader, perf_lib.PERF_EVENT_IOC_DISABLE, perf_lib.PERF_IOC_FLAG_GROUP);
    }

    // 读取并累加
    var total_ins: u128 = 0;
    var total_cyc: u128 = 0;
    i = 0;
    while (i < fd_count) : (i += 2) {
        const fd_leader = fds[i];

        // 期望返回：nr=2，time_enabled，time_running，value(cycles)，value(instr)
        var buf: [5]u64 = undefined;
        const sz = try std.posix.read(fd_leader, std.mem.asBytes(&buf));
        if (sz < @sizeOf(buf)) return error.UnexpectedReadSize;

        const nr = buf[0];
        if (nr != 2) return error.UnexpectedCounterCount;

        const time_enabled = buf[1];
        const time_running = buf[2];
        const raw_cyc = buf[3];
        const raw_ins = buf[4];

        // 若被 multiplex，需要按 time_running/ time_enabled 做缩放
        const scale = if (time_running > 0) @as(u128, time_enabled) * 1_000_000_000 / @as(u128, time_running) else 1;
        const adj_cyc = if (time_running > 0) (raw_cyc * time_enabled) / time_running else raw_cyc;
        const adj_ins = if (time_running > 0) (raw_ins * time_enabled) / time_running else raw_ins;

        _ = scale; // 保留可选的额外缩放，目前未使用

        total_cyc += adj_cyc;
        total_ins += adj_ins;
    }

    // 关闭所有 fd
    i = 0;
    while (i < fd_count) : (i += 1) {
        std.posix.close(fds[i]);
    }

    if (total_cyc == 0) return 0.0;
    return @as(f64, @floatFromInt(total_ins)) / @as(f64, @floatFromInt(total_cyc));
}
