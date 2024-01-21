
function throw_on_api_error(response::JSON3.Object)
    if haskey(response, :error)
        throw(JSON3.read(JSON3.write(response.error), ApiError))
    end
end

function Base.showerror(io::IO, err::ApiError)
    print(io, "JetStream ")
    printstyled(io, "$(err.code)"; color=Base.error_color())
    if !isnothing(err.description)
        print(io, ": $(err.description).")
    end
end
