using Test
using NATS
using Random

function restart_nats_server()
    io = IOBuffer();
    run(pipeline(`docker ps -f name=nats -q`; stdout = io))
    output = String(take!(io))
    container_id = split(output, '\n')[1]
    cmd = `docker container restart $container_id`
    result = run(cmd)
    if result.exitcode == 0
        @info "Restarted NATS server."
    else
        @warn "Cannot restart NATS server, exit code from $cmd was $(result.exitcode)."
    end
    result.exitcode
end

@testset "Reconnecting." begin
    nc = NATS.connect()
    @test restart_nats_server() == 0
    sleep(5)
    @test nc.status == NATS.CONNECTED
    resp = request("help.please")
    @test resp isa NATS.Message
end

@testset "Subscribtion survive reconnect." begin
    nc = NATS.connect()
    c = Channel(100)
    subject = randstring(5)
    sub = subscribe(subject) do msg
        put!(c, msg)
    end
    sleep(0.5)
    @test restart_nats_server() == 0
    sleep(5)
    @test nc.status == NATS.CONNECTED
    publish(subject; payload = "Hi!")
    sleep(0.5)
    @test Base.n_avail(c) == 1
end

@testset "Reconnect during request." begin
    nc = NATS.connect()
    subject = randstring(5)
    sub = reply(subject) do msg
        sleep(5)
        "This is a reply."
    end
    t = @async begin
        sleep(1)
        restart_nats_server()
    end
    rep = request(subject; timer = Timer(20))
    @test payload(rep) == "This is a reply."
    @test nc.status == NATS.CONNECTED
    rep = request(subject; timer = Timer(20))
    @test payload(rep) == "This is a reply."
    @test t.result == 0
end

@testset "40K requests" begin
    nc = NATS.connect()
    @async interactive_status(tm)

    n = 40000

    subject = @lock NATS.state.lock randstring(5)

    sub = reply(subject) do msg
        sleep(5)
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        t = Threads.@spawn :default begin
            msg = request(subject; timer=Timer(30))
            put!(results, msg)
            if Base.n_avail(results) == n
                close(cond)
                close(results)
            end
        end
        errormonitor(t)
    end
    @async begin sleep(30); close(cond); close(results) end
    sleep(0.5)
    # @test restart_nats_server() == 0
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