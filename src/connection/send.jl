function send(nc::Connection, message::ProtocolMessage)
    if isdrained(nc)
        if message isa Unsub || message isa Pong
            status(nc) == DRAINED && error("Connection is drained.")
        else
            error("Connection is drained.")
        end
    end

    # When connection is lost outbox might be closed. Retry until new outbox is there.
    delays = vcat(0.001, 0.01, repeat([0.1], 100))
    retry(put!; delays)(outbox(nc), message)
end

const buffer = ProtocolMessage[]

function sendloop(nc::Connection, io::IO)
    try
        mime = MIME_PROTOCOL()
        outbox_channel = outbox(nc)
        while isopen(outbox_channel)
            if !isempty(buffer)
                @warn "Buffer has $(length(buffer)) messages."
            end
            fetch(outbox_channel) # Wait untill some messages are there.
            buf = IOBuffer() # Buffer write to avoid often task yield.
            pending = Base.n_avail(outbox_channel)
            batch = min(pending, 5000)
            @assert batch > 0
            for msg in buffer
                show(buf, mime, msg)
            end
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
            write(io, take!(buf))
            flush(io)
            empty!(buffer)
        end
    catch err
        if err isa InvalidStateException
            # This is fine, outbox closed by reconnect loop.
        else
            rethrow()
        end
    end
end
