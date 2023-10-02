function send(nc::Connection, message::ProtocolMessage)
    st = status(nc::Connection)
    while !isopen(nc.outbox) # TODO: this check is not threadsafe, use try catch.
        sleep(1)
    end
    put!(nc.outbox, message)
end

function sendloop(nc::Connection, io::IO)
    mime = MIME_PROTOCOL() 
    while true
        if !isopen(nc.outbox)
            error("Outbox is closed.")
        end
        pending = Base.n_avail(nc.outbox)
        buf = IOBuffer() # TODO: maybe this buffering is not necessary.
        batch = min(max(1, pending), 5000)

        for _ in 1:batch
            msg = take!(nc.outbox)
            if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                @lock state.lock begin nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
            end
            show(buf, mime, msg)
        end
        write(io, take!(buf))
        flush(io)
    end
end
