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

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

Default timeout is $DEFAULT_REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timeout`. It can be configured globally with `NATS_REQUEST_TIMEOUT_SECONDS` env variable.

Optional keyword arguments are:
- `timeout`: error will be thrown if no replies received until `timeout` number of seconds

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

Requests for multiple replies. Vector of messages is returned after receiving `nreplies` replies or timer expired.
Can return less messages than specified (also empty array if timeout occurs), errors are not filtered.

Optional keyword arguments are:
- `timout`: empty vector will be returned if no replies received until `timeout` number of seconds

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
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    find_data_conversion_or_throw(typeof(data))
    if NATS.status(connection) in [NATS.DRAINED, NATS.DRAINING]
        throw(NATS.NATSError(499, "Connection is drained."))
    end
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    if timeout isa Period # TODO: get rid of if in 1.11
        timeout = Nanosecond(timeout) / Nanosecond(Second(1))
    end
    if request_dedicated_inbox(subject)
        return request_with_own_inbox(connection, nreplies, subject, data, timeout)
    end
    # Replies arrive on the connection wide muxer subscription, so a request
    # costs no SUB or UNSUB round trip and does not touch the subscription
    # registry. Registration happens before publishing so a reply cannot
    # arrive before there is a channel to route it to.
    reply_to, token, ch = register_reply_channel(connection, nreplies)
    result = Msg[]
    try
        publish(connection, subject, data; reply_to)
        # Closing the channel is what wakes up a blocked `take!`.
        timer = Timer(timeout) do _
            try close(ch) catch end
        end
        try
            for _ in 1:nreplies
                msg = try
                    take!(ch)
                catch err
                    # Closed by the timer, or drained.
                    err isa InvalidStateException || rethrow()
                    break
                end
                push!(result, msg)
                has_error_status(msg) && break
            end
        finally
            close(timer)
        end
    finally
        unregister_reply_channel(connection, token)
    end
    result
end

# """
# Request using a subscription dedicated to this request. Needed when replies
# do not arrive on the inbox subject, see `request_dedicated_inbox`.
# """
function request_with_own_inbox(
    connection::Connection,
    nreplies::Integer,
    subject::String,
    data,
    timeout::Real
)
    reply_to = new_inbox(connection)
    sub = subscribe(connection, reply_to)
    unsubscribe(connection, sub; max_msgs = nreplies)
    publish(connection, subject, data; reply_to)
    timer = Timer(timeout) do _; drain(connection, sub) end
    result = Msg[]
    try
        for _ in 1:nreplies
            msg = next(connection, sub; no_throw = true)
            isnothing(msg) && break # Do not throw when unsubscribed.
            push!(result, msg)
            has_error_status(msg) && break
        end
    finally
        close(timer)
        drain(connection, sub)
    end
    result
end

"""
Request a reply from a service listening for `subject` messages. Reply is converted to specified type. Apropriate `convert` method must be defined, otherwise error is thrown.
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
