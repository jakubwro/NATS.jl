using Test
using Random
using NATS

@show Threads.nthreads()
@show Threads.nthreads(:interactive)
@show Threads.nthreads(:default)

include("util.jl")

@testset "Warmup" begin
    connection = NATS.connect()
    empty!(NATS.state.fallback_handlers)
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

function msgs_per_second(connection::NATS.Connection, connection2::NATS.Connection, spawn = false)
    empty!(NATS.state.fallback_handlers)
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
    pub = NATS.Pub(subject, nothing, UInt8[], uint8_vec("Hi!"))
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
    while isopen(tm)
        res = request(connection, "help.please")
        counter = counter + 1
    end
    @info "Exteranal service: $counter requests / second."
    NATS.status()
end

@testset "Publisher benchmark." begin
    connection = NATS.connect()

    # pub = NATS.Pub("zxc", nothing, UInt8[], uint8_vec("Hello world!!!!!"))

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

@testset "Subscriber benchmark" begin
    docker_network = get(ENV, "TEST_JOB_CONTAINER_NETWORK", nothing)

    if isnothing(docker_network)
        @info "No docker network specified, skipping benchmarks"
        return
    end

    cmd = `docker run --entrypoint nats synadia/nats-box:latest --server nats:4222 bench foo --sub 1 --pub 1 --size 16`

    io = IOBuffer();
    cmd = `docker ps -f name=$name -q`
    result = run(pipeline(cmd; stdout = io))
    result.exitcode == 0 || error(" $cmd failed with $(result.exitcode)")
    output = String(take!(io))
    println(output)
end
