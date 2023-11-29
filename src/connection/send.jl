const SEND_BUFFER_SOFT_SIZE_LIMIT = 2 * 1024 * 1024 # 2 MB
const SEND_RETRY_DELAYS = Base.ExponentialBackOff(n=200, first_delay=0.01, max_delay=0.1)

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

function try_send(nc::Connection, msgs::Vector{Pub})::Bool
    if status(nc) in [DRAINING, DRAINED, DISCONNECTED]
        error("Cannot send on connection with status $(status(nc))")
    end
    
    @lock nc.send_buffer_cond begin
        if nc.send_buffer.size < SEND_BUFFER_SOFT_SIZE_LIMIT
            for msg in msgs
                show(nc.send_buffer, MIME_PROTOCOL(), msg)
            end
            notify(nc.send_buffer_cond)
            true
        else
            false
        end
    end
end

function try_send(nc::Connection, msg::ProtocolMessage)
    can_send(nc, msg) || error("Cannot send on connection with status $(status(nc))")

    @lock nc.send_buffer_cond begin
        if msg isa Pub && nc.send_buffer.size > SEND_BUFFER_SOFT_SIZE_LIMIT
            # Apply limits only for publications, to allow unsubs and subs be done with higher priority.
            false
        else
            show(nc.send_buffer, MIME_PROTOCOL(), msg)
            notify(nc.send_buffer_cond)
            true
        end
    end
end

function send(nc::Connection, message::Union{ProtocolMessage, Vector{Pub}})
    for d in SEND_RETRY_DELAYS
        if try_send(nc, message)
            return
        end
        sleep(d)
    end
    error("Cannot send, send buffer too large.")
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
    # @show Threads.threadid()
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
