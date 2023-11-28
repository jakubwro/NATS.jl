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
    @lock nc.send_buffer_cond begin
        show(nc.send_buffer, MIME_PROTOCOL(), message)
        notify(nc.send_buffer_cond)
    end
end

function send(nc::Connection, msgs::Vector{ProtocolMessage})
    @lock nc.send_buffer_cond begin
        for msg in msgs
            show(nc.send_buffer, MIME_PROTOCOL(), msg)
        end
        notify(nc.send_buffer_cond)
    end
end

function sendloop(nc::Connection, io::IO)
    @show Threads.threadid()
    try
        out = outbox(nc)
        while isopen(out) # @show !eof(io) && !isdrained(nc)
            buf = @lock nc.send_buffer_cond begin
                taken = take!(nc.send_buffer)
                if isempty(taken)
                    wait(nc.send_buffer_cond)
                    take!(nc.send_buffer)
                else
                    taken
                end
            end
            write(io, buf)
            flush(io)
        end
        @info "Sender task finished at $(time())" #TODO: bytes in buffer
catch err
    @error err
end
end


for i in 1:1000
    Threads.@spawn for j in 1:1000
        publish("foo"; payload = "This is a payload")
    end
end