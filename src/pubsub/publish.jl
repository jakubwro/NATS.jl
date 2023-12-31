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

Publish `data` to a `subject`, payload is obtained with `show` method taking `mime` `$(MIME_PAYLOAD())`, headers are obtained with `show` method taking `mime` `$(MIME_HEADERS())`.

There are predefined convertion defined for `String` type. To publish headers there is defined conversion from tuple taking vector of pairs of strings.

Optional parameters:
- `reply_to`: subject to which a result should be published

Examples:
```
    publish(nc, "some_subject", "Some payload")
    publish("some_subject", ("Some payload", ["some_header" => "Example header value"]))
```

"""
function publish(
    connection::Connection,
    subject::String,
    data = nothing;
    reply_to::Union{String, Nothing} = nothing
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    headers_bytes = repr(MIME_HEADERS(), data)
    send(connection, Pub(subject, reply_to, headers_bytes, payload_bytes))
    inc_stats(:msgs_published, 1, connection.stats, state.stats)
    sub_stats = ScopedValues.get(scoped_subscription_stats)
    if !isnothing(sub_stats)
        inc_stat(sub_stats.value, :msgs_published, 1)
    end
end
