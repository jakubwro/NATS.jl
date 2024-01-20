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
    if isempty(replies) || all(has_error_status, replies)
        error("No replies received.")
    end
    first(filter(!has_error_status, replies))
end

function has_error_status(msg::NATS.Msg)
    statuscode(msg) in 400:599
end

"""
$(SIGNATURES)

Requests for multiple replies. Vector of messages is returned after receiving `nreplies` replies or timer expired.

Optional keyword arguments are:
- `timer`: empty vector will be returned if no replies received until `timer` expires

# Examples
```julia-repl
julia> request(connection, 2, "help.please"; timer = Timer(0))
NATS.Msg[]
```
"""
function request_old(
    connection::Connection,
    nreplies::Integer,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    find_data_conversion_or_throw(typeof(data))
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = new_inbox(connection)
    replies_channel = Channel{NATS.Msg}(nreplies)
    sub = subscribe(connection, reply_to; spawn = false) do msg
        put!(replies_channel, msg)
        if Base.n_avail(replies_channel) == nreplies || has_error_status(msg)
            close(replies_channel)
        end
    end
    unsubscribe(connection, sub; max_msgs = nreplies)
    publish(connection, subject, data; reply_to)
    timeout_task = Threads.@spawn :interactive disable_sigint() do
        try wait(timer) catch end
        drain(connection, sub)
    end
    bind(replies_channel, timeout_task)
    errormonitor(timeout_task)
    replies = collect(replies_channel) # Waits until channel closed.
    # @debug "Received $(length(replies)) messages with statuses: $(map(m -> statuscode(m), replies))"
    replies
end

function request(
    connection::Connection,
    nreplies::Integer,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    find_data_conversion_or_throw(typeof(data))
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = new_inbox(connection)
    sub = subscribe(connection, reply_to)
    unsubscribe(connection, sub; max_msgs = nreplies)
    publish(connection, subject, data; reply_to)
    timeout_task = Threads.@spawn :interactive disable_sigint() do
        try wait(timer) catch end
        drain(connection, sub)
    end
    errormonitor(timeout_task)
    result = Msg[]
    for _ in 1:nreplies
        msg = next(connection, sub)
        push!(result, msg)
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
