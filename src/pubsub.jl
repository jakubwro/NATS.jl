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

function _start_handler(f::Function, subject::String)
    ch = Channel(10000000) # TODO: move to const
    Threads.@spawn begin 
        last_error_time = time()
        errors_since_last_log = 0
        last_error = nothing
        while true
            try
                msg = take!(ch)
                f(msg)
            catch err
                if err isa InvalidStateException
                    break
                end
                last_error = err
                errors_since_last_log = errors_since_last_log + 1
                now = time()
                time_diff = now - last_error_time
                if last_error_time < now - 5.0
                    last_error_time = now
                    @error "$errors_since_last_log handler errors on \"$subject\" in last $(round(time_diff, digits = 2)) s. Last one:" err
                    errors_since_last_log = 0
                end
            end
        end
        if errors_since_last_log > 0
            @error "$errors_since_last_log handler errors on \"$subject\"in last $(round(time() - last_error_time, digits = 2)) s. Last one:" last_error
        end
    end
    ch
end

function _start_async_handler(f::Function, subject::String)
    error_ch = Channel(100000)

    ch = Channel(10000000, spawn = true) do ch # TODO: move to const
        try
            while true
                msg = take!(ch)
                Threads.@spawn :default try
                    f(msg)
                catch err
                    put!(error_ch, err)
                end
            end
        catch
            close(error_ch)
        end
    end
    Threads.@spawn :default begin
        while true
            sleep(5)
            avail = Base.n_avail(error_ch)
            errors = [ take!(error_ch) for _ in 1:avail ]
            if !isempty(errors)
                @error "$(length(errors)) handler errors on \"$subject\" in last 5 s. Last one:" last(errors)
            end
        end
    end
    ch
end

"""
$(SIGNATURES)

Subscribe to a subject.
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = default_connection(),
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    sid = @lock NATS.state.lock randstring(connection.rng, 20)
    sub = Sub(subject, queue_group, sid)
    c = if async_handlers
            _start_async_handler(_fast_call(f, arg_t), subject)
        else
            _start_handler(_fast_call(f, arg_t), subject)
        end
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
