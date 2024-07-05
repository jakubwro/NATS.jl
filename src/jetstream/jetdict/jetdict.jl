

include("encode.jl")

struct JetDict{T} <: AbstractDict{String, T}
    connection::NATS.Connection
    bucket::String
    stream_info::StreamInfo
    T::DataType
    revisions::ScopedValue{Dict{String, UInt64}}
    encoding::KeyEncoding
end

function get_jetdict_stream_info(connection, bucket, encoding)
    res = stream_info(connection, "$KV_STREAM_NAME_PREFIX$bucket"; no_throw = true)
    if res isa ApiError
        res.code != 404 && throw(res)
        keyvalue_stream_create(connection, bucket, encoding, 1)
    else
        stream_encoding = isnothing(res.config.metadata) ? :none : Symbol(get(res.config.metadata, "encoding", "none"))
        if encoding != stream_encoding
            error("Encoding do not match, cannot use :$encoding encoding on stream with :$stream_encoding encoding")
        end
        res
    end
end

function JetDict{T}(connection::NATS.Connection, bucket::String, encoding::Symbol = :none) where T
    check_encoding_implemented(encoding)
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    stream = get_jetdict_stream_info(connection, bucket, encoding)
    JetDict{T}(connection, bucket, stream, T, ScopedValue{Dict{String, UInt64}}(), KeyEncoding{encoding}())
end

function setindex!(jetdict::JetDict{T}, value::T, key::String) where T
    escaped = encodekey(jetdict.encoding, key)
    validate_key(escaped)
    revisions = ScopedValues.get(jetdict.revisions)
    if !isnothing(revisions)
        revision = get(revisions.value, key, 0)
        ack = keyvalue_put(jetdict.connection, jetdict.bucket, escaped, value, revision)
        @assert ack isa PubAck
        revisions.value[key] = ack.seq
    else
        ack = keyvalue_put(jetdict.connection, jetdict.bucket, escaped, value)
        @assert ack isa PubAck
    end
    jetdict
end

function getindex(jetdict::JetDict, key::String)
    escaped = encodekey(jetdict.encoding, key)
    validate_key(escaped)
    msg = try
            keyvalue_get(jetdict.connection, jetdict.bucket, escaped)
          catch err
            if err isa NATS.NATSError && err.code == 404
                throw(KeyError(key))
            else
                rethrow()
            end
          end
    if isdeleted(msg)
        throw(KeyError(key))
    end
    revisions = ScopedValues.get(jetdict.revisions)
    if !isnothing(revisions)
        seq = NATS.header(msg, "Nats-Sequence")
        revisions.value[key] = parse(UInt64, seq)
    end
    convert(jetdict.T, msg)
end

function delete!(jetdict::JetDict, key::String)
    escaped = encodekey(jetdict.encoding, key)
    ack = keyvalue_delete(jetdict.connection, jetdict.bucket, escaped)
    @assert ack isa PubAck
    jetdict
end

# No way to get number of not deleted items fast, also kv can change during iteration.
IteratorSize(::JetDict) = Base.SizeUnknown()
IteratorSize(::Base.KeySet{String, JetDict{T}}) where {T} = Base.SizeUnknown()
IteratorSize(::Base.ValueIterator{JetDict{T}}) where {T} = Base.SizeUnknown()

function iterate(jetdict::JetDict)
    unique_keys = Set{String}()
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = consumer_create(jetdict.connection, consumer_config, jetdict.stream_info)
    msg = consumer_next(jetdict.connection, consumer, no_wait = true, no_throw = true)
    msg_status = NATS.statuscode(msg)
    msg_status == 404 && return nothing
    NATS.throw_on_error_status(msg)
    key = decodekey(jetdict.encoding, replace(msg.subject, "\$KV.$(jetdict.bucket)." => ""))
    value = convert(jetdict.T, msg)
    push!(unique_keys, key)
    (key => value, (consumer, unique_keys))
end

function iterate(jetdict::JetDict, (consumer, unique_keys))
    msg = consumer_next(jetdict.connection, consumer, no_wait = true, no_throw = true) 
    msg_status = NATS.statuscode(msg)
    msg_status == 404 && return nothing
    NATS.throw_on_error_status(msg)
    key = decodekey(jetdict.encoding, replace(msg.subject, "\$KV.$(jetdict.bucket)." => ""))
    if key in unique_keys
        @warn "Key \"$key\" changed during iteration."
        # skip item
        iterate(jetdict, (consumer, unique_keys))
    elseif isdeleted(msg)
        # skip item
        iterate(jetdict, (consumer, unique_keys))
    else
        value = convert(jetdict.T, msg)
        push!(unique_keys, key)
        (key => value, (consumer, unique_keys))
    end
end


function length(jetdict::JetDict)
    # TODO: this is not reliable way to check length, it counts deleted items
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = consumer_create(jetdict.connection, consumer_config, "KV_$(jetdict.bucket)")
    msg = consumer_next(jetdict.connection, consumer, no_wait = true, no_throw = true)
    msg_status = NATS.statuscode(msg)
    msg_status == 404 && return 0
    NATS.throw_on_error_status(msg)
    remaining = last(split(msg.reply_to, "."))
    parse(Int64, remaining) + 1
end

function empty!(jetdict::JetDict)
    keyvalue_stream_purge(jetdict.connection, jetdict.bucket)
    jetdict
end

function with_optimistic_concurrency(f, kv::JetDict)
    with(f, kv.revisions => Dict{String, UInt64}())
end

function isdeleted(msg)
    NATS.header(msg, "KV-Operation") in [ "DEL", "PURGE" ]
end

function watch(f, jetdict::JetDict, key = ALL_KEYS; skip_deletes = false)
    keyvalue_watch(jetdict.connection, jetdict.bucket, key) do msg
        deleted = isdeleted(msg)
        if !(skip_deletes && isdeleted(msg))
            encoded_key = msg.subject[begin + 1 + length(keyvalue_subject_prefix(jetdict.bucket)):end]
            key = decodekey(jetdict.encoding, encoded_key)
            value = deleted ? nothing : convert(jetdict.T, msg)
            f(key => value)
        end
    end
end
