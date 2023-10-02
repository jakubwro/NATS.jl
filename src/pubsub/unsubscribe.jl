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
