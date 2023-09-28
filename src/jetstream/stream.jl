

abstract type JetStreamPayload end

@enum SteramRetentionPolicy limits interest workqueue
@enum StreamStorage file memory

struct StreamConfiguration <: JetStreamPayload
    "A unique name for the Stream, empty for Stream Templates."
    name::Union{String, Nothing}
    "A short description of the purpose of this stream"
    description::Union{String, Nothing}
    "A list of subjects to consume, supports wildcards. Must be empty when a mirror is configured. May be empty when sources are configured."
    subjects::Union{Vector{String}, Nothing}
    "How messages are retained in the Stream, once this is exceeded old messages are removed."
    retention::SteramRetentionPolicy
    "The storage backend to use for the Stream."
    max_consumers::Int64
    max_msgs::Int64
    max_bytes::Int64
    max_age::Int64
    storage::StreamStorage
end

const DEFAULT_STREAM_CONFIGURATION = (
    name = nothing,
    description  = nothing,
    subjects = nothing,
    retention = limits,
    max_consumers = -1, # Unlimited.
    max_msgs = -1, # Unlimited.
    max_bytes = -1, # Unlimited.
    max_age = 0, # Unlimited.
    storage = memory
)

function throw_on_api_error(response::JSON3.Object, message::String)
    if haskey(response, :error)
        error("$message: $(response.error.description).")
    end
end

function stream_create(; connection::NATS.Connection, kwargs...)
    config = NATS.from_kwargs(StreamConfiguration, DEFAULT_STREAM_CONFIGURATION, kwargs)
    validate_name(config.name)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.CREATE.$(config.name)", config; connection)
    throw_on_api_error(resp, "Failed to create stream \"$(config.name)\"")
    resp.did_create
end

# function stream_update(; connection::NATS.Connection, kwargs...)
#     config = NATS.from_kwargs(StreamConfiguration, DEFAULT_STREAM_CONFIGURATION, kwargs)
#     validate_name(config.name)
#     resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.UPDATE.$(config.name)", config; connection)
#     haskey(resp, :error) && error("Failed to update stream \"$(config.name)\": $(resp.error.description).")
#     true
# end

function stream_delete(; connection::NATS.Connection, name::String)
    validate_name(name)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.DELETE.$(name)"; connection)
    throw_on_api_error(resp, "Failed to delete stream \"$(name)\"")
    resp.success
end

# function stream_list(; connection::NATS.Connection)
#     resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.LIST"; connection)
#     haskey(resp, :error) && error("Failed to get stream list: $(resp.error.description).")
#     #TODO: pagination
#     resp.streams
# end

function stream_names(; subject = nothing, connection::NATS.Connection, timer = Timer(5))
    req = isnothing(subject) ? nothing : "{\"subject\": \"$subject\"}"
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.NAMES", req; connection, timer)
    throw_on_api_error(resp, "Failed to get stream names$(isnothing(subject) ? "" : " for subject \"$subject\"")")
    # total, offset, limit = resp.total, resp.offset, resp.limit
    #TODO: pagination
    @something resp.streams String[]
end
