

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

function stream_create(config::StreamConfiguration; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.CREATE.$(config.name)", config)
    haskey(resp, :error) && error("Failed to create stream \"$(config.name)\": $(resp.error.description).")
    resp.did_create
end

function stream_update(config::StreamConfiguration; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.UPDATE.$(config.name)", config)
    haskey(resp, :error) && error("Failed to update stream \"$(config.name)\": $(resp.error.description).")
    true
end

function stream_delete(name::String; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.DELETE.$(name)")
    haskey(resp, :error) && error("Failed to delete stream \"$(name)\": $(resp.error.description).")
    resp.success
end

function stream_list(; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.LIST")
    haskey(resp, :error) && error("Failed to get stream list: $(resp.error.description).")
    #TODO: pagination
    resp
end

function stream_names(subject = nothing; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.NAMES", "{\"subject\": \"$subject\"}")
    if haskey(resp, :error)
        error("Failed to get stream names$(isnothing(subject) ? "" : " for subject \"$subject\""): $(resp.error.description).")
    end
    # total, offset, limit = resp.total, resp.offset, resp.limit
    #TODO: pagination
    resp.streams
end
