
using NATS

function main()
    NATS.connect(default = true)

    subscribe("test_subject") do x
        @show x
    end

    while true
        sleep(5)
        try
            publish("test_subject")
        catch
            break
        end
    end

    sleep(10)
end

Base.exit_on_sigint(false)

disable_sigint() do
    main()
end
