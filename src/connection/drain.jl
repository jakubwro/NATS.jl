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
# This file contains implementation of connection draining, which means
# to close it while processing all messages that are in the buffers already.
#
### Code:

# Actual drain logic, for thread safety executed in the connection controller task.
function _do_drain(nc::Connection, is_connected::Bool; timeout::Union{Real, Period} = nc.drain_timeout)
    timer = Timer(timeout)
    sids = @lock nc.lock copy(keys(nc.sub_data))
    for sid in sids
        send(nc, Unsub(sid, 0))
    end
    sleep(nc.drain_poll)
    conn_stats = stats(nc)
    while !is_every_message_handled(conn_stats)
        if !isopen(timer)
            @error "Timeout for drain exceeded, not all subs might be drained."
            # TODO: add log about count of messages not handled.
            break
        end
        sleep(nc.drain_poll)
    end
    for sid in sids
        cleanup_sub_resources(nc, sid)
    end
    # At this point no more publications can be done. Wait for the `send_buffer` flush.
    while !is_send_buffer_flushed(nc)
        if !isopen(timer)
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

Unsubscribe all subscriptions, wait for processing all messages in the buffers,
then close the connection. A drained connection is no more usable. This method is
used to gracefully stop the process.

Underneath it periodically checks for the state of all buffers, the interval for checks
is configurable per connection with the `drain_poll` parameter of the `connect` method.
It can also be set globally with the `NATS_DRAIN_POLL_INTERVAL_SECONDS` environment
variable. If not set explicitly the default polling interval is
`$DEFAULT_DRAIN_POLL_INTERVAL_SECONDS` seconds.

An error will be written to the log if the drain is not finished until the timeout expires.
The default timeout value is configurable per connection on `connect` with
`drain_timeout`. It can be also set globally with the `NATS_DRAIN_TIMEOUT_SECONDS`
environment variable. If not set explicitly the default drain timeout is
`$DEFAULT_DRAIN_TIMEOUT_SECONDS` seconds.

If connection is reconnecting, drain may wait for connection attempt to finish.
Time spent reconnecting is not included in `drain_timeout`.
"""
function drain(connection::Connection)
    @lock connection.status_change_cond begin
        notify(connection.drain_event)
        # There is a chance that connection is DISCONNECTED or is in CONNECTING
        # state and became DISCONNECTED before the drain event is handled. Wake it up
        # to force reconnect that will promptly do drain.
        notify(connection.reconnect_event) 
        while connection.status != DRAINED
            wait(connection.status_change_cond)
        end
    end
end

