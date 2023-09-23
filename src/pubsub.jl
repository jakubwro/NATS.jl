"""
$(SIGNATURES)

Publish message to a subject.
"""
function publish(
    nc::Connection,
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(nc, subject, (payload, headers); reply_to)
end

function publish(
    nc::Connection,
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
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

"""
$(SIGNATURES)

Publish message to a subject with default connection.
"""
function publish(
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(default_connection(), subject, (payload, headers); reply_to)
end

function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
)
    publish(default_connection(), subject, data; reply_to)
end

"""
$(SIGNATURES)

Subscribe to a subject.
"""
function subscribe(
    f,
    nc::Connection,
    subject::String;
    queue_group::Union{String, Nothing} = nothing
)
    find_msg_conversion_or_throw(argtype(f))
    sid = randstring(nc.rng, 20)
    sub = Sub(subject, queue_group, sid)
    lock(state.lock) do
        state.handlers[sid] = f
        nc.subs[sid] = sub
    end
    send(nc, sub)
    sub
end

"""
$(SIGNATURES)

Subscribe to a subject with default connection.
"""
function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing
)
    subscribe(f, default_connection(), subject; queue_group)
end

function unsubscribe(
    nc::Connection,
    sid::String;
    max_msgs::Union{Int, Nothing} = nothing
)
    # TODO: do not send unsub if sub alredy removed by Msg handler.
    usnub = Unsub(sid, max_msgs)
    send(nc, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(nc, sid)
    end
    usnub
end

"""
$(SIGNATURES)

Unsubscrible from a subject.
"""
function unsubscribe(
    nc::Connection,
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(nc, sub.sid; max_msgs)
end

"""
$(SIGNATURES)

Unsubscrible from with default connection.
"""
function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(default_connection(), sub.sid; max_msgs)
end
