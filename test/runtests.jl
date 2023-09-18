using NATS
using Test
using JSON3

using NATS: next_protocol_message
using NATS: Info, Msg, Ping, Pong, Ok, Err, HMsg, Pub, HPub, Sub, Unsub, Connect
using NATS: Headers, headers, header
using NATS: MIME_PROTOCOL, MIME_PAYLOAD, MIME_HEADERS

@testset "Parsing server operations." begin
    buffer = IOBuffer("""INFO {"server_id":"NCUWF4KWI6NQR4NRT2ZWBI6WBW6V63XERJGREROVAVV6WZ4O4D7R6CVK","server_name":"my_nats_server","version":"2.9.21","proto":1,"git_commit":"b2e7725","go":"go1.19.12","host":"0.0.0.0","port":4222,"headers":true,"max_payload":1048576,"jetstream":true,"client_id":61,"client_ip":"127.0.0.1"} \r\n""")
    @test next_protocol_message(buffer) == Info("NCUWF4KWI6NQR4NRT2ZWBI6WBW6V63XERJGREROVAVV6WZ4O4D7R6CVK", "my_nats_server", "2.9.21", "go1.19.12", "0.0.0.0", 4222, true, 1048576, 1, 0x000000000000003d, nothing, nothing, nothing, nothing, nothing, nothing, nothing, "b2e7725", true, nothing, "127.0.0.1", nothing, nothing, nothing)

    buffer = IOBuffer("MSG FOO.BAR 9 11\r\nHello World\r\n")
    @test next_protocol_message(buffer) == NATS.Msg("FOO.BAR", "9", nothing, 11, "Hello World")

    buffer = IOBuffer("MSG FOO.BAR 9 GREETING.34 11\r\nHello World\r\n")
    @test next_protocol_message(buffer) == Msg("FOO.BAR", "9", "GREETING.34", 11, "Hello World")

    buffer = IOBuffer("HMSG FOO.BAR 9 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n")
    @test next_protocol_message(buffer) == HMsg("FOO.BAR", "9", nothing, 34, 45, "NATS/1.0\r\nFoodGroup: vegetable\r\n\r\n", "Hello World")

    buffer = IOBuffer("HMSG FOO.BAR 9 BAZ.69 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n")
    @test next_protocol_message(buffer) == HMsg("FOO.BAR", "9", "BAZ.69", 34, 45, "NATS/1.0\r\nFoodGroup: vegetable\r\n\r\n", "Hello World")

    buffer = IOBuffer("HMSG FOO.BAR 9 16 16\r\nNATS/1.0 503\r\n\r\n\r\n")
    @test next_protocol_message(buffer) == HMsg("FOO.BAR", "9", nothing, 16, 16, "NATS/1.0 503\r\n\r\n", nothing)
    @test isempty(read(buffer))

    buffer = IOBuffer("PING\r\n")
    @test next_protocol_message(buffer) == Ping()

    buffer = IOBuffer("PONG\r\n")
    @test next_protocol_message(buffer) == Pong()

    buffer = IOBuffer("+OK\r\n")
    @test next_protocol_message(buffer) == Ok()

    buffer = IOBuffer("-ERR 'Unknown Protocol Operation'\r\n")
    @test next_protocol_message(buffer) == Err("Unknown Protocol Operation")
end

@testset "Serializing client operations." begin
    serialize(m) = String(repr(NATS.MIME_PROTOCOL(), m))

    json = """{"verbose":false,"pedantic":false,"tls_required":false,"lang":"julia","version":"0.0.1"}"""
    @test serialize(JSON3.read(json, NATS.Connect)) == """CONNECT $json\r\n"""

    @test serialize(Pub("FOO", nothing, 11, "Hello NATS!")) == "PUB FOO 11\r\nHello NATS!\r\n"
    @test serialize(Pub("FRONT.DOOR", "JOKE.22", 11, "Knock Knock")) == "PUB FRONT.DOOR JOKE.22 11\r\nKnock Knock\r\n"
    @test serialize(Pub("NOTIFY", nothing, 0, "")) == "PUB NOTIFY 0\r\n\r\n"

    @test serialize(HPub("FOO", nothing, 22, 33, "NATS/1.0\r\nBar: Baz\r\n\r\n", "Hello NATS!")) == "HPUB FOO 22 33\r\nNATS/1.0\r\nBar: Baz\r\n\r\nHello NATS!\r\n"
    @test serialize(HPub("FRONT.DOOR", "JOKE.22", 45, 56, "NATS/1.0\r\nBREAKFAST: donut\r\nLUNCH: burger\r\n\r\n", "Knock Knock")) == "HPUB FRONT.DOOR JOKE.22 45 56\r\nNATS/1.0\r\nBREAKFAST: donut\r\nLUNCH: burger\r\n\r\nKnock Knock\r\n"

    @test serialize(HPub("NOTIFY", nothing, 22, 22, "NATS/1.0\r\nBar: Baz\r\n\r\n", "")) == "HPUB NOTIFY 22 22\r\nNATS/1.0\r\nBar: Baz\r\n\r\n\r\n"
    @test serialize(HPub("MORNING.MENU", nothing, 47, 51, "NATS/1.0\r\nBREAKFAST: donut\r\nBREAKFAST: eggs\r\n\r\n", "Yum!")) == "HPUB MORNING.MENU 47 51\r\nNATS/1.0\r\nBREAKFAST: donut\r\nBREAKFAST: eggs\r\n\r\nYum!\r\n"

    @test serialize(Sub("FOO", nothing, "1")) == "SUB FOO 1\r\n"
    @test serialize(Sub("BAR", "G1", "44")) == "SUB BAR G1 44\r\n"

    @test serialize(Unsub("1", nothing)) == "UNSUB 1\r\n"
    @test serialize(Unsub("1", 5)) == "UNSUB 1 5\r\n"
end

@testset "Serializing headers." begin
    hmsg = HMsg("FOO.BAR", "9", "BAZ.69", 34, 45, "NATS/1.0\r\nA: B\r\nC: D\r\nC: E\r\n\r\n", "Hello World")
    @test headers(hmsg) == ["A" => "B", "C" => "D", "C" => "E"]
    @test headers(hmsg, "C") == ["D", "E"]
    @test_throws ArgumentError header(hmsg, "C")
    @test header(hmsg, "A") == "B"
    @test String(repr(MIME_HEADERS(), headers(hmsg))) == hmsg.headers

    no_responder_hmsg = HMsg("FOO.BAR", "9", "BAZ.69", 16, 16, "NATS/1.0 503\r\n\r\n", nothing)
    @test NATS.statuscode(no_responder_hmsg) == 503
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
