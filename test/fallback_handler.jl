
using Test
using NATS

@testset "Test fallback handler" begin
    nc = NATS.connect()
    sub = subscribe("SOME.BAR") do msg
        @show msg
    end
    empty!(NATS.state.handlers) # Break state of connection to force fallback handler.
    publish("SOME.BAR"; payload = "Hi!")
    sleep(0.5) # Wait for compilation.
    @test nc.stats.msgs_not_handled > 0
    unsubscribe(sub)
end

@testset "Test custom fallback handler" begin
    nc = NATS.connect()
    empty!(NATS.state.fallback_handlers)
    was_called = false
    push!(NATS.state.fallback_handlers, (nc, msg) -> begin
            was_called = true
            @info "Custom fallback called." msg
        end
    )
    sub = subscribe("SOME.FOO") do msg
        @show msg
    end
    empty!(NATS.state.handlers) # Break state of connection to force fallback handler.
    publish("SOME.FOO"; payload = "Hi!")
    sleep(0.5) # Wait for compilation.
    @test nc.stats.msgs_not_handled > 0
    @test was_called
    unsubscribe(sub)
end

NATS.status()
