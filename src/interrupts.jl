

const INTERRUPT_HANDLER_SLEEP_SECONDS = 0.1

function start_interrupt_handler()
    interrupt_handler_task = @async begin

        if Threads.threadid() != 1
            @warn "Interrupt handler started on a wrong thread, must run on thread 1 to receive interrupts"
            # In this case interrupt will be ignored, better to kill process on interrupt.
            Base.exit_on_sigint(true)
            return
        end

        Base.exit_on_sigint(false)

        while true
            try
                sleep(INTERRUPT_HANDLER_SLEEP_SECONDS)
            catch err
                if err isa InterruptException
                    disable_sigint() do
                        @info "Handling interrupt."
                        if isdefined(Base, :active_repl_backend) && Base.active_repl_backend.in_eval
                            schedule(Base.roottask, InterruptException(); error = true)
                        else
                            drain()
                        end
                    end
                end
            end
        end
    end

    errormonitor(interrupt_handler_task)
end
