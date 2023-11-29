using Test
using Random
using NATS

@show Threads.nthreads()
@show Threads.nthreads(:interactive)
@show Threads.nthreads(:default)

include("util.jl")

@testset "Warmup" begin
    connection = NATS.connect(default = false)
    empty!(NATS.state.fallback_handlers)
    c = Channel(1000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 1.0
    tm = Timer(time_to_wait_s)
    sub = subscribe(subject; connection) do msg
        if isopen(tm)
            try put!(c, msg) catch err @error err end
        end
    end
    publish(subject; payload = "Hi!", connection)
    unsubscribe(sub; connection)
    sleep(2)
    close(c)
    NATS.status()
end

function msgs_per_second(connection::NATS.Connection, connection2::NATS.Connection, async_handlers = false)
    empty!(NATS.state.fallback_handlers)
    c = Channel(100000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 10.0
    tm = Timer(time_to_wait_s)
    sub = subscribe(subject; connection, async_handlers) do msg
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
        unsubscribe(sub; connection)
    end
    errormonitor(t)
    # @async interactive_status(tm)
    wait(t)
    received = Base.n_avail(c)
    @info "Received $received messages in $time_to_wait_s s, $(received / time_to_wait_s) msgs / s."
    NATS.status()
end

@testset "Msgs per second." begin
    connection = NATS.connect(default = false)
    msgs_per_second(connection, connection)
end

@testset "Msgs per second with async handlers." begin
    sleep(5)
    connection = NATS.connect(default = false)
    msgs_per_second(connection, connection, true)
end

@testset "Requests per second with sync handlers." begin
    connection = NATS.connect(default = false)
    subject = randstring(5)
    sub = reply(subject; connection) do msg
        "This is a reply."
    end
    counter = 0
    tm = Timer(1.0)
    while isopen(tm)
        res = request(subject; connection)
        counter = counter + 1
    end
    unsubscribe(sub; connection)
    @info "Sync handlers: $counter requests / second."
    NATS.status()
end

@testset "Requests per second with async handlers." begin
    connection = NATS.connect(default = false)
    subject = randstring(5)
    sub = reply(subject; connection, async_handlers = true) do msg
        "This is a reply."
    end
    counter = 0
    tm = Timer(1.0)
    while isopen(tm)
        res = request(subject; connection)
        counter = counter + 1
    end
    unsubscribe(sub; connection)
    @info "Async handlers: $counter requests / second."
    NATS.status()
end

@testset "External requests per second." begin
    connection = NATS.connect(default = false)
    counter = 0
    tm = Timer(1.0)
    while isopen(tm)
        res = request("help.please"; connection)
        counter = counter + 1
    end
    @info "Exteranal service: $counter requests / second."
    NATS.status()
end

@testset "Publisher benchmark." begin
    connection = NATS.connect(default = false)

    # pub = NATS.Pub("zxc", nothing, UInt8[], uint8_vec("Hello world!!!!!"))

    tm = Timer(1.0)
    counter = 0
    c = 0
    while isopen(tm)
        publish("zxc"; payload = "Hello world!!!!!", connection)
        counter = counter + 1
        c += 1
        if c == 10000
            c = 0
            yield()
        end
    end

    @info "Published $counter messages."
end