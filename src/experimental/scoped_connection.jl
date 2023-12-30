
const sconnection = ScopedValue{Connection}()

function with_connection(f, nc::Connection)
    with(f, sconnection => nc)
end

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

function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sconnection[], sub; max_msgs)
end

function unsubscribe(
    sid::String;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(sconnection[], sid; max_msgs)
end

function publish(
    subject::String;
    reply_to::Union{String, Nothing} = nothing,
    payload::Union{String, Nothing} = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(sconnection[], subject; payload, headers, reply_to)
end

function publish(
    subject::String,
    data;
    reply_to::Union{String, Nothing} = nothing
)
    publish(sconnection[], subject, data; reply_to)
end

function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    async_handlers = false
)
    reply(f, sconnection[], subject; queue_group, async_handlers)
end

function request(
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], subject, data; timer)
end

function request(
    subject::String,
    data,
    nreplies::Integer;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], subject, data, nreplies; timer)
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(sconnection[], T, subject, data; timer)
end
