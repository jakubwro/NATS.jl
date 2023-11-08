

const INTERRUPT_HANDLER_SLEEP_SECONDS = 0.3333

function start_interrupt_handler()

    if Threads.nthreads(:interactive) != 1
        @warn "Running $(Threads.nthreads(:interactive)) interactive threads. NATS require exactly one interactive thread to handle SIGINT correctly."
    end

    interrupt_handler_task = Threads.@spawn :interactive begin
        while true
            try
                sleep(INTERRUPT_HANDLER_SLEEP_SECONDS)
            catch err
                if err isa InterruptException
                    @info "Handling interrupt."
                    # if isinteractive()
                        # For interractive session interrupt REPL, `drain` manually if needed.
                        # schedule(Base.roottask, InterruptException(); error = true)
                    # else
                        # Non interactive, drain all connections.
                        drain()
                    # end
                end
            end
        end
    end

    errormonitor(interrupt_handler_task)
end