

const CHANNEL_STREAM_PREFIX = "JLCH"

struct JetChannel{T} <: AbstractChannel{T}
    connection::NATS.Connection
    name::String
    stream::Stream
end

struct JetStreamChannel{T} <: AbstractChannel{T}
    connection::NATS.Connection
    name::String
end

# use two streams, one for write, second for read

function JetStreamChannel(name::String, sz::Int64; connection::NATS.Connection = NATS.connection(:default))
    # in case of 0 size use 1 size and block until consumer proceeds

    # create or open a stream with workqueue retention
    stream_name = "$(CHANNEL_STREAM_PREFIX)_$(name)"
    subject = "$(CHANNEL_STREAM_PREFIX)_$(name)"
    stream_create_or_update(;
        name = stream_name,
        subjects = [subject],
        retention = :workqueue,
        connection)

    consumer_create_or_update(
        stream_name;
        connection,
        ack_policy = :explicit,
        name = "$(stream_name)_CON",
        durable_name = "$(stream_name)_CON")

    JetStreamChannel{String}(connection, name)
end

function put!(ch::JetStreamChannel, data)
    isopen(ch) || error("Channel is closed.")
    JetStream.publish("julia_channel.$(ch.name)_in", data)
end

function take!(ch::JetStreamChannel)
    while true
        try
            msg = next("$(ch.name)_out", "channel_consumer"; connection = ch.connection)
            ack(msg; connection = ch.connection)
            return msg
        catch
        end
    end
end

# function close(ch::JetStreamChannel)
#     # put metadata
#     stream_delete(connection = ch.connection, name = "$(ch.name)_in")
# end

# function isopen(ch::JetStreamChannel)
#     try
#         JetStream.stream_info("$(ch.name)_in")
#         true
#     catch err
#         if err isa ApiError && err.code == 404
#             false
#         else
#             rethrow()
#         end
#     end
# end
