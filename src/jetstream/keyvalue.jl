



@enum KeyValueOperation NONE PUT DELETE PURGE

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
end

function kv_store_create()

end

function kv_store_delete()

end

function kv_store_names()

end

function kv_store_list()

end


function kv_get(; revision::UInt64 = nothing)

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
