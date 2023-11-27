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

    @lock nc.send_buffer_lock show(nc.send_buffer, MIME_PROTOCOL(), message)
end

function sendloop(nc::Connection, io::IO)
    @show Threads.threadid()
    mime = MIME_PROTOCOL()
    while !isdrained(nc)
        sleep(0.001)
        buf = @lock nc.send_buffer_lock take!(nc.send_buffer)
        if isempty(buf)
            continue
        end
        # @info length(buf)
        write(io, buf)
        flush(io)
    end
    @info "Sender task finished at $(time())" #TODO: bytes in buffer
end
