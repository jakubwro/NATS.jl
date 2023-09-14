
using Test
using NATS

@testset "Publish subscribe tests" begin
    nc = NATS.connect()
    c = Channel()
    sub = subscribe(nc, "FOO.BAR") do msg
        @show "Received"
        put!(c, msg)
    end
    publish(nc, "FOO.BAR"; payload = "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(nc.handlers) == 1
    NATS.unsubscribe(nc, sub)
    sleep(0.1)
    @test length(nc.handlers) == 0
end

@testset "Request reply tests" begin
    nc = NATS.connect()
    sub = reply(nc, "FOO.REQUESTS") do msg
        "This is a reply."
    end
    result = request(nc, "FOO.REQUESTS")
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
end

@testset "Many requests." begin
    nc = NATS.connect()
    n = 4000
    sub = reply(nc, "FOO.REQUESTS") do msg
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        @async begin
            msg = request(nc, "FOO.REQUESTS")
            put!(results, msg)
            if Base.n_avail(results) == n
                close(cond)
                close(results)
            end
        end
    end
    try take!(cond) catch end
    NATS.unsubscribe(nc, sub)
    replies = collect(results)
    @test length(replies) == n
    @test all(r -> r.payload == "This is a reply.", replies)
end

@testset "No responders." begin
    nc = NATS.connect()
    @test_throws ErrorException request(nc, "FOO.NULL")
end
