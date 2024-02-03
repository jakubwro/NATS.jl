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

Default timeout is $DEFAULT_REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`. It can be configured globally with `NATS_REQUEST_TIMEOUT_SECONDS` env variable.

Optional keyword arguments are:
- `timer`: error will be thrown if no replies received until `timer` expires

# Examples
```julia-repl
julia> NATS.request(connection, "help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, "", "OK, I CAN HELP!!!")

julia> request(connection, "help.please"; timer = Timer(0))
ERROR: No replies received.
```
"""
function request(
    connection::Connection,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    replies = request(connection, 1, subject, data; timer)
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
- `timer`: empty vector will be returned if no replies received until `timer` expires

# Examples
```julia-repl
julia> request(connection, 2, "help.please"; timer = Timer(0))
NATS.Msg[]
```
"""
function request(
    connection::Connection,
    nreplies::Integer,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
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
    timeout_task = Threads.@spawn :interactive begin
        Base.sigatomic_begin() # `disable_sigint` is not enought here, must be sure that this task never receives interrupt
        try wait(timer) catch end
        drain(connection, sub)
    end
    errormonitor(timeout_task)
    result = Msg[]
    for _ in 1:nreplies
        msg = next(connection, sub; no_throw = true)
        isnothing(msg) && break # Do not throw when unsubscribed.
        push!(result, msg)
        has_error_status(msg) && break
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
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    find_msg_conversion_or_throw(T)
    result = request(connection, subject, data; timer)
    convert(T, result)
end
