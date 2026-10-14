
using Test
using NATS

@testset "Test fallback handler" begin
    sub = subscribe(nc, "SOME.BAR") do msg
        @show msg
    end
    @lock nc.lock empty!(nc.sub_data) # Break state of connection to force fallback handler.
    dropped_before = @atomic nc.stats.msgs_dropped
    publish(nc, "SOME.BAR", "Hi!")
    @test timedwait(() -> (@atomic nc.stats.msgs_dropped) > dropped_before,
        10.0; pollint = 0.01) == :ok
    drain(nc, sub)
end

NATS.status()

@testset "Test custom fallback handler" begin
    @lock nc.lock empty!(nc.fallback_handlers)
    was_called = Threads.Atomic{Bool}(false)
    NATS.install_fallback_handler(nc) do nc, msg
        was_called[] = true
        @info "Custom fallback called." msg
    end
    sub = subscribe(nc, "SOME.FOO") do msg
        @show msg
    end
    @lock nc.lock empty!(nc.sub_data) # Break state of connection to force fallback handler.
    dropped_before = @atomic nc.stats.msgs_dropped
    publish(nc, "SOME.FOO", "Hi!")
    @test timedwait(() -> was_called[] && (@atomic nc.stats.msgs_dropped) > dropped_before,
        10.0; pollint = 0.01) == :ok
    drain(nc, sub)
end

NATS.status()
