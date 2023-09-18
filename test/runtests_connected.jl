
using Test
using NATS

@testset "Publish subscribe tests" begin
    nc = NATS.connect()
    c = Channel()
    sub = subscribe(nc, "SOME.BAR") do msg
        put!(c, msg)
    end
    publish(nc, "SOME.BAR"; payload = "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(nc.handlers) == 1
    unsubscribe(nc, sub)
    sleep(0.1)
    @test length(nc.handlers) == 0
end

@testset "Request reply tests" begin
    nc = NATS.connect()
    sub = reply(nc, "SOME.REQUESTS") do msg
        "This is a reply."
    end
    result = request(nc, "SOME.REQUESTS")
    unsubscribe(nc, sub)
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
end

@testset "4K requests" begin
    nc = NATS.connect()
    n = 4000
    sub = reply(nc, "SOME.REQUESTS") do msg
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        @async begin
            msg = request(nc, "SOME.REQUESTS")
            put!(results, msg)
            if Base.n_avail(results) == n
                close(cond)
                close(results)
            end
        end
    end
    try take!(cond) catch end
    unsubscribe(nc, sub)
    replies = collect(results)
    @test length(replies) == n
    @test all(r -> r.payload == "This is a reply.", replies)
end

@testset "4K requests external" begin
    nc = NATS.connect()
    n = 1000
    results = Channel(n)
    cond = Channel()
    t = @timed begin
        for _ in 1:n
            @async begin
                msg = request(nc, "help.please")
                put!(results, msg)
                if Base.n_avail(results) == n
                    close(cond)
                    close(results)
                end
            end
        end
        try take!(cond) catch end
        replies = collect(results)
    end
    replies = t.value
    @test length(replies) == n
    @test all(r -> r.payload == "OK, I CAN HELP!!!", replies)
    @info "Total time of $n requests is $(t.time) s, average $(1000 * t.time / n) ms per request."
end

@testset "No responders." begin
    nc = NATS.connect()
    @test_throws ErrorException request(nc, "SOME.NULL")
end


@testset "Typed subscription handlers" begin
    nc = NATS.connect()
    c = Channel()

    sub = subscribe(nc, "SOME.BAR") do msg::String
        put!(c, msg)
    end
    publish(nc, "SOME.BAR"; payload = "Hi!")
    result = take!(c)
    @test result == "Hi!"
    @test length(nc.handlers) == 1
    unsubscribe(nc, sub)
    sleep(0.1)
    @test length(nc.handlers) == 0
end


@testset "Typed request reply tests" begin
    nc = NATS.connect()
    sub = reply(nc, "SOME.REQUESTS") do msg::String
        "Received $msg"
    end
    result = request(nc, "SOME.REQUESTS"; payload = "Hi!")
    unsubscribe(nc, sub)
    @test result isa NATS.Msg
    @test payload(result) == "Received Hi!"
end

@testset "Method error hints." begin
    nc = NATS.connect()
    
    @test_throws MethodError subscribe(nc, "SOME.THING") do msg::Float64
        put!(c, msg)
    end
    @test_throws MethodError request(nc, "SOME.REQUESTS"; payload = 4)
    @test_throws MethodError reply(nc, "SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end
