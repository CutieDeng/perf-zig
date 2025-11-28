pub const PerfEventAttr = packed struct {
    const SampleValue = packed union {
        sample_period: u64,
        sample_freq: u64,
    };
    const WakeupValue = packed union {
        wakeup_events: u32,    
        wakeup_watermark: u32, 
    };
    const BpValue = packed union {
        bp_addr: u64,
        kprobe_func: u64,
        uprobe_path: u64,
        config1: u64,
    };
    const BpValue2 = packed union {
        bp_len: u64,
        kprobe_addr: u64,
        probe_offset: u64,
        config2: u64,
    };
    
    @"type": u32,
    size: u32,
    config: u64,

    sample_v: SampleValue,
    sample_type: u64,
    read_format: u64,
    
    disabled: u1,
    inherit: u1,
    pinned: u1,
    exclusive: u1,
    exclude_user: u1,
    exclude_kernel: u1,
    exclude_kv: u1,
    exclude_idle: u1,
    mmap: u1,
    comm: u1,
    freq: u1,
    inherit_stat: u1,
    enable_on_exec: u1,
    task: u1,
    watermark: u1,
    precise_ip: u2,
    mmap_data: u1,
    sample_id_all: u1,

    exclude_host: u1,
    exclude_guest: u1,

    exclude_callchain_kernel: u1,
    exclude_callchain_user: u1,
    mmap2: u1,
    comm_exec: u1,
    use_clockid: u1,
    context_switch: u1,
    write_backward: u1,
    namespaces: u1,
    ksymbol: u1,
    bpf_event: u1,
    aux_output: u1,
    cgroup: u1,
    text_poke: u1,
    __reserved_1: u30 = 0,
    
    wakeup_v: WakeupValue,
    
    bp_type: u32,
    bp_v: BpValue,
    bp_v2: BpValue2,
    branch_sample_type: u64,

    sample_regs_user: u64,
    sample_stack_user: u32,
    clockid: u32,
    sample_regs_intr: u64,
    aux_watermark: u32,
    sample_max_stack: u16,
    __reserved_2: u16 = 0,
    aux_sample_size: u32,
    __reserved_3: u32 = 0,
};
