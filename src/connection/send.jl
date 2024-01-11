### send.jl
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
# This file contains logic related to sending messages to NATS server.
#
### Code:

const SEND_RETRY_DELAYS = Base.ExponentialBackOff(n=53, first_delay=0.01, max_delay=0.1)

function can_send(nc::Connection, ::ProtocolMessage)
    # Drained conection is not usable, otherwise allow ping and pong and unsubs.
    status(nc) != DRAINED
end

function can_send(nc::Connection, ::Union{Ping, Pong})
    # Do not let PING and PONG polute send buffer during drain.
    conn_status = status(nc)
    conn_status != DRAINED && conn_status != DRAINING
end

function can_send(nc::Connection, ::Union{Pub, Vector{Pub}})
    conn_status = status(nc)
    if conn_status == CONNECTED
        true
    elseif conn_status == CONNECTING
        true # TODO: or nc.send_enqueue_when_disconnected?
    elseif conn_status == DISCONNECTED
        nc.send_enqueue_when_disconnected
    elseif conn_status == DRAINING
        # Allow handlers to publish results during drain
        sub_stats = ScopedValues.get(scoped_subscription_stats)
        is_called_from_subscription_handler = !isnothing(sub_stats)
        is_called_from_subscription_handler
    elseif conn_status == DRAINED
        false
    end
end

function can_send(nc::Connection, ::Sub)
    conn_status = status(nc)
    if conn_status == CONNECTED
        true
    elseif conn_status == CONNECTING
        true
    elseif conn_status == DISCONNECTED
        true
    elseif conn_status == DRAINING
        # No new subs allowed during drain.
        false
    elseif conn_status == DRAINED
        false
    end
end

function try_send(nc::Connection, msgs::Vector{Pub})::Bool
    can_send(nc, msgs) || error("Cannot send on connection with status $(status(nc))")
    
    @lock nc.send_buffer_cond begin
        if nc.send_buffer.size < nc.send_buffer_limit
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
        if msg isa Pub && nc.send_buffer.size > nc.send_buffer_limit
            # Apply limits only for publications, to allow unsubs and subs be done with higher priority.
            false
        else
            show(nc.send_buffer, MIME_PROTOCOL(), msg)
            notify(nc.send_buffer_cond)
            true
        end
    end
end

function send(nc::Connection, message::Union{String, ProtocolMessage, Vector{Pub}})
    if try_send(nc, message)
        return
    end
    for d in nc.send_retry_delays
        sleep(d)
        if try_send(nc, message)
            return
        end
    end
    error("Cannot send, send buffer too large.")
end

# Calling this function is an easy way to force crash of sender task what will force reconnect.
function reopen_send_buffer(nc::Connection)
    @lock nc.send_buffer_cond begin
        new_send_buffer = IOBuffer()
        data = take!(nc.send_buffer)
        for (sid, sub_data) in pairs(nc.sub_data)
            show(new_send_buffer, MIME_PROTOCOL(), sub_data.sub)
            unsub_max_msgs = get(nc.unsubs, sid, nothing) # TODO: lock on connection may be needed
            isnothing(unsub_max_msgs) || show(new_send_buffer, MIME_PROTOCOL(), Unsub(sid, unsub_max_msgs))
        end
        @debug "Restored subs buffer length $(length(data))"
        write(new_send_buffer, data)
        @debug "Total restored buffer length $(length(data))"
        close(nc.send_buffer)
        nc.send_buffer = new_send_buffer
        notify(nc.send_buffer_cond)
    end
end

# Tells if send buffer if flushed what means no protocol messages are waiting
# to be delivered to the server.
function is_send_buffer_flushed(nc::Connection)
    @lock nc.send_buffer_cond begin
        nc.send_buffer.size == 0 && (@atomic nc.send_buffer_flushed) 
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
                @atomic nc.send_buffer_flushed = false
                take!(send_buffer)
            else
                @atomic nc.send_buffer_flushed = false
                taken
            end
        end
        write(io, buf)
        flush(io)
        @atomic nc.send_buffer_flushed = true
    end
    @debug "Sender task finished. $(send_buffer.size) bytes in send buffer."
end
