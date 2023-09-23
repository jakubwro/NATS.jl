import Base.convert

function convert(::Type{JSON3.Object}, msg::NATS.Message)
    JSON3.read(msg.payload)
end
