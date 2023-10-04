function isdrained(nc::Connection)
    status(nc) in [DRAINING, DRAINED]
end

function drain(nc::Connection)
    if isdrained(nc)
        return
    end
    status(nc, DRAINING)
    for (_, sub) in nc.subs
        unsubscribe(sub; max_msgs = 0, connection = nc)
    end
    sleep(3)
    length(nc.subs) > 0 && @warn "$(length(nc.subs)) not unsubscribed during drain."
    status(nc, DRAINED)
    close(outbox(nc))
end