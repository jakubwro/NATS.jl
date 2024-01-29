
function throw_on_api_error(response::JSON3.Object)
    if haskey(response, :error)
        throw(StructTypes.constructfrom(ApiError, response.error))
    end
end

function throw_on_api_error(response::ApiError)
    throw(response)
end

function throw_on_api_error(response::ApiResponse)
    # Nothing to do
end

function Base.showerror(io::IO, err::ApiError)
    print(io, "JetStream ")
    printstyled(io, "$(err.code)"; color=Base.error_color())
    if !isnothing(err.description)
        print(io, ": $(err.description).")
    end
end
