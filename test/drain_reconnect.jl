# Run without a server: julia --project=. --threads=4,1 test/drain_reconnect.jl
module DrainReconnectTests

using Test
using NATS

function offline_connection()
    NATS.Connection(;
        url = "nats://", status = NATS.CONNECTED, info = nothing,
        send_enqueue_when_disconnected = true,
        pong_count = 0, pong_received_at = 0.0,
        connect_init_count = 0, reconnect_count = 0,
        send_buffer_flushed = true, drain_timeout = 5.0, drain_poll = 0.001,
        request_counter = 0, request_subscription = nothing)
end

take_wire(nc) = @lock nc.send_buffer_cond String(take!(nc.send_buffer))

@testset "Reconnect does not restore draining subscriptions" begin
    for unsub_sent in (false, true)
        @testset "UNSUB already sent: $unsub_sent" begin
            nc = offline_connection()
            started = Base.Event()
            release = Base.Event()
            sub = NATS.subscribe(nc, "drain.reconnect"; queue_group = "workers") do msg
                notify(started)
                wait(release)
            end
            active = NATS.subscribe(nc, "keep.subscribed")
            take_wire(nc) # Both SUBs have reached the original server.

            parser = NATS.ParserData()
            wire = "MSG drain.reconnect $(sub.sid) 1\r\nx\r\n"
            NATS.parse_buffer(IOBuffer(), Vector{UInt8}(wire), parser)
            NATS.process(nc, parser.results)
            @test timedwait(() -> (@atomic started.set), 5.0) == :ok

            draining = @async NATS.drain(nc, sub)
            try
                @test timedwait(5.0) do
                    @lock nc.send_buffer_cond nc.send_buffer.size > 0
                end == :ok
                @test !istaskdone(draining) # The handler still owns a message.
                unsub = "UNSUB $(sub.sid) 0\r\n"
                if unsub_sent
                    @test take_wire(nc) == unsub
                end

                # Reconnect while the handler is running, before local cleanup.
                NATS.reopen_send_buffer(nc)
                restored = take_wire(nc)
                expected = sprint(show, NATS.MIME_PROTOCOL(), active)
                @test restored == expected * (unsub_sent ? "" : unsub)
                @test haskey(nc.sub_data, sub.sid)

                notify(release)
                @test timedwait(() -> istaskdone(draining), 5.0) == :ok
                fetch(draining)
                @test !haskey(nc.sub_data, sub.sid)
                @test (@atomic nc.stats.msgs_handled) == 1
                @test (@atomic nc.stats.msgs_dropped) == 0
                @test isempty(take_wire(nc))
            finally
                notify(release)
                NATS.cleanup_sub_resources(nc, sub.sid)
                NATS.cleanup_sub_resources(nc, active.sid)
            end
        end
    end
end

end # module
