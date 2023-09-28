
const DEFAULT_NEXT_TIMEOUT_SECONDS = 5

const DEFAULT_CONSUMER_CONFIG = (
    deliver_policy = "all",
    durable_name = nothing,
    name = nothing,
    description = nothing,
    deliver_subject = nothing,
    ack_policy = "all",
    ack_wait = 30000000000,
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
    "How long (in nanoseconds) to allow messages to remain un-acknowledged before attempting redelivery. Default is $(div(DEFAULT_CONSUMER_CONFIG.ack_wait, 10^9)) seconds."
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

# function consumer_create_or_update(stream::String, connection)

# end

using StructTypes
StructTypes.omitempties(::Type{ConsumerConfiguration}) = true

function consumer_create(stream::String; connection::NATS.Connection, kwargs...)
    haskey(kwargs, :durable_name) && error("`durable_name` is deprecated, use `name`.")
    # TODO: handling of unnamed empheral consumers. Not clear if this is really needed.
    !haskey(kwargs, :name) && error("`name` is mandatory.")
    kwargs = merge((durable_name = get(kwargs, :name, nothing),), kwargs)
    subject = "\$JS.API.CONSUMER.CREATE.$(stream).$(kwargs[:name])"
    config = NATS.from_kwargs(ConsumerConfiguration, DEFAULT_CONSUMER_CONFIG, kwargs)
    req = JSON3.write(Dict(:stream_name => stream, :config => config))
    resp = NATS.request(JSON3.Object, subject, req; connection)
    haskey(resp, :error) && error("Failed to create consumer: $(resp.error.description).")
    resp.name
end

# function consumer_update(stream::String, config::ConsumerConfiguration; connection)

# end

# function consumer_ordered(stream::String, name::String)

# end

# function consumer_delete()

# end

function next(stream::String, consumer::String; timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS), connection::NATS.Connection)
    msg = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer"; connection, timer)
    # if isnothing(timer)
    #     NATS.request(connection, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{\"no_wait\": true}")
    # else
    #     NATS.request(connection, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer"; timer)
    # end
end

# function next(n::Int64, stream::String, consumer::String; connection::NATS.Connection)
#     # TODO: n validation
#     msgs = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{ \"batch\": $n}", n; connection)
#     msgs
# end

"""
Confirms message delivery to server.
"""
function ack(msg::NATS.Message; connection::NATS.Connection)
    if startswith(msg.reply_to, "\$JS.ACK")
        NATS.publish(msg.reply_to; connection)
    else
        @warn "Tried to `ack` message that don't need acknowledge." 
    end
end

"""
Mark message as undelivered, what avoid waiting for timeout before redelivery.
"""
function nak(msg::NATS.Message; connection::NATS.Connection)
    if startswith(msg.reply_to, "\$JS.ACK")
        NATS.publish(msg.reply_to; connection, payload = "-NAK")
    else
        @warn "Tried to `nak` message that does not need acknowledge." 
    end
end
