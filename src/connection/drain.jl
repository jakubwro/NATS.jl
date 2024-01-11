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

# Actual drain logic, for thread safety executed in connection controller task.
function _do_drain(nc::Connection, is_connected; timeout = Timer(nc.drain_timeout))
    all_subs = @lock nc.lock copy(nc.sub_data)
    for (sid, _) in all_subs
        send(nc, Unsub(sid, 0))
    end
    sleep(nc.drain_poll)
    conn_stats = @lock nc.lock nc.stats
    while !is_every_message_handled(conn_stats)
        if !isopen(timeout)
            @error "Timeout for drain exceeded, not all subs might be drained."
            # TODO: add log about count of messages not handled.
            break
        end
        sleep(nc.drain_poll)
    end
    # At this point no more publications can be done. Wait for `send_buffer` flush.
    while !is_send_buffer_flushed(nc)
        if !isopen(timeout)
            @error "Timeout for drain exceeded, some publications might be lost."
            # TODO: add log about count of messages undelivered.
            break
        end
        if !is_connected
            @error "Cannot flush send buffer as connection is disconnected from server, some publications might be lost."
            # TODO: add log about count of messages undelivered.
            break
        end
        sleep(nc.drain_poll)
    end
    @lock nc.lock empty!(nc.sub_data)
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
