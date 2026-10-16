# Run standalone, without a server: julia --project=. test/parser_fragmentation.jl
using Test
using NATS

# Serves `chunks` one by one, like a socket that receives every chunk in a separate read.
mutable struct ChunkedIO <: IO
    chunks::Vector{Vector{UInt8}}
end

Base.eof(io::ChunkedIO) = isempty(io.chunks)
Base.bytesavailable(io::ChunkedIO) = eof(io) ? 0 : length(first(io.chunks))

function Base.read(io::ChunkedIO, ::Type{UInt8})
    eof(io) && throw(EOFError())
    chunk = first(io.chunks)
    byte = popfirst!(chunk)
    isempty(chunk) && popfirst!(io.chunks)
    byte
end

# Parses `wire` received in chunks ending at `split_points`.
function parse_chunks(wire, split_points)
    bytes = Vector{UInt8}(wire)
    bounds = [0; split_points; length(bytes)]
    io = ChunkedIO([bytes[bounds[i]+1:bounds[i+1]] for i in 1:length(bounds)-1])
    result = NATS.ProtocolMessage[]
    NATS.parser_loop(io) do msgs
        append!(result, map(msg -> msg isa NATS.MsgRaw ? convert(NATS.Msg, msg) : msg, msgs))
    end
    result
end

@testset "Fragmented message headers preserve bytes" begin
    for header in ("MSG foo 1 4\r\n", "HMSG foo 1 12 16\r\n")
        headers = startswith(header, "HMSG") ? "NATS/1.0\r\n\r\n" : ""
        wire = header * headers * "🙂\r\n"
        for split_points in (Int[], [ncodeunits(header) - 1])
            msg = only(parse_chunks(wire, split_points))
            @test msg.subject == "foo"
            @test msg.headers_length == ncodeunits(headers)
            @test NATS.payload(msg) == "🙂"
        end
    end

    # Split inside the subject, including a split inside UTF-8.
    wire = "MSG f🙂 1 4\r\n🙂\r\n"
    for split_point in (ncodeunits("MSG f"), ncodeunits("MSG f") + 1)
        msg = only(parse_chunks(wire, [split_point]))
        @test msg.subject == "f🙂"
        @test NATS.payload(msg) == "🙂"
    end
end

@testset "Messages split at any position" begin
    wire = """INFO {"server_id":"NCUWF4KWI6NQR4NRT2ZWBI6WBW6V63XERJGREROVAVV6WZ4O4D7R6CVK","server_name":"my_nats_server","version":"2.9.21","proto":1,"go":"go1.19.12","host":"0.0.0.0","port":4222,"headers":true,"max_payload":1048576} \r\n""" *
        "MSG FOO.BAR 9 11\r\nHello World\r\n" *
        "MSG   FOO.BAR  9     GREETING.34  11\r\nHello World\r\n" *
        "HMSG FOO.BAR 9 BAZ.69 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n" *
        "PING\r\nPONG\r\n+OK\r\n-ERR 'Unknown Protocol Operation'\r\n" *
        "MSG FOO.BAR 9 $(10_000)\r\n$(repeat("x", 10_000))\r\n" *
        "MSG FOO.BAR 9 0\r\n\r\n"
    expected = parse_chunks(wire, Int[])
    @test length(expected) == 10
    @test NATS.payload(expected[9]) == repeat("x", 10_000)

    # Split in two chunks at every position.
    @test all(parse_chunks(wire, [i]) == expected for i in 1:ncodeunits(wire)-1)
    # Every message split across many small chunks.
    for chunk_size in (1, 2, 3, 7, 64, 4096)
        @test parse_chunks(wire, collect(chunk_size:chunk_size:ncodeunits(wire)-1)) == expected
    end
end

@testset "Connection closed in the middle of a message" begin
    @test parse_chunks("PING\r\nMSG FOO.BAR 9 11\r\nHello", Int[]) == [NATS.Ping()]
end
