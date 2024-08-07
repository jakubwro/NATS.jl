using Test
using Random
using NATS

@show Threads.nthreads()
@show Threads.nthreads(:interactive)
@show Threads.nthreads(:default)

include("util.jl")

@testset "Warmup" begin
    connection = NATS.connect()
    empty!(connection.fallback_handlers)
    c = Channel(1000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 1.0
    tm = Timer(time_to_wait_s)
    sub = subscribe(connection, subject) do msg
        if isopen(tm)
            try put!(c, msg) catch err @error err end
        end
    end
    publish(connection, subject, "Hi!")
    drain(connection, sub)
    close(c)
    NATS.status()
end

@testset "Pub-sub latency" begin
    nc = NATS.connect()
    published_time = 0.0
    received_time = 0.0
    nsamples = 26
    with_connection(nc) do
        subscribe("latency") do msg
            received_time = time()
        end
        
        latencies = []
        for i in 1:nsamples
            published_time = time()
            publish("latency", "This is payload!")
            sleep(0.25)
            diff = 1000 * (received_time - published_time)
            i == 1 || push!(latencies, diff) # skip first - compilation included
        end
        @info "Latencies in ms: $(round.(latencies, digits = 2))"
        @info "min: $(minimum(latencies)), max: $(maximum(latencies)), avg: $(sum(latencies)/length(latencies))"
    end
    drain(nc)
end

@testset "Request-reply latency" begin
    nc = NATS.connect()
    published_time = 0.0
    received_time = 0.0
    nsamples = 26
    with_connection(nc) do
        reply("latency") do msg
            return "This is a reply!"
        end
        
        latencies = []
        for i in 1:nsamples
            @timed _, tm = @timed request("latency", "This is request!")
            i == 1 || push!(latencies, 1000*tm)
        end
        @info "Latencies in ms: $(round.(latencies, digits = 2))"
        @info "min: $(minimum(latencies)), max: $(maximum(latencies)), avg: $(sum(latencies)/length(latencies))"
    end
    drain(nc)
end

function msgs_per_second(connection::NATS.Connection, connection2::NATS.Connection, spawn = false)
    empty!(connection.fallback_handlers)
    c = Channel(100000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 10.0
    tm = Timer(time_to_wait_s)
    msgs_after_timeout = Threads.Atomic{Int64}(0)
    time_first_pub = 0.0
    time_first_msg = 0.0
    sub = subscribe(connection, subject; spawn) do msg
        if time_first_msg == 0.0
            time_first_msg = time()
        end
        if isopen(tm)
            try put!(c, msg) catch err @error err end
        else 
            Threads.atomic_add!(msgs_after_timeout, 1)
        end
    end
    sleep(1)
    t = Threads.@spawn :default begin
        @time while isopen(tm)
            if time_first_pub == 0.0
                time_first_pub = time()
            end
            publish(connection2, subject, "Hi!")
            # NATS.send(connection2, pub)

        end
        drain(connection, sub)
    end
    errormonitor(t)
    # @async interactive_status(tm)
    wait(t)
    received = Base.n_avail(c)
    @info "Received $received messages in $time_to_wait_s s, $(received / time_to_wait_s) msgs / s."
    NATS.status()
    @show connection.stats connection2.stats msgs_after_timeout[]
    @show (time_first_msg - time_first_pub)
    sleep(1)
end

@testset "Msgs per second." begin
    connection = NATS.connect()
    msgs_per_second(connection, connection)
end

@testset "Msgs per second with async handlers." begin
    connection = NATS.connect()
    msgs_per_second(connection, connection, true)
end

@testset "Requests per second with sync handlers." begin
    sleep(5) # Wait for buffers flush from previous tests.
    connection = NATS.connect()
    subject = randstring(5)
    sub = reply(connection, subject) do msg
        "This is a reply."
    end
    counter = 0
    tm = Timer(1.0)
    while isopen(tm)
        res = request(connection, subject)
        counter = counter + 1
    end
    drain(connection, sub)
    @info "Sync handlers: $counter requests / second."
    NATS.status()
end

@testset "Requests per second with async handlers." begin
    connection = NATS.connect()
    subject = randstring(5)
    sub = reply(connection, subject; spawn = true) do msg
        "This is a reply."
    end
    counter = 0
    tm = Timer(1.0)
    while isopen(tm)
        res = request(connection, subject)
        counter = counter + 1
    end
    drain(connection, sub)
    @info "Async handlers: $counter requests / second."
    NATS.status()
end

@testset "External requests per second." begin
    connection = NATS.connect()
    counter = 0
    tm = Timer(1.0)
    response = try request(connection, "help.please") catch err; err end
    if response isa NATSError && response.code == 503
        @info "No external service working, skipping test"
        return
    end
    
    while isopen(tm)
        res = request(connection, "help.please")
        counter = counter + 1
    end
    @info "Exteranal service: $counter requests / second."
    NATS.status()
end

@testset "Publisher benchmark." begin
    connection = NATS.connect()

    tm = Timer(1.0)
    counter = 0
    c = 0
    while isopen(tm)
        publish(connection, "zxc", "Hello world!!!!!")
        counter = counter + 1
        c += 1
        if c == 10000
            c = 0
            yield()
        end
    end

    @info "Published $counter messages."
end

@testset "Publisher benchmark with `nats bench`" begin
    docker_network = get(ENV, "TEST_JOB_CONTAINER_NETWORK", nothing)

    if isnothing(docker_network)
        @info "No docker network specified, skipping benchmarks"
        return
    end

    conn = NATS.connect()

    n = 1000000
    t = @async begin
        cmd = `docker run --network $docker_network -e GITHUB_ACTIONS=true -e CI=true --entrypoint nats synadia/nats-box:latest --server nats:4222 bench foo --sub 1 --pub 0 --size 16 --msgs $n`
        io = IOBuffer();
        result = run(pipeline(cmd; stdout = io))
        # result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
        output = String(take!(io))
        println(output)
    end
    
    sleep(1)

    first_msg_time = time()
    for i in 1:n
        publish(conn, "foo", "This is payload!")
    end
    last_msg_time = time()

    try
        wait(t)
    finally
        drain(conn)
    end
    sleep(1)
    @show conn.stats
    total_time = last_msg_time - first_msg_time
    @info "Performance is $( n / total_time) msgs/sec"
end

@testset "Subscriber benchmark with `nats bench`" begin
    docker_network = get(ENV, "TEST_JOB_CONTAINER_NETWORK", nothing)

    if isnothing(docker_network)
        @info "No docker network specified, skipping benchmarks"
        return
    end

    conn = NATS.connect()

    n = 1000000
    received_count = 0
    first_msg_time = 0.0
    last_msg_time = 0.0
    sub = subscribe(conn, "foo") do msg
            if first_msg_time == 0.0
                 first_msg_time = time()
            end
            received_count += 1
            if received_count == n
                last_msg_time = time()
            end
          end
    sleep(0.1) # Give server time to process sub.
    t = @async begin
        cmd = `docker run --network $docker_network -e GITHUB_ACTIONS=true -e CI=true --entrypoint nats synadia/nats-box:latest --server nats:4222 bench foo --pub 1 --size 16 --msgs $n`
        io = IOBuffer();
        result = run(pipeline(cmd; stdout = io))
        # result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
        output = String(take!(io))
        println(output)
    end
    
    try
        wait(t)
    finally
        drain(conn)
    end
    sleep(1)
    @show conn.stats
    total_time = last_msg_time - first_msg_time
    @info "Received $received_count messages from $n expected"
    if received_count == n
        @info "Performance is $( n / total_time) msgs/sec"
    end
end

@testset "Benchmark msgs / sec roundtrip" begin
    nc = NATS.connect()
    function subscribe_until_timeout(nc::NATS.Connection, timeout = 1.0)
        tm = Timer(timeout)
        counter = 0
        start = nothing
        sub = subscribe(nc, "foo") do
            if isnothing(start)
                start = time()
            end
            counter += 1
        end
        wait(tm)
        unsubscribe(nc, sub)
        if counter == 0
            @info "No messages"
        else
            @info "Processed $counter messages in $(time() - start) s. $(counter / (time() - start)) msgs/sec)"
        end
        counter
    end

    bench_task = @async begin
        sub_task = Threads.@spawn :default subscribe_until_timeout(nc, 1.0)
        Threads.@spawn :default while !istaskdone(sub_task)
            publish(nc, "foo", "This is payload!")
        end
        wait(sub_task)
        sub_task.result
    end
    _, tm = @timed wait(bench_task);
    received_messages = bench_task.result
    @info "$(received_messages / tm) msgs / sec"
end