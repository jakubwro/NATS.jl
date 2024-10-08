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
    4222 => find_container_id("nats-node-1"),
    4223 => find_container_id("nats-node-2"),
    4224 => find_container_id("nats-node-3")
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
    connection = NATS.connect("localhost:4222")

    sub = reply(connection, "a_topic"; spawn = true) do msg
        sleep(7)
        "This is a reply."
    end

    errormonitor(@async begin
        sleep(2)
        signal_lame_duck_mode(port_to_container[4222])
    end)

    start_time = time()
    response = request(String, connection, "a_topic", timeout = 15)
    @info "Response time was $(time() - start_time)"

    @test response == "This is a reply."
    @show connection.url
    @test !endswith(connection.url, ":4222")

    sleep(15) # Wait at least 10 s for server exit
    start_container(port_to_container[4222])
    sleep(10)
    @test "localhost:4222" in connection.info.connect_urls
    drain(connection)
end

@testset "No messages lost during node switch." begin
    pub_conn = NATS.connect("localhost:4222") # TODO: unclear why echo needs to be false to not have doubled msgs.
    sub_conn = NATS.connect("localhost:4223") 
    
    sub_conn_received_count = 0
    sub_conn_results = []
    sub1 = subscribe(sub_conn, "a_topic"; spawn = false) do msg
        sub_conn_received_count = sub_conn_received_count + 1
        push!(sub_conn_results, payload(msg))
    end

    pub_conn_received_count = 0
    pub_conn_results = []
    sub2 = subscribe(pub_conn, "a_topic"; spawn = false) do msg
        pub_conn_received_count = pub_conn_received_count + 1
        push!(pub_conn_results, payload(msg))
    end

    sleep(0.5) # TODO: this sleep should be removed?

    errormonitor(@async begin
        sleep(2)
        signal_lame_duck_mode(port_to_container[4222])
    end)

    n = 1500
    start_time = time()
    for i in 1:n
        publish(pub_conn, "a_topic", "$i")
        sleep(0.001)
    end
    @info "Published $n messages in $(time() - start_time) seconds."

    sleep(0.1)

    @info "Distrupted connection received $pub_conn_received_count msgs."

    @test pub_conn_received_count > n - 5
    @test pub_conn_received_count <= n
    @test unique(pub_conn_results) == pub_conn_results
    @show first(pub_conn_results) last(pub_conn_results)

    @test sub_conn_received_count == n
    @test unique(sub_conn_results) == sub_conn_results
    @show first(sub_conn_results) last(sub_conn_results)

    sleep(15) # Wait at least 10 s for server exit
    start_container(port_to_container[4222])
    sleep(10)

    drain(pub_conn)
    drain(sub_conn)

    @show NATS.state.stats

end

@testset "Lame Duck Mode during heavy publications" begin
    connection = NATS.connect("localhost:4222")
    subscription_connection = NATS.connect("localhost:4224")

    received_count = Threads.Atomic{Int64}(0)
    published_count = Threads.Atomic{Int64}(0)
    subject = "pub_subject"
    sub = subscribe(subscription_connection, subject) do msg
        Threads.atomic_add!(received_count, 1)
    end
    sleep(0.5)

    pub_task = Threads.@spawn begin
        # publishes 100k msgs / s for 10s (roughly)
        for i in 1:10000
            timer = Timer(0.001)
            for _ in 1:100
                publish(connection, subject, "Hi!")
            end
            Threads.atomic_add!(published_count, 100)
            try wait(timer) catch end
        end
        @info "Publisher finished."
    end
    sleep(2)
    @info "Published: $(published_count.value), received: $(received_count.value)."
    sleep(2)
    signal_lame_duck_mode(port_to_container[4222])

    while !istaskdone(pub_task)
        sleep(2)
        @info "Published: $(published_count.value), received: $(received_count.value)."
    end
    sleep(5) # Wait all messages delivered
    unsubscribe(connection, sub)
    @info "Published: $(published_count.value), received: $(received_count.value)."

    @test published_count[] == received_count.value[]

    sleep(15) # Wait at least 10 s for server exit
    start_container(port_to_container[4222])
    sleep(10)
    @test "localhost:4222" in connection.info.connect_urls
    drain(connection)
end


# @testset "Switch sub connection." begin
#     conn_a = NATS.connect("localhost", 4222)
#     conn_b = NATS.connect("localhost", 4223) 

#     subject = "switch"

#     sub = subscribe(subject; connection = conn_a) do msg
#         @show msg
#     end

#     @async for i in 1:10
#         publish(subject; payload = "$i", connection = conn_a)
#         sleep(1)
#     end

#     sleep(5)
#     unsubscribe(sub; connection = conn_a)
#     NATS.send(conn_b, sub)

#     # unsubscribe(sub; connection = conn_a)

# end