# Run standalone, without a server: julia --project=. test/parser_fragmentation.jl
using Test
using NATS

# Returns at most `chunk` bytes per read, like a socket receiving data in TCP fragments.
mutable struct ChunkedIO <: IO
    data::Vector{UInt8}
    pos::Int
    chunk::Int
end

Base.eof(io::ChunkedIO) = io.pos > length(io.data)
Base.bytesavailable(io::ChunkedIO) = min(io.chunk, length(io.data) - io.pos + 1)
function Base.unsafe_read(io::ChunkedIO, p::Ptr{UInt8}, n::UInt)
    n <= bytesavailable(io) || throw(EOFError())
    GC.@preserve io unsafe_copyto!(p, pointer(io.data, io.pos), n)
    io.pos += n
    nothing
end

function parse_chunked(wire, chunk)
    ops, msgs = NATS.ProtocolMessage[], NATS.Msg[]
    NATS.parser_loop(ChunkedIO(Vector{UInt8}(wire), 1, chunk)) do batch_ops, batch_msgs
        append!(ops, batch_ops)
        append!(msgs, convert.(NATS.Msg, batch_msgs))
    end
    ops, msgs
end

@testset "Fragmented messages preserve bytes" begin
    large = repeat("x", 3 * NATS.READ_BUFFER_SIZE + 17) # Does not fit the read buffer.
    wire = "MSG foo 1 4\r\n🙂\r\n" *
        "HMSG foo 1 12 16\r\nNATS/1.0\r\n\r\n🙂\r\n" *
        "PING\r\n" *
        "MSG f🙂 2 reply.to 4\r\n🙂\r\n" *
        "+OK\r\n" *
        "MSG large 3 $(ncodeunits(large))\r\n$large\r\n" *
        "MSG foo 1 0\r\n\r\n" *
        "-ERR 'Some error'\r\n" *
        "HMSG foo 1 reply 12 12\r\nNATS/1.0\r\n\r\n\r\n"
    expected_ops = [NATS.Ping(), NATS.Ok(), NATS.Err("Some error")]
    expected_msgs = [
        NATS.Msg("foo", 1, nothing, 0, Vector{UInt8}("🙂")),
        NATS.Msg("foo", 1, nothing, 12, Vector{UInt8}("NATS/1.0\r\n\r\n🙂")),
        NATS.Msg("f🙂", 2, "reply.to", 0, Vector{UInt8}("🙂")),
        NATS.Msg("large", 3, nothing, 0, Vector{UInt8}(large)),
        NATS.Msg("foo", 1, nothing, 0, UInt8[]),
        NATS.Msg("foo", 1, "reply", 12, Vector{UInt8}("NATS/1.0\r\n\r\n")),
    ]
    # Small chunks split messages at every position, including inside UTF-8 characters.
    for chunk in [1:40; 1000; NATS.READ_BUFFER_SIZE - 1; NATS.READ_BUFFER_SIZE + 1; ncodeunits(wire)]
        ops, msgs = parse_chunked(wire, chunk)
        @test ops == expected_ops
        @test msgs == expected_msgs
        @test NATS.payload(msgs[1]) == "🙂"
        @test NATS.payload(msgs[2]) == "🙂"
    end
end

@testset "Messages from a small read do not keep the read buffer alive" begin
    wire = "MSG foo 1 3\r\nabc\r\n"
    _, msgs = parse_chunked(wire, ncodeunits(wire))
    @test length(parent(only(msgs).payload)) == ncodeunits(wire)
end

@testset "Malformed message headers" begin
    for wire in ("MSX foo 1 3\r\nabc\r\n", "MSG foo 1\r\n", "MSG foo x 3\r\nabc\r\n", "MSG foo 1 3a\r\nabc\r\n",
                 "HMSG foo 1 5 3\r\nabc\r\n", "MSG foo 1 2 3 4 5\r\nabc\r\n")
        @test_throws ErrorException parse_chunked(wire, ncodeunits(wire))
    end
end
