

const INTERRUPT_HANDLER_SLEEP_SECONDS = 0.1

function start_interrupt_handler()
    interrupt_handler_task = @async begin

        if Threads.threadid() != 1
            @warn "Interrupt handler started on wrong thread"
            # In this case interrupt will be ignored, better to kill process on interrupt.
            Base.exit_on_sigint(true)
            return
        end

        while true
            try
                sleep(INTERRUPT_HANDLER_SLEEP_SECONDS)
            catch err
                if err isa InterruptException
                    disable_sigint() do
                        @info "Handling interrupt."
                        drain()
                    end
                end
            end
        end
    end

    errormonitor(interrupt_handler_task)
end
