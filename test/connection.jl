
using Test
using NATS
using Random

NATS.status()

nc = NATS.connect()

@testset "Ping" begin
    ping(nc)
    @test true # TODO: add pong count to connection stats
end

NATS.status()

@testset "Show connection status" begin
    @test startswith(repr(nc), "NATS.Connection(")
end

NATS.status()

@testset "Publication subscription stats should be counted from nested spawned task." begin
    conn = NATS.connect()
    sub = subscribe(conn, "stats_test") do 
        Threads.@spawn begin
            Threads.@spawn publish(conn, "some_other_subject", "Some payload")
        end
    end
    sleep(0.1)
    publish(conn, "stats_test")
    sleep(0.1)
    @test conn.stats.msgs_published == 2
    sub_stats = conn.sub_data[sub.sid].stats
    @test sub_stats.msgs_published == 1
    drain(conn, sub)
end

NATS.status()

@testset "Method error hints." begin
    # hint = """To use `Type{Float64}` as parameter of subscription handler apropriate conversion from `Type{NATS.Msg}` must be provided.
    #         ```
    #         import Base: convert
            
    #         function convert(::Type{Type{Float64}}, msg::Msg)
    #             # Implement conversion logic here.
    #         end
    #         """
    @test_throws MethodError subscribe(nc, "SOME.THING") do msg::Float64 end
    @test_throws MethodError request(nc, "SOME.REQUESTS", 4)
    # hint = """Object of type `Int64` cannot be serialized into payload."""
    @test_throws MethodError request(nc, 4, "SOME.REQUESTS", 4) # TODO: in this case there should be rather warning about missing payload.
    # hint = """To use `Type{Integer}` as parameter of subscription handler apropriate conversion from `Type{NATS.Msg}` must be provided.
    #         ```
    #         import Base: convert
            
    #         function convert(::Type{Type{Integer}}, msg::Msg)
    #             # Implement conversion logic here.
    #         end
    #         """
    @test_throws MethodError reply(nc, "SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

@testset "Connection url schemes" begin
    try
        @test_throws Base.IOError NATS.connect("tls://localhost:4321")

        conn = NATS.connect("nats://username:passw0rd@localhost:4222")
        @test NATS.status(conn) == NATS.CONNECTED
        
        conn = NATS.connect("nats://localhost:4321,localhost:5555", retry_on_init_fail = true)
        @test NATS.status(conn) == NATS.CONNECTING
        drain(conn)

        @test_throws ErrorException NATS.connect(":4321")

        conn = NATS.connect("localhost")
        @test NATS.status(conn) == NATS.CONNECTED

        conn = NATS.connect("localhost:4321,localhost:4322,localhost:4222", retry_on_init_fail = true, retain_servers_order = true, reconnect_delays = [0.1, 0.1, 0.1])
        sleep(1)
        @test conn.reconnect_count == 1
        @test conn.connect_init_count == 3
    catch
        # This may fail for some NATS server setup and this is ok.
        @info "`Connection url schemes` tests ignored."
    end
end

NATS.status()

@testset "Handler error throttling." begin
    subject = randstring(8)
    sub = subscribe(nc, subject) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(nc, subject, "Hi!")
        sleep(0.1)
    end

    drain(nc, sub)
end

NATS.status()

@testset "Handler error throttling async." begin
    subject = randstring(8)
    sub = subscribe(nc, subject, spawn = true) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(nc, subject, "Hi!")
        sleep(0.1)
    end
    drain(nc, sub)
end

NATS.status()

@testset "Should reconnect on malformed msg" begin
    options = merge(NATS.default_connect_options(), (protocol=100,) )
    con_msg = NATS.from_options(NATS.Connect, options)
    NATS.send(nc, con_msg)
    sleep(10)
    @test nc.status == NATS.CONNECTED
end

NATS.status()

@testset "Should reconnect on send buffer closed" begin
    NATS.reopen_send_buffer(nc)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

NATS.status()

@testset "Draining connection." begin
    nc = NATS.connect()
    subject = "DRAIN_TEST"
    sub = subscribe(nc, "DRAIN_TEST") do msg end
    @test length(nc.sub_data) == 1
    NATS.drain(nc)
    @test isempty(nc.sub_data)
    @test_throws ErrorException publish(nc, "DRAIN_TEST")
    @test_throws ErrorException ping(nc)
    @test NATS.status(nc) == NATS.DRAINED
    NATS.drain(nc) # Draining drained connection is noop.
    @test NATS.status(nc) == NATS.DRAINED
    @test isempty(nc.sub_data)
end

NATS.status()

@testset "Connections API" begin
    @test NATS.connection(1) isa NATS.Connection

    @test_throws ErrorException NATS.connection(10000000)
end

NATS.status()

@testset "Connect error from protocol init when options are wrong" begin
    @test_throws "invalid client protocol" NATS.connect(protocol = 100)
    @test_throws "Client requires TLS but it is not available for the server." NATS.connect(tls_required = true)
end

NATS.status()

@testset "Subscription warnings" begin
    NATS.status()
    sub1 = subscribe(nc, "too_many_handlers", spawn = true, monitoring_throttle_seconds = 15.0) do msg
        sleep(21)
    end
    for _ in 1:1001
        publish(nc, "too_many_handlers")
    end

    sub2 = subscribe(nc, "overload_channel", spawn = false, channel_size = 100, monitoring_throttle_seconds = 15.0) do msg
        sleep(21)
    end
    for _ in 1:82
        publish(nc, "overload_channel")
        sleep(0.01) # Sleep causes that msga are not batches.
    end
    sleep(21)

    unsubscribe(nc, sub1)
    unsubscribe(nc, sub2)

    NATS.status()
    sub3 = subscribe(nc, "overload_channel", spawn = false, channel_size = 10) do msg
        sleep(5)
    end
    for _ in 1:15
        publish(nc, "overload_channel")
        sleep(0.01) # Sleep causes that msga are not batches.
    end
    sleep(5)
    unsubscribe(nc, sub3)
    NATS.status()
end

NATS.status()

@testset "Send buffer overflow" begin
    connection = NATS.connect(send_buffer_size = 5, send_retry_delays = [])

    @test_throws ErrorException for _ in 1:100
        publish(connection, "overflow_buffer", "some long payload to overflow buffer")
    end
    NATS.ping(connection) # Ping should work even when buffer is overflown
    
    connection = NATS.connect(send_buffer_size = 5)
    counter = 0
    sub = subscribe(connection, "overflow_buffer") do msg
        counter += 1
    end
    for _ in 1:100
        publish(connection, "overflow_buffer", "test retry path")
    end
    sleep(1)
    unsubscribe(connection, sub)
    @test counter > 90
end

NATS.status()

@testset "Publish on drained connection fails" begin
    connection = NATS.connect()

    @async NATS.drain(connection)
    sleep(0.1)
    @test_throws ErrorException publish(connection, "test_publish_on_drained")

    pub = NATS.Pub("test_publish_on_drained", nothing, UInt8[], UInt8[])
    @test_throws ErrorException NATS.send(connection, repeat([pub], 10))
end

NATS.status()
