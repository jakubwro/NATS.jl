function publish(
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload = nothing,
    headers::Union{Nothing, Headers} = nothing,
    nc::Connection = default_connection()
)
    publish(subject, (payload, headers); reply_to, nc)
end

function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing,
    nc::Connection = default_connection()
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    payload = isempty(payload_bytes) ? nothing : String(payload_bytes)
    headers_bytes = repr(MIME_HEADERS(), data)
    headers = isempty(headers_bytes) ? nothing : String(headers_bytes)

    if isnothing(headers)
        send(nc, Pub(subject, reply_to, sizeof(payload), payload))
    else
        headers_size = sizeof(headers)
        total_size = headers_size + sizeof(payload)
        send(nc, HPub(subject, reply_to, headers_size, total_size, headers, payload))
    end
end

function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing, sync = true,
    nc::Connection = default_connection()
)
    find_msg_conversion_or_throw(argtype(f))
    sid = randstring(nc.rng, 20)
    sub = Sub(subject, queue_group, sid)
    lock(nc.lock) do
        nc.handlers[sid] = f
        nc.stats[sid] = 0
    end
    send(nc, sub)
    sub
end

function unsubscribe(
    sid::String;
    max_msgs::Union{Int, Nothing} = nothing,
    nc::Connection = default_connection()
)
    # TODO: do not send unsub if sub alredy removed by Msg handler.
    usnub = Unsub(sid, max_msgs)
    send(nc, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(nc, sid)
    end
    usnub
end

function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing,
    nc::Connection = default_connection()
)
    unsubscribe(sub.sid; max_msgs, nc)
end
