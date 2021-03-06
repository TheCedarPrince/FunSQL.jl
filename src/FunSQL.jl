module FunSQL

using Dates

#
# SQL table.
#

mutable struct SQLTable
    scm::Symbol
    name::Symbol
    cols::Vector{Symbol}
end

#
# SQL Nodes.
#

abstract type SQLCore end

mutable struct SQLNode
    core::SQLCore
    args::Vector{SQLNode}
end

const EMPTY_SQLNODE_VECTOR = SQLNode[]

SQLNode(core::SQLCore) =
    SQLNode(core, EMPTY_SQLNODE_VECTOR)

SQLNode(core::SQLCore, arg::SQLNode) =
    SQLNode(core, [arg])

#
# Closure for incremental construction.
#

struct SQLNodeClosure
    core::SQLCore
    args::Vector{SQLNode}
end

SQLNodeClosure(core::SQLCore) =
    SQLNodeClosure(core, [])

(c::SQLNodeClosure)(n::SQLNode) =
    SQLNode(c.core, [n, c.args...])

(c::SQLNodeClosure)(n) =
    c(convert(SQLNode, n))

#
# Node cores.
#

@inline SQLCore(T::Type{<:SQLCore}, args...) =
    T(SQLCore, args...)

struct Unit <: SQLCore
    Unit(::Type{SQLCore}) =
        new()
end

struct From <: SQLCore
    tbl::SQLTable

    From(::Type{SQLCore}, tbl::SQLTable) =
        new(tbl)
end

struct Select <: SQLCore
    Select(::Type{SQLCore}) =
        new()
end

struct Where <: SQLCore
    Where(::Type{SQLCore}) =
        new()
end

struct Join <: SQLCore
    is_left::Bool
    is_right::Bool
    is_lateral::Bool

    Join(::Type{SQLCore}, is_left::Bool, is_right::Bool, is_lateral::Bool) =
        new(is_left, is_right, is_lateral)
end

struct Group <: SQLCore
    Group(::Type{SQLCore}) =
        new()
end

struct Window <: SQLCore
    order_length::Int
    frame_start::Symbol
    frame_end::Symbol
    frame_exclusion::Symbol

    Window(::Type{SQLCore}, order_length) =
        new(order_length, :_, :_, :_)
end

struct Append <: SQLCore
    Append(::Type{SQLCore}) =
        new()
end

struct As <: SQLCore
    name::Symbol

    As(::Type{SQLCore}, name::Symbol) =
        new(name)
end

struct Literal{T} <: SQLCore
    val::T

    Literal{T}(::Type{SQLCore}, val::T) where {T} =
        new{T}(val)
end

struct Lookup <: SQLCore
    name::Symbol

    Lookup(::Type{SQLCore}, name::Symbol) =
        new(name)
end

struct GetCall <: SQLCore
    name::Symbol

    GetCall(::Type{SQLCore}, name::Symbol) =
        new(name)
end

struct FunCall{S} <: SQLCore
    FunCall{S}(::Type{SQLCore}) where {S} =
        new{S}()
end

struct AggCall{S} <: SQLCore
    distinct::Bool

    AggCall{S}(::Type{SQLCore}, distinct::Bool) where {S} =
        new{S}(distinct)
end

struct Placeholder <: SQLCore
    pos::Int

    Placeholder(::Type{SQLCore}, pos::Int) =
        new(pos)
end

struct SelectClause <: SQLCore
    distinct::Bool

    SelectClause(::Type{SQLCore}, distinct::Bool=false) =
        new(distinct)
end

struct FromClause <: SQLCore
    FromClause(::Type{SQLCore}) =
        new()
end

struct JoinClause <: SQLCore
    is_left::Bool
    is_right::Bool

    JoinClause(::Type{SQLCore}, is_left::Bool, is_right::Bool) =
        new(is_left, is_right)
end

struct WhereClause <: SQLCore
    WhereClause(::Type{SQLCore}) =
        new()
end

struct HavingClause <: SQLCore
    HavingClause(::Type{SQLCore}) =
        new()
end

struct GroupClause <: SQLCore
    GroupClause(::Type{SQLCore}) =
        new()
end

struct WindowClause <: SQLCore
    order_length::Int
    frame_start::Symbol
    frame_end::Symbol
    frame_exclusion::Symbol

    WindowClause(::Type{SQLCore}, order_length) =
        new(order_length, :_, :_, :_)
end

struct UnionClause <: SQLCore
    all::Bool

    UnionClause(::Type{SQLCore}, all::Bool=true) =
        new(all)
end


#
# Constructors.
#

# From

From(::Nothing) =
    SQLNode(SQLCore(Unit))

From(tbl::SQLTable) =
    SQLNode(SQLCore(From, tbl))

const FromNothing = From(nothing)

Base.convert(::Type{SQLNode}, tbl::SQLTable) =
    From(tbl)

# Select

Select(list::Vector{SQLNode}) =
    SQLNodeClosure(SQLCore(Select), list)

Select(list::AbstractVector) =
    SQLNodeClosure(SQLCore(Select), SQLNode[list...])

Select(list...) =
    SQLNodeClosure(SQLCore(Select), SQLNode[list...])

# Where

Where(pred) =
    SQLNodeClosure(SQLCore(Where), SQLNode[pred])

# Join

Join(right, on; is_left::Bool=false, is_right::Bool=false, is_lateral::Bool=false) =
    SQLNodeClosure(SQLCore(Join, is_left, is_right, is_lateral), SQLNode[right, on])

# Group

Group(list::Vector{SQLNode}) =
    SQLNodeClosure(SQLCore(Group), list)

Group(list::AbstractVector) =
    SQLNodeClosure(SQLCore(Group), SQLNode[list...])

Group(list...) =
    SQLNodeClosure(SQLCore(Group), SQLNode[list...])

# Window

Window(list::AbstractVector; order::AbstractVector=EMPTY_SQLNODE_VECTOR) =
    SQLNodeClosure(SQLCore(Window, length(order)), SQLNode[list..., order...])

Window(list...; order::AbstractVector=EMPTY_SQLNODE_VECTOR) =
    SQLNodeClosure(SQLCore(Window, length(order)), SQLNode[list..., order...])

# Append (UNION ALL)

Append(list::Vector{SQLNode}) =
    SQLNodeClosure(SQLCore(Append), list)

Append(list::AbstractVector) =
    SQLNodeClosure(SQLCore(Append), SQLNode[list...])

Append(list...) =
    SQLNodeClosure(SQLCore(Append), SQLNode[list...])

# Aliases

As(name::Symbol) =
    SQLNodeClosure(SQLCore(As, name))

As(name::AbstractString) =
    SQLNodeClosure(SQLCore(As, Symbol(name)))

Base.convert(::Type{SQLNode}, p::Pair{Symbol}) =
    convert(SQLNode, last(p)) |> As(first(p))

Base.convert(::Type{SQLNode}, p::Pair{<:AbstractString}) =
    convert(SQLNode, Symbol(first(p)) => last(p))

# Constants

Literal(val::T) where {T} =
    SQLNode(SQLCore(Literal{T}, val))

Base.convert(::Type{SQLNode}, val::Union{Bool,Number,AbstractString,Dates.AbstractTime}) =
    Literal(val)

# Bound columns

Lookup(name::Symbol) =
    SQLNodeClosure(SQLCore(Lookup, name))

# Lookup

struct GetNamespace
end

struct GetClosure
    base::SQLNode
end

const Get = GetNamespace()

(nav::GetNamespace)(name::Symbol) =
    GetClosure(SQLNode(SQLCore(GetCall, name)))

function (nav::GetClosure)(name::Symbol)
    base = getfield(nav, :base)
    GetClosure(SQLNode(SQLCore(GetCall, name), base))
end

(nav::Union{GetNamespace,GetClosure})(name::AbstractString) =
    nav(Symbol(name))

(nav::Union{GetNamespace,GetClosure})(name::Union{Symbol,AbstractString}, more::Union{Symbol,AbstractString}...) =
    nav(name)(more...)

Base.getproperty(nav::Union{GetNamespace,GetClosure}, name::Symbol) =
    nav(name)

Base.getproperty(nav::Union{GetNamespace,GetClosure}, name::AbstractString) =
    nav(name)

Base.convert(::Type{SQLNode}, nav::GetClosure) =
    getfield(nav, :base)

# Operations

struct FunNamespace
end

struct FunClosure
    name::Symbol
end

const Fun = FunNamespace()

(fun::FunNamespace)(name::Symbol, args...) =
    SQLNode(SQLCore(FunCall{Symbol(uppercase(String(name)))}), SQLNode[args...])

(fun::FunNamespace)(name::AbstractString, args...) =
    SQLNode(SQLCore(FunCall{Symbol(name)}), SQLNode[args...])

Base.getproperty(fun::FunNamespace, name::Symbol) =
    FunClosure(Symbol(uppercase(String(name))))

Base.getproperty(fun::FunNamespace, name::AbstractString) =
    FunClosure(Symbol(name))

(fun::FunClosure)(args...) =
    SQLNode(SQLCore(FunCall{fun.name}), SQLNode[args...])

# Aggregate operations

struct AggNamespace
end

struct AggClosure
    name::Symbol
end

const Agg = AggNamespace()

(agg::AggNamespace)(name::Symbol, args...; over=FromNothing, distinct::Bool=false) =
    SQLNode(SQLCore(AggCall{Symbol(uppercase(String(name)))}, distinct), SQLNode[over, args...])

(agg::AggNamespace)(name::AbstractString, args...; over=FromNothing, distinct::Bool=false) =
    SQLNode(SQLCore(AggCall{Symbol(name)}, distinct), SQLNode[over, args...])

Base.getproperty(agg::AggNamespace, name::Symbol) =
    AggClosure(Symbol(uppercase(String(name))))

Base.getproperty(agg::AggNamespace, name::AbstractString) =
    AggClosure(Symbol(name))

(agg::AggClosure)(args...; over=FromNothing, distinct::Bool=false) =
    SQLNode(SQLCore(AggCall{agg.name}, distinct), SQLNode[over, args...])

const Count = Agg.COUNT

const Max = Agg.MAX

# Placeholder

Placeholder(pos) =
    SQLNode(SQLCore(Placeholder, pos))

# From Clause

FromClause() =
    SQLNodeClosure(SQLCore(FromClause))

# Select Clause

SelectClause(list::Vector{SQLNode}; distinct::Bool=false) =
    SQLNodeClosure(SQLCore(SelectClause, distinct), list)

SelectClause(list::AbstractVector; distinct::Bool=false) =
    SQLNodeClosure(SQLCore(SelectClause, distinct), SQLNode[list...])

SelectClause(list...; distinct::Bool=false) =
    SQLNodeClosure(SQLCore(SelectClause, distinct), SQLNode[list...])

# Where and Having Clauses

WhereClause(pred) =
    SQLNodeClosure(SQLCore(WhereClause), SQLNode[pred])

HavingClause(pred) =
    SQLNodeClosure(SQLCore(HavingClause), SQLNode[pred])

# Join Clause

JoinClause(right, on; is_left::Bool=false, is_right::Bool=false) =
    SQLNodeClosure(SQLCore(JoinClause, is_left, is_right), SQLNode[right, on])

# Group Clause

GroupClause(list::Vector{SQLNode}) =
    SQLNodeClosure(SQLCore(GroupClause), list)

GroupClause(list::AbstractVector) =
    SQLNodeClosure(SQLCore(GroupClause), SQLNode[list...])

GroupClause(list...) =
    SQLNodeClosure(SQLCore(GroupClause), SQLNode[list...])

# Window Clause

WindowClause(list::AbstractVector; order::AbstractVector=EMPTY_SQLNODE_VECTOR) =
    SQLNodeClosure(SQLCore(WindowClause, length(order)), SQLNode[list..., order...])

WindowClause(list...; order::AbstractVector=EMPTY_SQLNODE_VECTOR) =
    SQLNodeClosure(SQLCore(WindowClause, length(order)), SQLNode[list..., order...])

# Union Clause

UnionClause(list::Vector{SQLNode}; all::Bool=true) =
    SQLNodeClosure(SQLCore(UnionClause, all), list)

UnionClause(list::AbstractVector; all::Bool=true) =
    SQLNodeClosure(SQLCore(UnionClause, all), SQLNode[list...])

UnionClause(list...; all::Bool=true) =
    SQLNodeClosure(SQLCore(UnionClause, all), SQLNode[list...])

# Aliases

alias(n::SQLNode) =
    alias(n.core, n)::Union{Symbol,Nothing}

alias(core::SQLCore, n) =
    nothing

alias(core::As, n) =
    core.name

alias(core::Literal{T}, n) where {T} =
    nameof(T)

alias(core::Lookup, n) =
    core.name

alias(core::GetCall, n) =
    core.name

alias(core::FunCall{name}, n) where {name} =
    name

alias(core::AggCall{name}, n) where {name} =
    name

# Lookup

Base.getindex(n::SQLNode, name::Symbol) =
    lookup(n, name)

Base.getindex(n::SQLNode, name::AbstractString) =
    lookup(n, Symbol(name))

function lookup(n::SQLNode, name::Symbol)
    l = lookup(n, name, nothing)
    l !== nothing || error("cannot find $name")
    l
end

lookup(n::SQLNode, name::Symbol, default::T) where {T} =
    lookup(n.core, n, name, default)::Union{SQLNode,T}

lookup(::SQLCore, n, name, default) =
    default

lookup(::As, n, name, default) =
    lookup(n.args[1], name, default)

lookup(core::From, n, name, default) =
    name in core.tbl.cols ? n |> Lookup(name) : default

function lookup(::Select, n, name, default)
    list = @view n.args[2:end]
    for arg in list
        if alias(arg) === name
            return n |> Lookup(name)
        end
    end
    default
end

function lookup(::Where, n, name, default)
    base = n.args[1]
    base_alias = alias(base)
    base_alias === nothing ?
        lookup(base, name, default) :
    base_alias === name ?
        base.args[1] :
        default
end

function lookup(::Join, n, name, default)
    left = n.args[1]
    right = n.args[2]
    left_alias = alias(left)
    right_alias = alias(right)
    if name === left_alias
        return left.args[1]
    end
    if name === right_alias
        return right.args[1]
    end
    if left_alias === nothing
        l = lookup(left, name, nothing)
        if l !== nothing
            return l
        end
    end
    if right_alias === nothing
        l = lookup(right, name, nothing)
        if l !== nothing
            return l
        end
    end
    default
end

function lookup(::Group, n, name, default)
    base = n.args[1]
    base_alias = alias(base)
    if name === base_alias
        return base.args[1]
    end
    list = @view n.args[2:end]
    for arg in list
        if alias(arg) === name
            return n |> Lookup(name)
        end
    end
    if base_alias === nothing
        return lookup(base, name, default)
    end
    default
end

function lookup(::Window, n, name, default)
    base = n.args[1]
    base_alias = alias(base)
    base_alias === nothing ?
        lookup(base, name, default) :
    base_alias === name ?
        base.args[1] :
        default
end

function lookup(::Append, n, name, default)
    for arg in n.args
        if lookup(arg, name, nothing) === nothing
            return default
        end
    end
    return n |> Lookup(name)
end

function lookup_group(n::SQLNode)
    l = lookup_group(n, nothing)
    l !== nothing || error("cannot find a Group node")
    l
end

lookup_group(n::SQLNode, default::T) where {T} =
    lookup_group(n.core, n, default)::Union{SQLNode,T}

lookup_group(::SQLCore, n, default) =
    default

lookup_group(::Union{As,Select,Where}, n, default) =
    lookup_group(n.args[1], default)

function lookup_group(::Join, n, default)
    left = n.args[1]
    right = n.args[2]
    l = lookup_group(left, nothing)
    if l !== nothing
        return l
    end
    l = lookup_group(right, nothing)
    if l !== nothing
        return l
    end
    default
end

lookup_group(::Union{Group,Window}, n, default) =
    n

operation_name(core::FunCall{S}) where {S} =
    S

operation_name(core::AggCall{S}) where {S} =
    S

function collect_refs(n)
    refs = Set{SQLNode}()
    collect_refs!(n, refs)
    refs
end

function collect_refs!(n::SQLNode, refs)
    if n.core isa Lookup || n.core isa AggCall
        push!(refs, n)
    else
        collect_refs!(n.args, refs)
    end
end

function collect_refs!(ns::AbstractVector{SQLNode}, refs)
    for n in ns
        collect_refs!(n, refs)
    end
end

function replace_refs(n::SQLNode, repl)
    if n.core isa Lookup || n.core isa AggCall
        return get(repl, n, n)
    end
    args′ = replace_refs(n.args, repl)
    args′ != n.args ? SQLNode(n.core, args′) : n
end

replace_refs(ns::AbstractVector{SQLNode}, repl) =
    SQLNode[replace_refs(n, repl) for n in ns]

default_list(n::SQLNode) =
    default_list(n.core, n)::Vector{SQLNode}

default_list(@nospecialize(::SQLCore), n) =
    SQLNode[]

default_list(core::From, n) =
    SQLNode[n |> Lookup(name) for name in core.tbl.cols]

default_list(::Select, n) =
    SQLNode[n |> Lookup(alias(l)) for l in @view n.args[2:end]]

function default_list(::Union{Where,Window}, n)
    base, pred = n.args
    default_list(base)
end

function default_list(::Join, n)
    #=
    left, right = n.args
    SQLNode[default_list(left)..., default_list(right)...]
    =#
    left, right = n.args
    left_name = alias(left)
    right_name = alias(right)
    list = SQLNode[]
    if left_name === nothing
        append!(list, default_list(left))
    end
    if right_name === nothing
        append!(list, default_list(right))
    end
    list
end

default_list(::Group, n) =
    SQLNode[n |> Lookup(alias(l)) for l in @view n.args[2:end]]

function default_list(::Append, n)
    list = default_list(n.args[1])
    for arg in @view n.args[2:end]
        arg_list = default_list(arg)
        seen = Set{Symbol}([alias(l) for l in arg_list])
        list = SQLNode[l for l in list if alias(l) in seen]
    end
    SQLNode[n |> Lookup(alias(l)) for l in list]
end

resolve(ns::AbstractVector{SQLNode}, bases::AbstractVector{SQLNode}) =
    SQLNode[resolve(n, bases) for n in ns]

function resolve(n::SQLNode, bases::AbstractVector{SQLNode})
    core = n.core
    if core isa GetCall
        if isempty(n.args)
            for base in bases
                base_alias = alias(base)
                if base_alias !== nothing
                    if base_alias === core.name
                        return base.args[1]
                    end
                else
                    n′ = lookup(base, core.name, nothing)
                    if n′ !== nothing
                        return n′
                    end
                end
            end
            error("cannot resolve $(core.name)")
        else
            parent, = n.args
            parent′ = resolve(parent, bases)
            return lookup(parent′, core.name)
        end
    elseif core isa AggCall
        over = n.args[1]
        if over.core isa Unit
            for base in bases
                over′ = lookup_group(base, nothing)
                if over′ !== nothing
                    over = over′
                    break
                end
            end
        else
            over′ = resolve(over, bases)
        end
        args′ = copy(n.args)
        args′[1] = over′
        return SQLNode(core, args′)
    else
        args′ = resolve(n.args, bases)
        args′ != n.args ? SQLNode(core, args′) : n
    end
end

function normalize(n::SQLNode)
    n′, repl = normalize(n, default_list(n), :_)
    n′
end

normalize(n::SQLNode, refs, as) =
    normalize(n.core, n, refs, as)

normalize(::As, n, refs, as) =
    normalize(n.args[1], refs, as)

function normalize(core::Select, n, refs, as)
    base = n.args[1]
    list = resolve(@view(n.args[2:end]), [base])
    base_refs = collect_refs(list)
    base_as = gensym()
    base′, base_repl = normalize(base, base_refs, base_as)
    list′ = SQLNode[]
    seen = Set{Symbol}()
    for l in list
        name = alias(l)
        if name in seen
            name = gensym(name)
        end
        push!(seen, name)
        l = (l.core isa As ? l.args[1] : l) |> As(name)
        push!(list′, l)
    end
    list′ = replace_refs(list′, base_repl)
    n′ = base′ |>
         As(base_as) |>
         FromClause() |>
         SelectClause(list′)
    repl = Dict{SQLNode,SQLNode}()
    for ref in refs
        ref_core = ref.core
        if ref_core isa Lookup && ref.args[1] === n
            repl[ref] = Literal((as, ref_core.name))
        end
    end
    n′, repl
end

function normalize(::Where, n, refs, as)
    base, pred = n.args
    pred = resolve(pred, [base])
    base_refs = collect_refs(pred)
    for ref in refs
        push!(base_refs, ref)
    end
    base_as = gensym()
    base′, base_repl = normalize(base, base_refs, base_as)
    pred′ = replace_refs(pred, base_repl)
    n′ = base′ |>
         As(base_as) |>
         FromClause() |>
         WhereClause(pred′) |>
         SelectClause()
    repl = Dict{SQLNode,SQLNode}()
    pos = 0
    for ref in refs
        if ref in keys(base_repl)
            pos += 1
            name = Symbol(alias(ref), "_", pos)
            repl[ref] = Literal((as, name))
            push!(n′.args, base_repl[ref] |> As(name))
        end
    end
    n′, repl
end

function normalize(core::Join, n, refs, as)
    left, right, on = n.args
    on = resolve(on, [left, right])
    all_refs = collect_refs(on)
    for ref in refs
        push!(all_refs, ref)
    end
    left_as = gensym()
    left′, left_repl = normalize(left, all_refs, left_as)
    right_as = gensym()
    right′, right_repl = normalize(right, all_refs, right_as)
    all_repl = merge(left_repl, right_repl)
    on′ = replace_refs(on, all_repl)
    n′ = left′ |>
         As(left_as) |>
         FromClause() |>
         JoinClause(right′ |> As(right_as), on′, is_left=core.is_left, is_right=core.is_right) |>
         SelectClause()
    repl = Dict{SQLNode,SQLNode}()
    pos = 0
    for ref in refs
        if ref in keys(all_repl)
            pos += 1
            name = Symbol(alias(ref), "_", pos)
            repl[ref] = Literal((as, name))
            push!(n′.args, all_repl[ref] |> As(name))
        end
    end
    n′, repl
end

function normalize(core::From, n, refs, as)
    s = Literal((core.tbl.scm, core.tbl.name)) |>
        FromClause() |>
        SelectClause()
    repl = Dict{SQLNode,SQLNode}()
    seen = Set{Symbol}()
    for ref in refs
        ref_core = ref.core
        if ref_core isa Lookup && ref.args[1] === n
            name = ref_core.name
            repl[ref] = Literal((as, name))
            if !(name in seen)
                push!(s.args, Literal(name))
                push!(seen, name)
            end
        end
    end
    s, repl
end

function normalize(core::Group, n, refs, as)
    base = n.args[1]
    list = resolve(@view(n.args[2:end]), [base])
    base_refs = collect_refs(list)
    refs_args = Vector{SQLNode}[]
    for ref in refs
        ref_core = ref.core
        if ref_core isa AggCall && ref.args[1] === n
            ref_args = resolve(@view(ref.args[2:end]), [base])
            push!(refs_args, ref_args)
            collect_refs!(ref_args, base_refs)
        end
    end
    base_as = gensym()
    base′, base_repl = normalize(base, base_refs, base_as)
    list′ = SQLNode[l.core isa As ? l : l |> As(alias(l)) for l in list]
    list′ = replace_refs(list′, base_repl)
    n′ = base′ |>
         As(base_as) |>
         FromClause() |>
         GroupClause(SQLNode[Literal(k) for k = 1:length(list)]) |>
         SelectClause(list′)
    repl = Dict{SQLNode,SQLNode}()
    pos = 0
    for ref in refs
        ref_core = ref.core
        if ref_core isa Lookup && ref.args[1] === n
            pos += 1
            repl[ref] = Literal((as, ref_core.name))
        elseif ref_core isa AggCall && ref.args[1] === n
            pos += 1
            name = Symbol(alias(ref), "_", pos)
            repl[ref] = Literal((as, name))
            push!(n′.args, SQLNode(ref_core, SQLNode[FromNothing, replace_refs(popfirst!(refs_args), base_repl)...]) |> As(name))
        end
    end
    n′, repl
end

function normalize(core::Window, n, refs, as)
    base = n.args[1]
    list = resolve(@view(n.args[2:end]), [base])
    base_refs = collect_refs(list)
    refs_args = Vector{SQLNode}[]
    for ref in refs
        ref_core = ref.core
        if ref_core isa AggCall && ref.args[1] === n
            ref_args = resolve(@view(ref.args[2:end]), [base])
            push!(refs_args, ref_args)
            collect_refs!(ref_args, base_refs)
        else
            push!(base_refs, ref)
        end
    end
    base_as = gensym()
    base′, base_repl = normalize(base, base_refs, base_as)
    list′ = replace_refs(list, base_repl)
    win_as = gensym()
    n′ = base′ |>
         As(base_as) |>
         FromClause() |>
         WindowClause(list′[1:end-core.order_length], order=list′[end-core.order_length+1:end]) |>
         As(win_as) |>
         SelectClause()
    repl = Dict{SQLNode,SQLNode}()
    pos = 0
    for ref in refs
        ref_core = ref.core
        if ref_core isa AggCall && ref.args[1] === n
            pos += 1
            name = Symbol(alias(ref), "_", pos)
            repl[ref] = Literal((as, name))
            push!(n′.args, SQLNode(ref_core, SQLNode[Literal(win_as), replace_refs(popfirst!(refs_args), base_repl)...]) |> As(name))
        else
            pos += 1
            name = Symbol(alias(ref), "_", pos)
            repl[ref] = Literal((as, name))
            push!(n′.args, base_repl[ref] |> As(name))
        end
    end
    n′, repl
end

function normalize(::Append, n, refs, as)
    bases′ = SQLNode[]
    for arg in n.args
        arg_refs = SQLNode[]
        seen = Set{Symbol}()
        for ref in refs
            ref_core = ref.core
            if ref_core isa Lookup && ref.args[1] === n
                !(ref_core.name in seen) || continue
                push!(seen, ref_core.name)
                arg_ref = lookup(arg, ref_core.name)::SQLNode
                push!(arg_refs, arg_ref)
            end
        end
        arg_as = gensym()
        arg′, arg_repl = normalize(arg, arg_refs, arg_as)
        base′ = arg′ |>
                As(arg_as) |>
                FromClause() |>
                SelectClause(SQLNode[arg_repl[arg_ref] |> As(arg_ref.core.name) for arg_ref in arg_refs])
        push!(bases′, base′)
    end
    n′ = bases′[1] |> UnionClause(@view bases′[2:end])
    repl = Dict{SQLNode,SQLNode}()
    for ref in refs
        ref_core = ref.core
        seen = Set{Symbol}()
        if ref_core isa Lookup && ref.args[1] === n
                !(ref_core.name in seen) || continue
                push!(seen, ref_core.name)
            repl[ref] = Literal((as, ref_core.name))
        end
    end
    n′, repl
end

Base.@kwdef mutable struct ToSQLContext <: IO
    io::IOBuffer = IOBuffer()
    level::Int = 0              # indentation level
    nested::Bool = false        # SELECT needs parenthesis
end

Base.write(ctx::ToSQLContext, octet::UInt8) =
    write(ctx.io, octet)

Base.unsafe_write(ctx::ToSQLContext, input::Ptr{UInt8}, nbytes::UInt) =
    unsafe_write(ctx.io, input, nbytes)

function newline(ctx::ToSQLContext)
    print(ctx, "\n")
    for k = 1:ctx.level
        print(ctx, "  ")
    end
end

function to_sql(n::SQLNode)
    ctx = ToSQLContext()
    to_sql!(ctx, n)
    String(take!(ctx.io))
end

to_sql!(ctx, n::SQLNode) =
    to_sql!(ctx, n.core, n)

function to_sql!(ctx, ns::AbstractVector{SQLNode}, sep=", ", left="(", right=")")
    print(ctx, left)
    first = true
    for n in ns
        if !first
            print(ctx, sep)
        else
            first = false
        end
        to_sql!(ctx, n)
    end
    print(ctx, right)
end

to_sql!(ctx, core::Literal, n) =
    to_sql!(ctx, core.val)

function to_sql!(ctx, @nospecialize(core::AggCall{S}), n) where {S}
    over = n.args[1]
    print(ctx, S)
    args = @view n.args[2:end]
    if isempty(args) && S === :COUNT
        args = SQLNode[true]
    end
    to_sql!(ctx, args, ", ", (core.distinct ? "(DISTINCT " : "("))
    if !(over.core isa Unit)
        print(ctx, " OVER ")
        to_sql!(ctx, over)
    end
end

function to_sql!(ctx, @nospecialize(core::FunCall{S}), n) where {S}
    print(ctx, S)
    to_sql!(ctx, n.args)
end

function to_sql!(ctx, core::FunCall{:(=)}, n)
    to_sql!(ctx, n.args, " = ")
end

function to_sql!(ctx, core::FunCall{:(>)}, n)
    to_sql!(ctx, n.args, " > ")
end

function to_sql!(ctx, core::FunCall{:(>=)}, n)
    to_sql!(ctx, n.args, " >= ")
end

function to_sql!(ctx, core::FunCall{:(<)}, n)
    to_sql!(ctx, n.args, " < ")
end

function to_sql!(ctx, core::FunCall{:(<=)}, n)
    to_sql!(ctx, n.args, " <= ")
end

function to_sql!(ctx, core::FunCall{:(+)}, n)
    to_sql!(ctx, n.args, " + ")
end

function to_sql!(ctx, core::FunCall{:(-)}, n)
    to_sql!(ctx, n.args, " - ")
end

function to_sql!(ctx, core::Union{FunCall{:AND}}, n)
    if isempty(n.args)
        print(ctx, "TRUE")
    else
        to_sql!(ctx, n.args, " AND ")
    end
end

function to_sql!(ctx, core::Union{FunCall{:OR}}, n)
    if isempty(n.args)
        print(ctx, "FALSE")
    else
        to_sql!(ctx, n.args, " OR ")
    end
end

function to_sql!(ctx, core::Union{FunCall{:ISNULL},FunCall{:IS_NULL},FunCall{Symbol("IS NULL")}}, n)
    arg, = n.args
    print(ctx, "(")
    to_sql!(ctx, arg)
    print(ctx, " IS NULL)")
end

function to_sql!(ctx, core::Placeholder, n)
    print(ctx, '$')
    to_sql!(ctx, core.pos)
end

function to_sql!(ctx, core::As, n)
    arg, = n.args
    if arg.core isa WindowClause
        to_sql!(ctx, arg.core, arg, core.name)
    else
        to_sql!(ctx, arg)
        print(ctx, " AS ")
        to_sql!(ctx, core.name)
    end
end

function to_sql!(ctx, core::FromClause, n)
    base, = n.args
    newline(ctx)
    print(ctx, "FROM ")
    to_sql!(ctx, base)
end

function to_sql!(ctx, core::SelectClause, n)
    base = n.args[1]
    list = @view n.args[2:end]
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, "(")
        newline(ctx)
    end
    ctx.nested = true
    print(ctx, "SELECT ")
    if core.distinct
        print(ctx, "DISTINCT ")
    end
    to_sql!(ctx, list, ", ", "", "")
    to_sql!(ctx, base)
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ")")
    end
end

function to_sql!(ctx, core::UnionClause, n)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, "(")
        newline(ctx)
    end
    ctx.nested = false
    first = true
    for arg in n.args
        if !first
            newline(ctx)
            print(ctx, core.all ? "UNION ALL" : "UNION")
            newline(ctx)
        else
            first = false
        end
        to_sql!(ctx, arg)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ")")
    end
end

function to_sql!(ctx, core::WhereClause, n)
    base, pred = n.args
    to_sql!(ctx, base)
    newline(ctx)
    print(ctx, "WHERE ")
    to_sql!(ctx, pred)
end

function to_sql!(ctx, core::HavingClause, n)
    base, pred = n.args
    to_sql!(ctx, base)
    newline(ctx)
    print(ctx, "HAVING ")
    to_sql!(ctx, pred)
end

function to_sql!(ctx, core::JoinClause, n)
    left, right, on = n.args
    to_sql!(ctx, left)
    newline(ctx)
    if core.is_left && core.is_right
        print(ctx, "FULL JOIN ")
    elseif core.is_left
        print(ctx, "LEFT JOIN ")
    elseif core.is_right
        print(ctx, "RIGHT JOIN ")
    else
        print(ctx, "JOIN ")
    end
    to_sql!(ctx, right)
    print(ctx, " ON ")
    to_sql!(ctx, on)
end

function to_sql!(ctx, core::GroupClause, n)
    base = n.args[1]
    list = @view n.args[2:end]
    to_sql!(ctx, base)
    newline(ctx)
    print(ctx, "GROUP BY ")
    if isempty(list)
        print(ctx, "()")
    else
        to_sql!(ctx, list, ", ", "", "")
    end
end

function to_sql!(ctx, core::WindowClause, n, name)
    base = n.args[1]
    list = @view n.args[2:end]
    partition = list[1:end-core.order_length]
    order = list[end-core.order_length+1:end]
    to_sql!(ctx, base)
    newline(ctx)
    print(ctx, "WINDOW ")
    to_sql!(ctx, name)
    print(ctx, " AS (")
    first = true
    if !isempty(partition)
        first = false
        print(ctx, "PARTITION BY ")
        to_sql!(ctx, partition, ", ", "", "")
    end
    if !isempty(order)
        if !first
            print(ctx, " ")
        else
            first = false
        end
        print(ctx, "ORDER BY ")
        to_sql!(ctx, order, ", ", "", "")
    end
    print(ctx, ")")
end

function to_sql!(ctx, ::Missing)
    print(ctx, "NULL")
end

function to_sql!(ctx, b::Bool)
    print(ctx, b ? "TRUE" : "FALSE")
end

function to_sql!(ctx, n::Number)
    print(ctx, n)
end

function to_sql!(ctx, s::AbstractString)
    print(ctx, '\'', replace(s, '\'' => "''"), '\'')
end

function to_sql!(ctx, d::Dates.Day)
    to_sql!(ctx, string(d))
    print(ctx, "::INTERVAL")
end

function to_sql!(ctx, n::Symbol)
    print(ctx, '"', replace(string(n), '"' => "\"\""), '"')
end

function to_sql!(ctx, qn::Tuple{Symbol,Symbol})
    to_sql!(ctx, qn[1])
    print(ctx, '.')
    to_sql!(ctx, qn[2])
end

end
