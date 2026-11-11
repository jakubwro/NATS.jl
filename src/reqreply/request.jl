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
- `timeout`: error will be thrown if no replies are received until `timeout` number of seconds

# Examples
```julia-repl
julia> NATS.request(connection, "help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, "", "OK, I CAN HELP!!!")

julia> request(connection, "help.please"; timeout = 0)
ERROR: No replies received.
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
- `timeout`: an empty vector will be returned if no replies are received until `timeout` number of seconds
- `stop_on_status`: a collection of status codes, a reply with one of them is the last collected and the remaining replies are not waited for. By default it is every error status (`$DEFAULT_REQUEST_STOP_ON_STATUS`), what includes `503` sent by the server when there are no responders. Replies with other statuses are collected as any other reply, pass an empty collection to always wait for `nreplies` replies or the `timeout`.

# Examples
```julia-repl
julia> request(connection, 2, "help.please"; timeout = 0)
NATS.Msg[]
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
    find_data_conversion_or_throw(typeof(data))
    if NATS.status(connection) in [NATS.DRAINED, NATS.DRAINING]
        throw(NATS.NATSError(499, "Connection is drained."))
    end
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = new_inbox(connection)
    sub = subscribe(connection, reply_to)
    unsubscribe(connection, sub; max_msgs = nreplies)
    publish(connection, subject, data; reply_to)
    timeout = timeout isa Period ? Nanosecond(timeout) : Nanosecond(round(Int64, 1e9 * timeout))
    add_request_deadline(connection, sub.sid, timeout)
    result = Msg[]
    for _ in 1:nreplies
        msg = next(connection, sub; no_throw = true)
        isnothing(msg) && break # Do not throw when unsubscribed.
        push!(result, msg)
        if statuscode(msg) in stop_on_status
            # The auto unsubscribe waits for all `nreplies` messages, what will not happen after stopping.
            length(result) < nreplies && unsubscribe(connection, sub)
            break
        end
    end
    remove_request_deadline(connection, sub.sid)
    result
end

# A request that gets no reply in time is unsubscribed, what ends `next` it is blocked on. Deadlines of all requests of a
# connection are kept in a table and served by a single `Timer`, armed for the earliest one. A timer for every request
# was ~10% of its time, closing a `Timer` waits for the event loop. Requests with the same timeout have growing deadlines,
# so the timer is replaced only when a request with a shorter timeout arrives.
function add_request_deadline(nc::Connection, sid::Int64, timeout::Nanosecond)
    deadline = Nanosecond(time_ns()) + timeout
    replaced = @lock nc.request_lock begin
        nc.request_deadlines[sid] = deadline
        deadline < nc.request_timer_at ? arm_request_timer(nc, deadline) : nothing
    end
    isnothing(replaced) || close(replaced)
end

function remove_request_deadline(nc::Connection, sid::Int64)
    @lock nc.request_lock begin
        delete!(nc.request_deadlines, sid)
    end
end

# Needs `nc.request_lock`, returns the timer that is replaced to close it after the lock is released.
function arm_request_timer(nc::Connection, deadline::Nanosecond)
    replaced = nc.request_timer
    # TODO: pass the period in 1.11, in 1.10 `Timer` with a callback takes only seconds.
    nc.request_timer = Timer(max(deadline - Nanosecond(time_ns()), Nanosecond(0)) / Second(1)) do timer
        expire_requests(nc, timer)
    end
    nc.request_timer_at = deadline
    replaced
end

function expire_requests(nc::Connection, timer::Timer)
    now = Nanosecond(time_ns())
    expired = Int64[]
    @lock nc.request_lock begin
        next_deadline = typemax(Nanosecond)
        for (sid, deadline) in nc.request_deadlines
            if deadline <= now
                push!(expired, sid)
                delete!(nc.request_deadlines, sid)
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
    for sid in expired
        (@lock nc.lock haskey(nc.sub_data, sid)) && unsubscribe(nc, sid)
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
