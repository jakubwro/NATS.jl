### reply.jl
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
# This file contains implementations of functions for replying to a subject.
#
### Code:

"""
$(SIGNATURES)

Reply for messages for a `subject`. Works like `subscribe` with automatic `publish` to the subject from `reply_to` field.

Optional keyword arguments are:
- `queue_group`: NATS server will distribute messages across queue group members
- `spawn`: if `true` task will be spawn for each `f` invocation, otherwise messages are processed sequentially, default is `false`

# Examples
```julia-repl
julia> sub = reply("FOO.REQUESTS") do msg
    "This is a reply payload."
end
NATS.Sub("FOO.REQUESTS", nothing, "jdnMEcJN")

julia> sub = reply("FOO.REQUESTS") do msg
    "This is a reply payload.", ["example_header" => "This is a header value"]
end
NATS.Sub("FOO.REQUESTS", nothing, "jdnMEcJN")

julia> unsubscribe(sub)
```
"""
function reply(
    f,
    connection::Connection,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    spawn::Bool = false
)
    fast_f = _fast_call(f)
    subscribe(connection, subject; queue_group, spawn) do msg
        data = fast_f(msg)
        publish(connection, msg.reply_to, data)
    end
end
