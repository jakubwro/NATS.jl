using Test
using NATS
using Random

@info "Running with $(Threads.nthreads()) threads."

function find_container_id(name)
    io = IOBuffer();
    cmd = `docker ps -f name=$name -q`
    result = run(pipeline(cmd; stdout = io))
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
    output = String(take!(io))
    container_id = only(split(output, '\n'; keepempty=false))
    container_id
end

function signal_lame_duck_mode(container_id)
    cmd = `docker exec -it $container_id nats-server --signal ldm=1`
    result = run(cmd)
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
end

function start_container(container_id)
    @show cmd = `docker start $container_id`
    result = run(cmd)
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
end

@testset "Request during node switch" begin
    connection = NATS.connect("localhost", 5222, default=false)

    reply("a_topic"; async_handlers = true, connection) do msg
        sleep(7)
        "This is a reply."
    end

    container_id = find_container_id("nats-node-1")
    @async begin
        sleep(2)
        signal_lame_duck_mode(container_id)
    end

    response = request(String, "a_topic", timer = Timer(10); connection)

    @test response == "This is a reply."
    @test connection.port != 5222

    sleep(15) # Wait at least 10 s for server exit

    start_container(container_id)

    sleep(5)

    @test "localhost:5222" in connection.info.connect_urls
end
