using Test
using NATS
using Random

Base.exit_on_sigint(false)

function sigint_current_process()
    cmd = `kill -2 $(getpid())`
    res = run(cmd)
    res.exitcode == 0 || error("$cmd failed with $(res.exitcode)")
end

@testset "SIGINT during heavy publications." begin
    nc = NATS.connect()
    received_count = Threads.Atomic{Int64}(0)
    published_count = Threads.Atomic{Int64}(0)
    subject = "pub_subject"
    sub = subscribe(subject) do msg
        Threads.atomic_add!(received_count, 1)
    end
    sleep(0.5)

    pub_task = Threads.@spawn begin
        for i in 1:10000
            timer = Timer(0.001)
            for _ in 1:10
                publish(subject; payload = "Hi!")
            end
            Threads.atomic_add!(published_count, 10)
            try wait(timer) catch end
        end
        @info "Publisher finished."
    end
    sleep(2)
    @info "Published: $(published_count.value), received: $(received_count.value)."
    @info "Sending SIGINT"
    sigint_current_process()
    wait(pub_task)
    @info "Published: $(published_count.value), received: $(received_count.value)."

    @test status(nc) == NATS.DRAINED
end

