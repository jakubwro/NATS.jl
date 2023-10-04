function isdrained(nc::Connection)
    status(nc) in [DRAINING, DRAINED]
end

function drain(nc::Connection)
    if isdrained(nc)
        return
    end

    for (_, sub) in nc.subs
        unsubscribe(sub; max_msgs = 0, connection = nc)
    end
    sleep(3)
    status(nc, DRAINING)
    sleep(1)
    status(nc, DRAINED)
    close(outbox(nc))
end