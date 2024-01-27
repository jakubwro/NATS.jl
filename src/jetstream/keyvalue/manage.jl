

function keyvalue_stream_name(bucket::String)
    "KV_$bucket"
end

function keyvalue_subject_prefix(bucket::String)
    "\$KV.$bucket"
end

const MAX_HISTORY = 64

"""
$(SIGNATURES)

Create a stream for KV bucket.
"""
function keyvalue_stream_create(connection::NATS.Connection, bucket::String, encoding::Symbol, history = 1)
    history in 1:MAX_HISTORY || error("History must be greater than 0 and cannot be greater than $MAX_HISTORY")
    stream_config = StreamConfiguration(
        name = keyvalue_stream_name(bucket),
        subjects = ["$(keyvalue_subject_prefix(bucket)).>"],
        allow_rollup_hdrs = true,
        deny_delete = true,
        allow_direct = true,
        max_msgs_per_subject = history,
        discard = :new,
        metadata = Dict("encoding" => string(encoding))
    )
    stream_create(connection::NATS.Connection, stream_config)
end

function keyvalue_stream_info(connection::NATS.Connection, bucket::String)
    stream_info(connection, keyvalue_stream_name(bucket))
end

"""
$(SIGNATURES)

Delete a KV stream by bucket name.
"""
function keyvalue_stream_delete(connection::NATS.Connection, bucket::String)
    stream_delete(connection, keyvalue_stream_name(bucket))
end

"""
$(SIGNATURES)

Purge a KV stream.
"""
function keyvalue_stream_purge(connection::NATS.Connection, bucket::String)
    stream_purge(connection, keyvalue_stream_name(bucket))
end

"""
$(SIGNATURES)

Get a value from KV stream.
"""
function keyvalue_get(connection::NATS.Connection, bucket::String, key::String)::NATS.Msg
    validate_key(key)
    stream = keyvalue_stream_name(bucket)
    subject = "$(keyvalue_subject_prefix(bucket)).$key"
    stream_message_get(connection, stream, subject; allow_direct = true)
end

"""
$(SIGNATURES)

Put a value to KV stream.
"""
function keyvalue_put(connection::NATS.Connection, bucket::String, key::String, value, revision = 0)::PubAck
    validate_key(key)
    hdrs = NATS.Headers() #TODO: can preserve original headers?
    if revision > 0
        push!(hdrs, "Nats-Expected-Last-Subject-Sequence" => string(revision))
    end
    subject = "$(keyvalue_subject_prefix(bucket)).$key"
    stream_publish(connection, subject, (value, hdrs))
end

"""
$(SIGNATURES)

Delete a value from KV stream.
"""
function keyvalue_delete(connection::NATS.Connection, bucket::String, key)::PubAck
    validate_key(key)
    hdrs = [ "KV-Operation" => "DEL" ]
    subject = "$(keyvalue_subject_prefix(bucket)).$key"
    stream_publish(connection, subject, (nothing, hdrs))
end

function keyvalue_buckets(connection::NATS.Connection)
    map(stream_names(connection::NATS.Connection, "\$KV.>")) do stream_name
        stream_name[begin+length(KV_STREAM_NAME_PREFIX):end]
    end
end