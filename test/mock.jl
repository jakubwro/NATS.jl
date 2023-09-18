
import Base: read, write, close, eof, readuntil

# https://github.com/JuliaLang/julia/issues/24526

struct TCPSocketMock <: IO
    input::IO
    output::IO
    traffic_generator::Function
    function TCPSocketMock(traffic_generator)
        @warn "Using mocked connection."
        new(Base.BufferStream(), Base.BufferStream(), traffic_generator)
    end
end

read(mock::TCPSocketMock, n::Int) = read(mock.output, n)
write(mock::TCPSocketMock, s::String) = write(mock.input, s)
close(mock::TCPSocketMock) = nothing
eof(mock::TCPSocketMock) = false
readuntil(mock::TCPSocketMock, s::String) = readuntil(mock.output, s)

function init_connection(io::IO)
    # write(io, info)
    op = readline(io.input)
    @assert startswith(op, "CONNECT")

end

function wait_on_sub_and_publish(io::IO)
    init_connection(io)
    op = next_protocol_message(io.input)
    @assert op isa Sub

    for i in 1:10
        show(io, MIME_PROTOCOL(), Pub(op.reply_to, nothing, 0, nothing))
    end
end

function reply_on_request(io::IO)
    init_connection(io)
    
    op = NATS.next_protocol_message(io)
    while true
        @assert op isa Msg
        show(io, MIME_PROTOCOL(), NATS.Pub(op.reply_to, nothing, 0, nothing))
    end
end

using Pretend

@testset "Request reply." begin
    Pretend.activate()

    mock = TCPSocketMock(identity)

    t = @async reply_on_request(mock)
    errormonitor(t)

    Pretend.apply(NATS.mockable_socket_connect => (port::Integer) -> mock) do
        nc = NATS.connect()
        sleep(1)
        nc
    end
end
