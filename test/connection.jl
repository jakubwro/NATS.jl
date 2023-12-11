
using Test
using NATS
using Random

@testset "Should error when no default connection." begin
    @test_throws ErrorException publish("SOME_SUBJECT"; payload = "Hi!")
end

NATS.status()

nc = NATS.connect(default = true)

@testset "Ping" begin
    ping(nc)
    @test true # TODO: add pong count to connection stats
end

NATS.status()

@testset "Show connection status" begin
    @test startswith(repr(nc), "NATS.Connection(")
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
    @test_throws MethodError subscribe("SOME.THING") do msg::Float64 end
    @test_throws MethodError request("SOME.REQUESTS"; payload = 4)
    # hint = """Object of type `Int64` cannot be serialized into payload."""
    @test_throws MethodError request("SOME.REQUESTS", 4) # TODO: in this case there should be rather warning about missing payload.
    # hint = """To use `Type{Integer}` as parameter of subscription handler apropriate conversion from `Type{NATS.Msg}` must be provided.
    #         ```
    #         import Base: convert
            
    #         function convert(::Type{Type{Integer}}, msg::Msg)
    #             # Implement conversion logic here.
    #         end
    #         """
    @test_throws MethodError reply("SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

NATS.status()

@testset "Handler error throttling." begin
    subject = randstring(8)
    sub = subscribe(subject) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(1) # wait for all errors.

    unsubscribe(sub)
    sleep(0.1)
end

NATS.status()

@testset "Handler error throttling async." begin
    subject = randstring(8)
    sub = subscribe(subject, async_handlers = true) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(1) # wait for all errors.

    unsubscribe(sub)
    sleep(0.1)
end

NATS.status()

@testset "Should reconnect on malformed msg" begin
    options = merge(NATS.default_connect_options(), (protocol=100,) )
    con_msg = NATS.from_options(NATS.Connect, options)
    NATS.send(nc, con_msg)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

NATS.status()

@testset "Should reconnect on outbox closed" begin
    NATS.reopen_send_buffer(nc)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

NATS.status()

@testset "Draining connection." begin
    nc = NATS.connect(default = false)
    subject = "DRAIN_TEST"
    sub = subscribe("DRAIN_TEST"; connection = nc) do msg end
    @test length(nc.subs) == 1
    NATS.drain(nc)
    @test isempty(nc.subs)
    @test_throws ErrorException publish("DRAIN_TEST"; connection = nc)
    @test_throws ErrorException ping(nc)
    @test NATS.status(nc) == NATS.DRAINED
    NATS.drain(nc) # Draining drained connectin is noop.
    @test NATS.status(nc) == NATS.DRAINED

    @test isempty(nc.subs)
    @test isempty(NATS.state.handlers)
end

NATS.status()

@testset "Connections API" begin
    @test NATS.connection(:default) isa NATS.Connection
    @test NATS.connection(1) isa NATS.Connection

    @test_throws ErrorException NATS.connection(:something)
    nc = NATS.connection(:default)
    @test_throws ErrorException NATS.connection(:something, nc)
    @test_throws ErrorException NATS.connection(10000000)
    @test_throws ErrorException NATS.connect(default = true) # Cannot have more than one default connection.
end

NATS.status()

@testset "Connect error from protocol init when options are wrong" begin
    @test_throws "invalid client protocol" NATS.connect(default = false, protocol = 100)
    @test_throws "Client requires TLS but it is not available for the server." NATS.connect(default = false, tls_required = true)
end

NATS.status()

@testset "Subscription warnings" begin
    NATS.status()
    sub1 = subscribe("too_many_handlers", async_handlers = true, monitoring_throttle_seconds = 15.0) do msg
        sleep(21)
    end
    for _ in 1:1001
        publish("too_many_handlers")
    end

    sub2 = subscribe("overload_channel", async_handlers = false, channel_size = 100, monitoring_throttle_seconds = 15.0) do msg
        sleep(21)
    end
    for _ in 1:82
        publish("overload_channel")
        sleep(0.01) # Sleep causes that msga are not batches.
    end
    sleep(21)

    unsubscribe(sub1)
    unsubscribe(sub2)

    NATS.status()
    sub3 = subscribe("overload_channel", async_handlers = false, channel_size = 10) do msg
        sleep(5)
    end
    for _ in 1:15
        publish("overload_channel")
        sleep(0.01) # Sleep causes that msga are not batches.
    end
    sleep(5)
    unsubscribe(sub3)
    NATS.status()
end

NATS.status()

@testset "Send buffer overflow" begin
    connection = NATS.connect(default = false, send_buffer_size = 5, send_retry_delays = [])

    @test_throws ErrorException for _ in 1:100
        publish("overflow_buffer"; payload = "some long payload to overflow buffer", connection)
    end
    NATS.ping(connection) # Ping should work even when buffer is overflown
    
    connection = NATS.connect(default = false, send_buffer_size = 5)
    counter = 0
    sub = subscribe("overflow_buffer"; connection) do msg
        counter += 1
    end
    for _ in 1:100
        publish("overflow_buffer"; payload = "test retry path", connection)
    end
    sleep(1)
    unsubscribe(sub; connection)
    @test counter > 90
end

NATS.status()

@testset "Publish on drained connection fails" begin
    connection = NATS.connect(default = false)

    @async NATS.drain(connection)
    sleep(0.1)
    @test_throws ErrorException publish("test_publish_on_drained"; connection)

    pub = NATS.Pub("test_publish_on_drained", nothing, UInt8[], UInt8[])
    @test_throws ErrorException NATS.send(connection, repeat([pub], 10))
end

NATS.status()
