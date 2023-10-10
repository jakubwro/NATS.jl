function can_send(nc::Connection, message::ProtocolMessage)
    if isdrained(nc)
        if message isa Unsub || message isa Pong
            !(status(nc) == DRAINED || status(nc) == DISCONNECTED)
        else
            false
        end
    else
        true
    end
end

function send(nc::Connection, message::ProtocolMessage)
    can_send(nc, message) || error("Cannot send on connection with status $(status(nc))")

    delays = Base.ExponentialBackOff(n=100, first_delay=0.001, max_delay=0.01)
    
    # this is faster than
    # retry(() -> put!(outbox(nc), message); delays)()
    start_time = time()
    for d in delays
        try
            # During reconnect outbox might be closed. Wait for a new outbox open.
            put!(outbox(nc), message)
            time_elapsed = time() - start_time
            if time_elapsed > 1.0
                @warn "Enqueueing a message to outbox took $time_elapsed seconds. Outbox might be too small or connection disconnected too long. Outbox size: $(Base.n_avail(outbox(nc)))."
            end
            return
        catch
            can_send(nc, message) || error("Cannot send on connection with status $(status(nc))")
            sleep(d)
        end
    end
    error("Unable to send. Outbox closed for more than $(sum(delays)) seconds.")
end

function sendloop(nc::Connection, io::IO, old_sock)
    try
        mime = MIME_PROTOCOL()
        outbox_channel = outbox(nc)
        while isopen(outbox_channel)
            fetch(outbox_channel) # Wait untill some messages are there.
            buf = IOBuffer() # Buffer write to avoid often task yield.
            pending = Base.n_avail(outbox_channel)
            batch_size = min(pending, SEND_BATCH_SIZE) # TODO: configure it dynamically with ENV
            @assert batch_size > 0
            for _ in 1:batch_size
                msg = take!(outbox_channel)
                if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                    @lock state.lock begin nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
                end
                show(buf, mime, msg)
            end
           
            @async begin
                sleep(0.3)
                !isnothing(old_sock) && begin close(old_sock); @info "Socket close time: $(time())" end
                old_sock = nothing
            end
            write(io, take!(buf))
            flush(io)
        end
        @info "Sender task finished at $(time()), $(Base.n_avail(outbox_channel)) msgs in outbox."
    catch err
        @info "Sender task finished at $(time())."
        if err isa InvalidStateException
            # This is fine, outbox closed by reconnect loop.
        else
            rethrow()
            # TODO: If task errors on write, maybe msgs should be resend?
        end
    end
end
