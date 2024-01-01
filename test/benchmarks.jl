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
    unsubscribe(connection, sub)
    sleep(2)
    close(c)
    NATS.status()
end

function msgs_per_second(connection::NATS.Connection, connection2::NATS.Connection, spawn = false)
    empty!(NATS.state.fallback_handlers)
    c = Channel(100000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 10.0
    tm = Timer(time_to_wait_s)
    sub = subscribe(connection, subject; spawn) do msg
        if isopen(tm)
            try put!(c, msg) catch err @error err end
        end
    end
    pub = NATS.Pub(subject, nothing, UInt8[], uint8_vec("Hi!"))
    # TLS connection is much slower, give it smaller batches.
    batch_size = if something(connection2.info.tls_required, false) 150 else 150000 end
    batch = repeat([pub], batch_size)
    t = Threads.@spawn :default begin
        while isopen(tm)
            # Using `try_send` to not grow send buffer too much.
            NATS.try_send(connection2, batch)
            sleep(0.01)
        end
        unsubscribe(connection, sub)
    end
    errormonitor(t)
    # @async interactive_status(tm)
    wait(t)
    received = Base.n_avail(c)
    @info "Received $received messages in $time_to_wait_s s, $(received / time_to_wait_s) msgs / s."
    NATS.status()
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
    unsubscribe(connection, sub)
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
    unsubscribe(connection, sub)
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