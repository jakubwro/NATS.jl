function validate_name(name::String)
    # ^[^.*>]+$
    # https://github.com/nats-io/jsm.go/blob/30c85c3d2258321d4a2ded882fe8561a83330e5d/schema_source/jetstream/api/v1/definitions.json#L445
    isempty(name) && error("Name is empty.")
    for c in name
        if c == '.' || c == '*' || c == '>'
            error("Name \"$name\" contains invalid character '$c'.")
        end
    end
    true
end

function validate(stream_configuration::StreamConfiguration)
    validate_name(stream_configuration.name)
    stream_configuration.retention in STREAM_RETENTION_OPTIONS || error("Invalid `retention = :$(stream_configuration.retention)`, expected one of $STREAM_RETENTION_OPTIONS") 
    true
end
