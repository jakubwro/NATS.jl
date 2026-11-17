# Run in an isolated process by jetdict_concurrency.jl. Only remote operations
# are doubled; JetDict construction, scope inheritance and indexing are real.
using NATS
using NATS.JetStream
using Dates
using Test

const test_stream = JetStream.StreamInfo(
    config = JetStream.StreamConfiguration(name = "KV_concurrency"),
    state = JetStream.StreamState(messages = 0, bytes = 0,
        first_seq = 0, last_seq = 0, consumer_count = 0),
    created = JetStream.NanoDate(DateTime(2026)))

JetStream.get_jetdict_stream_info(::NATS.Connection, ::String, ::Symbol) = test_stream

const response_header = "NATS/1.0\r\nNats-Sequence: 1\r\n\r\n"
const read_response = NATS.Msg("unused", 0, nothing, sizeof(response_header),
    Vector{UInt8}(response_header * "value"))

JetStream.keyvalue_get(::NATS.Connection, ::String, ::String) = read_response

const cas_arrivals = Channel{Nothing}(2)
const cas_release = Base.Event()
const cas_lock = ReentrantLock()
const cas_revision = Ref(1)

function JetStream.keyvalue_put(::NATS.Connection, ::String, key::String, value::String, revision::Integer)
    seq = if key == "conflict"
        # Both competing writes must reach the server with the revision they
        # read, without a local lock serializing their network operations.
        put!(cas_arrivals, nothing)
        wait(cas_release)
        lock(cas_lock) do
            revision == cas_revision[] || throw(ErrorException("wrong last sequence"))
            cas_revision[] += 1
        end
    else
        expected = value == "first update" ? 1 : value == "second update" ? 2 : 3
        revision == expected || error("Expected revision $expected for $key, got $revision")
        revision + 1
    end
    JetStream.PubAck(stream = "KV_concurrency", seq = seq, duplicate = nothing, domain = nothing)
end

@testset "Parallel optimistic reads and writes retain every revision" begin
    nc = NATS.Connection(;
        url = "nats://", status = NATS.CONNECTED, info = nothing,
        send_enqueue_when_disconnected = true,
        pong_count = 0, pong_received_at = 0.0,
        connect_init_count = 0, reconnect_count = 0,
        send_buffer_flushed = true, drain_timeout = 0.1, drain_poll = 0.0,
        request_counter = 0, request_subscription = nothing)
    kv = JetDict{String}(nc, "concurrency")

    with_optimistic_concurrency(kv) do
        # Compile the indexing path before releasing concurrent readers.
        kv["warmup"]
        kv["warmup"] = "first update"
        kv["warmup"] = "second update"
        workers = max(4, Threads.nthreads())
        keys_per_worker = 20_000
        start = Base.Event()
        tasks = map(1:workers) do worker
            Threads.@spawn begin
                wait(start)
                for i in 1:keys_per_worker
                    key = "$(worker)_$i"
                    kv[key] == "value" || error("Unexpected read response")
                    kv[key] = "first update"
                    kv[key] = "second update"
                end
            end
        end
        notify(start)
        foreach(fetch, tasks)
        # Every key must retain its last acknowledged revision. The response
        # double rejects a final update if any revision was lost or corrupted.
        @test all(setindex!(kv, "final update", "$(worker)_$i") === kv
            for worker in 1:workers for i in 1:keys_per_worker)
        @test setindex!(kv, "final update", "warmup") === kv
    end

    @testset "Competing writes keep server compare-and-set semantics" begin
        with_optimistic_concurrency(kv) do
            @test kv["conflict"] == "value"
            tasks = map(1:2) do _
                Threads.@spawn try
                    kv["conflict"] = "update"
                    :updated
                catch err
                    err
                end
            end
            arrived = timedwait(() -> Base.n_avail(cas_arrivals) == 2, 5.0; pollint = 0.001)
            # Always release the first writer, including if a regression holds
            # the revision lock across its request and blocks the second one.
            notify(cas_release)
            @test arrived == :ok
            results = fetch.(tasks)
            @test count(==(:updated), results) == 1
            @test count(r -> r isa ErrorException && r.msg == "wrong last sequence", results) == 1
        end
    end
end
