function interactive_status(cond = nothing)
    try
        while true
            NATS.status()
            sleep(0.05)
            if !isnothing(cond) && !isopen(cond)
                return
            end
            write(stdout, "\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K")
        end
    catch e
        if !(e isa InterruptException)
            throw(e)
        end
    end
end
