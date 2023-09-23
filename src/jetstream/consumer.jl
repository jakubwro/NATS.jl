
const ACK_WAIT_DEFAULT = 30000000

struct ConsumerConfiguration
    deliver_policy::String
    durable_name::Union{String, Nothing}
    "A unique name for a durable consumer"
    name::Union{String, Nothing}
    "A short description of the purpose of this consumer"
    description::Union{String, Nothing}
    "Consumers can be in 'push' or 'pull' mode, in 'push' mode messages are dispatched in real time to a target NATS subject, this is that subject. Leaving this blank creates a 'pull' mode Consumer."
    deliver_subject::Union{String, Nothing}
    "Messages that are not acknowledged will be redelivered at a later time. 'none' means no acknowledgement is needed only 1 delivery ever, 'all' means acknowledging message 10 will also acknowledge 0-9 and 'explicit' means each has to be acknowledged specifically"
    ack_policy::String
    "How long (in nanoseconds) to allow messages to remain un-acknowledged before attempting redelivery. Default is $(div(ACK_WAIT_DEFAULT, 1000*1000)) seconds."
    ack_wait::Int64
    "When this is -1 unlimited attempts to deliver an un acknowledged message is made, when this is >0 it will be maximum amount of times a message is delivered after which it is ignored."
    max_deliver::Int64
    "Filter the stream by a single subjects"
    filter_subject::Union{String, Nothing}
    "Filter the stream by multiple subjects"
    filter_subjects::Union{Vector, Nothing}
    "Messages can be replayed at the rate they arrived in or as fast as possible."
    replay_policy::String
    sample_freq::Union{String, Nothing}
    "The maximum number of messages without acknowledgement that can be outstanding, once this limit is reached message delivery will be suspended"
    max_ack_pending::Int64
    "For push consumers this will regularly send an empty mess with Status header 100 and a reply subject, consumers must reply to these messages to control the rate of message delivery"
    flow_control::Union{Bool, Nothing}
    "Creates a special consumer that does not touch the Raft layers, not for general use by clients, internal use only"
    direct::Union{Bool, Nothing}
    "Delivers only the headers of messages in the stream and not the bodies. Additionally adds Nats-Msg-Size header to indicate the size of the removed payload"
    headers_only::Union{Bool, Nothing}
    "The largest batch property that may be specified when doing a pull on a Pull Consumer"
    max_batch::Union{Int64, Nothing}
    "List of durations in Go format that represents a retry time scale for NaK'd messages"
    backoff::Union{Vector, Nothing}
    "Force the consumer state to be kept in memory rather than inherit the setting from the stream"
    mem_storage::Union{Bool, Nothing}
end

const DEFAULT_CONSUMER_CONFIG = (
    deliver_policy = "all",
    durable_name = nothing,
    name = nothing,
    description = nothing,
    deliver_subject = nothing,
    ack_policy = "all",
    ack_wait = ACK_WAIT_DEFAULT,
    max_deliver = 1000,
    filter_subject = nothing,
    filter_subjects = nothing,
    replay_policy = "instant",
    sample_freq = nothing,
    max_ack_pending = 1000,
    flow_control = nothing,
    direct = nothing,
    headers_only = nothing,
    max_batch = nothing,
    backoff = nothing,
    mem_storage = nothing
)

struct Consumer
    connection::NATS.Connection
end

function consumer_create_or_update(stream::String, connection)

end

using StructTypes
StructTypes.omitempties(::Type{ConsumerConfiguration}) = true

function consumer_create(stream::String; connection::NATS.Connection, kwargs...)
    haskey(kwargs, :durable_name) && error("`durable_name` is deprecated, use `name` or leave not set for empheral consumer.")
    subject = if haskey(kwargs, :name)
        # Creating durable consumer.
        kwargs = merge((durable_name = get(kwargs, :name, nothing),), kwargs)
        "\$JS.API.CONSUMER.DURABLE.CREATE.$(stream).$(get(kwargs, :name, nothing))"
    else
        # Creating empheral consumer.
        kwargs = merge((name = randstring(connection.rng, 10),), kwargs)
        "\$JS.API.CONSUMER.CREATE.$(stream).$(kwargs.name)"
    end
    config = NATS.from_kwargs(ConsumerConfiguration, DEFAULT_CONSUMER_CONFIG, kwargs)
    req = JSON3.write(Dict(:stream_name => stream, :config => config))
    resp = NATS.request(JSON3.Object, connection, subject, req)
    haskey(resp, :error) && error("Failed to create consumer: $(resp.error.description).")
    resp.name
end

function consumer_update(stream::String, config::ConsumerConfiguration; connection)

end

function consumer_ordered(stream::String, name::String)

end

function consumer_delete()

end

function consumer()
    connection::NATS.connection
end

function next(consumer::Consumer)
    msg = request(nc, "\$JS.API.CONSUMER.MSG.NEXT.$(conumer.stream).$(consumer.name)")
end

function next(stream::String, consumer::String; connection::NATS.Connection)
    msg = NATS.request(connection, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer")
end

function fetch()
end

function ack(msg::NATS.Message; connection::NATS.Connection)
    publish(nc, msg.reply_to)
end

function nak(msg::NATS.Message; connection::NATS.Connection)
    publish(nc, msg.reply_to; payload = "-NAK")
end
