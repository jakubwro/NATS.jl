
using Test
using NATS

import Base: convert, show

struct Person
    name::String
    age::Int64
    departament::String
end

function convert(::Type{Person}, msg::NATS.Msg)
    name, age, departament = split(payload(msg), ",")
    Person(name, parse(Int64, age), departament)
end

function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
    print(io, ",")
    print(io, person.departament)
end

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection."

@testset "Publish subscribe with custom data" begin
    c = Channel()
    sub = subscribe(nc, "EMPLOYEES") do person::Person
        put!(c, person)
    end
    publish(nc, "EMPLOYEES", Person("Jacek", 33, "IT"))
    result = take!(c)
    @test result isa Person
    @test result.name == "Jacek"
    @test result.age == 33
    @test length(nc.sub_data) == 1
    drain(nc, sub)
    @test length(nc.sub_data) == 0
end

@testset "Request reply with custom data" begin
    sub = reply(nc, "EMPLOYEES.SUPERVISOR") do person::Person
        if person.departament == "IT"
            Person("Zbigniew", 44, "IT"), ["status" => "ok"]
        elseif person.departament == "HR"
            Person("Maciej", 55, "HR"), ["status" => "ok"]
        else
            @info "Error response."
            ["status" => "error", "message" => "Unexpected departament `$(person.departament)`"]
        end
    end
    supervisor = request(Person, nc, "EMPLOYEES.SUPERVISOR", Person("Jacek", 33, "IT"))
    @test supervisor isa Person
    @test supervisor.name == "Zbigniew"
    @test supervisor.age == 44

    msg = request(nc, "EMPLOYEES.SUPERVISOR", Person("Anna", 33, "ACCOUNTING"))
    @test msg isa NATS.Msg
    @test headers(msg) == ["status" => "error", "message" => "Unexpected departament `ACCOUNTING`"]
    drain(nc, sub)
end