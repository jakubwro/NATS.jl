using Test
using NATS
using NATS.JetStream
using Random

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection, ensure NATS is working on $(NATS.NATS_DEFAULT_HOST):$(NATS.NATS_DEFAULT_PORT)."


@testset "Create stream" begin
    connection = NATS.connect()
    did_create = stream_create(;
        name = "SOME_STREAM",
        description = "SOME_STREAM stream",
        subjects = ["SOME_STREAM.*"],
        retention = workqueue,
        storage = memory,
        connection = connection)

    @test did_create
end

@testset "Create stream, publish and subscribe." begin

    connection = NATS.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    did_create = stream_create(
        connection = connection,
        name = stream_name,
        description = "Test generated stream.",
        subjects = ["$subject_prefix.*"],
        retention = limits,
        storage = memory)

    @test did_create

    publish(connection, "$subject_prefix.test", "Publication 1")
    publish(connection, "$subject_prefix.test", "Publication 2")
    publish(connection, "$subject_prefix.test", "Publication 3")

    consumer = NATS.JetStream.consumer_create(
        stream_name;
        connection,
        filter_subject="$subject_prefix.*",
        ack_policy = "explicit",
        name ="c1")
    
    msg = NATS.JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    msg = NATS.JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    msg = NATS.JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    @test_throws ErrorException NATS.JetStream.next(stream_name, consumer; connection)
end
