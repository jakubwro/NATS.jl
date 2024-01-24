
#TODO key escape
struct JetDict{T} <: AbstractDict{String, T}
    connection::NATS.Connection
    bucket::String
    stream_info::StreamInfo
    T::DataType
    revisions::ScopedValue{Dict{String, UInt64}}
    encoding::Symbol
end

function JetDict{T}(connection::NATS.Connection, bucket::String, encoding = :none) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    stream = begin
        res = stream_info(connection, "$KV_STREAM_NAME_PREFIX$bucket"; no_throw = true)
        if res isa ApiError
            res.code != 404 && throw(res)
            keyvalue_stream_create(connection, bucket, encoding)
        else
            res
        end
    end
    stream_encoding = begin
        if isnothing(stream.config.metadata)
            :none
        else
            Symbol(get(stream.config.metadata, "encoding", "none"))
        end
    end
    if encoding != :none
        encoding != stream_encoding && error("Encoding do not match, cannot use $encoding encoding on stream with $stream_encoding encoding")
    else
        encoding != stream_encoding && @warn "Steam uses $stream_encoding key encoding, keys may look odd"
    end
    JetDict{T}(connection, bucket, stream, T, ScopedValue{Dict{String, UInt64}}(), encoding)
end

function setindex!(jetdict::JetDict{T}, value::T, key::String) where T
    escaped = encodekey(key, jetdict.encoding)
    validate_key(escaped)
    revisions = ScopedValues.get(jetdict.revisions)
    hdrs = NATS.Headers()
    if !isnothing(revisions)
        revision = get(revisions, key, 0)
        push!(hdrs, "Nats-Expected-Last-Subject-Sequence" => string(revision))
    end
    ack = JetStream.stream_publish(jetdict.connection, "\$KV.$(jetdict.bucket).$escaped", (value, hdrs))
    @assert !isnothing(ack.seq)
    if !isnothing(revisions)
        revisions[key] = ack.seq
    end
    jetdict
end

function getindex(jetdict::JetDict, key::String)
    escaped = encodekey(key, jetdict.encoding)
    validate_key(escaped)

    subject = "\$KV.$(jetdict.bucket).$escaped"
    msg = try
            stream_message_get(jetdict.connection, jetdict.stream_info, subject)
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
    revisions = ScopedValues.get(jetdict.revisions)
    if !isnothing(revisions)
        revisions[key] = parse(UInt64, seq)
    end
    convert(jetdict.T, msg)
end

function delete!(jetdict::JetDict, key::String)
    escaped = encodekey(key, jetdict.encoding)
    hdrs = [ "KV-Operation" => "DEL" ]
    ack = stream_publish(jetdict.connection, "\$KV.$(jetdict.bucket).$escaped", (nothing, hdrs))
    @assert ack isa PubAck
    jetdict
end

# No way to get number of not deleted items fast, also kv can change during iteration.
IteratorSize(::JetDict) = Base.SizeUnknown()
IteratorSize(::Base.KeySet{String, JetDict{T}}) where {T} = Base.SizeUnknown()
IteratorSize(::Base.ValueIterator{JetDict{T}}) where {T} = Base.SizeUnknown()

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

function iterate(jetdict::JetDict)
    unique_keys = Set{String}()
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = consumer_create(jetdict.connection, consumer_config, jetdict.stream_info)
    msg = try 
            consumer_next(jetdict.connection, consumer, no_wait = true)
          catch err #TODO: redesign it without try catch
            if err isa NATS.NATSError && err.code == 404
                return nothing
            else
                rethrow()
            end
          end
    key = decodekey(replace(msg.subject, "\$KV.$(jetdict.bucket)." => ""), jetdict.encoding)
    value = convert(jetdict.T, msg)
    push!(unique_keys, key)
    (key => value, (consumer, unique_keys))
end

function iterate(jetdict::JetDict, (consumer, unique_keys))
    msg = try 
        consumer_next(jetdict.connection, consumer, no_wait = true)
      catch err
        if err isa NATS.NATSError && err.code == 404
            return nothing
        else
            rethrow()
        end
      end
    key = decodekey(replace(msg.subject, "\$KV.$(jetdict.bucket)." => ""), jetdict.encoding)
    op = _kv_op(msg)
    if key in unique_keys
        @warn "Key \"$key\" changed during iteration."
        # skip item
        iterate(jetdict, (consumer, unique_keys))
    elseif op == :del || op == :purge 
        # Item is deleted, continue.
        #TODO change cond order
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
    msg = consumer_next(jetdict.connection, consumer, no_wait = true)
    if NATS.statuscode(msg) == 404
        0
    else
        remaining = last(split(msg.reply_to, "."))
        parse(Int64, remaining) + 1
    end
end

function empty!(jetdict::JetDict)
    keyvalue_stream_purge(jetdict.connection, jetdict.bucket)
    jetdict
end



const DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES = 3

function with_optimistic_concurrency(f, kv::JetDict; retry = true)
    with(kv.revisions => Dict{String, UInt64}()) do
        for _ in 1:DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES
            try
                f()
            catch err
                if err isa ApiError && err.err_code == 10071
                    @warn "Key update clash."
                    retry && continue
                else
                    rethrow()
                end
            end
        end
    end
end

function watch(f, jetdict::JetDict; skip_deletes = false)
    keyvalue_watch(jetdict.connection, jetdict.bucket) do msg
        if !(skip_deletes && isdeleted(msg))
            f(msg)
        end
    end
end

function watch(f, jetdict::JetDict, key::String; skip_deletes = false)
    keyvalue_watch(jetdict.connection, jetdict.bucket, key) do msg
        if !(skip_deletes && isdeleted(msg))
            f(msg)
        end
    end
end
