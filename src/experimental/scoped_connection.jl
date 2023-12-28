
const sconnection = ScopedValue{Connection}()


function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    monitoring_throttle_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    subscribe(f, sconnection[], subject; queue_group, async_handlers, channel_size, monitoring_throttle_seconds)
end


function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
)
    publish(sconnection[], subject, data; reply_to)
end
