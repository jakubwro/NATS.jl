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
    # A drained connection is not usable, otherwise allow ping and pong and unsubs.
    status(nc) != DRAINED
end

function can_send(nc::Connection, ::Union{Ping, Pong})
    # Do not let PING and PONG pollute the send buffer during the drain.
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
        # Allow handlers to publish the results during the drain
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
        # No new subs are allowed during the drain.
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
            # Apply limits only for publications, to allow unsubs and subs to be done with higher priority.
            false
        else
            show(nc.send_buffer, MIME_PROTOCOL(), msg)
            notify(nc.send_buffer_cond)
            true
        end
    end
end

function send(nc::Connection, message::Union{ProtocolMessage, Vector{Pub}})
    if try_send(nc, message)
        return
    end
    for d in nc.send_retry_delays
        wait_for_send_buffer_space(nc, d)
        if try_send(nc, message)
            return
        end
    end
    error("Cannot send, send buffer too large.")
end

# Waits until the sender task takes data from a full send buffer, but no longer than `timeout` seconds.
function wait_for_send_buffer_space(nc::Connection, timeout::Real)
    @lock nc.send_buffer_cond begin
        is_timed_out = false
        timer = Timer(timeout) do _
            @lock nc.send_buffer_cond begin
                is_timed_out = true
                notify(nc.send_buffer_cond)
            end
        end
        try
            while !is_timed_out && nc.send_buffer.size >= nc.send_buffer_limit
                wait(nc.send_buffer_cond)
            end
        finally
            close(timer)
        end
    end
end

# Calling this function is an easy way to force a crash of the sender task what will force a reconnect.
function reopen_send_buffer(nc::Connection)
    @lock nc.send_buffer_cond begin
        new_send_buffer = IOBuffer()
        data = take!(nc.send_buffer)
        @lock nc.lock begin
            for (sid, sub_data) in pairs(nc.sub_data)
                show(new_send_buffer, MIME_PROTOCOL(), sub_data.sub)
                unsub_max_msgs = get(nc.unsubs, sid, nothing)
                isnothing(unsub_max_msgs) || show(new_send_buffer, MIME_PROTOCOL(), Unsub(sid, unsub_max_msgs))
            end
            @debug "Restored subs buffer length $(length(data))"
            write(new_send_buffer, data)
            @debug "Total restored buffer length $(length(data))"
            close(nc.send_buffer)
            nc.send_buffer = new_send_buffer
        end
        notify(nc.send_buffer_cond)
    end
end

# Tells if the send buffer is flushed, which means no protocol messages are waiting
# to be delivered to the server.
function is_send_buffer_flushed(nc::Connection)
    @lock nc.send_buffer_cond begin
        nc.send_buffer.size == 0 && (@atomic nc.send_buffer_flushed) 
    end
end

# Moves the send buffer content to `buf`. Unlike `take!` it keeps memory allocated by the send buffer,
# so it is not reallocated and grown again for every batch. Memory is released after unusually large
# batches, e.g. buffered during disconnection.
function consume_send_buffer!(buf::Vector{UInt8}, send_buffer::IOBuffer, limit::Int64)
    if send_buffer.size > 2 * limit
        return take!(send_buffer)
    end
    seekstart(send_buffer)
    read!(send_buffer, resize!(buf, send_buffer.size))
    truncate(send_buffer, 0)
    buf
end

function sendloop(nc::Connection, io::IO, send_buffer::IO)
    # @show Threads.threadid()
    buf = UInt8[]
    while isopen(send_buffer) # @show !eof(io) && !isdrained(nc)
        taken = @lock nc.send_buffer_cond begin
            # TODO: check for eof on io
            while isopen(send_buffer) && send_buffer.size == 0
                wait(nc.send_buffer_cond)
                # TODO: check for eof on io
            end
            isopen(send_buffer) || break # Reconnect might have colsed the send buffer, double check
            @atomic nc.send_buffer_flushed = false
            taken = consume_send_buffer!(buf, send_buffer, nc.send_buffer_limit)
            notify(nc.send_buffer_cond) # Wake up publishers
            taken
        end
        write(io, taken)
        flush(io)
        @atomic nc.send_buffer_flushed = true
    end
    @debug "Sender task finished. $(send_buffer.size) bytes in send buffer."
end
