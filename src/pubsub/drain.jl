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

function drain(connection::Connection, sid::String; timer = Timer(connection.drain_timeout))
    sub_data = @lock connection.lock begin
        get(connection.sub_data, sid, nothing)
    end
    if isnothing(sub_data)
        return # Already drained.
    end
    sub_stats = sub_data.stats
    send(connection, Unsub(sid, 0))
    sleep(connection.drain_poll)
    while !is_every_message_handled(sub_stats)
        if !isopen(timer) 
            @error "Timeout for drain exceeded, not all msgs might be processed."
        end
        sleep(connection.drain_poll)
    end
    _delete_sub_data(connection, sid)
end

function drain(connection::Connection, sub::Sub)
    drain(connection, sub.sid)
end
