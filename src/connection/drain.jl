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
    close(nc.send_buffer)
    @lock nc.send_buffer_cond notify(nc.send_buffer_cond)
    @warn "connection drained"
end

"""
$SIGNATURES

`drains` all connections.
"""
function drain()
    drain.(NATS.state.connections)
end
