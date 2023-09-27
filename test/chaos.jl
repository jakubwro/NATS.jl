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

@testset "Subscribtions survive reconnect." begin
    nc = NATS.connect()
    c = Channel(100)
    subject = randstring(5)
    sub = subscribe(subject) do msg
        put!(c, msg)
    end
    @test restart_nats_server() == 0
    sleep(5)
    @test nc.status == NATS.CONNECTED
    publish(subject; payload = "Hi!")
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
    resp = request(subject; timer = Timer(20))
    @test nc.status == NATS.CONNECTED
    rep = request(subject)
    @test payload(rep) == "This is a reply."
    @test t.result == 0
end