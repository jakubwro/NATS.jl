using Test
using NATS
using NATS.JetStream
using Random

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection, ensure NATS is working on $(NATS.NATS_DEFAULT_HOST):$(NATS.NATS_DEFAULT_PORT)."


@testset "Work queue." begin

    connection = NATS.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    did_create = stream_create(
        connection = connection,
        name = stream_name,
        description = "Work queue stream.",
        subjects = ["$subject_prefix.*"],
        retention = workqueue,
        storage = memory)

    @test did_create

    consumer = NATS.JetStream.consumer_create(
        stream_name;
        connection,
        filter_subject="$subject_prefix.*",
        ack_policy = "explicit",
        name ="workqueue_consumer")

    n_workers = 3
    n_publications = 100
    results = Channel(n_publications)
    cond = Channel()

    for i in 1:n_workers
        worker_task = Threads.@spawn :default NATS.JetStream.worker(stream_name, "workqueue_consumer"; connection) do msg
            put!(results, (i, msg))
            if Base.n_avail(results) == n_publications
                close(cond)
            end
        end
        errormonitor(worker_task)
    end
    
    for i in 1:n_publications
        publish(connection, "$subject_prefix.task", "Task $i")
    end

    try take!(cond) catch end
    close(results)
    res = collect(results)
    wa = first.(res)
    msgs = last.(res)


    for i in 1:n_workers
        @test i in wa
    end

    payloads = NATS.payload.(msgs)

    for i in 1:n_publications
        @test "Task $i" in payloads
    end
end
