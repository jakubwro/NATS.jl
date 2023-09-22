import Base.convert

function convert(::Type{StreamCreateResponse}, msg::NATS.Message)
    JSON3.read(msg.payload, StreamCreateResponse)
end
