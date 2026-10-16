# Subscriber benchmark, works like `nats bench sub <subject> --msgs <n>`.
#
# Usage:
#     julia --project=. -t 2,1 scripts/bench_sub.jl foo --msgs 1000000
#
# Then start a publisher, e.g. `nats bench pub foo --size 3 --msgs 1000000`.
#
# Options:
#     --msgs=N           number of messages to wait for, default 100000
#     -s, --server=URL   server url, default `NATS_URL` env or NATS.jl default
#     --[no-]progress    print progress, enabled by default when stderr is a terminal
#     --profile=PATH    write CPU samples by thread and allocation/GC counters to PATH
#
# Throughput is measured from the first to the last expected message. CPU usage of the process
# is measured in the same time window, 100% means one core.
# Profiling adds overhead; use separate runs without --profile for throughput comparisons.

using NATS
using Dates
using Printf
using Profile

const USAGE = "Usage: julia --project=. -t 2,1 scripts/bench_sub.jl <subject> [--msgs=N] [--server=URL] [--[no-]progress] [--profile=PATH]"

function parse_cli(args, known)
    positional = String[]
    opts = Dict{String, String}()
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "-h" || arg == "--help"
            println(USAGE)
            exit(0)
        elseif arg == "--progress"
            opts["progress"] = "true"
        elseif startswith(arg, "--no-")
            opts[arg[6:end]] = "false"
        elseif startswith(arg, "--") || arg == "-s"
            if occursin('=', arg)
                key, value = split(arg[3:end], '='; limit = 2)
            else
                i < length(args) || error("Missing value for $arg.\n$USAGE")
                key, value = lstrip(arg, '-'), args[i += 1]
            end
            opts[key == "s" ? "server" : key] = value
        else
            push!(positional, arg)
        end
        i += 1
    end
    unknown = setdiff(keys(opts), known)
    isempty(unknown) || error("Unknown options: $(join(unknown, ", ")).\n$USAGE")
    length(positional) == 1 || error(USAGE)
    only(positional), opts
end

commas(n::Integer) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

# CPU time of the process in seconds, summed over all threads.
cpu_time() = ccall(:clock, Int64, ()) / 1_000_000 # CLOCKS_PER_SEC is 10^6 on POSIX systems.

mutable struct SubState
    received::Int64
    bytes::Int64
    first_ns::UInt64
    last_ns::UInt64
    first_cpu::Float64
    last_cpu::Float64
    first_gc::Union{Nothing, Base.GC_Num}
    last_gc::Union{Nothing, Base.GC_Num}
end

function announce_and_wait(done, msgs)
    println("$(Dates.format(now(), "HH:MM:SS")) Subscribed, expecting $(commas(msgs)) messages")
    flush(stdout)
    wait(done)
end

function write_profile(path, state, elapsed)
    gc = Base.GC_Diff(state.last_gc, state.first_gc)
    open(path, "w") do io
        println(io, "Julia: $VERSION, machine: $(Sys.MACHINE), kernel: $(Sys.KERNEL)")
        println(io, "Threads: default=$(Threads.nthreads(:default)), interactive=$(Threads.nthreads(:interactive)), GC=$(Threads.ngcthreads())")
        println(io, "Messages: $(state.received), payload bytes: $(state.bytes), elapsed: $elapsed s")
        println(io, "Process counters from first to last message:")
        println(io, "  Allocated: $(gc.allocd) bytes ($(Base.gc_alloc_count(gc)) allocations)")
        println(io, "  GC elapsed: $(gc.total_time / 1e9) s, pauses: $(gc.pause), full collections: $(gc.full_sweep)")
        println(io, "\nCPU samples cover subscription readiness through completion, including time waiting for the publisher.")
        println(io, "Profiling adds overhead; measure throughput separately without --profile.\n")
        Profile.print(IOContext(io, :displaysize => (24, 240));
            format = :flat, groupby = :thread, C = true, sortedby = :count)
    end
end

function main(args)
    subject, opts = parse_cli(args, ["msgs", "server", "progress", "profile"])
    msgs = parse(Int64, get(opts, "msgs", "100000"))
    msgs > 0 || error("--msgs must be positive")
    progress = get(opts, "progress", string(stderr isa Base.TTY)) != "false"
    url = get(opts, "server", get(ENV, "NATS_URL", nothing))
    profile_path = get(opts, "profile", nothing)
    if !isnothing(profile_path)
        isempty(profile_path) && error("--profile requires a nonempty path")
        profile_path = abspath(profile_path)
        mkpath(dirname(profile_path))
        println("Profiling enabled; sampling affects throughput. Report: $profile_path")
    end

    Threads.nthreads(:interactive) == 0 &&
        @warn "No interactive threads, NATS.jl IO tasks will compete with handlers. Run with `-t 2,1`."

    nc = isnothing(url) ? NATS.connect() : NATS.connect(url)

    println("$(Dates.format(now(), "HH:MM:SS")) Starting NATS.jl subscriber benchmark [msgs=$(commas(msgs)), subject=$subject]")
    flush(stdout)

    state = SubState(0, 0, 0, 0, 0.0, 0.0, nothing, nothing)
    done = Base.Event()
    sub = subscribe(nc, subject) do msg
        state.received < msgs || return
        state.received += 1
        if state.received == 1
            isnothing(profile_path) || (state.first_gc = Base.gc_num())
            state.first_cpu = cpu_time()
            state.first_ns = time_ns()
        end
        state.bytes += length(msg.payload) - msg.headers_length
        if state.received == msgs
            state.last_ns = time_ns()
            state.last_cpu = cpu_time()
            isnothing(profile_path) || (state.last_gc = Base.gc_num())
            notify(done)
        end
    end
    # PONG means the server processed SUB, so the subscription is active.
    ping(nc; timeout = 10.0, measure = false)

    progress_timer = !progress ? nothing : Timer(1.0; interval = 1.0) do _
        stats = NATS.stats(nc, sub)
        isnothing(stats) && return
        print(stderr, "\rreceived: $(commas(stats.msgs_received)) / $(commas(msgs)), dropped: $(commas(stats.msgs_dropped))")
    end

    if isnothing(profile_path)
        announce_and_wait(done, msgs)
    else
        Profile.clear()
        Profile.@profile announce_and_wait(done, msgs)
    end
    isnothing(progress_timer) || (close(progress_timer); println(stderr))

    # With a single message first and last are the same, avoid dividing by zero.
    elapsed = max(state.last_ns - state.first_ns, 1) / 1e9
    rate = msgs / elapsed
    mib = state.bytes / elapsed / 2^20
    println()
    println("NATS.jl subscriber stats: $(commas(round(Int64, rate))) msgs/sec ~ $(@sprintf("%.1f", mib)) MiB/sec ~ $(@sprintf("%.3f", elapsed)) s ~ ",
        "cpu: $(round(Int, 100 * (state.last_cpu - state.first_cpu) / elapsed))%")

    drain(nc)
    isnothing(profile_path) || write_profile(profile_path, state, elapsed)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
