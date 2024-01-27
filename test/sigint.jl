using NATS
using Random

@show getpid()
Base.exit_on_sigint(false)

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
    sub = subscribe(connection, subject) do msg
        Threads.atomic_add!(received_count, 1)
    end
    sleep(0.5)

    pub_task = Threads.@spawn disable_sigint() do
        Base.sigatomic_begin()
        for i in 1:1000
            timer = Timer(0.01)
            for _ in 1:10
                publish(connection, subject, "Hi!")
            end
            Threads.atomic_add!(published_count, 10)
            try wait(timer) catch end
        end
        @info "Publisher finished."
    end
    # errormonitor(pub_task)
    sleep(2)
    @info "Published: $(published_count.value), received: $(received_count.value)."

    sleep(2)

end

t = Threads.@spawn :default disable_sigint() do
    Base.sigatomic_begin()
    run_test()
end
errormonitor(t)

try
    while true
        sleep(0.2)
    end
catch err
    @error err
end
drain(NATS.connection(1))

NATS.status()
if NATS.status(NATS.connection(1)) == NATS.DRAINED
    @info "Test passed correctly."
else
    @error "Test failed, connection status is not DRAINED"
end
