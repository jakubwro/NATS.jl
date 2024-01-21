

function keyvalue_stream_create_or_update(bucket::String, history = 1)
    
end

function keyvalue_stream_info(bucket::String)
    JetStream.stream_info(connection, "KV_$bucket")
end
