# Run without a server: julia --project=. --threads=4,1 test/send_buffer.jl
module SendBufferTests

using NATS
using Dates
using Test

function offline_connection()
    NATS.Connection(;
        url = "nats://", status = NATS.CONNECTED, info = nothing,
        send_enqueue_when_disconnected = true,
        pong_count = 0, pong_received_at = 0.0,
        connect_init_count = 0, reconnect_count = 0,
        send_buffer_flushed = true, drain_timeout = 0.1, drain_poll = 0.001,
        request_counter = 0, request_subscription = nothing)
end

take_wire(nc) = @lock nc.send_buffer_cond String(take!(nc.send_buffer))
wire(msg::NATS.ProtocolMessage) = sprint(show, NATS.MIME_PROTOCOL(), msg)
wire(msgs::Vector{NATS.Pub}) = join(wire.(msgs))

# Pause only after the first enqueue attempt has encountered backpressure.
struct GatedRetry
    entered::Base.Event
    release::Base.Event
end

function Base.iterate(delays::GatedRetry, state = 1)
    state > 1 && return nothing
    notify(delays.entered)
    wait(delays.release)
    (0.001, state + 1)
end

@testset "Send buffer synchronization" begin
    pub = NATS.Pub("buffer.test", nothing, 0, UInt8[0x78])
    for message in (pub, [pub])
        @testset "Backpressure: $(typeof(message))" begin
            nc = offline_connection()
            nc.send_buffer_limit = 1
            write(nc.send_buffer, "full")
            @test !NATS.try_send(nc, message)

            delays = GatedRetry(Base.Event(), Base.Event())
            nc.send_retry_delays = delays
            sender = @async NATS.send(nc, message)
            try
                @test timedwait(() -> (@atomic delays.entered.set), 5.0) == :ok
                # Another task must be able to free space while send is backing off.
                @test take_wire(nc) == "full"
            finally
                notify(delays.release)
            end
            @test timedwait(() -> istaskdone(sender), 5.0) == :ok
            @test fetch(sender) === nothing
            @test take_wire(nc) == wire(message)

            write(nc.send_buffer, "full")
            nc.send_retry_delays = Float64[]
            @test_throws "Cannot send, send buffer too large." NATS.send(nc, message)
            @test take_wire(nc) == "full"
        end
    end

    @testset "Control messages can use an outer lock despite backpressure" begin
        nc = offline_connection()
        nc.send_buffer_limit = 1
        nc.send_retry_delays = Float64[]
        write(nc.send_buffer, "full")
        sub = NATS.Sub("buffer.control", nothing, 1)
        unsub = NATS.Unsub(1, 0)
        @lock nc.send_buffer_cond begin
            @test NATS.send(nc, sub) === nothing
            @test NATS.send(nc, unsub) === nothing
        end
        @test take_wire(nc) == "full" * wire(sub) * wire(unsub)
    end

    @testset "Rejected sends leave state untouched" begin
        nc = offline_connection()
        @test_throws NATS.SendDeadlineExceeded NATS.send(nc, pub; deadline = Nanosecond(0))
        @test isempty(take_wire(nc))
        sub = NATS.subscribe(nc, "buffer.rejected")
        sub_data = nc.sub_data[sub.sid]
        take_wire(nc)
        NATS.status(nc, NATS.DRAINED)
        @test_throws ErrorException NATS.unsubscribe(nc, sub; max_msgs = 2)
        @test !haskey(nc.unsubs, sub.sid)
        @test_throws ErrorException NATS.unsubscribe(nc, sub)
        @test isopen(sub_data.channel)
        @test_throws ErrorException NATS.drain(nc, sub)
        @test isempty(nc.draining_sids)
        @test isempty(take_wire(nc))
        NATS.cleanup_sub_resources(nc, sub.sid)
    end

    @testset "Unsubscribe state is retained across reconnect" begin
        nc = offline_connection()
        sub = NATS.subscribe(nc, "buffer.unsubscribe")
        take_wire(nc)
        NATS.unsubscribe(nc, sub; max_msgs = 2)
        @test take_wire(nc) == wire(NATS.Unsub(sub.sid, 2))
        NATS.reopen_send_buffer(nc)
        @test take_wire(nc) == wire(sub) * wire(NATS.Unsub(sub.sid, 2))
        NATS.unsubscribe(nc, sub)
        @test !haskey(nc.sub_data, sub.sid)
        @test !haskey(nc.unsubs, sub.sid)
    end
end

end # module
