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

function _do_drain(nc::Connection)
    all_subs = copy(nc.subs)
    channels = collect(values(nc.sub_channels))
    for (_, sub) in all_subs
        unsubscribe(nc, sub; max_msgs = 0)
    end
    while any(ch -> Base.n_avail(ch) > 0, channels)
        sleep(1)
    end
    while (@atomic nc.stats.handlers_running) > 0
        sleep(1)
    end
    length(nc.subs) > 0 && @warn "$(length(nc.subs)) not unsubscribed during drain."
end

"""
$SIGNATURES

Unsubscribe all subscriptions, wait for precessing all messages in buffers, then close connection.
Drained connection is no more usable. This method is used to gracefuly stop the process.
"""
function drain(nc::Connection)
    @lock nc.status_change_cond begin
        notify(nc.drain_event)
        # There is a chance that connection is DISCONNECTED or is in CONNECTING
        # state and became DISCONNECTED before drain event is handled. Wake it up
        # to force reconnect that will promptly do drain.
        notify(nc.reconnect_event) 
        while nc.status != DRAINED
            wait(nc.status_change_cond)
        end
    end
end

"""
$SIGNATURES

`drains` all connections.
"""
function drain()
    drain.(NATS.state.connections)
end
