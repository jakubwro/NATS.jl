
using NATS

function main()
    nc = NATS.connect()

    subscribe(nc, "test_subject") do x
        @show x
    end

    while true
        sleep(5)
        try
            publish(nc, "test_subject")
        catch
            break
        end
    end

    sleep(10)
end

disable_sigint() do
    main()
end
