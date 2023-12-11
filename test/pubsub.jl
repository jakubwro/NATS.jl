
using Test
using NATS
using Random

@testset "Publish subscribe" begin
    c = Channel()
    sub = subscribe("SOME.BAR") do msg
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0
end

NATS.status()

@testset "Publish subscribe with sync handlers" begin
    connection = NATS.connect(default = false)
    c = Channel()
    sub = subscribe("SOME.BAR"; connection) do msg
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!", connection)
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub; connection)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0

    c = Channel()
    sub = subscribe("SOME.BAR"; connection) do msg::String
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!", connection)
    result = take!(c)
    unsubscribe(sub; connection)
    @test result == "Hi!"
end

NATS.status()

@testset "Typed subscription handlers" begin
    c = Channel()

    sub = subscribe("SOME.BAR") do msg::String
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!")
    result = take!(c)
    @test result == "Hi!"
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0
end

NATS.status()

@testset "Publish subscribe with headers" begin
    c = Channel()
    sub = subscribe("SOME.BAR") do msg
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!", headers = ["A" => "B"])
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test headers(result) == ["A" => "B"]
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0
end

NATS.status()

@testset "Subscription without argument" begin
    subject = randstring(8)
    was_delivered = false
    sub = subscribe(subject) do
        was_delivered = true
        "nothing to do"
    end
    publish(subject, payload = "Hi!")
    sleep(1)
    unsubscribe(sub)
    @test was_delivered
end

NATS.status()

@testset "Subscription with multiple arguments" begin
    subject = randstring(8)
    # TODO: test if error message is clear.
    @test_throws MethodError subscribe(subject) do x, y, z
        "nothing to do"
    end
end

NATS.status()
