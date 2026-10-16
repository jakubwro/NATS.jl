# Publisher benchmark, works like `nats bench pub <subject> --size <size> --msgs <n>`.
#
# Usage:
#     julia --project=. -t 2,1 scripts/bench_pub.jl foo --size 3 --msgs 1000000
#
# Start a subscriber first to measure end to end, e.g. `nats bench sub foo --msgs 1000000`.
#
# Options:
#     --msgs=N           number of messages to publish, default 100000
#     --size=SIZE        payload size, e.g. 3, 128B, 1KB, default 128B
#     -s, --server=URL   server url, default `NATS_URL` env or NATS.jl default
#
# Throughput is measured from the first publish until the server confirms with PONG
# that all messages were processed, like `nc.Flush()` in `nats bench`. Latency is
# the time spent in a single `publish` call. CPU usage of the process is measured in
# the same time window, 100% means one core.

using NATS
using Dates
using Printf

const USAGE = "Usage: julia --project=. -t 2,1 scripts/bench_pub.jl <subject> [--size=SIZE] [--msgs=N] [--server=URL]"

function parse_cli(args, known)
    positional = String[]
    opts = Dict{String, String}()
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "-h" || arg == "--help"
            println(USAGE)
            exit(0)
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

function parse_size(s::AbstractString)
    m = match(r"^(\d+)\s*([kmg]?)i?b?$"i, strip(s))
    isnothing(m) && error("Invalid --size value: $s")
    unit = lowercase(m[2])
    parse(Int64, m[1]) * 1024^(isempty(unit) ? 0 : findfirst(==(only(unit)), "kmg"))
end

commas(n::Integer) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

# CPU time of the process in seconds, summed over all threads.
cpu_time() = ccall(:clock, Int64, ()) / 1_000_000 # CLOCKS_PER_SEC is 10^6 on POSIX systems.

function publish_all!(latencies::Vector{Int64}, nc::NATS.Connection, subject::String, payload::String)
    for i in eachindex(latencies)
        t0 = time_ns()
        publish(nc, subject, payload)
        latencies[i] = Int64(time_ns() - t0)
    end
end

function main(args)
    subject, opts = parse_cli(args, ["msgs", "size", "server"])
    msgs = parse(Int64, get(opts, "msgs", "100000"))
    msgs > 0 || error("--msgs must be positive")
    size = parse_size(get(opts, "size", "128B"))
    url = get(opts, "server", get(ENV, "NATS_URL", nothing))

    Threads.nthreads(:interactive) == 0 &&
        @warn "No interactive threads, NATS.jl IO tasks will compete with the publisher. Run with `-t 2,1`."

    nc = isnothing(url) ? NATS.connect() : NATS.connect(url)
    payload = repeat("a", size)

    # Compile the publish path before measuring, on a subject nobody listens to. Publish enough
    # to fill the send buffer a few times, so waiting for the space in it is compiled as well.
    warmup_msgs = cld(4 * nc.send_buffer_limit, size + 32)
    publish_all!(zeros(Int64, warmup_msgs), nc, "_BENCH_WARMUP.$(getpid())", payload)
    ping(nc; timeout = 10.0, measure = false)

    println("$(Dates.format(now(), "HH:MM:SS")) Starting NATS.jl publisher benchmark [msg-size=$(commas(size)) B, msgs=$(commas(msgs)), subject=$subject]")
    flush(stdout)

    latencies = zeros(Int64, msgs)
    start_cpu = cpu_time()
    start = time_ns()
    publish_all!(latencies, nc, subject, payload)
    ping(nc; timeout = 60.0, measure = false)
    elapsed = (time_ns() - start) / 1e9
    cpu = cpu_time() - start_cpu

    sort!(latencies)
    us(ns) = @sprintf("%.2fus", ns / 1000)
    pct(p) = us(latencies[clamp(ceil(Int, p * msgs), 1, msgs)])
    rate = msgs / elapsed
    mib = msgs * size / elapsed / 2^20
    println()
    println("NATS.jl publisher stats: $(commas(round(Int64, rate))) msgs/sec ~ $(@sprintf("%.1f", mib)) MiB/sec ~ ",
        "min: $(us(first(latencies))) ~ avg: $(us(sum(latencies) / msgs)) ~ max: $(us(last(latencies))) ~ ",
        "P50: $(pct(0.5)) ~ P90: $(pct(0.9)) ~ P99: $(pct(0.99)) ~ P99.9: $(pct(0.999)) ~ ",
        "cpu: $(round(Int, 100 * cpu / elapsed))%")

    drain(nc)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
