
function keyvalue_history(connection::NATS.Connection, bucket::String, key::String)
    subject = "$(keyvalue_subject_prefix(bucket)).$(key)"
    consumer_config = ConsumerConfiguration(;
        name = randstring(10),
        filter_subjects = [ subject ]
    )
    consumer = consumer_create(connection, consumer_config, keyvalue_stream_name(bucket))
    consumer_next(connection, consumer, 64; no_wait = true)
end
