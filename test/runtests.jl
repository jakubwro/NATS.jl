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
include("parser_fragmentation.jl")
include("reconnect_events.jl")

function is_nats_available()
    try
        url = get(ENV, "NATS_CONNECT_URL", NATS.DEFAULT_CONNECT_URL)
        host, port = NATS.host_port(url)
        Sockets.getaddrinfo(host)
        nc = NATS.connect()
        NATS.ping(nc; timeout = 10.0, measure = false)
        @assert NATS.status(nc) == NATS.CONNECTED
        @info "NATS available, running connected tests."
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
        connections = lock(NATS.state.lock) do
            copy(NATS.state.connections)
        end
        settled = timedwait(10.0) do
            all(connections) do nc
                subs_closed = lock(nc.lock) do
                    isempty(nc.sub_data) && isempty(nc.unsubs)
                end
                buffer_empty = lock(nc.send_buffer_cond) do
                    nc.send_buffer.size == 0
                end
                subs_closed && buffer_empty
            end
        end
        @test settled == :ok
        for nc in connections
            lock(nc.lock) do
                @test isempty(nc.sub_data)
                @test isempty(nc.unsubs)
            end
            lock(nc.send_buffer_cond) do
                if nc.send_buffer.size > 0
                    @info "Buffer content" String(nc.send_buffer.data[begin:nc.send_buffer.size])
                end
                @test nc.send_buffer.size == 0
            end
        end
    end

    NATS.status()
end
