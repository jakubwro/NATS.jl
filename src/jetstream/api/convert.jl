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
    throw_on_api_error(response)
    StructTypes.constructfrom(T, response)
end

function convert(::Type{Union{T, ApiError}}, msg::NATS.Msg) where { T <: ApiResponse }
    # TODO: check headers
    response  = JSON3.read(@view msg.payload[begin+msg.headers_length:end])
    if haskey(response, :error)
        StructTypes.constructfrom(ApiError, response.error)
    else
        StructTypes.constructfrom(T, response)
    end
end
