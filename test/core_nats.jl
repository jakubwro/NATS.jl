
using Test
using NATS
using Random

@testset "Ping" begin
    nc = NATS.connect()
    ping(nc)
    @test true # TODO: add pong count to connection stats
end

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

@testset "Request reply" begin
    nc = NATS.connect()
    sub = reply("SOME.REQUESTS") do msg
        "This is a reply."
    end
    result, tm = @timed request("SOME.REQUESTS")
    @info "First reply time was $(1000 * tm) ms."
    result, tm = @timed request("SOME.REQUESTS")
    @info "Second reply time was $(1000 * tm) ms."
    unsubscribe(sub)
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
end

@testset "4K requests" begin
    nc = NATS.connect()
    n = 4000

    subject = @lock NATS.state.lock randstring(5)

    sub = reply(subject) do msg
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        t = Threads.@spawn :default begin
            msg =   if haskey(ENV, "CI")
                        request(subject; timer=Timer(20))
                    else
                        request(subject)
                    end
            put!(results, msg)
            if Base.n_avail(results) == n
                close(cond)
                close(results)
            end
        end
        errormonitor(t)
    end
    @async begin sleep(20); close(cond); close(results) end
    if !haskey(ENV, "CI")
        @async NATS.istatus(cond)
    end
    try take!(cond) catch end
    unsubscribe(sub)
    replies = collect(results)
    @test length(replies) == n
    @test all(r -> r.payload == "This is a reply.", replies)
    NATS.status()
end

@testset "4K requests external" begin
    nc = NATS.connect()
    
    try
        request("help.please")
    catch
        @info "Skipping \"4K requests external\" testset. Ensure `nats reply help.please 'OK, I CAN HELP!!!'` is running."
        return
    end

    n = 4000
    results = Channel(n)
    cond = Channel()
    t = @timed begin
        for _ in 1:n
            t = @async begin #TODO: add error monitor.
                msg = request("help.please")
                put!(results, msg)
                if Base.n_avail(results) == n
                    close(cond)
                    close(results)
                end
            end
        end
        @async begin sleep(30); close(cond); close(results) end
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
    @test_throws ErrorException request("SOME.NULL")
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

@testset "Typed request reply tests" begin
    nc = NATS.connect()
    sub = reply("SOME.REQUESTS") do msg::String
        "Received $msg"
    end
    result = request("SOME.REQUESTS", "Hi!")
    unsubscribe(sub)
    @test result isa NATS.Msg
    @test payload(result) == "Received Hi!"
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

@testset "Request reply with headers" begin
    nc = NATS.connect()
    sub = reply("SOME.REQUESTS") do msg
        "This is a reply.", ["A" => "B"]
    end
    result = request("SOME.REQUESTS")
    unsubscribe(sub)
    @test result isa NATS.HMsg
    @test payload(result) == "This is a reply."
    @test headers(result) == ["A" => "B"]
end

@testset "All subs should be closed" begin
    nc = NATS.connect()
    @test isempty(NATS.state.handlers)
    @test isempty(nc.unsubs)
end

NATS.status()