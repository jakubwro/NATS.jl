
"""
$(SIGNATURES)

Create a stream.
"""
function stream_create(connection::NATS.Connection, config::StreamConfiguration; no_throw = false)
    validate(config)
    response = NATS.request(Union{StreamInfo, ApiError}, connection, "\$JS.API.STREAM.CREATE.$(config.name)", JSON3.write(config))
    no_throw || throw_on_api_error(response)
    response
end

"""
$(SIGNATURES)

Update a stream.
"""
function stream_update(connection::NATS.Connection, config::StreamConfiguration; no_throw = false)
    validate(config)
    response = NATS.request(Union{StreamInfo, ApiError}, connection, "\$JS.API.STREAM.UPDATE.$(config.name)", JSON3.write(config))
    no_throw || throw_on_api_error(response)
    response
end

function stream_update_or_create(connection::NATS.Connection, config::StreamConfiguration)
    res = stream_update(connection, config; no_throw = true)
    if res isa StreamInfo
        res
    elseif res isa ApiError
        if res.code == 404
            stream_create(connection, config)
        else
            throw(res)
        end
    end
end

"""
$(SIGNATURES)

Delete a stream.
"""
function stream_delete(connection::NATS.Connection, stream::String; no_throw = false)
    res = NATS.request(Union{ApiResult, ApiError}, connection, "\$JS.API.STREAM.DELETE.$(stream)")
    no_throw || throw_on_api_error(res)
    res
end

function stream_delete(connection::NATS.Connection, stream::StreamInfo; no_throw = false)
    stream_delete(connection, stream.config.name; no_throw)
end

"""
$(SIGNATURES)

Purge a stream. It is equivalent of deleting all messages.
"""
function stream_purge(connection::NATS.Connection, stream::String; no_throw = false)
    res = NATS.request(Union{ApiResult, ApiError}, connection, "\$JS.API.STREAM.PURGE.$stream")
    no_throw || throw_on_api_error(res)
    res
end

function stream_purge(connection::NATS.Connection, stream::StreamInfo; no_throw = false)
    stream_purge(connection, stream.config.name; no_throw)
end
