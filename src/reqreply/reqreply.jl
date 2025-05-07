### reqreply.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains aggregates utils for request - reply pattern.
#
### Code:

include("request.jl")
include("reply.jl")

@testitem "Request reply" setup=[GetConnection] begin
    sub = reply(nc, "SOME.REQUESTS") do msg
        "This is a reply."
    end
    result, tm = @timed request(nc, "SOME.REQUESTS")
    @info "First reply time was $(1000 * tm) ms."
    result, tm = @timed request(nc, "SOME.REQUESTS")
    @info "Second reply time was $(1000 * tm) ms."
    drain(nc, sub)
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
end

@testitem "Request multiple replies." setup=[GetConnection] begin
    using Random

    subject = randstring(10)
    sub1 = reply(nc, subject) do msg
        "Reply from service 1."
    end
    sub2 = reply(nc, subject) do msg
        "Reply from service 2."
    end
    results = request(nc, 2, subject, "This is request payload")
    drain(nc, sub1)
    drain(nc, sub2)
    @test length(results) == 2
    payloads = payload.(results)
    @test "Reply from service 1." in payloads
    @test "Reply from service 2." in payloads
end

@testitem "4K requests" setup=[GetConnection] begin
    using Random 

    n = 4000

    subject = @lock NATS.state.lock randstring(5)

    sub = reply(nc, subject) do msg
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        t = Threads.@spawn :default begin
            msg =   if haskey(ENV, "CI")
                        request(nc, subject; timeout=20)
                    else
                        request(nc, subject)
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
    unsubscribe(nc, sub)
    replies = collect(results)
    @test length(replies) == n
    @test all(r -> payload(r) == "This is a reply.", replies)
end

@testitem "4K requests external" setup=[GetConnection] begin
    try
        request(nc, "help.please")

        n = 4000
        results = Channel(n)
        cond = Channel()
        t = @timed begin
            for _ in 1:n
                t1 = @async begin #TODO: add error monitor.
                    msg = request(nc, "help.please")
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
        @test all(r -> payload(r) == "OK, I CAN HELP!!!", replies)
        @info "Total time of $n requests is $(t.time) s, average $(1000 * t.time / n) ms per request."
    catch err
        if err isa NATSError
            @info "Skipping \"4K requests external\" testset. Ensure `nats reply help.please 'OK, I CAN HELP!!!'` is running."
        else
            rethrow()
        end
    end
end

@testitem "No responders." setup=[GetConnection] begin
    @test_throws NATSError request(nc, "SOME.NULL")
end

@testitem "Typed request reply tests" setup=[GetConnection] begin
    using JSON3

    sub = reply(nc, "SOME.REQUESTS") do msg::String
        "Received $msg"
    end
    result = request(String, nc, "SOME.REQUESTS", "Hi!")
    drain(nc, sub)
    @test result isa String
    @test result == "Received Hi!"

    sub = reply(nc, "SOME.REQUESTS") do msg::JSON3.Object
        word = msg[:message]
        JSON3.read("""{"reply": "This is a reply for '$word'"}""")
    end
    result = request(JSON3.Object, nc, "SOME.REQUESTS", JSON3.read("""{"message": "Hi!"}"""))
    drain(nc, sub)
    @test result[:reply] == "This is a reply for 'Hi!'"
end

@testitem "Request reply with headers" setup=[GetConnection] begin
    sub = reply(nc, "SOME.REQUESTS") do msg
        "This is a reply.", ["A" => "B"]
    end
    result = request(nc, "SOME.REQUESTS")
    drain(nc, sub)
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
    @test headers(result) == ["A" => "B"]
end
