
using Test
using NATS

@testset "Publish subscribe tests" begin
    nc = NATS.connect()
    c = Channel()
    sub, = subscribe(nc, "FOO.BAR") do msg
        put!(c, msg)
    end
    publish(nc, "FOO.BAR"; payload = "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(nc.subs) == 1
    NATS.unsubscribe(nc, sub)
    sleep(0.1)
    @test length(nc.subs) == 0
end

@testset "Request reply tests" begin
    nc = NATS.connect()
    subscribe(nc, "FOO.REQUESTS") do msg
        "This is a reply."
    end
    result = request(nc, "FOO.REQUESTS")
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
end
