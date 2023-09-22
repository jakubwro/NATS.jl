@enum KeyValueOperation NONE PUT DELETE PURGE

const MAX_HISTORY    = 64
const ALL_KEYS       = ">"
const LATEST_REVISION = UInt(0)

struct KeyValueEntry
    # Bucket is the bucket the data was loaded from.
    bucket::String
    # Key is the key that was retrieved.
    key::String
    # Value is the retrieved value.
    value::Vector{UInt8}
    # Revision is a unique sequence for this value.
    revision::UInt64
    # Created is the time the data was put in the bucket.
    created::Any # DateTime
    # Delta is distance from the latest value.
    delta::UInt64
    # Operation returns Put or Delete or Purge.
    operation::KeyValueOperation
end

struct KeyValue <: AbstractDict{String, KeyValueEntry}
    connection::NATS.Connection
end

function keyvalue_create(stream_config::StreamConfiguration; connection::NATS.Connection = NATS.default_connection(), timer = Timer(JS_TM_S))
    res = request("\$JS.API.STREAM.DELETE.<stream>", stream_config;  connection)
    if error
        error("")
    end
end

function keyvalue_delete()

end

function keyvalue_names()

end

function keyvalue_list()

end

function keyvalue(; connection::NATS.Connection = NATS.default_connection())::KeyValue

end

function kv_get(; revision::UInt64 = LATST_REVISION)

end

function kv_put() # setindex!

end

function kv_create() # setindex!

end

function kv_update() # setindex!(; revision)

end

function kv_delete() # delete!

end

function kv_purge() # empty!

end

function kv_watch(kv::Any, key::String = nothing; kw...)::Channel{KeyValueEntry} # better use do

end

function kv_keys(kv::Any) # keys

end


function kv_history(kv::Any, key::String)

end

function kv_bucket()

end

function kv_status()

end

# https://github.com/JuliaLang/julia/issues/25941

# get!, get,  getindex, haskey, setindex!, pairs, keys, values, delete!
# additionally: history(kventry::KeyValueEntry), get(; revision = nothing)


default_options = (a = 2, b = 4)

function _zxc(x; options...)
    @show options
end

function zxc(x; options...)
    @show setdiff(keys(options), keys(default_options))
    # options = merge(options, default_options)
    @show options
end
