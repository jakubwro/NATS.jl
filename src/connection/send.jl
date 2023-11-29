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

    delays = Base.ExponentialBackOff(n=200, first_delay=0.01, max_delay=0.1)

    for d in delays
        @lock nc.send_buffer_cond begin
            if nc.send_buffer.size < 2 * 1024 * 1024
                show(nc.send_buffer, MIME_PROTOCOL(), message)
                notify(nc.send_buffer_cond)
                return
            end
        end
        sleep(d)
    end
    error("Cannot send, send buffer too large.")
end

function send(nc::Connection, msgs::Vector{ProtocolMessage})
    delays = Base.ExponentialBackOff(n=200, first_delay=0.01, max_delay=0.1)

    for d in delays
        @lock nc.send_buffer_cond begin
            if nc.send_buffer.size < 2 * 1024 * 1024
                for msg in msgs
                    show(nc.send_buffer, MIME_PROTOCOL(), msg)
                end
                notify(nc.send_buffer_cond)
                return
            end
        end
        sleep(d)
    end
end

function reopen_send_buffer(nc::Connection)
    @lock nc.send_buffer_cond begin
        new_send_buffer = IOBuffer()
        data = take!(nc.send_buffer)
        for (sid, sub) in pairs(nc.subs)
            show(new_send_buffer, MIME_PROTOCOL(), sub)
            unsub_max_msgs = get(nc.unsubs, sid, nothing)
            isnothing(unsub_max_msgs) || show(new_send_buffer, MIME_PROTOCOL(), Unsub(sid, unsub_max_msgs))
        end
        @info "Restored subs buffer length $(length(data))"
        write(new_send_buffer, data)
        @info "Total restored buffer length $(length(data))"
        close(nc.send_buffer)
        nc.send_buffer = new_send_buffer
        notify(nc.send_buffer_cond)
    end
end

function sendloop(nc::Connection, io::IO)
    @show Threads.threadid()
    send_buffer = nc.send_buffer
    while isopen(send_buffer) # @show !eof(io) && !isdrained(nc)
        buf = @lock nc.send_buffer_cond begin
            taken = take!(send_buffer)
            if isempty(taken)
                wait(nc.send_buffer_cond)
                if !isopen(send_buffer)
                    break
                end
                take!(send_buffer)
            else
                taken
            end
        end
        write(io, buf)
        # flush(io)
    end
    @info "Sender task finished at $(time())" #TODO: bytes in buffer
    error("sender task finished")
end


for i in 1:1000
    Threads.@spawn for j in 1:1000
        publish("foo"; payload = "This is a payload")
    end
end