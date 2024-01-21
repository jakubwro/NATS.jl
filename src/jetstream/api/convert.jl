import Base.convert

# const api_type_map = Dict(
#     "io.nats.jetstream.api.v1.consumer_create_response" => ConsumerInfo,
#     "io.nats.jetstream.api.v1.stream_create_response" => StreamInfo,
#     "io.nats.jetstream.api.v1.stream_delete_response" => ApiResult,
#     "io.nats.jetstream.api.v1.stream_info_response" => StreamInfo
# )

function convert(::Type{T}, msg::NATS.Msg) where { T <: ApiResponse }
    # TODO: check headers
    response  = JSON3.read(@view msg.payload[(begin + msg.headers_length):end])
    if haskey(response, :error)
        err = StructTypes.constructfrom(ApiError, response.error)
        throw(err)
    end
    StructTypes.constructfrom(T, response)
end

function convert(::Type{Union{T, ApiError}}, msg::NATS.Msg) where { T <: ApiResponse }
    # TODO: check headers
    pl = NATS.payload(msg)
    pl = replace(pl, "0001-01-01T00:00:00Z" => "0001-01-01T00:00:00.000Z")
    response  = JSON3.read(pl)

    if haskey(response, :error)
        StructTypes.constructfrom(ApiError, response.error)
    else
        StructTypes.constructfrom(T, response)
    end
end

function convert(::Type{KeyValueEntry}, msg::NATS.Msg)
    splitted = split(msg.reply_to, ".")
    bucket = splitted[3]
    key = msg.subject
    value = NATS.payload(msg)
    _, _, stream, cons, _, seq, _, nanos, rem = splitted
    seq = splitted[7]
    revision = splitted[6]

    KeyValueEntry(bucket, key, value, parse(UInt64, seq), NanoDate(), 0, :none)
end
