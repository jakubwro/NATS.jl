using Test
using NATS
using NATS.JetStream
using Random
using Sockets

@info "Running with $(Threads.nthreads()) threads."

function have_nats()
    try
        Sockets.getaddrinfo(get(ENV, "NATS_HOST", "localhost"))
        nc = NATS.connect()
        @assert nc.status == NATS.CONNECTED
        @assert NATS.info(nc).jetstream == true
        @info "JetStream avaliable, running connected tests."
        true
    catch err
        @info "JetStream unavailable, skipping connected tests."  err
        false
    end
end

@testset "Should be connected to JetStream" begin
    @test have_nats()
end

@testset "Create stream and delete stream." begin
    connection = NATS.connect()
    stream_config = StreamConfiguration(
        name = "SOME_STREAM",
        description = "SOME_STREAM stream",
        subjects = ["SOME_STREAM.*"],
        retention = :workqueue,  
        storage = :memory,
    )
    stream_info = JetStream.stream_create(connection, stream_config)

    @test stream_info isa JetStream.StreamInfo
    names = JetStream.stream_names(connection, "SOME_STREAM.*")
    @test "SOME_STREAM" in names
    @test length(names) == 1
    JetStream.stream_delete(connection, stream_info)
    names = JetStream.stream_names(connection, "SOME_STREAM.*")
    @test !("SOME_STREAM" in names)
end

# @testset "Stream names handling error." begin
#     connection = NATS.connect()
#     # @test_throws ErrorException JetStream.stream_names(; connection, timer = Timer(0))

#     response = JSON3.read("""{"error": {"code": 400, "description": "failed"}}""")
#     @test_throws JetStream.ApiError JetStream.throw_on_api_error(response)
# end

@testset "Invalid stream name." begin
    connection = NATS.connect()
    stream_config = StreamConfiguration(
        name = "SOME*STREAM",
        description = "Stream with invalid name",
        subjects = ["SOME_STREAM.*"],
    )
    @test_throws ErrorException JetStream.stream_create(connection, stream_config)
end

@testset "Create stream, publish and subscribe." begin
    connection = NATS.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    stream_config = StreamConfiguration(
        name = stream_name,
        description = "Test generated stream.",
        subjects = ["$subject_prefix.*"],
        retention = :limits,
        storage = :memory,
        metadata = Dict("asdf" => "aaaa")
    )
    stream_info = JetStream.stream_create(connection, stream_config)
    @test stream_info isa JetStream.StreamInfo

    # TODO: fix this
    # @test_throws ErrorException JetStream.create(connection, stream_config)

    NATS.publish(connection, "$subject_prefix.test", "Publication 1")
    NATS.publish(connection, "$subject_prefix.test", "Publication 2")
    NATS.publish(connection, "$subject_prefix.test", "Publication 3")

    consumer_config = JetStream.ConsumerConfiguration(
        filter_subjects=["$subject_prefix.*"],
        ack_policy = :explicit,
        name ="c1",
        durable_name = "c1" #TODO: make it not durable
    )
    consumer = JetStream.consumer_create(connection, consumer_config, stream_info)
    for i in 1:3
        msg = JetStream.consumer_next(connection, consumer, no_wait = true)
        @test msg isa NATS.Msg
    end

    @test_throws NATSError @show JetStream.consumer_next(connection, consumer; no_wait = true)
    JetStream.consumer_delete(connection, consumer)
end

uint8_vec(s::String) = convert.(UInt8, collect(s))

# TODO: fix this testest
# @testset "Ack" begin
#     connection = NATS.connect()
#     no_reply_to_msg = NATS.Msg("FOO.BAR", "9", nothing, 0, uint8_vec("Hello World"))
#     @test_throws ErrorException JetStream.consumer_ack(no_reply_to_msg; connection)
#     @test_throws ErrorException JetStream.consumer_nak(no_reply_to_msg; connection)

#     msg = NATS.Msg("FOO.BAR", "9", "ack_subject", 0, uint8_vec("Hello World"))
#     c = Channel(10)
#     sub = NATS.subscribe(connection, "ack_subject") do msg
#         put!(c, msg)
#     end
#     received = take!(c)
#     JetStream.consumer_ack(received; connection)
#     JetStream.consumer_nak(received; connection)
#     NATS.drain(connection, sub)
#     close(c)
#     acks = collect(c)
#     @test length(acks) == 2
#     @test "-NAK" in NATS.payload.(acks)
# end

@testset "Key value - 100 keys" begin
    connection = NATS.connect()
    kv = JetStream.JetDict{String}(connection, "test_kv")
    @time @sync for i in 1:100
        @async kv["key_$i"] = "value_$i"
    end

    other_conn = NATS.connect()
    kv = JetStream.JetDict{String}(connection, "test_kv")
    for i in 1:100
        @test kv["key_$i"] == "value_$i"
    end
    
    @test length(collect(kv)) == 100
    keyvalue_stream_delete(connection, "test_kv")
end

@testset "Create and delete KV bucket" begin
    connection = NATS.connect()
    bucket = randstring(10)
    kv = JetStream.JetDict{String}(connection, bucket)
    @test_throws KeyError kv["some_key"]
    kv["some_key"] = "some_value"
    @test kv["some_key"] == "some_value"
    empty!(kv)
    @test_throws KeyError kv["some_key"]
    JetStream.keyvalue_stream_delete(connection, bucket)
    @test_throws "stream not found" first(kv)
end

@testset "Watch kv changes" begin
    connection = NATS.connect()
    kv = JetStream.JetDict{String}(connection, "test_kv")

    changes = []
    sub = watch(kv) do change
        push!(changes, change)
    end

    t = @async begin
        kv["a"] = "1"
        sleep(0.1)
        kv["b"] = "2"
        sleep(0.1)
        delete!(kv, "a")
        sleep(0.1)
        kv["b"] = "3"
        sleep(0.1)
        kv["a"] = "4"
        sleep(0.5)
    end

    wait(t)
    stream_unsubscribe(connection, sub)

    @test length(changes) == 5
    @test changes == ["a" => "1", "b" => "2", "a" => nothing, "b" => "3", "a" => "4"]
    keyvalue_stream_delete(connection, "test_kv")
end


@testset "Channel message passing" begin
    connection = NATS.connect()
    ch = JetChannel{String}(connection, "test_channel")
    put!(ch, "msg 1")
    @test take!(ch) == "msg 1"

    t = @async take!(ch)
    sleep(5)
    put!(ch, "msg 2")
    wait(t)
    @test t.result == "msg 2"
    channel_stream_delete(connection, "test_channel")
end
