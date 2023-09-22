

using Test
using NATS
using NATS.JetStream

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