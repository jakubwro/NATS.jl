"""
$(SIGNATURES)

Publish message to a subject.
"""
function publish(
    subject::String;
    connection::Connection = default_connection(),
    reply_to::Union{String, Nothing} = nothing,
    payload = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(subject, (payload, headers); connection, reply_to)
end

function publish(
    subject::String,
    data;
    connection::Connection = default_connection(),
    reply_to::Union{String, Nothing} = nothing
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    payload = isempty(payload_bytes) ? nothing : String(payload_bytes)
    headers_bytes = repr(MIME_HEADERS(), data)
    headers = isempty(headers_bytes) ? nothing : String(headers_bytes)

    if isnothing(headers)
        send(connection, Pub(subject, reply_to, sizeof(payload), payload))
    else
        headers_size = sizeof(headers)
        total_size = headers_size + sizeof(payload)
        send(connection, HPub(subject, reply_to, headers_size, total_size, headers, payload))
    end
end

function _fast_call(f::Function, arg_t::Type)
    if arg_t === Any || arg_t === NATS.Message
        f
    else
        msg -> f(convert(arg_t, msg))
    end
end

function _start_handler(arg_t::Type, f::Function)
    # TODO: try set sitcky flag
    fast_f = _fast_call(f, arg_t)
    Channel(10000000, spawn = true) do ch
        last_error_time = 0.0
        while true
            msg = take!(ch)
            try
                fast_f(msg)
            catch err
                now = time()
                if last_error_time < now - 5.0
                    last_error_time = now
                    @error err
                end
            end
        end
    end
end

"""
$(SIGNATURES)

Subscribe to a subject.
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = default_connection(),
    queue_group::Union{String, Nothing} = nothing
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    sid = @lock NATS.state.lock randstring(connection.rng, 20)
    sub = Sub(subject, queue_group, sid)
    c = _start_handler(arg_t, f)
    @lock NATS.state.lock begin
        state.handlers[sid] = c
        connection.subs[sid] = sub
    end
    send(connection, sub)
    sub
end

function unsubscribe(
    sid::String;
    connection::Connection,
    max_msgs::Union{Int, Nothing} = nothing
)
    # TODO: do not send unsub if sub alredy removed by Msg handler.
    usnub = Unsub(sid, max_msgs)
    send(connection, usnub)
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(connection, sid)
    end
    usnub
end

"""
$(SIGNATURES)

Unsubscrible from a subject.
"""
function unsubscribe(
    sub::Sub;
    connection::Connection = default_connection(),
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sub.sid; connection, max_msgs)
end
