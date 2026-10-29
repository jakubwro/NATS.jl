
using Test
using NATS
using Random
using ScopedValues
using StructTypes

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
    sub_stats = NATS.stats(conn, sub)
    publish(conn, "stats_test")
    @test timedwait(() -> (@atomic sub_stats.msgs_published) >= 1, 10.0) == :ok
    @test (@atomic conn.stats.msgs_published) == 2
    @test (@atomic sub_stats.msgs_published) == 1
    drain(conn, sub)
end

NATS.status()

@testset "Method error hints." begin
    @test_throws "Conversion of a NATS message into type Float64 is not defined" subscribe(nc, "SOME.THING") do msg::Float64 end
    @test_throws "Conversion of type Int64 to NATS payload is not defined." request(nc, "SOME.REQUESTS", 4)
    @test_throws "Conversion of type Int64 to NATS payload is not defined." request(nc, 4, "SOME.REQUESTS", 4)
    @test_throws "Conversion of a NATS message into type Integer is not defined." reply(nc, "SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

@testset "Connection url schemes" begin
    try
        @test_throws NATS.Reseau.HostResolvers.OpError NATS.connect("tls://localhost:4321")

        conn = NATS.connect("nats://username:passw0rd@localhost:4222")
        @test NATS.status(conn) == NATS.CONNECTED
        
        conn = NATS.connect("nats://localhost:4321,localhost:5555", retry_on_init_fail = true)
        @test NATS.status(conn) == NATS.CONNECTING
        drain(conn)

        @test_throws ErrorException NATS.connect(":4321")

        conn = NATS.connect("localhost")
        @test NATS.status(conn) == NATS.CONNECTED

        conn = NATS.connect("localhost:4321,localhost:4322,localhost:4222", retry_on_init_fail = true, retain_servers_order = true, reconnect_delays = [0.1, 0.1, 0.1])
        @test timedwait(() -> (@atomic conn.reconnect_count) >= 1, 10.0) == :ok
        @test (@atomic conn.reconnect_count) == 1
        @test (@atomic conn.connect_init_count) == 3
    catch
        # This may fail for some NATS server setups and this is ok.
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
    con_msg = StructTypes.constructfrom(Connect, options)
    reconnects = @atomic nc.reconnect_count
    NATS.send(nc, con_msg)
    @test timedwait(() -> (@atomic nc.reconnect_count) > reconnects &&
        NATS.status(nc) == NATS.CONNECTED, 15.0) == :ok
end

NATS.status()

@testset "Should reconnect on send buffer closed" begin
    reconnects = @atomic nc.reconnect_count
    NATS.reopen_send_buffer(nc)
    @test timedwait(() -> (@atomic nc.reconnect_count) > reconnects &&
        NATS.status(nc) == NATS.CONNECTED, 15.0) == :ok
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
    NATS.drain(nc) # Draining a drained connection is a no-op.
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
    if isnothing(get(ENV, "NATS_TLS_CA_PATH", nothing))
        @test_throws "Client requires TLS but it is not available for the server." NATS.connect(tls_required = true)
    end
end

@testset "TLS-first is a recognized client option" begin
    err = try
        NATS.connect("tls://localhost:4321"; tls_first = true)
    catch e
        e
    end
    @test !occursin("Unknown `connect` options", sprint(showerror, err))
end

@testset "TLS-first refuses a plaintext broker (fail closed)" begin
    @test_throws Exception NATS.connect(tls_first = true)
end

@testset "TLS-first skips the INFO tls_available check" begin
    # A TLS-first server can omit `tls_available` from INFO.
    buf() = IOBuffer("INFO {\"server_id\":\"t\",\"server_name\":\"t\"," *
                     "\"version\":\"2.10.0\",\"go\":\"go1.21\"," *
                     "\"host\":\"0.0.0.0\",\"port\":4222,\"headers\":true," *
                     "\"proto\":1,\"max_payload\":1048576,\"client_id\":1}\r\n")
    info = NATS.next_protocol_message(buf())
    @test info isa NATS.Info && isnothing(info.tls_available)
    @test isnothing(NATS.validate_connect_options(
        info, (tls_required = true, tls_first = true)))
    @test_throws "Client requires TLS but it is not available for the server." NATS.validate_connect_options(
        info, (tls_required = true,))
end

@testset "TLS required by the client is met by a server that requires it" begin
    # A TLS-only server sends `tls_required` and omits `tls_available`.
    buf() = IOBuffer("INFO {\"server_id\":\"t\",\"server_name\":\"t\"," *
                     "\"version\":\"2.10.0\",\"go\":\"go1.21\"," *
                     "\"host\":\"0.0.0.0\",\"port\":4222,\"headers\":true," *
                     "\"proto\":1,\"max_payload\":1048576,\"client_id\":1,\"tls_required\":true}\r\n")
    info = NATS.next_protocol_message(buf())
    @test info isa NATS.Info && info.tls_required == true && isnothing(info.tls_available)
    @test (NATS.validate_connect_options(info, (tls_required = true,)); true)
    if !isnothing(get(ENV, "NATS_TLS_CA_PATH", nothing))
        _, port = NATS.host_port(get(ENV, "NATS_CONNECT_URL", NATS.DEFAULT_CONNECT_URL))
        for nc in (NATS.connect(tls_required = true), NATS.connect("tls://localhost:$port"))
            @test NATS.status(nc) == NATS.CONNECTED
            drain(nc)
        end
    end
end

@testset "TLS required by the client upgrades a server that only allows it" begin
    # The server sends `tls_available` only; the client's first byte is a TLS record (0x16) or `CONNECT`.
    function first_byte(; kw...)
        server = listen(ip"127.0.0.1", 0)
        _, port = getsockname(server)
        got = Channel{UInt8}(1)
        @async begin
            sock = accept(server)
            write(sock, "INFO {\"server_id\":\"t\",\"server_name\":\"t\",\"version\":\"2.10.0\",\"go\":\"go1.21\"," *
                        "\"host\":\"127.0.0.1\",\"port\":$port,\"headers\":true,\"proto\":1," *
                        "\"max_payload\":1048576,\"client_id\":1,\"tls_available\":true}\r\n")
            put!(got, read(sock, UInt8))
            close(sock)
        end
        try
            NATS.connect("127.0.0.1:$port"; kw...)
        catch
        end
        b = take!(got)
        close(server)
        b
    end
    @test first_byte(tls_required = true) == 0x16
    @test first_byte() == UInt8('C')
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
        sleep(0.01) # Sleep causes that msgs are not batched.
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
        sleep(0.01) # Sleep causes that msgs are not batched.
    end
    sleep(5)
    unsubscribe(nc, sub3)
    NATS.status()
end

NATS.status()

@testset "Send buffer overflow" begin
    connection = NATS.connect(send_buffer_limit = 5, send_retry_delays = [])

    @test_throws ErrorException for _ in 1:100
        publish(connection, "overflow_buffer", "some long payload to overflow buffer")
    end
    NATS.ping(connection) # Ping should work even when buffer has overflowed
    
    connection = NATS.connect(send_buffer_limit = 5)
    counter = Threads.Atomic{Int}(0)
    sub = subscribe(connection, "overflow_buffer") do msg
        Threads.atomic_add!(counter, 1)
    end
    for _ in 1:100
        publish(connection, "overflow_buffer", "test retry path")
    end
    @test timedwait(() -> counter[] > 90, 10.0) == :ok
    unsubscribe(connection, sub)
    @test counter[] > 90
end

NATS.status()

@testset "Publish on drained connection fails" begin
    connection = NATS.connect()

    draining = @async NATS.drain(connection)
    @test timedwait(() -> istaskdone(draining), 10.0) == :ok
    istaskdone(draining) && fetch(draining)
    @test_throws ErrorException publish(connection, "test_publish_on_drained")

    pub = NATS.Pub("test_publish_on_drained", nothing, 0, UInt8[])
    @test_throws ErrorException NATS.send(connection, repeat([pub], 10))
end

NATS.status()

@testset "Subscription draining" begin
    connection = NATS.connect()

    published_count = 0
    delivered_count = Threads.Atomic{Int}(0)
    sub = subscribe(connection, "some_topic") do msg
        sleep(0.1)
        Threads.atomic_add!(delivered_count, 1)
    end
    NATS.ping(connection; timeout = 10.0, measure = false)
    publisher = @async for i in 1:300
        publish(connection, "some_topic", "Hi!")
        published_count += 1
        sleep(0.01)
    end
    @test timedwait(() -> delivered_count[] > 0, 10.0) == :ok
    drain(connection, sub)
    @test delivered_count[] > 0
    @test timedwait(() -> istaskdone(publisher), 10.0) == :ok
    istaskdone(publisher) && fetch(publisher)
    @show delivered_count[] published_count
    @test (@atomic connection.stats.msgs_handled) == delivered_count[]
    @test (@atomic connection.stats.msgs_received) == delivered_count[]
end

NATS.status()

@testset "Connection draining" begin
    connection = NATS.connect()

    published_count = 0
    delivered_count = Threads.Atomic{Int}(0)
    sub = subscribe(connection, "some_topic") do msg
        sleep(0.05)
        Threads.atomic_add!(delivered_count, 1)
    end
    NATS.ping(connection; timeout = 10.0, measure = false)
    publisher = @async for i in 1:300
        publish(connection, "some_topic", "Hi!")
        published_count += 1
        sleep(0.01)
    end
    @test timedwait(() -> delivered_count[] > 0, 10.0) == :ok
    @time drain(connection)
    @test delivered_count[] > 0
    @test timedwait(() -> istaskdone(publisher), 10.0) == :ok
    if istaskdone(publisher)
        @test_throws r"Cannot send on connection with status DRAIN(ING|ED)" wait(publisher)
    end
    @show delivered_count[] published_count
    @test (@atomic connection.stats.msgs_handled) == delivered_count[]
    @test (@atomic connection.stats.msgs_received) == delivered_count[]
end

NATS.status()
