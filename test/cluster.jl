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

port_to_container = Dict(
    5222 => find_container_id("nats-node-1"),
    5223 => find_container_id("nats-node-2"),
    5224 => find_container_id("nats-node-3")
)

function signal_lame_duck_mode(container_id)
    cmd = `docker exec $container_id nats-server --signal ldm=1`
    result = run(cmd)
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
end

function start_container(container_id)
    cmd = `docker start $container_id`
    result = run(cmd)
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
end

@testset "Request during node switch" begin
    connection = NATS.connect("localhost", 5222, default=false)

    sub = reply("a_topic"; async_handlers = true, connection) do msg
        sleep(7)
        "This is a reply."
    end

    errormonitor(@async begin
        sleep(2)
        signal_lame_duck_mode(port_to_container[5222])
    end)

    response = request(String, "a_topic", timer = Timer(10); connection)

    @test response == "This is a reply."
    @test connection.port != 5222

    sleep(15) # Wait at least 10 s for server exit
    start_container(port_to_container[5222])
    sleep(10)
    @test "localhost:5222" in connection.info.connect_urls
    drain(connection)
end

@testset "No messages lost during node switch." begin
    pub_conn = NATS.connect("localhost", 5222, default=false) # TODO: unclear why echo needs to be false to not have doubled msgs.
    sub_conn = NATS.connect("localhost", 5223, default=false) 
    
    sub_conn_received_count = 0
    sub_conn_results = []
    sub1 = subscribe("a_topic"; async_handlers = false, connection = sub_conn) do msg
        sub_conn_received_count = sub_conn_received_count + 1
        push!(sub_conn_results, payload(msg))
    end

    pub_conn_received_count = 0
    pub_conn_results = []
    sub2 = subscribe("a_topic"; async_handlers = false, connection = pub_conn) do msg
        pub_conn_received_count = pub_conn_received_count + 1
        push!(pub_conn_results, payload(msg))
    end

    sleep(0.5) # TODO: this sleep should be removed?

    errormonitor(@async begin
        sleep(2)
        signal_lame_duck_mode(port_to_container[5222])
    end)

    n = 1500
    start_time = time()
    for i in 1:n
        publish("a_topic"; payload = "$i", connection = pub_conn)
        sleep(0.001)
    end

    sleep(0.1)

    @info "Published $n messages in $(time() - start_time) seconds."
    @info "Distrupted connection received $pub_conn_received_count msgs."

    # TODO: try minimize this closig socket after openning new one.
    @test pub_conn_received_count > n - 5 # allow some messages lost cause sub is disconnected for few ms
    @test unique(pub_conn_results) == pub_conn_results

    @test sub_conn_received_count == n
    @test unique(sub_conn_results) == sub_conn_results

    sleep(15) # Wait at least 10 s for server exit
    start_container(port_to_container[5222])
    sleep(10)

    drain(pub_conn)
    drain(sub_conn)

end
