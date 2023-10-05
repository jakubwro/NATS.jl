include("sub_sync.jl")
include("sub_async.jl")

"""
$(SIGNATURES)

Subscribe to a subject.
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = connection(:default),
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    error_throttling_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    f_typed = _fast_call(f, arg_t)
    sid = @lock NATS.state.lock randstring(connection.rng, 20) # TODO: make helper method
    sub = Sub(subject, queue_group, sid)
    c = if async_handlers
            _start_async_handler(f_typed, subject, channel_size, error_throttling_seconds)
        else
            _start_handler(f_typed, subject, channel_size, error_throttling_seconds)
        end
    @lock NATS.state.lock begin
        state.handlers[sid] = c
        connection.subs[sid] = sub
    end
    send(connection, sub)
    sub
end
