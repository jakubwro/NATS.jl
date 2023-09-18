function publish(nc::Connection, subject::String; reply_to::Union{String, Nothing} = nothing, payload = nothing, headers::Union{Nothing, Headers} = nothing)
    payload = String(repr(MIME_PROTOCOL(), payload))
    if isnothing(headers)
        nbytes = sizeof(payload)
        send(nc, Pub(subject, reply_to, nbytes, payload))
    else
        error("not implemented")
    end
end

function subscribe(f, nc::Connection, subject::String; queue_group::Union{String, Nothing} = nothing, sync = true)
    find_msg_conversion_or_throw(argtype(f))
    sid = randstring()
    sub = Sub(subject, queue_group, sid)
    lock(nc.lock) do
        nc.handlers[sid] = f
    end
    send(nc, sub)
    sub
end

function unsubscribe(nc::Connection, sid::String; max_msgs::Union{Int, Nothing} = nothing)
    # TODO: do not send unsub if sub alredy removed by Msg handler.
    usnub = Unsub(sid, max_msgs)
    send(nc, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(nc, sid)
    end
    usnub
end

function unsubscribe(nc::Connection, sub::Sub; max_msgs::Union{Int, Nothing} = nothing)
    unsubscribe(nc, sub.sid; max_msgs)
end
