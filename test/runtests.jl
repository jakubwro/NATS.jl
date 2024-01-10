using NATS
using Test
using JSON3
using Sockets

using NATS: next_protocol_message
using NATS: Info, Msg, Ping, Pong, Ok, Err, Pub, Sub, Unsub, Connect
using NATS: Headers, headers, header
using NATS: MIME_PROTOCOL, MIME_PAYLOAD, MIME_HEADERS

include("util.jl")

@show Threads.nthreads()
@show Threads.nthreads(:interactive)
@show Threads.nthreads(:default)

include("protocol.jl")

function is_nats_available()
    try
        url = get(ENV, "NATS_CONNECT_URL", NATS.DEFAULT_CONNECT_URL)
        host, port = NATS.host_port(url)
        Sockets.getaddrinfo(host)
        nc = NATS.connect()
        sleep(5)
        @assert nc.status == NATS.CONNECTED
        @info "NATS avaliable, running connected tests."
        true
    catch err
        @info "NATS unavailable, skipping connected tests."  err
        false
    end
end

have_nats = is_nats_available()

@testset "Should run connected tests" begin
    @test have_nats
end

if have_nats
    include("connection.jl")
    include("pubsub.jl")
    include("reqreply.jl")
    # include("channel.jl")
    include("fallback_handler.jl")
    include("experimental.jl")

    @testset "All subs should be closed" begin
        sleep(5)
        for nc in NATS.state.connections
            @test isempty(nc.sub_data)
            @test isempty(nc.unsubs)
            if nc.send_buffer.size > 0
                @info "Buffer content" String(nc.send_buffer.data[begin:nc.send_buffer.size])
            end
            @test nc.send_buffer.size == 0
        end
    end

    NATS.status()
end
