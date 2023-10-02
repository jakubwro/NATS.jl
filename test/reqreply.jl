using Test
using NATS
using Random

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

@testset "Request multiple replies." begin
    nc = NATS.connect()
    subject = randstring(10)
    sub1 = reply(subject) do msg
        "Reply from service 1."
    end
    sub2 = reply(subject) do msg
        "Reply from service 2."
    end
    results = request(subject, "This is request payload", 2)
    unsubscribe(sub1)
    unsubscribe(sub2)
    sleep(0.1)
    @test length(results) == 2
    payloads = payload.(results)
    @test "Reply from service 1." in payloads
    @test "Reply from service 2." in payloads
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
    @async begin sleep(40); close(cond); close(results) end
    if !haskey(ENV, "CI")
        @async interactive_status(cond)
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

@testset "Typed request reply tests" begin
    nc = NATS.connect()
    sub = reply("SOME.REQUESTS") do msg::String
        "Received $msg"
    end
    result = request(String, "SOME.REQUESTS", "Hi!")
    unsubscribe(sub)
    @test result isa String
    @test result == "Received Hi!"
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
