

function Base.show(io::IO, ::NATS.MIME_PAYLOAD, config::JetStreamPayload)
    # Allows to return string from handler for `reply`.
    JSON3.write(io, config)
    nothing
end

