### drain.jl
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
# This file contains implementation of connection draining what means
# to close it with processing all messages that are in buffers already.
#
### Code:

function isdrained(nc::Connection)
    status(nc) in [DRAINING, DRAINED]
end

"""
$SIGNATURES

Unsubscribe all subscriptions, wait for precessing all messages in buffers, then close connection.
Drained connection is no more usable. This method is used to gracefuly stop the process.
"""
function drain(nc::Connection)
    if isdrained(nc)
        return
    end
    status(nc, DRAINING)
    for (_, sub) in nc.subs
        unsubscribe(sub; max_msgs = 0, connection = nc)
    end
    # TODO: wait for handlers running == 0
    sleep(3)
    length(nc.subs) > 0 && @warn "$(length(nc.subs)) not unsubscribed during drain."
    status(nc, DRAINED)
    reopen_send_buffer(nc)
    @warn "connection drained"
end

"""
$SIGNATURES

`drains` all connections.
"""
function drain()
    drain.(NATS.state.connections)
end
