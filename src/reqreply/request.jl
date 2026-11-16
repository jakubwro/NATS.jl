### request.jl
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
# This file contains implementations of functions for requesting a reply.
#
### Code:

"""
$(SIGNATURES)

Send a NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

The default timeout is $DEFAULT_REQUEST_TIMEOUT_SECONDS seconds which can be overridden by passing `timeout`. It can be configured globally with the `NATS_REQUEST_TIMEOUT_SECONDS` env variable.

Optional keyword arguments are:
- `timeout`: error will be thrown if no replies are received until `timeout` number of seconds, `NATS.SendDeadlineExceeded` if the request could not be queued for sending in that time

# Examples
```julia-repl
julia> NATS.request(connection, "help.please")
MSG _INBOX.VnRLq6t91z.1 0 17
OK, I CAN HELP!!!

julia> request(connection, "help.please"; timeout = 0)
ERROR: Send deadline exceeded.
```
"""
function request(
    connection::Connection,
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    replies = request(connection, 1, subject, data; timeout)
    if isempty(replies)
        throw(NATSError(408, "No replies received in specified time."))
    end
    if length(replies) > 1
        @warn "Multiple replies."
    end
    msg = first(replies)
    throw_on_error_status(msg)
    msg
end

"""
$(SIGNATURES)

Requests for multiple replies. Vector of messages is returned after receiving `nreplies` replies, a reply with one of `stop_on_status` codes or the timer expired.
Can return less messages than specified (also an empty array if a timeout occurs), errors are not filtered.

Optional keyword arguments are:
- `timeout`: an empty vector will be returned if no replies are received until `timeout` number of seconds, `NATS.SendDeadlineExceeded` is thrown if the request could not be queued for sending in that time
- `stop_on_status`: a collection of status codes, a reply with one of them is the last collected and the remaining replies are not waited for. By default it is every error status (`$DEFAULT_REQUEST_STOP_ON_STATUS`), what includes `503` sent by the server when there are no responders. Replies with other statuses are collected as any other reply, pass an empty collection to always wait for `nreplies` replies or the `timeout`.

# Examples
```julia-repl
julia> request(connection, 2, "help.please"; timeout = 0)
ERROR: Send deadline exceeded.
```
"""
function request(
    connection::Connection,
    nreplies::Integer,
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))),
    stop_on_status = DEFAULT_REQUEST_STOP_ON_STATUS
)
    timeout = timeout isa Period ? Nanosecond(timeout) : Nanosecond(round(Int64, 1e9 * timeout))
    deadline = Nanosecond(time_ns()) + timeout
    find_data_conversion_or_throw(typeof(data))
    if NATS.status(connection) in [NATS.DRAINED, NATS.DRAINING]
        throw(NATS.NATSError(499, "Connection is drained."))
    end
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to, request_id = new_inbox(connection)
    # Room for `nreplies` replies, so the receiver never waits for the requester and knows a single-reply request.
    ch = Channel{MsgRaw}(nreplies)
    replaced_timer = @lock connection.request_lock begin
        connection.request_channels[request_id] = ch
        add_request_deadline(connection, request_id, deadline)
    end
    isnothing(replaced_timer) || close(replaced_timer)
    result = Msg[]
    try
        publish(connection, subject, data; reply_to, deadline)
        for _ in 1:nreplies
            raw = try
                take!(ch)
            catch err
                if err isa InvalidStateException
                    break # channel closed by timeout
                else
                    rethrow()
                end
            end
            dec_stats(:msgs_pending, 1, connection.stats, state.stats)
            inc_stats(:msgs_handled, 1, connection.stats, state.stats)
            msg = convert(Msg, raw)
            push!(result, msg)
            if statuscode(msg) in stop_on_status
                break
            end
        end
    finally
        # The receiver ends a single-reply request when it delivers the reply.
        if nreplies > 1 || isempty(result)
            @lock connection.request_lock begin
                delete!(connection.request_deadlines, request_id)
                delete!(connection.request_channels, request_id)
            end
        end
        close(ch)
        # An early stop can leave buffered replies. Count these as dropped instead of pending or handled.
        n_dropped = Base.n_avail(ch)
        if n_dropped > 0
            dec_stats(:msgs_pending, n_dropped, connection.stats, state.stats)
            dec_stats(:msgs_received, n_dropped, connection.stats, state.stats)
            inc_stats(:msgs_dropped, n_dropped, connection.stats, state.stats)
        end
    end
    result
end

function new_inbox(nc::Connection)
    id = @atomic nc.request_counter += 1
    sub = @atomic nc.request_subscription
    if isnothing(sub)
        sub = @lock nc.request_lock begin
            if isnothing(@atomic nc.request_subscription)
                new_random_prefix = "$(nc.inbox_prefix).$(randstring(RandomDevice(), 10))"
                all_replies_subject = "$(new_random_prefix).>"
                sub = Sub(all_replies_subject, nothing, REQUEST_SUBSCRIPTION_SID)
                # Publish the subscription before a sender or reconnect can consume its SUB.
                @lock nc.send_buffer_cond begin
                    send(nc, sub)
                    @atomic nc.request_subscription = sub
                end
            end
            @atomic nc.request_subscription
        end
    end
    return sub.subject[begin:end-1] * string(id), id
end

# Called by the receiver with the replies of a batch, it takes the lock once, so it rarely waits for requesters. It must
# not block, so a reply that does not fit in its channel is not put. Replies that no request waits for are dropped.
function deliver_replies(nc::Connection, request_subscription::Sub, msgs::Vector{MsgRaw})
    # Reply subjects are the inbox prefix followed by the request id. Other subjects, like the stored subjects of messages
    # pulled from JetStream, are not parsed, so they cannot reach another request.
    prefix = codeunits(chop(request_subscription.subject))
    @lock nc.request_lock begin
        n_dropped = length(msgs)
        for msg in msgs
            # Request ids start from 1, so 0 finds no request.
            subject_has_prefix(msg, prefix) || continue
            id_range = (first(msg.subject_range) + length(prefix)):last(msg.subject_range)
            id = reply_id(msg.buffer, id_range)
            ch = get(nc.request_channels, id, nothing)
            if !isnothing(ch) && Base.n_avail(ch) < ch.sz_max
                if ch.sz_max == 1 # The only reply ends the request, its requester does not take the lock again.
                    delete!(nc.request_channels, id)
                    delete!(nc.request_deadlines, id)
                end
                inc_stats(:msgs_pending, 1, nc.stats, state.stats)
                inc_stats(:msgs_received, 1, nc.stats, state.stats)
                put!(ch, msg)
                n_dropped -= 1
            end
        end
        n_dropped > 0 && inc_stats(:msgs_dropped, n_dropped, nc.stats, state.stats)
    end
    nothing
end

# Only canonical positive decimal IDs name a request; invalid or overflowing suffixes match none.
function reply_id(buffer::Vector{UInt8}, range::UnitRange{Int64})
    isempty(range) && return Int64(0)
    0x31 <= buffer[first(range)] <= 0x39 || return Int64(0)
    id = Int64(0)
    for i in range
        byte = buffer[i]
        0x30 <= byte <= 0x39 || return Int64(0)
        digit = Int64(byte - 0x30)
        id > (typemax(Int64) - digit) ÷ 10 && return Int64(0)
        id = 10 * id + digit
    end
    id
end

# Whether the subject of `msg` starts with `prefix` and has something after it.
function subject_has_prefix(msg::MsgRaw, prefix::AbstractVector{UInt8})
    range = msg.subject_range
    length(range) > length(prefix) || return false
    for i in eachindex(prefix)
        @inbounds msg.buffer[first(range) + i - 1] == prefix[i] || return false
    end
    true
end

# A request that gets no reply in time has its channel closed, what ends its `take!`. Deadlines of all requests of a
# connection are kept in a table and served by a single `Timer`, armed for the earliest one. A timer for every request
# was ~10% of its time, closing a `Timer` waits for the event loop. Requests with the same timeout have growing deadlines,
# so the timer is replaced only when a request with a shorter timeout arrives.
# Needs `nc.request_lock`, returns the timer that is replaced to close it after the lock is released.
function add_request_deadline(nc::Connection, request_id::Int64, deadline::Nanosecond)
    nc.request_deadlines[request_id] = deadline
    deadline < nc.request_timer_at ? arm_request_timer(nc, deadline) : nothing
end

# Needs `nc.request_lock`, returns the timer that is replaced to close it after the lock is released.
function arm_request_timer(nc::Connection, deadline::Nanosecond)
    replaced = nc.request_timer
    # TODO: pass the period in 1.11, in 1.10 `Timer` with a callback takes only seconds.
    timer_timeout = max(0.0, (deadline - Nanosecond(time_ns())) / Second(1))
    nc.request_timer = Timer(timer_timeout) do timer
        expire_requests(nc, timer)
    end
    nc.request_timer_at = deadline
    replaced
end

function expire_requests(nc::Connection, timer::Timer)
    now = Nanosecond(time_ns())
    @lock nc.request_lock begin
        next_deadline = typemax(Nanosecond)
        for (request_id, deadline) in nc.request_deadlines
            if deadline <= now
                delete!(nc.request_deadlines, request_id)
                ch = get(nc.request_channels, request_id, nothing)
                if !isnothing(ch)
                    close(ch)
                    delete!(nc.request_channels, request_id)
                end
            else
                next_deadline = min(next_deadline, deadline)
            end
        end
        if nc.request_timer === timer
            if next_deadline == typemax(Nanosecond)
                nc.request_timer = nothing
                nc.request_timer_at = next_deadline
            else
                arm_request_timer(nc, next_deadline)
            end
        end
    end
end

"""
Request a reply from a service listening for `subject` messages. Reply is converted to specified type. An appropriate `convert` method must be defined, otherwise an error is thrown.
"""
function request(
    T::Type,
    connection::Connection,
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    find_msg_conversion_or_throw(T)
    result = request(connection, subject, data; timeout)
    convert(T, result) #TODO: invoke latest
end
