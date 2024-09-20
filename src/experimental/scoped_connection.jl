### scoped_connection.jl
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
# This file contains implementation of simplified interface utilizing connection as dynamically scoped variable.
#
### Code:

const sconnection = ScopedValue{Connection}()

function scoped_connection()
    conn = ScopedValues.get(sconnection)
    if isnothing(conn)
        error("""No scoped connection.
            To use methods without explicit `connection` parameter you need to wrap your logic into `with_connection` function.
            
            Example:
            ```
            nc = NATS.connect()
            with_connection(nc) do
                publish("some_subject", "Some payload")
            end
            ```

            Or pass `connection` explicitly:
            ```
            nc = NATS.connect()
            publish(nc, "some_subject", "Some payload")
            ```
            """)
    end
    conn.value
end

"""
$(SIGNATURES)

Create scope with ambient context connection, in which connection argument might be skipped during invocation of functions.

Usage:
```
    nc = NATS.connect()
    with_connection(nc) do
        publish("some.subject") # No `connection` argument.
    end
```
"""
function with_connection(f, nc::Connection)
    with(f, sconnection => nc)
end

function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    spawn = false,
    channel_size = parse(Int64, get(ENV, "NATS_SUBSCRIPTION_CHANNEL_SIZE", string(DEFAULT_SUBSCRIPTION_CHANNEL_SIZE))),
    monitoring_throttle_seconds = parse(Float64, get(ENV, "NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS", string(DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS)))
)
    subscribe(f, scoped_connection(), subject; queue_group, spawn, channel_size, monitoring_throttle_seconds)
end

function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sub; max_msgs)
end

function unsubscribe(
    sid::Int64;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sid; max_msgs)
end

function drain(sub::Sub)
    drain(scoped_connection(), sub)
end

function publish(
    subject::String,
    data = nothing;
    reply_to::Union{String, Nothing} = nothing
)
    publish(scoped_connection(), subject, data; reply_to)
end

function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    spawn = false
)
    reply(f, scoped_connection(), subject; queue_group, spawn)
end

function request(
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    request(scoped_connection(), subject, data; timer)
end

function request(
    nreplies::Integer,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    request(scoped_connection(), nreplies, subject, data; timer)
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    timer::Timer = Timer(parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS))))
)
    request(T, scoped_connection(), subject, data; timer)
end

function next(sub::Sub; no_wait = false, no_throw = false)::Union{Msg, Nothing}
    next(scoped_connection(), sub::Subscription; no_wait = false, no_throw = false)
end

function next(T::Type, sub::Sub; no_wait = false, no_throw = false)::Union{T, Nothing}
    next(T, scoped_connection(), sub::Subscription; no_wait = false, no_throw = false)
end

function next(sub::Sub, batch::Integer; no_wait = false, no_throw = false)::Vector{Msg}
    next(scoped_connection(), sub::Subscription; no_wait = false, no_throw = false)
end

function next(T::Type, sub::Sub, batch::Integer; no_wait = false, no_throw = false)::Vector{Type}
    next(T, scoped_connection(), sub::Subscription; no_wait = false, no_throw = false)
end
