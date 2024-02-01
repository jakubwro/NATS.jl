module JetStream

using Dates
using NanoDates
using StructTypes
using Random
using JSON3
using DocStringExtensions
using ScopedValues
using Base64
using CodecBase

import NATS

import Base: show, showerror
import Base: setindex!, getindex, empty!, delete!, iterate, length
import Base: IteratorSize
import Base: put!, take!


export StreamConfiguration
export stream_create, stream_update, stream_update_or_create, stream_purge, stream_delete
export stream_publish, stream_subscribe, stream_unsubscribe
export stream_message_get, stream_message_delete

export ConsumerConfiguration
export consumer_create, consumer_update, consumer_delete
export consumer_next, consumer_ack, consumer_nak

export keyvalue_stream_create, keyvalue_stream_purge, keyvalue_stream_delete
export keyvalue_get, keyvalue_put, keyvalue_delete, keyvalue_watch
export JetDict, watch, with_optimistic_concurrency

export JetChannel, destroy!

const STREAM_RETENTION_OPTIONS       = [:limits, :interest, :workqueue]
const STREAM_STORAGE_OPTIONS         = [:file, :memory]
const STREAM_COMPRESSION_OPTIONS     = [:none, :s2]
const CONSUMER_ACK_POLICY_OPTIONS    = [:none, :all, :explicit]
const CONSUMER_REPLAY_POLICY_OPTIONS = [:instant, :original]

include("api/api.jl")
include("stream/stream.jl")
include("consumer/consumer.jl")
include("keyvalue/keyvalue.jl")
include("jetdict/jetdict.jl")
include("jetchannel/jetchannel.jl")

end
