using NATS
using Random

Base.exit_on_sigint(false)

@show isinteractive()

function sigint_current_process()
    cmd = `kill -2 $(getpid())`
    res = run(cmd)
    res.exitcode == 0 || error("$cmd failed with $(res.exitcode)")
end

function run_test()
    connection = NATS.connect()
    received_count = Threads.Atomic{Int64}(0)
    published_count = Threads.Atomic{Int64}(0)
    subject = "pub_subject"
    sub = subscribe(subject; connection) do msg
        Threads.atomic_add!(received_count, 1)
    end
    sleep(0.5)

    pub_task = Threads.@spawn begin
        for i in 1:10000
            timer = Timer(0.001)
            for _ in 1:10
                publish(connection, subject, "Hi!")
            end
            Threads.atomic_add!(published_count, 10)
            try wait(timer) catch end
        end
        @info "Publisher finished."
    end
    sleep(2)
    @info "Published: $(published_count.value), received: $(received_count.value)."
    @info "Sending SIGINT"
    @async begin
        sleep(2)
        sigint_current_process()
    end
    try wait(pub_task) catch end
    @info "Published: $(published_count.value), received: $(received_count.value)."

    sleep(2)

end

t = Threads.@spawn :default run_test()

wait(t)
sleep(5)
NATS.status()
if NATS.status(NATS.connection(1)) == NATS.DRAINED
    @info "Test passed correctly."
else
    @error "Test failed, connection status is not DRAINED"
end

exit()