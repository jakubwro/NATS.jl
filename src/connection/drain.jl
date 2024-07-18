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
    sids = @lock nc.lock copy(keys(nc.sub_data))
    for sid in sids
        send(nc, Unsub(sid, 0))
    end
    sleep(nc.drain_poll)
    conn_stats = stats(nc)
    while !is_every_message_handled(conn_stats)
        if !isopen(timeout)
            @error "Timeout for drain exceeded, not all subs might be drained."
            # TODO: add log about count of messages not handled.
            break
        end
        sleep(nc.drain_poll)
    end
    for sid in sids
        cleanup_sub_resources(nc, sid)
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

Unsubscribe all subscriptions, wait for precessing all messages in buffers,
then close connection. Drained connection is no more usable. This method is
used to gracefuly stop the process.

Underneeth it periodicaly checks for state of all buffers, interval for checks
is configurable per connection with `drain_poll` parameter of `connect` method.
It can also be set globally with `NATS_DRAIN_POLL_INTERVAL_SECONDS` environment
variable. If not set explicitly default polling interval is
`$DEFAULT_DRAIN_POLL_INTERVAL_SECONDS` seconds.

Error will be written to log if drain not finished until timeout expires.
Default timeout value is configurable per connection on `connect` with
`drain_timeout`. Can be also set globally with `NATS_DRAIN_TIMEOUT_SECONDS`
environment variable. If not set explicitly default drain timeout is
`$DEFAULT_DRAIN_TIMEOUT_SECONDS` seconds.
"""
function drain(connection::Connection)
    @lock connection.status_change_cond begin
        notify(connection.drain_event)
        # There is a chance that connection is DISCONNECTED or is in CONNECTING
        # state and became DISCONNECTED before drain event is handled. Wake it up
        # to force reconnect that will promptly do drain.
        notify(connection.reconnect_event) 
        while connection.status != DRAINED
            wait(connection.status_change_cond)
        end
    end
end

