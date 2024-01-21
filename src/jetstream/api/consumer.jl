
@kwdef struct ConsumerConfiguration
    "A unique name for a durable consumer"
    durable_name::Union{String, Nothing} = nothing
    "A unique name for a consumer"
    name::Union{String, Nothing} = nothing
    "A short description of the purpose of this consumer"
    description::Union{String, Nothing} = nothing
    deliver_subject::Union{String, Nothing} = nothing
    ack_policy::Symbol = :none
    "How long (in nanoseconds) to allow messages to remain un-acknowledged before attempting redelivery"
    ack_wait::Union{Int64, Nothing} = 30000000000
    "The number of times a message will be redelivered to consumers if not acknowledged in time"
    max_deliver::Union{Int64, Nothing} = 1000
    # This one is only for NATS 2.9 and older
    # "Filter the stream by a single subjects"
    # filter_subject::Union{String, Nothing} = nothing
    "Filter the stream by multiple subjects"
    filter_subjects::Union{Vector{String}, Nothing} = nothing
    replay_policy::Symbol = :instant
    sample_freq::Union{String, Nothing} = nothing
    "The rate at which messages will be delivered to clients, expressed in bit per second"
    rate_limit_bps::Union{UInt64, Nothing} = nothing
    "The maximum number of messages without acknowledgement that can be outstanding, once this limit is reached message delivery will be suspended"
    max_ack_pending::Union{Int64, Nothing} = nothing
    "If the Consumer is idle for more than this many nano seconds a empty message with Status header 100 will be sent indicating the consumer is still alive"
    idle_heartbeat::Union{Int64, Nothing} = nothing
    "For push consumers this will regularly send an empty mess with Status header 100 and a reply subject, consumers must reply to these messages to control the rate of message delivery"
    flow_control::Union{Bool, Nothing} = nothing
    "The number of pulls that can be outstanding on a pull consumer, pulls received after this is reached are ignored"
    max_waiting::Union{Int64, Nothing} = nothing
    "Delivers only the headers of messages in the stream and not the bodies. Additionally adds Nats-Msg-Size header to indicate the size of the removed payload"
    headers_only::Union{Bool, Nothing} = nothing
    "The largest batch property that may be specified when doing a pull on a Pull Consumer"
    max_batch::Union{Int64, Nothing} = nothing
    "The maximum expires value that may be set when doing a pull on a Pull Consumer"
    max_expires::Union{Int64, Nothing} = nothing
    "The maximum bytes value that maybe set when dong a pull on a Pull Consumer"
    max_bytes::Union{Int64, Nothing} = nothing
    "Duration that instructs the server to cleanup ephemeral consumers that are inactive for that long"
    inactive_threshold::Union{Int64, Nothing} = nothing
    "List of durations in Go format that represents a retry time scale for NaK'd messages"
    backoff::Union{Vector{Int64}, Nothing} = nothing
    "When set do not inherit the replica count from the stream but specifically set it to this amount"
    num_replicas::Union{Int64, Nothing} = nothing
    "Force the consumer state to be kept in memory rather than inherit the setting from the stream"
    mem_storage::Union{Bool, Nothing} = nothing
    # "Additional metadata for the Consumer"
    # metadata::Union{Any, Nothing} = nothing
end

@kwdef struct SequenceInfo
    "The sequence number of the Consumer"
    consumer_seq::UInt64
    "The sequence number of the Stream"
    stream_seq::UInt64
    "The last time a message was delivered or acknowledged (for ack_floor)"
    last_active::Union{NanoDate, Nothing} = nothing
end

@kwdef struct ConsumerInfo <: ApiResponse
    "The Stream the consumer belongs to"
    stream_name::String
    "A unique name for the consumer, either machine generated or the durable name"
    name::String
    "The server time the consumer info was created"
    ts::Union{NanoDate, Nothing} = nothing
    config::ConsumerConfiguration
    "The time the Consumer was created"
    created::NanoDate
    "The last message delivered from this Consumer"
    delivered::SequenceInfo
    "The highest contiguous acknowledged message"
    ack_floor::SequenceInfo
    "The number of messages pending acknowledgement"
    num_ack_pending::Int64
    "The number of redeliveries that have been performed"
    num_redelivered::Int64
    "The number of pull consumers waiting for messages"
    num_waiting::Int64
    "The number of messages left unconsumed in this Consumer"
    num_pending::UInt64
    cluster::Union{ClusterInfo, Nothing} = nothing
    "Indicates if any client is connected and receiving messages from a push consumer"
    push_bound::Union{Bool, Nothing} = nothing
end

@kwdef struct StoredMessage
    "The subject the message was originally received on"
    subject::String
    "The sequence number of the message in the Stream"
    seq::UInt64
    "The base64 encoded payload of the message body"
    data::Union{String, Nothing} = nothing
    "The time the message was received"
    time::String
    "Base64 encoded headers for the message"
    hdrs::Union{String, Nothing} = nothing
end
