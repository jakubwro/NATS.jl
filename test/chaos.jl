using Test
using NATS
using Random

function find_nats_container_id()
    io = IOBuffer();
    run(pipeline(`docker ps -f name=nats -q`; stdout = io))
    output = String(take!(io))
    @show output
    container_id = split(output, '\n')[1]
    container_id
end

function restart_nats_server(container_id = find_nats_container_id())
    cmd = `docker container restart $container_id`
    @info "Cmd is $cmd"
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

@testset "4K requests" begin
    nats_container_id = find_nats_container_id()
    @info "NATS container is $nats_container_id"
    nc = NATS.connect()
    @async interactive_status(tm)

    n = 4000

    subject = @lock NATS.state.lock randstring(5)
    cnt = Threads.Atomic{Int64}(0)
    sub = reply(subject) do msg
        sleep(10 * rand())
        Threads.atomic_add!(cnt, 1)
        "This is a reply."
    end
    results = Channel(n)
    cond = Channel()
    for _ in 1:n
        t = Threads.@spawn :default begin
            msg = request(subject; timer=Timer(15))
            put!(results, msg)
            if Base.n_avail(results) == n
                close(cond)
                close(results)
            end
        end
        errormonitor(t)
    end
    @async begin sleep(20); close(cond); close(results) end
    sleep(5)
    @info "Received $(Base.n_avail(results)) / $n results after half of time. "
    @test restart_nats_server(nats_container_id) == 0
    if !haskey(ENV, "CI")
        @async interactive_status(cond)
    end
    try take!(cond) catch end
    unsubscribe(sub)
    replies = collect(results)
    @info "Replies count is $(cnt.value)."
    @test length(replies) == n
    @test all(r -> r.payload == "This is a reply.", replies)
    NATS.status()
end