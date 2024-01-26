
include("manage.jl")

struct JetChannel{T} <: AbstractChannel{T}
    connection::NATS.Connection
    name::String
    stream::StreamInfo
    consumer::ConsumerInfo
end

function JetChannel{T}(connection::NATS.Connection, name::String) where T
    stream = channel_stream_create(connection, name)
    consumer = channel_consumer_create(connection, stream)

    JetChannel{T}(connection, name, stream, consumer)
end

function Base.take!(jetchannel::JetChannel{T}) where T
    msg = consumer_next(jetchannel.connection, jetchannel.consumer)
    ack = consumer_ack(jetchannel.connection, msg)
    @assert ack isa NATS.Msg
    convert(T, msg)
end


function Base.put!(jetchannel::JetChannel{T}, v::T) where T
    subject = channel_subject(jetchannel.name)
    ack = stream_publish(jetchannel.connection, subject, v)
    @assert ack.stream == jetchannel.stream.config.name
    jetchannel
end