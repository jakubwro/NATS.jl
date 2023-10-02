
using Test
using NATS
using Random

@testset "Publish subscribe" begin
    nc = NATS.connect()
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

@testset "Typed subscription handlers" begin
    nc = NATS.connect()
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


@testset "Publish subscribe with headers" begin
    nc = NATS.connect()
    c = Channel()
    sub = subscribe("SOME.BAR") do msg
        put!(c, msg)
    end
    publish("SOME.BAR"; payload = "Hi!", headers = ["A" => "B"])
    result = take!(c)
    @test result isa NATS.HMsg
    @test payload(result) == "Hi!"
    @test headers(result) == ["A" => "B"]
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0
end

@testset "Subscription without argument" begin
    nc = NATS.connect()
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

@testset "Subscription with multiple arguments" begin
    nc = NATS.connect()
    subject = randstring(8)
    # TODO: test if error message is clear.
    @test_throws MethodError subscribe(subject) do x, y, z
        "nothing to do"
    end
end
