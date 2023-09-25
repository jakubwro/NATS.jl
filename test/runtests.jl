using NATS
using Test
using JSON3
using Sockets
using Threads

using NATS: next_protocol_message
using NATS: Info, Msg, Ping, Pong, Ok, Err, HMsg, Pub, HPub, Sub, Unsub, Connect
using NATS: Headers, headers, header
using NATS: MIME_PROTOCOL, MIME_PAYLOAD, MIME_HEADERS

@info "Running with $(Threads.nthreads()) threads."

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
        @info "NATS unavailable, skipping connected tests." 
        false
    end
end

if have_nats()
    include("core_nats.jl")
    include("fallback_handler.jl")
    include("jetstream.jl")
    include("worker.jl")
end