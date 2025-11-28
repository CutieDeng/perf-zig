pub const PerfEventAttr = packed struct {
    const SampleValue = packed union {
        sample_period: u64,
        sample_freq: u64,
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
    
    
};
