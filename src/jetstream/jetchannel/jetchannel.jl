
include("manage.jl")

const DEFAULT_JETCHANNEL_DELAYS = ExponentialBackOff(n = typemax(Int64), first_delay = 0.2, max_delay = 0.5)

struct JetChannel{T} <: AbstractChannel{T}
    connection::NATS.Connection
    name::String
    stream::StreamInfo
    consumer::ConsumerInfo
end

const DEFAULT_JETCHANNEL_SIZE = 1

function JetChannel{T}(connection::NATS.Connection, name::String, size::Int64 = DEFAULT_JETCHANNEL_SIZE) where T
    stream = channel_stream_create(connection, name, size)
    consumer = channel_consumer_create(connection, name)

    JetChannel{T}(connection, name, stream, consumer)
end

function destroy!(jetchannel::JetChannel)
    channel_stream_delete(jetchannel.connection, jetchannel.name)
end

function show(io::IO, jetchannel::JetChannel{T}) where T
    sz = jetchannel.stream.config.max_msgs
    sz_str = sz == -1 ? "Inf" : string(sz)
    print(io, "JetChannel{$T}(\"$(jetchannel.name)\", $sz_str)")
end

function Base.take!(jetchannel::JetChannel{T}) where T
    msg = consumer_next(jetchannel.connection, jetchannel.consumer)
    ack = consumer_ack(jetchannel.connection, msg; delays = DEFAULT_JETCHANNEL_DELAYS)
    @assert ack isa NATS.Msg
    convert(T, msg)
end

function Base.put!(jetchannel::JetChannel{T}, v::T) where T
    subject = channel_subject(jetchannel.name)
    ack = stream_publish(jetchannel.connection, subject, v; delays = DEFAULT_JETCHANNEL_DELAYS)
    @assert ack.stream == jetchannel.stream.config.name
    v
end