
function consumer_create_or_update(connection::NATS.Connection, consumer_config::ConsumerConfiguration, stream::String)
    consumer_name = @something consumer_config.name consumer_config.durable_name randstring(20)
    subject = "\$JS.API.CONSUMER.CREATE.$stream.$consumer_name"
    req_data = Dict(:stream_name => stream, :config => consumer_config)
    # if !isnothing(action)
    #     req_data[:action] = action
    # end
    NATS.request(ConsumerInfo, connection, subject, JSON3.write(req_data))
end

function consumer_create_or_update(consumer::ConsumerConfiguration, stream::StreamInfo)
end

function consumer_create(connection::NATS.Connection, consumer::ConsumerConfiguration, stream::String)
    consumer_create_or_update(connection, consumer, stream)
end

function consumer_create(connection::NATS.Connection, consumer::ConsumerConfiguration, stream::StreamInfo)
    consumer_create_or_update(connection, consumer, stream.config.name)
end

function consumer_update(consumer::ConsumerConfiguration, stream::Union{StreamInfo, String})

end

function consumer_delete(connection::NATS.Connection, stream_name::String, consumer_name::String)
    subject = "\$JS.API.CONSUMER.DELETE.$stream_name.$consumer_name"
    res = NATS.request(Union{ApiResult, ApiError}, connection, subject)
    if res isa ApiError
        throw(res)
    end
    res
end

function consumer_delete(connection, consumer::ConsumerInfo)
    consumer_delete(connection, consumer.stream_name, consumer.name)
end
