function send(nc::Connection, message::ProtocolMessage)
    isdrained(nc) && error("Connection is drained.")
    # When connection is lost outbox might be closed. Retry until new outbox is there.
    delays = vcat(0.001, 0.01, repeat([0.1], 100))
    retry(put!; delays)(outbox(nc), message)
end

const buffer = ProtocolMessage[]

function sendloop(nc::Connection, io::IO)
    try
        mime = MIME_PROTOCOL() 
        while true
            if !isempty(buffer)
                @warn "Buffer has $(length(buffer)) messages."
            end
            if !isopen(nc.outbox)
                error("Outbox is closed.")
            end
            pending = Base.n_avail(nc.outbox)
            buf = IOBuffer() # TODO: maybe this buffering is not necessary.
            batch = min(max(1, pending), 5000)

            for msg in buffer
                show(buf, mime, msg)
            end
            # send_buf = []
            for _ in 1:batch
                msg = take!(nc.outbox)
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
