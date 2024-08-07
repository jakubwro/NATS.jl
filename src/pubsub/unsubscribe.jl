### unsubscribe.jl
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
# This file contains implementation of functions for unsubscribing a subscription.
#
### Code:

"""
$(SIGNATURES)

Unsubscrible from a subject. `sub` is an object returned from `subscribe` or `reply`.

Optional keyword arguments are:
- `max_msgs`: maximum number of messages server will send after `unsubscribe` message received in server side, what can occur after some time lag
"""
function unsubscribe(
    connection::Connection,
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(connection, sub.sid; max_msgs)
end

function unsubscribe(
    connection::Connection,
    sid::Int64;
    max_msgs::Union{Int, Nothing} = nothing
)
    usnub = Unsub(sid, max_msgs)
    send(connection, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        cleanup_sub_resources(connection, sid)
    else
        @lock connection.lock begin
            connection.unsubs[sid] = max_msgs
        end
    end
    nothing
end
