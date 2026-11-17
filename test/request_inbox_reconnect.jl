# Run in a separate process by reconnect_events.jl so this scheduling probe cannot affect other tests.
using NATS
using Test
using Dates

const buffer_consumer = Ref{Task}()

function NATS.send(nc::NATS.Connection, sub::NATS.Sub; deadline::Nanosecond = typemax(Nanosecond))
    invoke(NATS.send, Tuple{NATS.Connection, Union{NATS.ProtocolMessage, Vector{NATS.Pub}}}, nc, sub; deadline)
    # Try to flush and reconnect after send returns, before new_inbox registers its SUB.
    # The outer send buffer lock must keep both actions atomic.
    yield(buffer_consumer[])
end

@testset "Request inbox registration precedes its first flush" begin
    nc = NATS.Connection(;
        url = "nats://", status = NATS.CONNECTED, info = nothing,
        send_enqueue_when_disconnected = true,
        pong_count = 0, pong_received_at = 0.0,
        connect_init_count = 0, reconnect_count = 0,
        send_buffer_flushed = true, drain_timeout = 0.1, drain_poll = 0.0,
        request_counter = 0, request_subscription = nothing)
    flushed = Ref("")
    buffer_consumer[] = @task begin
        @lock nc.send_buffer_cond begin
            # Simulate flushing to the old server, then rebuilding the buffer for a new server.
            flushed[] = String(take!(nc.send_buffer))
            NATS.reopen_send_buffer(nc)
        end
    end
    inbox, id = NATS.new_inbox(nc)
    wait(buffer_consumer[])
    sub = @atomic nc.request_subscription
    expected = sprint(show, NATS.MIME_PROTOCOL(), sub)
    @test inbox == chop(sub.subject) * string(id)
    @test flushed[] == expected
    @test String(take!(nc.send_buffer)) == expected
end
