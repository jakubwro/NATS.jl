### connection.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains data structure definitions and aggregates utilities for handling connection to NATS server.
#
### Code:

@enum ConnectionStatus CONNECTING CONNECTED DISCONNECTED DRAINING DRAINED

include("stats.jl")
include("structs.jl")
include("state.jl")
include("utils.jl")
include("tls.jl")
include("send.jl")
include("handlers.jl")
include("drain.jl")
include("connect.jl")

# Try reuse existing connection or create new if not possible.
@testsnippet GetConnection begin
    using NATS
    try_reuse_connection = true
    alive_connections = filter!(NATS.state.connections) do conn
        conn.status == NATS.CONNECTED
    end
    nc = if !try_reuse_connection || isempty(alive_connections)
        NATS.connect()
    else
        first(alive_connections)
    end
end

@testitem "Ping" setup=[GetConnection] begin
    ping(nc)
    @test true
end

@testitem "Show connection status" setup=[GetConnection] begin
    @test startswith(repr(nc), "NATS.Connection(")
end

@testitem "Publication subscription stats should be counted from nested spawned task." setup=[GetConnection] begin
    initial_connection_published_count = nc.stats.msgs_published
    sub = subscribe(nc, "stats_test") do 
        Threads.@spawn begin
            Threads.@spawn publish(nc, "some_other_subject", "Some payload")
        end
    end
    sleep(0.2)
    publish(nc, "stats_test")
    sleep(0.2)
    @test nc.stats.msgs_published == initial_connection_published_count + 2
    sub_stats = nc.sub_data[sub.sid].stats
    @test sub_stats.msgs_published == 1
    drain(nc)
end

@testitem "Method error hints." setup=[GetConnection] begin
    @test_throws "Conversion of NATS message into type Float64 is not defined" subscribe(nc, "SOME.THING") do msg::Float64 end
    @test_throws "Conversion of type Int64 to NATS payload is not defined." request(nc, "SOME.REQUESTS", 4)
    @test_throws "Conversion of type Int64 to NATS payload is not defined." request(nc, 4, "SOME.REQUESTS", 4)
    @test_throws "Conversion of NATS message into type Integer is not defined." reply(nc, "SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

@testitem "Connection url schemes" setup=[GetConnection] begin
    try
        @test_throws Base.IOError NATS.connect("tls://localhost:4321")

        conn = NATS.connect("nats://username:passw0rd@localhost:4222")
        @test NATS.status(conn) == NATS.CONNECTED
        drain(conn)
        
        conn = NATS.connect("nats://localhost:4321,localhost:5555", retry_on_init_fail = true)
        @test NATS.status(conn) == NATS.CONNECTING
        drain(conn)

        @test_throws ErrorException NATS.connect(":4321")

        conn = NATS.connect("localhost")
        @test NATS.status(conn) == NATS.CONNECTED
        drain(conn)

        conn = NATS.connect("localhost:4321,localhost:4322,localhost:4222", retry_on_init_fail = true, retain_servers_order = true, reconnect_delays = [0.1, 0.1, 0.1])
        sleep(1)
        @test conn.reconnect_count == 1
        @test conn.connect_init_count == 3
        drain(conn)
    catch
        # This may fail for some NATS server setup and this is ok.
        @info "`Connection url schemes` tests ignored."
    end
end

@testitem "Handler error throttling." setup=[GetConnection] begin
    using Random

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

@testitem "Handler error throttling async." setup=[GetConnection] begin
    using Random

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

@testitem "Should reconnect on malformed msg" setup=[GetConnection] begin
    using StructTypes
    using NATS: Connect

    options = merge(NATS.default_connect_options(), (protocol=100,) )
    con_msg = StructTypes.constructfrom(Connect, options)
    NATS.send(nc, con_msg)
    sleep(10)
    @test nc.status == NATS.CONNECTED
end

@testitem "Should reconnect on send buffer closed" setup=[GetConnection] begin
    NATS.reopen_send_buffer(nc)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

@testitem "Connections API" setup=[GetConnection] begin
    @test NATS.connection(1) isa NATS.Connection

    @test_throws ErrorException NATS.connection(10000000)
end

@testitem "Connect error from protocol init when options are wrong" begin
    @test_throws "invalid client protocol" NATS.connect(protocol = 100)
    @test_throws "Client requires TLS but it is not available for the server." NATS.connect(tls_required = true)
end

@testitem "Subscription warnings" setup=[GetConnection] begin
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

    sub3 = subscribe(nc, "overload_channel", spawn = false, channel_size = 10) do msg
        sleep(5)
    end
    for _ in 1:15
        publish(nc, "overload_channel")
        sleep(0.01) # Sleep causes that msgs are not batched.
    end
    sleep(5)
    unsubscribe(nc, sub3)
end

@testitem "Send buffer overflow" begin
    connection = NATS.connect(send_buffer_limit = 5, send_retry_delays = [])
    @test_throws ErrorException for _ in 1:100
        publish(connection, "overflow_buffer", "some long payload to overflow buffer")
    end
    NATS.ping(connection) # Ping should work even when buffer is overflown
    drain(connection)

    connection = NATS.connect(send_buffer_limit = 5)
    counter = Ref(0)
    sub = subscribe(connection, "overflow_buffer") do msg
        counter[] += 1
    end
    for _ in 1:100
        publish(connection, "overflow_buffer", "test retry path")
    end
    sleep(1)
    unsubscribe(connection, sub)
    @test counter[] > 90
    drain(connection)
end

@testitem "Publish on drained connection fails" begin
    connection = NATS.connect()

    @async NATS.drain(connection)
    sleep(0.1)
    @test_throws ErrorException publish(connection, "test_publish_on_drained")

    pub = NATS.Pub("test_publish_on_drained", nothing, 0, UInt8[])
    @test_throws ErrorException NATS.send(connection, repeat([pub], 10))

    drain(connection)
end

@testitem "Subscription draining" begin
    connection = NATS.connect()

    published_count = Ref(0)
    delivered_count = Ref(0)
    sub = subscribe(connection, "some_topic") do msg
        sleep(0.1)
        delivered_count[] += 1
    end
    sleep(1) # Let server to notice subscribtion.
    publisher = @async for i in 1:300
        publish(connection, "some_topic", "Hi!")
        published_count[] += 1
        sleep(0.01)
    end
    sleep(0.2)
    drain(connection, sub)
    sleep(1)
    @test delivered_count[] > 0
    wait(publisher)
    @show delivered_count published_count
    @test connection.stats.msgs_handled == delivered_count[]
    @test connection.stats.msgs_received == delivered_count[]

    drain(connection)
end

@testitem "Connection draining" begin
    connection = NATS.connect()

    published_count = Ref(0)
    delivered_count = Ref(0)
    sub = subscribe(connection, "some_topic") do msg
        sleep(0.05)
        delivered_count[] += 1
    end
    sleep(1) # Let server to notice subscription.
    publisher = @async for i in 1:300
        publish(connection, "some_topic", "Hi!")
        published_count[] += 1
        sleep(0.01)
    end
    sleep(0.3)
    @time drain(connection)
    sleep(1)
    @test delivered_count[] > 0
    @test_throws "Cannot send on connection with status DRAINING" wait(publisher)
    @show delivered_count published_count
    @test connection.stats.msgs_handled == delivered_count[]
    @test connection.stats.msgs_received == delivered_count[]
    drain(connection)
end

@testitem "Test fallback handler" begin
    nc = NATS.connect()
    sub = subscribe(nc, "SOME.BAR") do msg
        @show msg
    end
    empty!(nc.sub_data) # Break state of connection to force fallback handler.
    publish(nc, "SOME.BAR", "Hi!")
    sleep(2) # Wait for compilation.
    @test nc.stats.msgs_dropped > 0
    drain(nc, sub)
    drain(nc)
end

@testitem "Test custom fallback handler" begin
    nc = NATS.connect()
    empty!(nc.fallback_handlers)
    was_called = Ref(false)
    NATS.install_fallback_handler(nc) do nc, msg
        was_called[] = true
        @info "Custom fallback called." msg
    end
    sub = subscribe(nc, "SOME.FOO") do msg
        @show msg
    end
    empty!(nc.sub_data) # Break state of connection to force fallback handler.
    publish(nc, "SOME.FOO", "Hi!")
    sleep(0.5) # Wait for compilation.
    @test nc.stats.msgs_dropped > 0
    @test was_called[]
    drain(nc, sub)
    drain(nc)
end

@testitem "Draining connection." setup=[GetConnection] begin
    subject = "DRAIN_TEST"
    sub = subscribe(nc, "DRAIN_TEST") do msg end
    @test length(nc.sub_data) == 1
    drain(nc)
    @test isempty(nc.sub_data)
    @test_throws ErrorException publish(nc, "DRAIN_TEST")
    @test_throws ErrorException ping(nc)
    @test NATS.status(nc) == NATS.DRAINED
    drain(nc) # Draining drained connection is noop.
    @test NATS.status(nc) == NATS.DRAINED
    @test isempty(nc.sub_data)
end
