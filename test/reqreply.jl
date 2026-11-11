using Test
using NATS
using Random
using JSON3

@testset "Request reply" begin
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

NATS.status()

@testset "Request multiple replies." begin
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

NATS.status()

@testset "4K requests" begin
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
    NATS.status()
end

NATS.status()

@testset "4K requests external" begin
    
    try
        request(nc, "help.please")
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
end

NATS.status()

@testset "No responders." begin
    @test_throws NATSError request(nc, "SOME.NULL")
end

NATS.status()

@testset "Typed request reply tests" begin
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

NATS.status()

@testset "Request reply with headers" begin
    sub = reply(nc, "SOME.REQUESTS") do msg
        "This is a reply.", ["A" => "B"]
    end
    result = request(nc, "SOME.REQUESTS")
    drain(nc, sub)
    @test result isa NATS.Msg
    @test payload(result) == "This is a reply."
    @test headers(result) == ["A" => "B"]
end

NATS.status()

@testset "Request timeout is not delayed by draining" begin
    subject = randstring(10)
    connection = NATS.connect(; drain_poll = 1.0)
    sub = subscribe(connection, subject) do msg end # Nobody replies.
    # Draining the reply subscription on timeout would delay returning by `drain_poll`.
    elapsed = @elapsed @test_throws NATSError request(connection, subject; timeout = 0.3)
    @test elapsed < 0.3 + 0.6
    @test length(connection.sub_data) == 1 # Only the `sub`, reply subscription is cleaned up.
    @test isempty(connection.unsubs)
    drain(connection)
end

NATS.status()

@testset "Requests do not leave timers behind" begin
    connection = NATS.connect()
    sub = reply(connection, randstring(10)) do msg "OK" end
    growth = active_handles_growth() do
        for _ in 1:100
            request(connection, sub.subject)
        end
    end
    @test growth < 20 # A single timer serves all the requests.
    @test isempty(connection.request_deadlines)
    drain(connection)
end

NATS.status()

@testset "Requests time out each at its own deadline" begin
    connection = NATS.connect()
    subject = randstring(10)
    subscribe(connection, subject) do msg end # Nobody replies.
    # The timer is armed for the request that has the longest timeout, shorter ones have to arm it for earlier deadlines.
    long = Threads.@spawn request(connection, 1, subject; timeout = 30, stop_on_status = Int[])
    @test timedwait(() -> length(connection.request_deadlines) == 1, 10.0) == :ok
    timeouts = [0.6, 0.2, 0.4]
    durations = fetch.([Threads.@spawn(@elapsed request(connection, 1, subject; timeout, stop_on_status = Int[])) for timeout in timeouts])
    @test all(i -> timeouts[i] - 0.001 <= durations[i] < timeouts[i] + 0.6, eachindex(timeouts))
    @test !istaskdone(long)
    @test length(connection.request_deadlines) == 1
    # Timers armed for requests with a shorter timeout do not stay behind while the long one is waiting.
    echo = reply(connection, randstring(10)) do msg "OK" end
    growth = active_handles_growth() do
        for _ in 1:20
            request(connection, echo.subject; timeout = 0.05)
            sleep(0.06) # Until the timer armed for the request fires.
        end
    end
    @test growth < 10
    drain(connection) # Ends the request that is still waiting.
    @test isempty(fetch(long))
    @test isempty(connection.request_deadlines)
end

NATS.status()

@testset "Request ending early on an error status frees its subscription at once" begin
    connection = NATS.connect(; drain_poll = 1.0)
    # Nobody listens on the subject, so the server replies with the 503 status instead of the 3 expected replies.
    elapsed = @elapsed replies = request(connection, 3, randstring(10))
    @test length(replies) == 1
    @test NATS.statuscode(only(replies)) == 503
    @test elapsed < 0.5 # Draining the subscription would take `drain_poll`.
    @test isempty(connection.sub_data)
    @test isempty(connection.unsubs)
    drain(connection)
end

NATS.status()

@testset "Request stops on specified status codes" begin
    connection = NATS.connect()
    codes(replies) = NATS.statuscode.(replies)

    # By default every error status ends the request. The late reply is released after the request finished,
    # so it is not waiting in the subscription buffer when the request unsubscribes.
    subject = randstring(10)
    release = Channel(1)
    subscribe(connection, subject) do msg
        reply_with_status(connection, msg, 500)
    end
    subscribe(connection, subject) do msg
        take!(release)
        publish(connection, msg.reply_to, "Late reply.")
    end
    replies = request(connection, 2, subject)
    @test codes(replies) == [500]
    put!(release, true)

    # Only 503 ends the request here, so the 500 status is collected as any other reply.
    subject = randstring(10)
    subscribe(connection, subject) do msg
        reply_with_status(connection, msg, 500)
    end
    subscribe(connection, subject) do msg
        publish(connection, msg.reply_to, "Another reply.")
    end
    replies = request(connection, 2, subject; stop_on_status = [503])
    @test sort(codes(replies)) == [200, 500]

    # A status that is not an error can end the request too.
    subject = randstring(10)
    release = Channel(1)
    subscribe(connection, subject) do msg
        publish(connection, msg.reply_to, "First reply.")
        reply_with_status(connection, msg, 204)
        take!(release)
        publish(connection, msg.reply_to, "Dropped reply.")
    end
    replies = request(connection, 3, subject; stop_on_status = [204])
    @test codes(replies) == [200, 204]
    put!(release, true)

    # With an empty collection nothing stops the request early. The 503 sent when there are no responders
    # is collected and the request lasts until the timeout.
    elapsed = @elapsed replies = request(connection, 2, randstring(10); timeout = 0.3, stop_on_status = Int[])
    @test codes(replies) == [503]
    @test elapsed >= 0.3

    drain(connection)
end

NATS.status()
