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
# This file contains implementation of subscrption draining what means to
# unsubscribe and ensure all pending messages in buffers are processed.
#
### Code:

"""
$SIGNATURES

Unsubscribe a subscription and wait for precessing all messages in the buffer.

Underneeth it periodicaly checks for state of the buffer, interval for checks
is configurable per connection with `drain_poll` parameter of `connect` method.
It can also be set globally with `NATS_DRAIN_POLL_INTERVAL_SECONDS` environment
variable. If not set explicitly default polling interval is
`$DEFAULT_DRAIN_POLL_INTERVAL_SECONDS` seconds. 

Optional keyword arguments:
- `timer`: error will be thrown if drain not finished until `timer` expires. Default value is configurable per connection on `connect` with `drain_timeout`. Can be also set globally with `NATS_DRAIN_TIMEOUT_SECONDS` environment variable. If not set explicitly default drain timeout is `$DEFAULT_DRAIN_TIMEOUT_SECONDS` seconds.
"""
function drain(connection::Connection, sub::Sub; timer::Timer = Timer(connection.drain_timeout))
    sub_stats = stats(connection, sub)
    if isnothing(sub_stats)
        return # Already drained.
    end
    send(connection, Unsub(sub.sid, 0))
    sleep(connection.drain_poll)
    while !is_every_message_handled(sub_stats)
        if !isopen(timer)
            @error "Timeout for drain exceeded, not all msgs might be processed." sub
            break
        end
        sleep(connection.drain_poll)
    end
    cleanup_sub_resources(connection, sub.sid)
    nothing
end
