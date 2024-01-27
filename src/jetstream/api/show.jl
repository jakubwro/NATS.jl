

StructTypes.omitempties(::Type{SubjectTransform}) = true
StructTypes.omitempties(::Type{Placement}) = true
StructTypes.omitempties(::Type{ExternalStreamSource}) = true
StructTypes.omitempties(::Type{StreamSource}) = true
StructTypes.omitempties(::Type{Republish}) = true
StructTypes.omitempties(::Type{StreamConsumerLimit}) = true
StructTypes.omitempties(::Type{StreamConfiguration}) = true
StructTypes.omitempties(::Type{ConsumerConfiguration}) = true 

show(io::IO, st::SubjectTransform) = JSON3.pretty(io, st)
show(io::IO, st::Placement) = JSON3.pretty(io, st)
show(io::IO, st::ExternalStreamSource) = JSON3.pretty(io, st)
show(io::IO, st::StreamSource) = JSON3.pretty(io, st)
show(io::IO, st::Republish) = JSON3.pretty(io, st)
show(io::IO, st::StreamConsumerLimit) = JSON3.pretty(io, st)
show(io::IO, st::StreamConfiguration) = JSON3.pretty(io, st)


# function show(io::IO, ::MIME"text/plain", response::ApiResponse)
#     JSON3.pretty(io, response)
# end
