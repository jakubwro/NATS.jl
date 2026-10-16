# Run standalone, without a server: julia --project=. test/parser_fragmentation.jl
using Test
using NATS

@testset "Fragmented message headers preserve bytes" begin
    function parse_fragmented(wire, first_read_length)
        io = IOBuffer(wire)
        # Model readavailable returning a prefix; the remainder stays in the same IO.
        buffer = read(io, first_read_length)
        data = NATS.ParserData()
        NATS.parse_buffer(io, buffer, data)
        # The next readavailable returns what the parser did not read itself.
        eof(io) || NATS.parse_buffer(io, read(io), data)
        @test eof(io)
        convert(NATS.Msg, only(data.results))
    end

    for header in ("MSG foo 1 4\r\n", "HMSG foo 1 12 16\r\n")
        headers = startswith(header, "HMSG") ? "NATS/1.0\r\n\r\n" : ""
        wire = header * headers * "🙂\r\n"
        # Split in the control line, headers, payload and trailing CRLF.
        for first_read_length in 1:ncodeunits(wire)
            msg = parse_fragmented(wire, first_read_length)
            @test msg.subject == "foo"
            @test msg.headers_length == ncodeunits(headers)
            @test NATS.payload(msg) == "🙂"
        end
    end

    # Exercise both header-completion branches, including a split inside UTF-8.
    wire = "MSG f🙂 1 4\r\n🙂\r\n"
    for first_read_length in (ncodeunits("MSG f"), ncodeunits("MSG f") + 1)
        msg = parse_fragmented(wire, first_read_length)
        @test msg.subject == "f🙂"
        @test NATS.payload(msg) == "🙂"
    end
end
