
const KEY_VALUE_OPERATIONS = [:none, :put, :delete, :purge]

const MAX_HISTORY    = 64
const ALL_KEYS       = ">"
const LATEST_REVISION = UInt(0)

function KeyValueEntry{T}(msg::NATS.Msg) where {T}
    @show NATS.headers(msg)
    _, _, stream, cons, _, revision, sequence, nanos, remaining = split(msg.reply_to, '.')
    key = string(last(split(msg.subject, '.')))
    op = _kv_op(msg)
    value = op == :put ? convert(T, msg) : nothing
    bucket = stream[4:end]
    KeyValueEntry{T}(
        bucket,
        key,
        value,
        parse(Int64, revision),
        NanoDate(parse(Int64, nanos)),
        0,
        op)
end

function show(io::IO, entry::KeyValueEntry)
    print(io, "$(entry.key) => $(entry.value)")
end

function isdeleted(entry::KeyValueEntry)
    entry.operation == :del || entry.operation == :purge
end

@kwdef struct KeyValue{TValue} <: AbstractDict{String, TValue}
    connection::NATS.Connection
    bucket::String
    stream_info::StreamInfo
    value_type::DataType
    revisions::ScopedValue{Dict{String, UInt64}} = ScopedValue{Dict{String, UInt64}}()
end

connection(kv::KeyValue) = kv.connection
bucket(kv::KeyValue) = kv.bucket
stream_name(kv::KeyValue) = kv.stream_info.config.name

function KeyValue{T}(bucket::String; connection::NATS.Connection = NATS.connection(:default)) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    try
        stream_info = JetStream.stream_info(connection, "KV_$bucket")
        KeyValue{T}(connection, bucket, stream_info, T, ScopedValue{Dict{String, UInt64}}())
    catch err
        (err isa ApiError && err.code == 404) || rethrow()
        @info "KV $bucket does not exists, creating now."
        stream_info = keyvalue_create(bucket; connection)
        KeyValue{T}(connection, bucket, stream_info, T,ScopedValue{Dict{String, UInt64}}())
    end
end

function KeyValue(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    KeyValue{String}(bucket::String; connection)
end

function keyvalue_create(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_config = StreamConfiguration(
        name = "KV_$bucket",
        subjects = ["\$KV.$bucket.>"],
        allow_rollup_hdrs = true,
        deny_delete = true,
        allow_direct = true,
        max_msgs_per_subject = 1,
        discard = :new;
    )
    stream_create(connection, stream_config)
end

function keyvalue_delete(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_delete(connection, "KV_$bucket")
end

function keyvalue_names(; connection::NATS.Connection = NATS.connection(:default))
    map(stream_names(; subject = "\$KV.>", connection)) do sn
        replace(sn, r"^KV_"=>"")
    end
end

function keyvalue_list(; connection::NATS.Connection = NATS.connection(:default))
    stream_list(; subject = "\$KV.>", connection)
end

function validate_key(key::String)
    isempty(key) && error("Key is an empty string.")
    first(key) == '.' && error("Key \"$key\" starts with '.'")
    last(key) == '.' && error("Key \"$key\" ends with '.'")
    for c in key
        is_valid = isdigit(c) || isletter(c) || c in [ '-', '/', '_', '=', '.' ]
        !is_valid && error("Key \"$key\" contains invalid character '$c'.")
    end
    true
end

function setindex!(kv::KeyValue, value, key::String)
    revisions = ScopedValues.get(kv.revisions)
    hdrs = NATS.Headers()
    if !isnothing(revisions)
        revision = get(revisions, key, 0)
        push!(hdrs, "Nats-Expected-Last-Subject-Sequence" => string(revision))
    end
    validate_key(key)
    ack = JetStream.stream_publish(connection(kv), "\$KV.$(kv.bucket).$key", (value, hdrs))
    @assert !isnothing(ack.seq)
    if !isnothing(revisions)
        revisions[key] = ack.seq
    end
    kv
end

#  revision::UInt64 = KV_REVISION_LATEST
function getindex(kv::KeyValue, key::String)
    validate_key(key)
    subject = "\$KV.$(kv.bucket).$key"
    msg = try
            stream_message_get(connection(kv), kv.stream_info, subject)
          catch err
            if err isa NATS.NATSError && err.code == 404
                throw(KeyError(key))
            else
                rethrow()
            end
          end
    op = NATS.headers(msg, "KV-Operation")
    if !isempty(op) && only(op) == "DEL"
        throw(KeyError(key))
    end
    seq = NATS.header(msg, "Nats-Sequence")
    revisions = ScopedValues.get(kv.revisions)
    if !isnothing(revisions)
        revisions[key] = parse(UInt64, seq)
    end
    # ts = NATS.header(msg, "Nats-Time-Stamp")
    # KeyValueEntry(kv.bucket, key, NATS.payload(msg), parse(UInt64, seq), NanoDate(ts), 0, :none)
    convert(kv.value_type, msg)
end

function empty!(kv::KeyValue)
    # hdrs = [ "KV-Operation" => "PURGE" ]
    # ack = publish("\$KV.$(kv.bucket)", (nothing, hdrs); connection = kv.connection)
    stream_purge(connection(kv), stream_name(kv))
end

function delete!(kv::KeyValue, key::String)
    hdrs = [ "KV-Operation" => "DEL" ]
    ack = stream_publish(connection(kv), "\$KV.$(kv.bucket).$key", (nothing, hdrs))
end

function _kv_op(msg::NATS.Msg)
    hdrs = String(@view msg.payload[begin:msg.headers_length])
    range = findfirst("KV-Operation", hdrs)
    isnothing(range) && return :put
    ending = findfirst("\r\n", hdrs[last(range):end])
    op = hdrs[(last(range) + 3):(last(range) + first(ending)-2)]
    if op == "DEL"
        :del
    elseif op == "PURGE"
        :purge
    else
        :unexpected
    end
end

function watch(f, kv::KeyValue; skip_deleted = false, all = true)::Tuple{NATS.Sub, ConsumerInfo}
    JetStream.stream_subscribe(connection(kv), "\$KV.$(kv.bucket).>") do msg
        entry = KeyValueEntry{kv.value_type}(msg)
        if !isdeleted(entry) || !skip_deleted
            f(entry)
        end
    end
end

function iterate(kv::KeyValue)
    unique_keys = Set{String}()
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = consumer_create(connection(kv), consumer_config, "KV_$(kv.bucket)")
    msg = try 
            consumer_next(connection(kv), consumer, no_wait = true)
          catch err
            if err isa NATS.NATSError && err.code == 404
                return nothing
            else
                rethrow()
            end
          end
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    value = convert(kv.value_type, msg)
    push!(unique_keys, key)
    (key => value, (consumer, unique_keys))
end

# function convert(::Type{KeyValueEntry}, msg::NATS.Msg)
#     spl = split(msg.reply_to, ".")
#     _1, _2, stream, cons, s1, seq, s3, nanos, rem = spl

#     KeyValueEntry(stream, msg.subject, NATS.payload(msg), parse(UInt64, seq), unixmillis2nanodate(parse(Int128, nanos)), 0, :none)
# end

# No way to get number of not deleted items fast, also kv can change during iteration.
IteratorSize(::KeyValue) = Base.SizeUnknown()
IteratorSize(::Base.KeySet{String, KeyValue{T}}) where {T} = Base.SizeUnknown()
IteratorSize(::Base.ValueIterator{JetStream.KeyValue{T}}) where {T} = Base.SizeUnknown()

function iterate(kv::KeyValue, (consumer, unique_keys))
    msg = try 
        consumer_next(connection(kv), consumer, no_wait = true)
      catch err
        if err isa NATS.NATSError && err.code == 404
            return nothing
        else
            rethrow()
        end
      end
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    op = _kv_op(msg)
    if key in unique_keys
        @warn "Key \"$key\" changed during iteration."
        # skip item
        iterate(kv, (consumer, unique_keys))
    elseif op == :del || op == :purge 
        # Item is deleted, continue.
        #TODO change cond order
        iterate(kv, (consumer, unique_keys))
    else
        value = convert(kv.value_type, msg)
        push!(unique_keys, key)
        (key => value, (consumer, unique_keys))
    end
end

function length(kv::KeyValue)
    # TODO: this is not reliable way to check length, it counts deleted items
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = consumer_create(connection(kv), consumer_config, "KV_$(kv.bucket)")
    msg = consumer_next(connection(kv), consumer, no_wait = true)
    if NATS.statuscode(msg) == 404
        0
    else
        remaining = last(split(msg.reply_to, "."))
        parse(Int64, remaining) + 1
    end
end

# function watch(f, kv::KeyValue, key::String = ALL_KEYS; kw...) 

# end

# function watch(kv::KeyValue, key::String = ALL_KEYS; kw...)::Channel{KeyValueEntry}

# end

function history(kv::KeyValue, key::String)::Vector{KeyValueEntry}

end

function kv_status()

end

# https://github.com/JuliaLang/julia/issues/25941

# get!, get,  getindex, haskey, setindex!, pairs, keys, values, delete!
# additionally: history(kventry::KeyValueEntry), get(; revision = nothing)
