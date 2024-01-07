### interrupts.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains logic for handling interrupt signal.
#
### Code:

const INTERRUPT_HANDLER_SLEEP_SECONDS = 0.1

function can_interrupt_repl()
    isdefined(Base, :active_repl_backend) && Base.active_repl_backend.in_eval
end


function start_legacy_interrupt_handler(interactive = isinteractive())
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
                            can_interrupt_repl() && schedule(Base.roottask, InterruptException(); error = true)
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


function start_new_interrupt_handler(interactive = isinteractive())
    @info "Starting new interrupt handler."
    interrupt_handler_task = @async begin
        if interactive && !isinteractive()
            @warn "Interrupt handler was started with `interactive` in non interactive session. Interrupts might be ignored."
        end

        while true
            @lock Base.INTERRUPT_CONDITION wait(Base.INTERRUPT_CONDITION)
            disable_sigint() do
                @info "Draining all due to interrupt signal."
                drain()
            end
        end
    end

    errormonitor(interrupt_handler_task)
end

function start_interrupt_handler(interactive = isinteractive())
    if VERSION < v"1.11"
        start_legacy_interrupt_handler(interactive)
    else
        start_new_interrupt_handler(interactive)
    end
end
