
const CHANNEL_STREAM_PREFIX = "JCH"

channel_stream_name(channel_name::String) = "$(CHANNEL_STREAM_PREFIX)_$(channel_name)"
channel_consumer_name(channel_name::String) = "$(CHANNEL_STREAM_PREFIX)_$(channel_name)_consumer"
channel_subject(channel_name::String) = "$(CHANNEL_STREAM_PREFIX)_$channel_subject"

function channel_stream_create(connection::NATS.Connection, name::String)
    config = StreamConfiguration(
        name = channel_stream_name(name),
        subjects = [ channel_subject(name) ],
        retention  = :workqueue
    )
    stream_create(connection, config)
end

function channel_stream_delete(connection::NATS.Connection, channel_name::String)
    stream_delete(connection, channel_stream_name(name))
end

function channel_consumer_create(connection::NATS.Connection, stream::StreamInfo)
    config = ConsumerConfiguration(
        ack_policy = :explicit,
        name = "$(stream.config.name)_consumer",
        durable_name = "$(stream.config.name)_consumer"
    )
    consumer_create(connection, config, stream)
end

function channel_consumer_delete(connection::NATS.Connection, stream::StreamInfo)
    config = ConsumerConfiguration(

    )

    consumer_create(connection, config, stream)

end