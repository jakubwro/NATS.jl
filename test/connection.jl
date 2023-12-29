
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

@testset "Method error hints." begin
    # hint = """To use `Type{Float64}` as parameter of subscription handler apropriate conversion from `Type{NATS.Msg}` must be provided.
    #         ```
    #         import Base: convert
            
    #         function convert(::Type{Type{Float64}}, msg::Msg)
    #             # Implement conversion logic here.
    #         end
    #         """
    @test_throws MethodError subscribe(nc, "SOME.THING") do msg::Float64 end
    @test_throws MethodError request(nc, "SOME.REQUESTS"; payload = 4)
    # hint = """Object of type `Int64` cannot be serialized into payload."""
    @test_throws MethodError request(nc, "SOME.REQUESTS", 4) # TODO: in this case there should be rather warning about missing payload.
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

NATS.status()

@testset "Handler error throttling." begin
    subject = randstring(8)
    sub = subscribe(nc, subject) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(nc, subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(1) # wait for all errors.

    unsubscribe(nc, sub)
    sleep(0.1)
end

NATS.status()

@testset "Handler error throttling async." begin
    subject = randstring(8)
    sub = subscribe(nc, subject, async_handlers = true) do msg
        error("Just testing...")
    end

    tm = Timer(7)
    while isopen(tm)
        publish(nc, subject, payload = "Hi!")
        sleep(0.1)
    end
    sleep(1) # wait for all errors.

    unsubscribe(nc, sub)
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
    nc = NATS.connect()
    subject = "DRAIN_TEST"
    sub = subscribe(nc, "DRAIN_TEST") do msg end
    @test length(nc.subs) == 1
    NATS.drain(nc)
    @test isempty(nc.subs)
    @test_throws ErrorException publish(nc, "DRAIN_TEST")
    @test_throws ErrorException ping(nc)
    @test NATS.status(nc) == NATS.DRAINED
    NATS.drain(nc) # Draining drained connectin is noop.
    @test NATS.status(nc) == NATS.DRAINED

    @test isempty(nc.subs)
    @test isempty(NATS.state.handlers)
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
    sub1 = subscribe(nc, "too_many_handlers", async_handlers = true, monitoring_throttle_seconds = 15.0) do msg
        sleep(21)
    end
    for _ in 1:1001
        publish(nc, "too_many_handlers")
    end

    sub2 = subscribe(nc, "overload_channel", async_handlers = false, channel_size = 100, monitoring_throttle_seconds = 15.0) do msg
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
    sub3 = subscribe(nc, "overload_channel", async_handlers = false, channel_size = 10) do msg
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
        publish(connection, "overflow_buffer"; payload = "some long payload to overflow buffer")
    end
    NATS.ping(connection) # Ping should work even when buffer is overflown
    
    connection = NATS.connect(send_buffer_size = 5)
    counter = 0
    sub = subscribe(connection, "overflow_buffer") do msg
        counter += 1
    end
    for _ in 1:100
        publish(connection, "overflow_buffer"; payload = "test retry path")
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
