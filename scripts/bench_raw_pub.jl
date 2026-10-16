# Raw socket publisher, an upper bound for publishing speed. Preformatted `PUB` messages are written
# directly to the socket, without any client library logic. Authentication and TLS are not supported.
#
# Usage:
#     julia scripts/bench_raw_pub.jl foo --size 3 --msgs 1000000
#
# Options:
#     --msgs=N           number of messages to publish, default 100000
#     --size=SIZE        payload size, e.g. 3, 128B, 1KB, default 128B
#     -s, --server=URL   server url, default `NATS_URL` env or nats://127.0.0.1:4222
#
# Throughput is measured from the first write until PONG confirms that the server processed all messages.
# CPU usage of the process is measured in the same time window, 100% means one core.

using Sockets
using Dates
using Printf

const USAGE = "Usage: julia scripts/bench_raw_pub.jl <subject> [--size=SIZE] [--msgs=N] [--server=URL]"

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

function parse_server(url::AbstractString)
    m = match(r"^(?:nats://)?(\[[^\]]+\]|[^:/\[]+)(?::(\d+))?/?$", url)
    isnothing(m) && error("Invalid server url: $url")
    strip(m[1], ['[', ']']), isnothing(m[2]) ? 4222 : parse(Int, m[2])
end

commas(n::Integer) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

# CPU time of the process in seconds, summed over all threads.
cpu_time() = ccall(:clock, Int64, ()) / 1_000_000 # CLOCKS_PER_SEC is 10^6 on POSIX systems.

# Sends PING and waits for PONG, what means the server processed everything sent before.
function flush_server(sock)
    write(sock, "PING\r\n")
    while true
        line = readline(sock)
        line == "PONG" && return
        line == "PING" && write(sock, "PONG\r\n")
        startswith(line, "-ERR") && error("Server error: $line")
        isempty(line) && eof(sock) && error("Connection closed by server.")
    end
end

# Preformatted messages, about 1 MiB in total, written to the socket with a single call.
function pub_chunk(subject, size)
    frame = Vector{UInt8}("PUB $subject $size\r\n" * "a"^size * "\r\n")
    repeat(frame, max(1, 2^20 ÷ length(frame))), length(frame)
end

function main(args)
    subject, opts = parse_cli(args, ["msgs", "size", "server"])
    msgs = parse(Int64, get(opts, "msgs", "100000"))
    msgs > 0 || error("--msgs must be positive")
    size = parse_size(get(opts, "size", "128B"))
    host, port = parse_server(get(opts, "server", get(ENV, "NATS_URL", "nats://127.0.0.1:4222")))

    sock = Sockets.connect(host, port)
    info = readline(sock)
    startswith(info, "INFO") || error("Expected INFO from server, got: $info")
    write(sock, "CONNECT {\"verbose\":false,\"pedantic\":false}\r\n")
    flush_server(sock)

    # Compile the write path before measuring, on a subject nobody listens to.
    warmup, _ = pub_chunk("_BENCH_WARMUP.$(getpid())", size)
    write(sock, warmup)
    flush_server(sock)

    println("$(Dates.format(now(), "HH:MM:SS")) Starting raw socket publisher benchmark [msg-size=$(commas(size)) B, msgs=$(commas(msgs)), subject=$subject]")
    flush(stdout)

    chunk, frame_length = pub_chunk(subject, size)
    full_chunks, rest = divrem(msgs, length(chunk) ÷ frame_length)
    last_chunk = chunk[1:rest * frame_length]
    start_cpu = cpu_time()
    start = time_ns()
    for _ in 1:full_chunks
        write(sock, chunk)
    end
    write(sock, last_chunk)
    flush_server(sock)
    elapsed = (time_ns() - start) / 1e9
    cpu = cpu_time() - start_cpu

    println()
    println("Raw socket publisher stats: $(commas(round(Int64, msgs / elapsed))) msgs/sec ~ $(@sprintf("%.1f", msgs * size / elapsed / 2^20)) MiB/sec ~ ",
        "cpu: $(round(Int, 100 * cpu / elapsed))%")
    close(sock)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
