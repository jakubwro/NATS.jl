include("sub_sync.jl")
include("sub_async.jl")

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
