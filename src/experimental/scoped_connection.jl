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
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    monitoring_throttle_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    subscribe(f, sconnection[], subject; queue_group, async_handlers, channel_size, monitoring_throttle_seconds)
end

function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sconnection[], sub; max_msgs)
end

function unsubscribe(
    sid::String;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sconnection[], sid; max_msgs)
end

function publish(
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload::Union{String, Nothing} = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(sconnection[], subject; payload, headers, reply_to)
end

function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
)
    publish(sconnection[], subject, data; reply_to)
end

function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    async_handlers = false
)
    reply(f, sconnection[], subject; queue_group, async_handlers)
end

function request(
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], subject, data; timer)
end

function request(
    subject::String,
    data,
    nreplies::Integer;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], subject, data, nreplies; timer)
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], T, subject, data; timer)
end
