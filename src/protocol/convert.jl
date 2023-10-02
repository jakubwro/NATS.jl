# Serialization of protocol messages into structured data.

function convert(::Type{String}, msg::Union{NATS.Msg, NATS.HMsg})
    # Default representation on msg content is payload string.
    # This allows to use handlers that take just string and do not need other fields.
    payload(msg)
end
