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
#
# Throughput is measured from the first to the last expected message. CPU usage of the process
# is measured in the same time window, 100% means one core.

using NATS
using Dates
using Printf

const USAGE = "Usage: julia --project=. -t 2,1 scripts/bench_sub.jl <subject> [--msgs=N] [--server=URL] [--[no-]progress]"

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
end

function main(args)
    subject, opts = parse_cli(args, ["msgs", "server", "progress"])
    msgs = parse(Int64, get(opts, "msgs", "100000"))
    msgs > 0 || error("--msgs must be positive")
    progress = get(opts, "progress", string(stderr isa Base.TTY)) != "false"
    url = get(opts, "server", get(ENV, "NATS_URL", nothing))

    Threads.nthreads(:interactive) == 0 &&
        @warn "No interactive threads, NATS.jl IO tasks will compete with handlers. Run with `-t 2,1`."

    nc = isnothing(url) ? NATS.connect() : NATS.connect(url)

    println("$(Dates.format(now(), "HH:MM:SS")) Starting NATS.jl subscriber benchmark [msgs=$(commas(msgs)), subject=$subject]")
    flush(stdout)

    state = SubState(0, 0, 0, 0, 0.0, 0.0)
    done = Base.Event()
    sub = subscribe(nc, subject) do msg
        state.received < msgs || return
        state.received += 1
        if state.received == 1
            state.first_cpu = cpu_time()
            state.first_ns = time_ns()
        end
        state.bytes += length(msg.payload) - msg.headers_length
        if state.received == msgs
            state.last_ns = time_ns()
            state.last_cpu = cpu_time()
            notify(done)
        end
    end
    # PONG means the server processed SUB, so the subscription is active.
    ping(nc; timeout = 10.0, measure = false)
    println("$(Dates.format(now(), "HH:MM:SS")) Subscribed, expecting $(commas(msgs)) messages")
    flush(stdout)

    progress_timer = !progress ? nothing : Timer(1.0; interval = 1.0) do _
        stats = NATS.stats(nc, sub)
        isnothing(stats) && return
        print(stderr, "\rreceived: $(commas(stats.msgs_received)) / $(commas(msgs)), dropped: $(commas(stats.msgs_dropped))")
    end

    wait(done)
    isnothing(progress_timer) || (close(progress_timer); println(stderr))

    # With a single message first and last are the same, avoid dividing by zero.
    elapsed = max(state.last_ns - state.first_ns, 1) / 1e9
    rate = msgs / elapsed
    mib = state.bytes / elapsed / 2^20
    println()
    println("NATS.jl subscriber stats: $(commas(round(Int64, rate))) msgs/sec ~ $(@sprintf("%.1f", mib)) MiB/sec ~ $(@sprintf("%.3f", elapsed)) s ~ ",
        "cpu: $(round(Int, 100 * (state.last_cpu - state.first_cpu) / elapsed))%")

    drain(nc)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
