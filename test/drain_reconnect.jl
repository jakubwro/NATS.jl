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
                @test sub.sid in nc.draining_sids

                notify(release)
                @test timedwait(() -> istaskdone(draining), 5.0) == :ok
                fetch(draining)
                @test !haskey(nc.sub_data, sub.sid)
                @test isempty(nc.draining_sids)
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

@testset "Draining an absent subscription is a no-op" begin
    nc = offline_connection()
    sub = NATS.subscribe(nc, "drain.again")
    take_wire(nc)
    @test NATS.drain(nc, sub) === nothing
    @test take_wire(nc) == "UNSUB $(sub.sid) 0\r\n"
    @test !haskey(nc.sub_data, sub.sid)
    for status in (NATS.CONNECTED, NATS.DRAINED)
        NATS.status(nc, status)
        @test NATS.drain(nc, sub) === nothing
        @test isempty(take_wire(nc))
    end
end

@testset "Buffered synchronous subscriptions stay excluded until consumed" begin
    nc = offline_connection()
    sub = NATS.subscribe(nc, "drain.buffered")
    NATS.unsubscribe(nc, sub; max_msgs = 2)
    take_wire(nc)
    parser = NATS.ParserData()
    NATS.parse_buffer(IOBuffer(), Vector{UInt8}("MSG drain.buffered $(sub.sid) 1\r\nx\r\n"), parser)
    NATS.process(nc, parser.results)

    # A timeout closes the channel but keeps its buffered message available to next.
    @test_logs (:error, r"Timeout for drain exceeded") NATS.drain(nc, sub; timeout = 0.0)
    @test haskey(nc.sub_data, sub.sid)
    @test haskey(nc.unsubs, sub.sid)
    @test sub.sid in nc.draining_sids
    take_wire(nc) # UNSUB has reached the old server.
    NATS.reopen_send_buffer(nc)
    @test isempty(take_wire(nc))

    @test NATS.payload(NATS.next(nc, sub)) == "x"
    @test !haskey(nc.sub_data, sub.sid)
    @test isempty(nc.unsubs)
    @test isempty(nc.draining_sids)
end

@testset "Connection shutdown cannot race the subscription lookup" begin
    nc = offline_connection()
    sub = NATS.subscribe(nc, "drain.shutdown")
    take_wire(nc)
    entered = Base.Event()
    draining = nothing
    lock(nc.send_buffer_cond)
    try
        draining = @async begin
            notify(entered)
            NATS.drain(nc, sub)
        end
        # This same-thread task must block on the buffer lock before looking up the subscription.
        wait(entered)
        @test !istaskdone(draining)
        NATS.cleanup_sub_resources(nc, sub.sid)
        NATS.status(nc, NATS.DRAINED)
    finally
        unlock(nc.send_buffer_cond)
    end
    @test timedwait(() -> istaskdone(draining), 5.0) == :ok
    @test fetch(draining) === nothing
    @test isempty(take_wire(nc))
end

end # module
