struct KeyValueEntry{TValue}
    bucket::String # Bucket is the bucket the data was loaded from.    
    key::String # Key is the key that was retrieved.    
    value::Union{TValue, Nothing} # Value is the retrieved value.    
    revision::UInt64 # Revision is a unique sequence for this value.    
    created::NanoDate # Created is the time the data was put in the bucket.    
    delta::UInt64 # Delta is distance from the latest value.    
    operation::Symbol # Operation returns Put or Delete or Purge.
end