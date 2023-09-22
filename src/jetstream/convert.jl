import Base.convert

function convert(::Type{T}, msg::NATS.Message) where { T <: JetStreamResponse }
    JSON3.read(msg.payload, T)
end
