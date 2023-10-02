
using Test
using NATS
using Random

@testset "Should error when no default connection." begin
    @test_throws ErrorException publish("SOME_SUBJECT"; payload = "Hi!")
end

@testset "Ping" begin
    nc = NATS.connect()
    ping(nc)
    @test true # TODO: add pong count to connection stats
end

@testset "Method error hints." begin
    nc = NATS.connect()
    
    @test_throws MethodError subscribe("SOME.THING") do msg::Float64
        put!(c, msg)
    end
    @test_throws MethodError request("SOME.REQUESTS"; payload = 4)
    @test_throws MethodError reply("SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

@testset "Handler error throttling." begin
    nc = NATS.connect()
    subject = randstring(8)
    sub = subscribe(subject) do msg
        error("Just testing...")
    end

    tm = Timer(15)
    while isopen(tm)
        publish(subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(5) # wait for all errors.

    unsubscribe(sub)
    sleep(0.1)
end

@testset "Handler error throttling async." begin
    nc = NATS.connect()
    subject = randstring(8)
    sub = subscribe(subject, async_handlers = true) do msg
        error("Just testing...")
    end

    tm = Timer(15)
    while isopen(tm)
        publish(subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(5) # wait for all errors.

    unsubscribe(sub)
    sleep(0.1)
end
