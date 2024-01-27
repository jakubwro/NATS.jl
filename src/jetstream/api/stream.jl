
@kwdef struct SubjectTransform
    "The subject transform source"
    src::String
    "The subject transform destination"
    dest::String
end
@kwdef struct Placement
    "The desired cluster name to place the stream"
    cluster::Union{String, Nothing}
    "Tags required on servers hosting this stream"
    tags::Union{Vector{String}, Nothing} = nothing
end

@kwdef struct ExternalStreamSource
    "The subject prefix that imports the other account/domain $JS.API.CONSUMER.> subjects"
    api::String
    "The delivery subject to use for the push consumer"
    deliver::Union{String, Nothing} = nothing
end

@kwdef struct StreamSource
    "Stream name"
    name::String
    "Sequence to start replicating from"
    opt_start_seq::Union{UInt64, Nothing} = nothing
    "Time stamp to start replicating from"
    opt_start_time::Union{NanoDate, Nothing} = nothing
    "Replicate only a subset of messages based on filter"
    filter_subject::Union{String, Nothing} = nothing
    "The subject filtering sources and associated destination transforms"
    subject_transforms::Union{Vector{SubjectTransform}, Nothing} = nothing
    external::Union{ExternalStreamSource, Nothing} = nothing
end

import Base: convert

function convert(::Type{StreamSource}, name::String)
    StreamSource(; name)
end

function convert(::Type{StreamSource}, t::NamedTuple)
    StreamSource(; t...)
end

@kwdef struct Republish
    "The source subject to republish"
    src::String
    "The destination to publish to"
    dest::String
    "Only send message headers, no bodies"
    headers_only::Union{Bool, Nothing} = nothing
end

@kwdef struct StreamConsumerLimit
    "Maximum value for inactive_threshold for consumers of this stream. Acts as a default when consumers do not set this value."
    inactive_threshold::Union{Int64, Nothing} = nothing
    "Maximum value for max_ack_pending for consumers of this stream. Acts as a default when consumers do not set this value."
    max_ack_pending::Union{Int64, Nothing} = nothing
end

"""
Configuration options for a stream.

$(TYPEDFIELDS)
"""
@kwdef struct StreamConfiguration
    "A unique name for the Stream."
    name::String
    "A short description of the purpose of this stream"
    description::Union{String, Nothing} = nothing
    "A list of subjects to consume, supports wildcards. Must be empty when a mirror is configured. May be empty when sources are configured."
    subjects::Union{Vector{String}, Nothing} = nothing
    "Subject transform to apply to matching messages"
    subject_transform::Union{SubjectTransform, Nothing} = nothing
    "How messages are retained in the Stream, once this is exceeded old messages are removed."
    retention::Symbol = :limits
    "How many Consumers can be defined for a given Stream. -1 for unlimited."
    max_consumers::Int64 = -1
    "How many messages may be in a Stream, oldest messages will be removed if the Stream exceeds this size. -1 for unlimited."
    max_msgs::Int64 = -1
    "For wildcard streams ensure that for every unique subject this many messages are kept - a per subject retention limit"
    max_msgs_per_subject::Union{Int64, Nothing} = nothing
    "How big the Stream may be, when the combined stream size exceeds this old messages are removed. -1 for unlimited."
    max_bytes::Int64 = -1
    "Maximum age of any message in the stream, expressed in nanoseconds. 0 for unlimited."
    max_age::Int64 = 0
    "The largest message that will be accepted by the Stream. -1 for unlimited."
    max_msg_size::Union{Int32, Nothing} = nothing
    "The storage backend to use for the Stream."
    storage::Symbol = :file
    "Optional compression algorithm used for the Stream."
    compression::Symbol = :none
    "A custom sequence to use for the first message in the stream"
    first_seq::Union{UInt64, Nothing} = nothing
    "How many replicas to keep for each message."
    num_replicas::Int64 = 1
    "Disables acknowledging messages that are received by the Stream."
    no_ack::Union{Bool, Nothing} = nothing
    "When a Stream reach it's limits either old messages are deleted or new ones are denied"
    discard::Union{Symbol, Nothing} = nothing
    "The time window to track duplicate messages for, expressed in nanoseconds. 0 for default"
    duplicate_window::Union{Int64, Nothing} = nothing
    "Placement directives to consider when placing replicas of this stream, random placement when unset"
    placement::Union{Placement, Nothing} = nothing
    "Maintains a 1:1 mirror of another stream with name matching this property.  When a mirror is configured subjects and sources must be empty."
    mirror::Union{StreamSource, Nothing} = nothing
    "List of Stream names to replicate into this Stream"
    sources::Union{Vector{StreamSource}, Nothing} = nothing
    "Sealed streams do not allow messages to be deleted via limits or API, sealed streams can not be unsealed via configuration update. Can only be set on already created streams via the Update API"
    sealed::Union{Bool, Nothing} = nothing
    "Restricts the ability to delete messages from a stream via the API. Cannot be changed once set to true"
    deny_delete::Union{Bool, Nothing} = nothing
    "Restricts the ability to purge messages from a stream via the API. Cannot be change once set to true"
    deny_purge::Union{Bool, Nothing} = nothing
    "Allows the use of the Nats-Rollup header to replace all contents of a stream, or subject in a stream, with a single new message"
    allow_rollup_hdrs::Union{Bool, Nothing} = nothing
    "Allow higher performance, direct access to get individual messages"
    allow_direct::Union{Bool, Nothing} = nothing
    "Allow higher performance, direct access for mirrors as well"
    mirror_direct::Union{Bool, Nothing} = nothing
    republish::Union{Republish, Nothing} = nothing
    "When discard policy is new and the stream is one with max messages per subject set, this will apply the new behavior to every subject. Essentially turning discard new from maximum number of subjects into maximum number of messages in a subject."
    discard_new_per_subject::Union{Bool, Nothing} = nothing
    "Additional metadata for the Stream"
    metadata::Union{Dict{String, String}, Nothing} = nothing # TODO: what is this for?
    "Limits of certain values that consumers can set, defaults for those who don't set these settings"
    consumer_limits::Union{StreamConsumerLimit, Nothing} = nothing
end

@kwdef struct StreamState
    "Number of messages stored in the Stream"
    messages::UInt64
    "Combined size of all messages in the Stream"
    bytes::UInt64
    "Sequence number of the first message in the Stream"
    first_seq::UInt64
    "The timestamp of the first message in the Stream"
    # first_ts::Union{NanoDate, Nothing} = nothing
    first_ts::Union{String, Nothing} = nothing
    "Sequence number of the last message in the Stream"
    last_seq::UInt64
    "The timestamp of the last message in the Stream"
    # last_ts::Union{NanoDate, Nothing} = nothing
    last_ts::Union{String, Nothing} = nothing
    "IDs of messages that were deleted using the Message Delete API or Interest based streams removing messages out of order"
    deleted::Union{Vector{UInt64}, Nothing} = nothing
    # "Subjects and their message counts when a subjects_filter was set"
    # subjects::Union{Any, Nothing} = nothing
    "The number of unique subjects held in the stream"
    num_subjects::Union{Int64, Nothing} = nothing
    "The number of deleted messages"
    num_deleted::Union{Int64, Nothing} = nothing
    # lost::Union{LostStreamData, Nothing} = nothing
    "Number of Consumers attached to the Stream"
    consumer_count::Int64
end

@kwdef struct PeerInfo
    "The server name of the peer"
    name::String
    "Indicates if the server is up to date and synchronised"
    current::Bool = false
    "Nanoseconds since this peer was last seen"
    active::Int64
    "Indicates the node is considered offline by the group"
    offline::Union{Bool, Nothing} = nothing
    "How many uncommitted operations this peer is behind the leader"
    lag::Union{Int64, Nothing} = nothing
end

@kwdef struct ClusterInfo
    "The cluster name"
    name::Union{String, Nothing} = nothing
    "The server name of the RAFT leader"
    leader::Union{String, Nothing} = nothing
    "The members of the RAFT cluster"
    replicas::Union{Vector{PeerInfo}, Nothing} = nothing
end

@kwdef struct StreamSourceInfo
    "The name of the Stream being replicated"
    name::String
    "The subject filter to apply to the messages"
    filter_subject::Union{String, Nothing} = nothing
    "The subject filtering sources and associated destination transforms"
    subject_transforms::Union{Vector{SubjectTransform}, Nothing} = nothing
    "How many messages behind the mirror operation is"
    lag::UInt64
    "When last the mirror had activity, in nanoseconds. Value will be -1 when there has been no activity."
    active::Int64
    external::Union{ExternalStreamSource, Nothing} = nothing
    error::Union{ApiError, Nothing} = nothing
end

@kwdef struct StreamAlternate
    "The mirror stream name"
    name::String
    "The name of the cluster holding the stream"
    cluster::String
    "The domain holding the string"
    domain::Union{String, Nothing} = nothing
end

@kwdef struct StreamInfo <: ApiResponse
    "The active configuration for the Stream"
    config::StreamConfiguration
    "Detail about the current State of the Stream"
    state::StreamState
    "Timestamp when the stream was created"
    created::NanoDate
    "The server time the stream info was created"
    ts::Union{NanoDate, Nothing} = nothing
    cluster::Union{ClusterInfo, Nothing} = nothing
    mirror::Union{StreamSourceInfo, Nothing} = nothing
    "Streams being sourced into this Stream"
    sources::Union{Vector{StreamSourceInfo}, Nothing} = nothing
    "List of mirrors sorted by priority"
    alternates::Union{Vector{StreamAlternate}, Nothing} = nothing
end

@kwdef struct PubAck
    stream::String
    seq::Union{Int64, Nothing}
    duplicate::Union{Bool, Nothing}
    domain::Union{String, Nothing}
end
