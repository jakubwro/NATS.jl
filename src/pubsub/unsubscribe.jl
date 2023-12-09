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
- `connection`: connection to be used, if not specified `default` connection is taken
- `max_msgs`: maximum number of messages server will send after `unsubscribe` message received in server side, what can occur after some time lag
"""
function unsubscribe(
    sub::Sub;
    connection::Connection = connection(:default),
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sub.sid; connection, max_msgs)
end

"""
$(SIGNATURES)

Unsubscrible from a subject. `sid` is an client generated subscription id that is a field of an object returned from `subscribe`

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `max_msgs`: maximum number of messages server will send after `unsubscribe` message received in server side, what can occur after some time lag
"""
function unsubscribe(
    sid::String;
    connection::Connection,
    max_msgs::Union{Int, Nothing} = nothing
)
    usnub = Unsub(sid, max_msgs)
    send(connection, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(connection, sid)
    else
        @lock connection.lock begin
            connection.unsubs[sid] = max_msgs
        end
    end
    usnub
end
