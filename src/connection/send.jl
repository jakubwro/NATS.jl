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

    delays = Base.ExponentialBackOff(n=1, first_delay=0.01, max_delay=1)
    
    # this is faster than
    # retry(() -> put!(outbox(nc), message); delays)()
    for d in delays
        try
            # During reconnect outbox might be closed. Wait for a new outbox open.
            put!(outbox(nc), message)
            return true
        catch
            can_send(nc, message) || error("Cannot send on connection with status $(status(nc))")
            sleep(d)
        end
    end
    false
end

const buffer = ProtocolMessage[]

function sendloop(nc::Connection, io::IO, old_sock)
    try
        mime = MIME_PROTOCOL()
        outbox_channel = outbox(nc)
        to_resend = collect(buffer)
        !isempty(to_resend) && @warn "Buffer has $(length(to_resend)) msgs"
        while isopen(outbox_channel)
            fetch(outbox_channel) # Wait untill some messages are there.
            empty!(buffer)
            buf = IOBuffer() # Buffer write to avoid often task yield.
            pending = Base.n_avail(outbox_channel)
            batch = min(pending, 5000)
            @assert batch > 0
            # for msg in to_resend
            #     show(buf, mime, msg)
            # end
            empty!(to_resend)
            # send_buf = []
            for _ in 1:batch
                msg = take!(outbox_channel)
                push!(buffer, msg)
                # push!(send_buf, msg)
                if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                    @lock state.lock begin nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
                end
                show(buf, mime, msg)
            end
           
            @async begin
                sleep(0.04)
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
            # If task errors on write, maybe msgs should be resend
        end
    end
end
