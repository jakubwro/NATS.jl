
const ALL_KEYS = ">"

"""
$(SIGNATURES)

Watch for changes in KV stream.
"""
function keyvalue_watch(f, connection::NATS.Connection, bucket::String, key = ALL_KEYS)
    prefix = keyvalue_subject_prefix(bucket)
    subject = "$prefix.$key"
    JetStream.stream_subscribe(f, connection, subject)
end
