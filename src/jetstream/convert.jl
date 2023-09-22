import Base.convert

function convert(::Type{T}, msg::NATS.Message) where { T <: JetStreamResponse }
    JSON3.read(msg.payload, T)
end

function convert(::Type{JSON3.Object}, msg::NATS.Message)
    JSON3.read(msg.payload)
end
