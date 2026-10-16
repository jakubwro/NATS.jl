# Run without a server: julia +1.10 --project=. test/reconnect_events.jl
using Test
using NATS

@testset "Reconnect event lifecycle" begin
    function offline_connection(status = NATS.CONNECTED)
        NATS.Connection(;
            url = "nats://", status, info = nothing,
            send_enqueue_when_disconnected = true,
            pong_count = 0, pong_received_at = 0.0,
            connect_init_count = 0, reconnect_count = 0,
            send_buffer_flushed = true, drain_timeout = 0.1, drain_poll = 0.0)
    end

    function finishes(f)
        result = timedwait(f, 5.0; pollint = 0.001)
        @test result == :ok
        result == :ok
    end

    @testset "Already connecting is a no-op" begin
        for should_wait in (false, true)
            nc = offline_connection(NATS.CONNECTING)
            NATS.reconnect(nc; should_wait)
            @test !(@atomic nc.reconnect_event.set)
        end
    end

    @testset "A late sender keeps its closed buffer" begin
        nc = offline_connection()
        old_buffer = nc.send_buffer
        write(old_buffer, "pending")
        output = IOBuffer()
        sender = Task(() -> NATS.sendloop(nc, output, old_buffer))

        # Replace the buffer before the old connection's sender gets to run.
        NATS.reopen_send_buffer(nc)
        schedule(sender)
        try
            if finishes(() -> istaskdone(sender))
                fetch(sender)
                @test !isopen(old_buffer)
                @test isopen(nc.send_buffer)
                @test isempty(take!(output))
                @test String(take!(nc.send_buffer)) == "pending"
            end
        finally
            # Also release a regressed sender that picked up the replacement buffer.
            NATS.reopen_send_buffer(nc)
            finishes(() -> istaskdone(sender))
        end
    end

    @testset "A sender waiting for the buffer lock notices replacement" begin
        nc = offline_connection()
        old_buffer = nc.send_buffer
        write(old_buffer, "pending")
        output = IOBuffer()
        started = Base.Event()
        sender = nothing

        lock(nc.send_buffer_cond)
        try
            sender = @async begin
                notify(started)
                NATS.sendloop(nc, output, old_buffer)
            end
            # The sender runs on this thread until it blocks on the held lock,
            # after passing its outer isopen check.
            wait(started)
            NATS.reopen_send_buffer(nc)
        finally
            unlock(nc.send_buffer_cond)
        end

        try
            if finishes(() -> istaskdone(sender))
                fetch(sender)
                @test !isopen(old_buffer)
                @test isempty(take!(output))
                @test String(take!(nc.send_buffer)) == "pending"
            end
        finally
            # Release a regressed sender that missed the replacement notification.
            @lock nc.send_buffer_cond notify(nc.send_buffer_cond)
            finishes(() -> istaskdone(sender))
        end
    end

    @testset "A late heartbeat keeps its original reconnect count" begin
        nc = offline_connection()
        reconnect_count = @atomic nc.reconnect_count
        heartbeat = Task(() -> NATS.ping_loop(nc, 0.001, 0, reconnect_count))

        @atomic nc.reconnect_count += 1
        schedule(heartbeat)
        try
            if finishes(() -> istaskdone(heartbeat))
                fetch(heartbeat)
                @test isempty(take!(nc.send_buffer))
            end
        finally
            NATS.status(nc, NATS.DRAINED)
            finishes(() -> istaskdone(heartbeat))
        end
    end

    @testset "A completed transition still releases reconnect callers" begin
        for final_status in (NATS.CONNECTED, NATS.DISCONNECTED, NATS.DRAINED)
            nc = offline_connection()
            caller = @async try
                NATS.reconnect(nc)
                :returned
            catch err
                err
            end
            try
                if finishes(() -> (@atomic nc.reconnect_event.set))
                    lock(nc.status_change_cond) do
                        # The caller cannot reacquire the lock until both transitions finish.
                        first_status = final_status == NATS.DRAINED ? NATS.DRAINING : NATS.CONNECTING
                        NATS.status(nc, first_status)
                        NATS.status(nc, final_status)
                    end
                    if finishes(() -> istaskdone(caller))
                        result = fetch(caller)
                        if final_status == NATS.DRAINED
                            @test result isa ErrorException
                        else
                            @test result == :returned
                        end
                        @test NATS.status(nc) == final_status
                    end
                end
            finally
                # A caller using only the current status can miss CONNECTING.
                NATS.status(nc, NATS.CONNECTING)
                finishes(() -> istaskdone(caller))
            end
        end
    end

    @testset "Each disconnected request starts one retry batch" begin
        # The empty host fails validation before DNS or Sockets.connect.
        # A retry delay also lets cleanup run if a stale event causes a loop.
        nc = NATS.connect("nats://"; retry_on_init_fail = true,
            reconnect_delays = [0.001], drain_timeout = 0.1, drain_poll = 0.0)
        try
            for should_wait in (false, true)
                finishes(() -> NATS.status(nc) == NATS.DISCONNECTED) || break
                previous_attempts = @atomic nc.connect_init_count
                expected_attempts = previous_attempts + 2
                # Bound even a blocking reconnect if its notification is lost.
                caller = @async NATS.reconnect(nc; should_wait)
                finishes(() -> istaskdone(caller)) || break
                fetch(caller)
                batch_finished = finishes() do
                    attempts = @atomic nc.connect_init_count
                    attempts >= expected_attempts &&
                        (NATS.status(nc) == NATS.DISCONNECTED || attempts > expected_attempts)
                end
                if batch_finished
                    @test NATS.status(nc) == NATS.DISCONNECTED
                    @test (@atomic nc.connect_init_count) == expected_attempts
                    @test !(@atomic nc.reconnect_event.set)
                end
                batch_finished || break
            end
        finally
            draining = @async NATS.drain(nc)
            if finishes(() -> istaskdone(draining))
                fetch(draining)
                @test NATS.status(nc) == NATS.DRAINED
            end
        end
    end
end
