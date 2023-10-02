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
include("protocol.jl")

function is_nats_available()
    try
        Sockets.getaddrinfo(NATS.NATS_HOST)
        nc = NATS.connect(default = false)
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

@testset "Shuold run connected tests" begin
    @test have_nats
end

if have_nats
    include("connection.jl")
    include("pubsub.jl")
    include("reqreply.jl")
    include("fallback_handler.jl")

    @testset "All subs should be closed" begin
        @test isempty(NATS.state.handlers)

        connections = NATS.Connection[]
        if !isnothing(NATS.state.default_connection)
            push!(connections, NATS.state.default_connection)
        end
        append!(connections, NATS.state.connections)

        for nc in connections
            @test isempty(nc.subs)
            @test isempty(nc.unsubs)
            @test Base.n_avail(nc.outbox) == 0
        end
    end

    NATS.status()
end
