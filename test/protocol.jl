uint8_vec(s::String) = convert.(UInt8, collect(s))

@testset "Parsing server operations." begin

    data_to_parse = UInt8[]
    append!(data_to_parse, """INFO {"server_id":"NCUWF4KWI6NQR4NRT2ZWBI6WBW6V63XERJGREROVAVV6WZ4O4D7R6CVK","server_name":"my_nats_server","version":"2.9.21","proto":1,"git_commit":"b2e7725","go":"go1.19.12","host":"0.0.0.0","port":4222,"headers":true,"max_payload":1048576,"jetstream":true,"client_id":61,"client_ip":"127.0.0.1"} \r\n""")
    append!(data_to_parse, "MSG FOO.BAR 9 11\r\nHello World\r\n")
    append!(data_to_parse, "MSG FOO.BAR 9 GREETING.34 11\r\nHello World\r\n")
    append!(data_to_parse, "HMSG FOO.BAR 9 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n")
    append!(data_to_parse, "HMSG FOO.BAR 9 BAZ.69 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n")
    append!(data_to_parse, "HMSG FOO.BAR 9 16 16\r\nNATS/1.0 503\r\n\r\n\r\n")
    append!(data_to_parse, "PING\r\n")
    append!(data_to_parse, "PONG\r\n")
    append!(data_to_parse, "+OK\r\n")
    append!(data_to_parse, "-ERR 'Unknown Protocol Operation'\r\n")
    io = IOBuffer(data_to_parse)
    result = NATS.ProtocolMessage[]
    NATS.parser_loop(io) do msgs
        append!(result, msgs)
    end

    @test result == [
        NATS.Info("NCUWF4KWI6NQR4NRT2ZWBI6WBW6V63XERJGREROVAVV6WZ4O4D7R6CVK", "my_nats_server", "2.9.21", "go1.19.12", "0.0.0.0", 4222, true, 1048576, 1, 0x000000000000003d, nothing, nothing, nothing, nothing, nothing, nothing, nothing, "b2e7725", true, nothing, "127.0.0.1", nothing, nothing, nothing),
        NATS.Msg("FOO.BAR", "9", nothing, 0, uint8_vec("Hello World")),
        NATS.Msg("FOO.BAR", "9", "GREETING.34", 0, uint8_vec("Hello World")),
        NATS.Msg("FOO.BAR", "9", nothing, 34, uint8_vec("NATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World")),
        NATS.Msg("FOO.BAR", "9", "BAZ.69", 34, uint8_vec("NATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World")),
        NATS.Msg("FOO.BAR", "9", nothing, 16, uint8_vec("NATS/1.0 503\r\n\r\n")),
        NATS.Ping(),
        NATS.Pong(),
        NATS.Ok(),
        NATS.Err("Unknown Protocol Operation"),
    ]

    io = IOBuffer("this is not expected\r\n")
    @test_throws ErrorException NATS.parser_loop(io) do; end
end

@testset "Serializing client operations." begin
    serialize(m) = String(repr(NATS.MIME_PROTOCOL(), m))

    json = """{"verbose":false,"pedantic":false,"tls_required":false,"lang":"julia","version":"0.0.1"}"""
    @test serialize(JSON3.read(json, NATS.Connect)) == """CONNECT $json\r\n"""

    @test serialize(Pub("FOO", nothing, UInt8[], uint8_vec("Hello NATS!"))) == "PUB FOO 11\r\nHello NATS!\r\n"
    @test serialize(Pub("FRONT.DOOR", "JOKE.22", UInt8[], uint8_vec("Knock Knock"))) == "PUB FRONT.DOOR JOKE.22 11\r\nKnock Knock\r\n"
    @test serialize(Pub("NOTIFY", nothing, UInt8[], UInt8[])) == "PUB NOTIFY 0\r\n\r\n"

    @test serialize(Pub("FOO", nothing, uint8_vec("NATS/1.0\r\nBar: Baz\r\n\r\n"), uint8_vec("Hello NATS!"))) == "HPUB FOO 22 33\r\nNATS/1.0\r\nBar: Baz\r\n\r\nHello NATS!\r\n"
    @test serialize(Pub("FRONT.DOOR", "JOKE.22", uint8_vec("NATS/1.0\r\nBREAKFAST: donut\r\nLUNCH: burger\r\n\r\n"), uint8_vec("Knock Knock"))) == "HPUB FRONT.DOOR JOKE.22 45 56\r\nNATS/1.0\r\nBREAKFAST: donut\r\nLUNCH: burger\r\n\r\nKnock Knock\r\n"

    @test serialize(Pub("NOTIFY", nothing, uint8_vec("NATS/1.0\r\nBar: Baz\r\n\r\n"), UInt8[])) == "HPUB NOTIFY 22 22\r\nNATS/1.0\r\nBar: Baz\r\n\r\n\r\n"
    @test serialize(Pub("MORNING.MENU", nothing, uint8_vec("NATS/1.0\r\nBREAKFAST: donut\r\nBREAKFAST: eggs\r\n\r\n"), uint8_vec("Yum!"))) == "HPUB MORNING.MENU 47 51\r\nNATS/1.0\r\nBREAKFAST: donut\r\nBREAKFAST: eggs\r\n\r\nYum!\r\n"

    @test serialize(Sub("FOO", nothing, "1")) == "SUB FOO 1\r\n"
    @test serialize(Sub("BAR", "G1", "44")) == "SUB BAR G1 44\r\n"

    @test serialize(Unsub("1", nothing)) == "UNSUB 1\r\n"
    @test serialize(Unsub("1", 5)) == "UNSUB 1 5\r\n"
end

@testset "Serializing headers." begin
    msg = Msg("FOO.BAR", "9", "BAZ.69", 30, uint8_vec("NATS/1.0\r\nA: B\r\nC: D\r\nC: E\r\n\r\nHello World"))
    @test headers(msg) == ["A" => "B", "C" => "D", "C" => "E"]
    @test headers(msg, "C") == ["D", "E"]
    @test_throws ArgumentError header(msg, "C")
    @test header(msg, "A") == "B"
    @test String(repr(MIME_HEADERS(), headers(msg))) == String(msg.payload[begin:msg.headers_length])
    @test isempty(headers(Msg("FOO.BAR", "9", "GREETING.34", 0, uint8_vec("Hello World"))))

    no_responder_msg = Msg("FOO.BAR", "9", "BAZ.69", 16, uint8_vec("NATS/1.0 503\r\n\r\n"))
    @test NATS.statuscode(no_responder_msg) == 503

end

@testset "Serializing typed handler results" begin
    @test String(repr(MIME_PAYLOAD(), "Hi!")) == "Hi!"
    @test String(repr(MIME_PAYLOAD(), ("Hi!", Headers()))) == "Hi!"
    @test String(repr(MIME_PAYLOAD(), (nothing, Headers()))) == ""
    @test String(repr(MIME_PAYLOAD(), Headers())) == ""
    @test String(repr(MIME_PAYLOAD(), (nothing, nothing))) == ""

    @test String(repr(MIME_HEADERS(), "Hi!")) == ""
    @test String(repr(MIME_HEADERS(), ("Hi!", Headers()))) == "NATS/1.0\r\n\r\n"
    @test String(repr(MIME_HEADERS(), ("Hi!", nothing))) == ""
    @test String(repr(MIME_HEADERS(), (nothing, Headers()))) == "NATS/1.0\r\n\r\n"
    @test String(repr(MIME_HEADERS(), Headers())) == "NATS/1.0\r\n\r\n"
    @test String(repr(MIME_HEADERS(), ["A" => "B"])) == "NATS/1.0\r\nA: B\r\n\r\n"
    @test String(repr(MIME_HEADERS(), (nothing, nothing))) == ""
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