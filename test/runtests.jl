using NATS
using Test
using JSON3
using Sockets

using NATS: next_protocol_message
using NATS: Info, Msg, Ping, Pong, Ok, Err, HMsg, Pub, HPub, Sub, Unsub, Connect
using NATS: Headers, headers, header
using NATS: MIME_PROTOCOL, MIME_PAYLOAD, MIME_HEADERS

include("util.jl")

@info "Running with $(Threads.nthreads()) threads."

include("utils.jl")
include("protocol_parsing.jl")

function have_nats()
    try
        Sockets.getaddrinfo(NATS.NATS_HOST)
        nc = NATS.connect()
        sleep(2)
        @assert nc.status == NATS.CONNECTED
        @info "NATS avaliable, running connected tests."
        true
    catch err
        @info "NATS unavailable, skipping connected tests."  err
        false
    end
end

if have_nats()
    include("core_nats.jl")
    include("fallback_handler.jl")
    include("jetstream.jl")
    include("worker.jl")

    if haskey(ENV, "CI")
        include("chaos.jl")
    else
        @info "Chaos testing disabled outside CI."
    end
end

