

STREAM_MESSAGES_LIMIT_UNLIMITED = -1
STREAM_MAX_BYTES_UNLIMITED = -1
# max message size bytes

abstract type JetStreamPayload end

struct StreamConfiguration <: JetStreamPayload
    "A unique name for the Stream, empty for Stream Templates."
    name::Union{String, Nothing}
    "A short description of the purpose of this stream"
    description::Union{String, Nothing}
    "A list of subjects to consume, supports wildcards. Must be empty when a mirror is configured. May be empty when sources are configured."
    subjects::Union{Vector{String}, Nothing}
    "How messages are retained in the Stream, once this is exceeded old messages are removed."
    retention::String
    "The storage backend to use for the Stream."
    storage::String
end

struct ApiError
    code::Int64
    description::String
    err_code::Int64
end

struct StreamCreateResponse
    config::Union{StreamConfiguration, Nothing}
    created::Union{String, Nothing}
    did_create::Union{Bool, Nothing}
    error::Union{ApiError, Nothing}
end

function stream_create(config::StreamConfiguration; connection::NATS.Connection)
    resp = NATS.request(StreamCreateResponse, connection, "\$JS.API.STREAM.CREATE.$(config.name)", config)
    !isnothing(resp.error) && error(resp.error.description)
    return resp.did_create
end

function stream_update(config::StreamConfiguration)

end

function stream_name_by_subject()

end

function stream_delete()

end

function stream_list()

end

function stream_names()

end
