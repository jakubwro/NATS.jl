# Run without a server: julia --project=. test/reconnect_events.jl
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
