
using Test
using NATS

@testset "Test fallback handler" begin
    sub = subscribe(nc, "SOME.BAR") do msg
        @show msg
    end
    empty!(nc.sub_data) # Break state of connection to force fallback handler.
    publish(nc, "SOME.BAR", "Hi!")
    sleep(2) # Wait for compilation.
    @test nc.stats.msgs_dropped > 0
    drain(nc, sub)
end

NATS.status()

@testset "Test custom fallback handler" begin
    empty!(nc.fallback_handlers)
    was_called = false
    NATS.install_fallback_handler(nc) do nc, msg
        was_called = true
        @info "Custom fallback called." msg
    end
    sub = subscribe(nc, "SOME.FOO") do msg
        @show msg
    end
    empty!(nc.sub_data) # Break state of connection to force fallback handler.
    publish(nc, "SOME.FOO", "Hi!")
    sleep(0.5) # Wait for compilation.
    @test nc.stats.msgs_dropped > 0
    @test was_called
    drain(nc, sub)
end

NATS.status()
