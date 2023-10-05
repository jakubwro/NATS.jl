
using Test
using NATS
using Random

@testset "Should error when no default connection." begin
    @test_throws ErrorException publish("SOME_SUBJECT"; payload = "Hi!")
end

@testset "Ping" begin
    nc = NATS.connect()
    ping(nc)
    @test true # TODO: add pong count to connection stats
end

@testset "Method error hints." begin
    nc = NATS.connect()
    
    # hint = """To use `Type{Float64}` as parameter of subscription handler apropriate conversion from `Type{NATS.Msg}` must be provided.
    #         ```
    #         import Base: convert
            
    #         function convert(::Type{Type{Float64}}, msg::Union{NATS.Msg, NATS.HMsg})
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
            
    #         function convert(::Type{Type{Integer}}, msg::Union{NATS.Msg, NATS.HMsg})
    #             # Implement conversion logic here.
    #         end
    #         """
    @test_throws MethodError reply("SOME.REQUESTS") do msg::Integer
        "Received $msg"
    end
end

@testset "Handler error throttling." begin
    nc = NATS.connect()
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

@testset "Handler error throttling async." begin
    nc = NATS.connect()
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

@testset "Should reconnect on malformed msg" begin
    nc = NATS.connect()
    con_msg = NATS.from_kwargs(NATS.Connect, NATS.DEFAULT_CONNECT_OPTIONS, (protocol=100,))
    NATS.send(nc, con_msg)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

@testset "Should reconnect on outbox closed" begin
    nc = NATS.connect()
    close(nc.outbox)
    sleep(5)
    @test nc.status == NATS.CONNECTED
end

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

@testset "Connections API" begin
    @test NATS.connection(:default) isa NATS.Connection
    @test NATS.connection(1) isa NATS.Connection

    @test_throws ErrorException NATS.connection(:something)
    nc = NATS.connection(:default)
    @test_throws ErrorException NATS.connection(:something, nc)
    @test_throws ErrorException NATS.connection(10000000)
end

@testset "Connect error from protocol init when options are wrong" begin
    @test_throws "invalid client protocol" NATS.connect(default = false, protocol = 100)
    @test_throws "Client requires TLS but it is not available for the server." NATS.connect(default = false, tls_required = true)
end


@testset "Nonce signatures" begin
    seed = "SUAJ4LZRG3KF7C7U4E5737YMAOGUAWBODUM6DBWLY4UPUMXH6TH7JLQFDM"
    nkey = "UAGPV4UFVS34M2XGY7HLSNEBDVJZZDZ6XMQ4NTXVEMKZQNSFH2AJFUA5"
    nonce = "XTdilcu9paonaBQ"
    sig = "3tsErI9fNKHWOHLAbc_XQ8Oo3XHv__7I_fA1aQ7xod3gYpxhDzt1vItbQLv3FhDtDFycxJJ0wA26rG3NEwWZBg"
    @test NATS.sign(nonce, seed) == sig

    seed = "SUADPKZWX3XJQO4GJEX2IGZAKCYUSLSLNJXFG7KPAYAODEVABRK6ZKKALA"
    nkey= "UDBKUC5JFUX5SDF6CGBT3WAZEZSJTGMWWSCRJMODEUPVOKBPCLVODH2J"
    nonce = "HiA_hND1AV-DjmM"
    sig = "g4HDazX_ZZig_FOFBzhorLSYCEDRlv20Y5vErFjDlTRZMqaaF27ImP16es_GI83Fn59xr9V98Ux5GlEvvaeADQ"
    @test NATS.sign(nonce, seed) == sig
end