const SUBSCRIPTION_CHANNEL_SIZE = 1000

function publish(conn::Connection, subject::String; reply_to::Union{String, Nothing} = nothing, payload::Union{String, Nothing} = nothing, headers::Union{Nothing, Dict{String, Vector{String}}} = nothing)
    if isnothing(headers)
        nbytes = isnothing(payload) ? 0 : ncodeunits(payload)
        send(conn, Pub(subject, reply_to, nbytes, payload))
    else
        
    end
end

function subscribe(f, conn::Connection, subject::String; queue_group::Union{String, Nothing} = nothing, sync = true)
    sid = randstring()
    sub = Sub(subject, queue_group, sid)
    lock(conn.lock) do
        conn.handlers[sid] = f
    end
    send(conn, sub)
    sub
end


function unsubscribe(nc::Connection, sid::String; max_msgs::Union{Int, Nothing} = nothing)
    # TODO: do not send unsub if sub alredy removed by Msg handler.
    send(nc, Unsub(sid, max_msgs))
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(nc, sid)
    end
    nothing
end

function unsubscribe(nc::Connection, sub::Sub; max_msgs::Union{Int, Nothing} = nothing)
    unsubscribe(nc, sub.sid; max_msgs)
end
