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
    ch = Channel(SUBSCRIPTION_CHANNEL_SIZE)
    lock(conn.lock) do
        conn.subs[sid] = ch
    end
    t = Threads.@spawn :default begin
        while true
            try
                msg = take!(ch)
                task = Threads.@spawn :default try
                    res = f(msg)
                    if !isnothing(msg.reply_to)
                        publish(conn, msg.reply_to, res)
                    end
                catch e
                    if e isa InvalidStateException
                        # Channel is closed. Message will be lost.
                        # TODO: add param to indicate how to signal this exception to user.
                    else
                        @error e
                    end
                end
                sync && wait(task)
            catch e
                if e isa InvalidStateException
                    # Closed channel, stop.
                else
                    @error e
                end
                break
            end
        end
    end

    sub = Sub(subject, queue_group, sid)
    send(conn, sub)
    sub, ch
end

function unsubscribe(conn::Connection, sub::Sub; max_msgs::Union{Int, Nothing} = nothing)
    send(conn, Unsub(sub.sid, max_msgs))
    if isnothing(max_msgs) || max_msgs == 0
        _cleanup_sub(conn, sub.sid)
    end
    nothing
end