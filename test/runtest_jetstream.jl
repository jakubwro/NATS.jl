

using Test
using NATS
using NATS.JetStream
using Random

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection, ensure NATS is working on $(NATS.NATS_DEFAULT_HOST):$(NATS.NATS_DEFAULT_PORT)."


@test "Create stream" begin
    connection = NATS.connect()
    stream_configuration = StreamConfiguration(
        "SOME_STREAM",
        "SOME_STREAM stream",
        ["SOME_STREAM.*"],
        "workqueue",
        "memory"
    )
    did_create = stream_create(stream_configuration; connection)
    @test did_create
end

@test "Create stream, publish and subscribe." begin

    connection = NATS.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    stream_configuration = StreamConfiguration(
        stream_name,
        "Test generated stream.",
        ["$subject_prefix.*"],
        "limits",
        "memory"
    )

    did_create = stream_create(stream_configuration; connection)
    @test did_create

    publish(connection, "$subject_prefix.test", "Publication 1")
    publish(connection, "$subject_prefix.test", "Publication 2")
    publish(connection, "$subject_prefix.test", "Publication 3")

    consumer = NATS.JetStream.consumer_create(stream_name; connection, filter_subject="$subject_prefix.*", ack_policy = "explicit", name ="c1")
    msg = NATS.JetStream.next(stream_name, consumer; connection)
end
