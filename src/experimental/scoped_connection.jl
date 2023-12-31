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

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    monitoring_throttle_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    subscribe(f, scoped_connection(), subject; queue_group, async_handlers, channel_size, monitoring_throttle_seconds)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sub; max_msgs)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function unsubscribe(
    sid::String;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sid; max_msgs)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function publish(
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload::Union{String, Nothing} = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(scoped_connection(), subject; payload, headers, reply_to)
end

"""
$(SIGNATURES)

This method is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
```
"""
function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
)
    publish(scoped_connection(), subject, data; reply_to)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    async_handlers = false
)
    reply(f, scoped_connection(), subject; queue_group, async_handlers)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function request(
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(scoped_connection(), subject, data; timer)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function request(
    subject::String,
    data,
    nreplies::Integer;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(scoped_connection(), subject, data, nreplies; timer)
end

"""
$(SIGNATURES)

This overload is supposed to be called from inside `with_connection` code block, otherwise error will be thrown.
"""
function request(
    T::Type,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(scoped_connection(), T, subject, data; timer)
end
