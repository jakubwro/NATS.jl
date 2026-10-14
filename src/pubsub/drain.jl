### drain.jl
#
# Copyright (C) 2024 Jakub Wronowski.
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
# This file contains implementation of subscription draining what means to
# unsubscribe and ensure all pending messages in the buffers are processed.
#
### Code:

"""
$SIGNATURES

Unsubscribe a subscription and wait for processing all messages in the buffer.

Underneath it periodically checks for the state of the buffer, the interval for checks
is configurable per connection with the `drain_poll` parameter of the `connect` method.
It can also be set globally with the `NATS_DRAIN_POLL_INTERVAL_SECONDS` environment
variable. If not set explicitly the default polling interval is
`$DEFAULT_DRAIN_POLL_INTERVAL_SECONDS` seconds. 

Optional keyword arguments:
- `timeout`: an error will be thrown if the drain is not finished until `timeout` expires. Default value is configurable per connection on `connect` with `drain_timeout`. It can be also set globally with the `NATS_DRAIN_TIMEOUT_SECONDS` environment variable. If not set explicitly the default drain timeout is `$DEFAULT_DRAIN_TIMEOUT_SECONDS` seconds.
"""
function drain(connection::Connection, sub::Sub; timeout::Union{Real, Period} = connection.drain_timeout)
    timer = Timer(timeout)
    sub_stats = stats(connection, sub)
    if isnothing(sub_stats)
        return # Already drained.
    end
    send(connection, Unsub(sub.sid, 0))
    sleep(connection.drain_poll)
    isok = :ok == timedwait(timeout; pollint = connection.drain_poll) do
        is_every_message_handled(sub_stats)
    end
    if !isok
        @error "Timeout for drain exceeded, not all msgs might be processed." sub
    end
    cleanup_sub_resources(connection, sub.sid)
    nothing
end
