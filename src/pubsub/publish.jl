### publish.jl
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
# This file contains implementation of functions for publishing messages.
#
### Code:

"""
$(SIGNATURES)

Publish message to a subject.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `reply_to`: subject to which a result should be published
- `payload`: payload string
- `headers`: vector of pair of string
"""
function publish(
    subject::String;
    connection::Connection = connection(:default),
    reply_to::Union{String, Nothing} = nothing,
    payload::Union{String, Nothing} = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(subject, (payload, headers); connection, reply_to)
end

"""
$(SIGNATURES)

Publish `data` to a `subject`, payload is obtained with `show` method taking `mime` `$(MIME_PAYLOAD())`, headers are obtained wth `show` method taking `mime` `$(MIME_HEADERS())`.

Optional parameters:
- `connection`: connection to be used, if not specified `default` connection is taken
- `reply_to`: subject to which a result should be published

It is equivalent to:
```
    publish(
        subject;
        payload = String(repr(NATS.MIME_PAYLOAD(), data)),
        headers = String(repr(NATS.MIME_PAYLOAD(), data)))
```
"""
function publish(
    subject::String,
    data;
    connection::Connection = connection(:default),
    reply_to::Union{String, Nothing} = nothing
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    headers_bytes = repr(MIME_HEADERS(), data)
    send(connection, Pub(subject, reply_to, headers_bytes, payload_bytes))
    @inc_stat :msgs_published 1 connection.stats state.stats
    t = current_task()
    if !isnothing(t.storage) && haskey(t.storage, "sub_stats")
        sub_stats = task_local_storage("sub_stats")
        @inc_stat :msgs_published 1 sub_stats
    end
    
    
end
