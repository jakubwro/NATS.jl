using Test
using NATS

function restart_nats_server()
    io = IOBuffer();
    run(pipeline(`docker ps -f name=nats -q`; stdout = io))
    output = String(take!(io))
    container_id = split(output, '\n')[1]
    run(`docker container restart $container_id`)
end

@testset "Chaos tests." begin
    nc = NATS.connect()
    restart_nats_server()
    sleep(5)
    @test nc.status == NATS.CONNECTED
    resp = request("help.please")
    @test resp isa NATS.Message
end
