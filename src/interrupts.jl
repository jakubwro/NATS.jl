

const INTERRUPT_HANDLER_SLEEP_SECONDS = 0.1

function start_interrupt_handler(interactive = isinteractive())
    interrupt_handler_task = @async begin

        if Threads.threadid() != 1
            @warn "Interrupt handler started on a wrong thread, must run on thread 1 to receive interrupts"
            # In this case interrupt will be ignored, better to kill process on interrupt.
            Base.exit_on_sigint(true)
            return
        end

        if interactive && !isinteractive()
            @warn "Interrupt handler was started with `interactive` in non interactive session. Interrupts might be ignored."
        end

        while true
            try
                sleep(INTERRUPT_HANDLER_SLEEP_SECONDS)
            catch err
                if err isa InterruptException
                    disable_sigint() do
                        @info "Handling interrupt."
                        if interactive 
                            if isdefined(Base, :active_repl_backend) && Base.active_repl_backend.in_eval
                                schedule(Base.roottask, InterruptException(); error = true)
                            end
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
