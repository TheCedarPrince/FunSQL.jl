# Rewriting the node graph to prepare it for translation.


# Auxiliary nodes.

# Get(over = Get(:a), name = :b) => NameBound(over = Get(:b), name = :a)
mutable struct NameBoundNode <: AbstractSQLNode
    over::SQLNode
    name::Symbol

    NameBoundNode(; over, name) =
        new(over, name)
end

NameBound(args...; kws...) =
    NameBoundNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(NameBound), pats::Vector{Any}) =
    dissect(scr, NameBoundNode, pats)

PrettyPrinting.quoteof(n::NameBoundNode, ctx::QuoteContext) =
    Expr(:call, nameof(NameBound), Expr(:kw, :over, quoteof(n.over, ctx)), Expr(:kw, :name, QuoteNode(n.name)))

# Get(over = q, name = :b) => HandleBound(over = Get(:b), handle = get_handle(q))
mutable struct HandleBoundNode <: AbstractSQLNode
    over::SQLNode
    handle::Int

    HandleBoundNode(; over, handle) =
        new(over, handle)
end

HandleBound(args...; kws...) =
    HandleBoundNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(HandleBound), pats::Vector{Any}) =
    dissect(scr, HandleBoundNode, pats)

PrettyPrinting.quoteof(n::HandleBoundNode, ctx::QuoteContext) =
    Expr(:call, nameof(NameBound), Expr(:kw, :over, quoteof(n.over, ctx)), Expr(:kw, :handle, n.handle))

mutable struct ExtendedBindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}
    owned::Bool     # Did we find the outer query for this node?

    function ExtendedBindNode(; over = nothing, list, label_map = nothing, owned = false)
        if label_map !== nothing
            return new(over, list, label_map, owned)
        end
        n = new(over, list, OrderedDict{Symbol, Int}())
        for (i, l) in enumerate(n.list)
            n.label_map[label(l)] = i
        end
        n
    end
end

ExtendedBind(args...; kws...) =
    ExtendedBindNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::ExtendedBindNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(ExtendedBind))
    if isempty(n.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.list, ctx))
    end
    push!(ex.args, Expr(:kw, :owned, n.owned))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

rebase(n::ExtendedBindNode, n′) =
    ExtendedBindNode(over = rebase(n.over, n′),
                     list = n.list, label_map = n.label_map, owned = n.owned)

mutable struct ExtendedJoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    left::Bool
    right::Bool
    type::BoxType               # Type of the product of `over` and `joinee`.
    lateral::Vector{SQLNode}    # References from `joinee` to `over` for JOIN LATERAL.

    ExtendedJoinNode(; over, joinee, on, left, right, type = EMPTY_BOX, lateral = SQLNode[]) =
        new(over, joinee, on, left, right, type, lateral)
end

ExtendedJoinNode(joinee, on; over = nothing, left = false, right = false, type = EMPTY_BOX, lateral = SQLNode[]) =
    ExtendedJoinNode(over = over, joinee = joinee, on = on, left = left, right = right, type = type, lateral = lateral)

ExtendedJoin(args...; kws...) =
    ExtendedJoinNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::ExtendedJoinNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(ExtendedJoin))
    if !ctx.limit
        push!(ex.args, quoteof(n.joinee, ctx))
        push!(ex.args, quoteof(n.on, ctx))
        if n.left
            push!(ex.args, Expr(:kw, :left, n.left))
        end
        if n.right
            push!(ex.args, Expr(:kw, :right, n.right))
        end
        if n.type !== EMPTY_BOX
            push!(ex.args, Expr(:kw, :type, n.type))
        end
        if !isempty(n.lateral)
            push!(ex.args, Expr(:kw, :lateral, Expr(:vect, quoteof(n.lateral, ctx)...)))
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

rebase(n::ExtendedJoinNode, n′) =
    ExtendedJoinNode(over = rebase(n.over, n′),
                     joinee = n.joinee, on = n.on, left = n.left, right = n.right, type = n.type, lateral = n.lateral)

label(n::Union{NameBoundNode, HandleBoundNode, ExtendedBindNode, ExtendedJoinNode}) =
    label(n.over)

# A SQL subquery with an undetermined SELECT list.
mutable struct BoxNode <: TabularNode
    over::Union{SQLNode, Nothing}
    type::BoxType
    handle::Int
    refs::Vector{SQLNode}

    BoxNode(; over = nothing, type = EMPTY_BOX, handle = 0, refs = SQLNode[]) =
        new(over, type, handle, refs)
end

Box(args...; kws...) =
    BoxNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Box), pats::Vector{Any}) =
    dissect(scr, BoxNode, pats)

function PrettyPrinting.quoteof(n::BoxNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Box))
    if !ctx.limit
        if n.type !== EMPTY_BOX
            push!(ex.args, Expr(:kw, :type, quoteof(n.type)))
        end
        if n.handle != 0
            push!(ex.args, Expr(:kw, :handle, n.handle))
        end
        if !isempty(n.refs)
            push!(ex.args, Expr(:kw, :refs, Expr(:vect, quoteof(n.refs, ctx)...)))
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::BoxNode) =
    n.type.name

rebase(n::BoxNode, n′) =
    BoxNode(over = rebase(n.over, n′),
            type = n.type, handle = n.handle, refs = n.refs)

box_type(n::BoxNode) =
    n.type

box_type(n::SQLNode) =
    box_type(n[]::BoxNode)


# Annotation context.

# Maps a node in the annotated graph to a path in the original graph (for error reporting).
struct PathMap
    paths::Vector{Tuple{SQLNode, Int}}
    origins::IdDict{Any, Int}

    PathMap() =
        new(Tuple{SQLNode, Int}[], IdDict{Any, Int}())
end

function get_path(map::PathMap, idx::Int)
    path = SQLNode[]
    while idx != 0
        n, idx = map.paths[idx]
        push!(path, n)
    end
    path
end

get_path(map::PathMap, n) =
    get_path(map, get(map.origins, n, 0))

struct AnnotateContext
    path_map::PathMap
    current_path::Vector{Int}
    handles::Dict{SQLNode, Int}
    boxes::Vector{BoxNode}

    AnnotateContext() =
        new(PathMap(), Int[0], Dict{SQLNode, Int}(), BoxNode[])
end

function grow_path!(ctx::AnnotateContext, n::SQLNode)
    push!(ctx.path_map.paths, (n, ctx.current_path[end]))
    push!(ctx.current_path, length(ctx.path_map.paths))
end

function shrink_path!(ctx::AnnotateContext)
    pop!(ctx.current_path)
end

function mark_origin!(ctx::AnnotateContext, n::SQLNode)
    ctx.path_map.origins[n] = ctx.current_path[end]
end

mark_origin!(ctx::AnnotateContext, n::AbstractSQLNode) =
    mark_origin!(ctx, convert(SQLNode, n))

get_path(ctx::AnnotateContext) =
    get_path(ctx.path_map, ctx.current_path[end])

get_path(ctx::AnnotateContext, n::SQLNode) =
    get_path(ctx.path_map, n)

function make_handle!(ctx::AnnotateContext, n::SQLNode)
    get!(ctx.handles, n) do
        length(ctx.handles) + 1
    end
end

function get_handle(ctx::AnnotateContext, n::SQLNode)
    handle = 0
    idx = get(ctx.path_map.origins, n, 0)
    if idx > 0
        n = ctx.path_map.paths[idx][1]
        handle = get(ctx.handles, n, 0)
    end
    handle
end

get_handle(ctx::AnnotateContext, ::Nothing) =
    0


# Rewriting of the node graph.

function annotate(n::SQLNode, ctx)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate(n[], ctx))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

function annotate_scalar(n::SQLNode, ctx)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate_scalar(n[], ctx))
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

annotate(ns::Vector{SQLNode}, ctx) =
    SQLNode[annotate(n, ctx) for n in ns]

annotate_scalar(ns::Vector{SQLNode}, ctx) =
    SQLNode[annotate_scalar(n, ctx) for n in ns]

function annotate(::Nothing, ctx)
    box = BoxNode()
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    n′
end

annotate_scalar(::Nothing, ctx) =
    nothing

annotate(n::AbstractSQLNode, ctx) =
    throw(IllFormedError(path = get_path(ctx)))

function annotate_scalar(n::TabularNode, ctx)
    n′ = convert(SQLNode, annotate(n, ctx))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    n′
end

function rebind(node, base, ctx)
    while @dissect node over |> Get(name = name)
        mark_origin!(ctx, base)
        base = NameBound(over = base, name = name)
        node = over
    end
    if node !== nothing
        handle = make_handle!(ctx, node)
        mark_origin!(ctx, base)
        base = HandleBound(over = base, handle = handle)
    end
    base
end

function annotate_scalar(n::AggregateNode, ctx)
    args′ = annotate_scalar(n.args, ctx)
    filter′ = annotate_scalar(n.filter, ctx)
    n′ = Agg(name = n.name, distinct = n.distinct, args = args′, filter = filter′)
    rebind(n.over, n′, ctx)
end

function annotate(n::AppendNode, ctx)
    over′ = annotate(n.over, ctx)
    list′ = annotate(n.list, ctx)
    Append(over = over′, list = list′)
end

function annotate(n::AsNode, ctx)
    over′ = annotate(n.over, ctx)
    As(over = over′, name = n.name)
end

function annotate_scalar(n::AsNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    As(over = over′, name = n.name)
end

function annotate(n::BindNode, ctx)
    over′ = annotate(n.over, ctx)
    list′ = annotate_scalar(n.list, ctx)
    ExtendedBind(over = over′, list = list′, label_map = n.label_map)
end

annotate_scalar(n::BindNode, ctx) =
    annotate(n, ctx)

function annotate(n::DefineNode, ctx)
    over′ = annotate(n.over, ctx)
    list′ = annotate_scalar(n.list, ctx)
    Define(over = over′, list = list′, label_map = n.label_map)
end

annotate(n::FromNode, ctx) =
    n

function annotate_scalar(n::FunctionNode, ctx)
    args′ = annotate_scalar(n.args, ctx)
    Fun(name = n.name, args = args′)
end

function annotate_scalar(n::GetNode, ctx)
    rebind(n.over, Get(name = n.name), ctx)
end

function annotate(n::GroupNode, ctx)
    over′ = annotate(n.over, ctx)
    by′ = annotate_scalar(n.by, ctx)
    Group(over = over′, by = by′, label_map = n.label_map)
end

function annotate(n::HighlightNode, ctx)
    over′ = annotate(n.over, ctx)
    Highlight(over = over′, color = n.color)
end

function annotate_scalar(n::HighlightNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    Highlight(over = over′, color = n.color)
end

function annotate(n::JoinNode, ctx)
    over′ = annotate(n.over, ctx)
    joinee′ = annotate(n.joinee, ctx)
    on′ = annotate_scalar(n.on, ctx)
    ExtendedJoin(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right)
end

function annotate(n::LimitNode, ctx)
    over′ = annotate(n.over, ctx)
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

annotate_scalar(n::LiteralNode, ctx) =
    n

function annotate(n::OrderNode, ctx)
    over′ = annotate(n.over, ctx)
    by′ = annotate_scalar(n.by, ctx)
    Order(over = over′, by = by′)
end

function annotate(n::PartitionNode, ctx)
    over′ = annotate(n.over, ctx)
    by′ = annotate_scalar(n.by, ctx)
    order_by′ = annotate_scalar(n.order_by, ctx)
    Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame)
end

function annotate(n::SelectNode, ctx)
    over′ = annotate(n.over, ctx)
    list′ = annotate_scalar(n.list, ctx)
    Select(over = over′, list = list′, label_map = n.label_map)
end

function annotate_scalar(n::SortNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    Sort(over = over′, value = n.value, nulls = n.nulls)
end

annotate_scalar(n::VariableNode, ctx) =
    n

function annotate(n::WhereNode, ctx)
    over′ = annotate(n.over, ctx)
    condition′ = annotate_scalar(n.condition, ctx)
    Where(over = over′, condition = condition′)
end


# Type resolution.

function resolve!(ctx::AnnotateContext)
    for box in ctx.boxes
        over = box.over
        if over !== nothing
            h = get_handle(ctx, over)
            t = resolve(over[])
            t = add_handle(t, h)
            box.handle = h
            box.type = t
        end
    end
end

function resolve(n::AppendNode)
    t = box_type(n.over)
    for m in n.list
        t = intersect(t, box_type(m))
    end
    t
end

function resolve(n::AsNode)
    t = box_type(n.over)
    fields = FieldTypeMap(n.name => t.row)
    row = RowType(fields)
    BoxType(n.name, row, t.handle_map)
end

function resolve(n::DefineNode)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for (f, ft) in t.row.fields
        if f in keys(n.label_map)
            ft = ScalarType()
        end
        fields[f] = ft
    end
    for f in keys(n.label_map)
        if !haskey(fields, f)
            fields[f] = ScalarType()
        end
    end
    row = RowType(fields, t.row.group)
    BoxType(t.name, row, t.handle_map)
end

resolve(n::Union{ExtendedBindNode, HighlightNode, LimitNode, OrderNode, WhereNode}) =
    box_type(n.over)

function resolve(n::ExtendedJoinNode)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    t = union(lt, rt)
    n.type = t
    t
end

function resolve(n::FromNode)
    fields = FieldTypeMap()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(n.table.name, row)
end

function resolve(n::GroupNode)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields, t.row)
    BoxType(t.name, row)
end

function resolve(n::PartitionNode)
    t = box_type(n.over)
    row = RowType(t.row.fields, t.row)
    BoxType(t.name, row, t.handle_map)
end

function resolve(n::SelectNode)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields)
    BoxType(t.name, row)
end


# Collecting references.

gather!(refs::Vector{SQLNode}, n::SQLNode) =
    gather!(refs, n[])

function gather!(refs::Vector{SQLNode}, ns::Vector{SQLNode})
    for n in ns
        gather!(refs, n)
    end
end

gather!(refs::Vector{SQLNode}, ::Union{AbstractSQLNode, Nothing}) =
    nothing

gather!(refs::Vector{SQLNode}, n::Union{AsNode, BoxNode, HighlightNode, SortNode}) =
    gather!(refs, n.over)

function gather!(refs::Vector{SQLNode}, n::ExtendedBindNode)
    gather!(refs, n.over)
    gather!(refs, n.list)
    n.owned = true
end

gather!(refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(refs, n.args)

function gather!(refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode, HandleBoundNode, NameBoundNode})
    push!(refs, n)
end


# Validating references.

function validate(t::BoxType, ref::SQLNode, ctx)
    if @dissect ref over |> HandleBound(handle = handle)
        if handle in keys(t.handle_map)
            ht = t.handle_map[handle]
            if ht isa AmbiguousType
                throw(ReferenceError(REFERENCE_ERROR_TYPE.AMBIGUOUS_HANDLE,
                                     path = get_path(ctx, ref)))
            end
            validate(ht, over, ctx)
        else
            throw(ReferenceError(REFERENCE_ERROR_TYPE.UNDEFINED_HANDLE,
                                 path = get_path(ctx, ref)))
        end
    else
        validate(t.row, ref, ctx)
    end
end

function validate(t::RowType, ref::SQLNode, ctx)
    while @dissect ref over |> NameBound(name = name)
        ft = get(t.fields, name, EmptyType())
        if !(ft isa RowType)
            type =
                ft isa EmptyType ? REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                ft isa ScalarType ? REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE :
                ft isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
        t = ft
        ref = over
    end
    if @dissect ref nothing |> Get(name = name)
        ft = get(t.fields, name, EmptyType())
        if !(ft isa ScalarType)
            type =
                ft isa EmptyType ? REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                ft isa RowType ? REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE :
                ft isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
    elseif @dissect ref nothing |> Agg(name = name)
        if !(t.group isa RowType)
            type =
                t.group isa EmptyType ? REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE :
                t.group isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_AGGREGATE : error()
            throw(ReferenceError(type, path = get_path(ctx, ref)))
        end
    else
        error()
    end
end

function gather_and_validate!(refs::Vector{SQLNode}, n, t::BoxType, ctx)
    start = length(refs) + 1
    gather!(refs, n)
    for k in start:length(refs)
        validate(t, refs[k], ctx)
    end
end

function route(lt::BoxType, rt::BoxType, ref::SQLNode)
    if @dissect ref over |> HandleBound(handle = handle)
        if get(lt.handle_map, handle, EmptyType()) isa EmptyType
            return 1
        else
            return -1
        end
    end
    return route(lt.row, rt.row, ref)
end

function route(lt::RowType, rt::RowType, ref::SQLNode)
    while @dissect ref over |> NameBound(name = name)
        lt′ = get(lt.fields, name, EmptyType())
        if lt′ isa EmptyType
            return 1
        end
        rt′ = get(rt.fields, name, EmptyType())
        if rt′ isa EmptyType
            return -1
        end
        @assert lt′ isa RowType && rt′ isa RowType
        lt = lt′
        rt = rt′
        ref = over
    end
    if @dissect ref Get(name = name)
        if name in keys(lt.fields)
            return -1
        else
            return 1
        end
    elseif @dissect ref over |> Agg(name = name)
        if lt.group isa RowType
            return -1
        else
            return 1
        end
    else
        error()
    end
end


# Linking references through box nodes.

function link!(ctx::AnnotateContext)
    root_box = ctx.boxes[end]
    for (f, ft) in root_box.type.row.fields
        if ft isa ScalarType
            push!(root_box.refs, Get(f))
        end
    end
    for box in reverse(ctx.boxes)
        box.over !== nothing || continue
        refs′ = SQLNode[]
        for ref in box.refs
            if (@dissect ref over |> HandleBound(handle = handle)) && handle == box.handle
                push!(refs′, over)
            else
                push!(refs′, ref)
            end
        end
        link!(box.over[], refs′, ctx)
    end
end

function link!(n::AppendNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    for l in n.list
        box = l[]::BoxNode
        append!(box.refs, refs)
    end
end

function link!(n::AsNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect ref over |> NameBound(name = name)
            @assert name == n.name
            push!(box.refs, over)
        elseif @dissect ref HandleBound()
            push!(box.refs, ref)
        else
            error()
        end
    end
end

function link!(n::DefineNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    seen = Set{Symbol}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            !(name in seen) || continue
            push!(seen, name)
            col = n.list[n.label_map[name]]
            gather_and_validate!(box.refs, col, box.type, ctx)
        else
            push!(box.refs, ref)
        end
    end
end

function link!(n::ExtendedBindNode, refs::Vector{SQLNode}, ctx)
    if !n.owned
        gather_and_validate!(SQLNode[], n.list, EMPTY_BOX, ctx)
    end
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(n::ExtendedJoinNode, refs::Vector{SQLNode}, ctx)
    lbox = n.over[]::BoxNode
    rbox = n.joinee[]::BoxNode
    gather_and_validate!(n.lateral, n.joinee, lbox.type, ctx)
    append!(lbox.refs, n.lateral)
    refs′ = SQLNode[]
    gather_and_validate!(refs′, n.on, n.type, ctx)
    append!(refs′, refs)
    for ref in refs′
        turn = route(lbox.type, rbox.type, ref)
        if turn < 0
            push!(lbox.refs, ref)
        else
            push!(rbox.refs, ref)
        end
    end
end

link!(::FromNode, ::Vector{SQLNode}, ctx) =
    nothing

function link!(n::GroupNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.by, box.type, ctx)
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, box.type, ctx)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, box.type, ctx)
            end
        end
    end
end

function link!(n::Union{HighlightNode, LimitNode}, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(n::OrderNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.by, box.type, ctx)
end

function link!(n::PartitionNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, box.type, ctx)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, box.type, ctx)
            end
        else
            push!(box.refs, ref)
        end
    end
    gather_and_validate!(box.refs, n.by, box.type, ctx)
    gather_and_validate!(box.refs, n.order_by, box.type, ctx)
end

function link!(n::SelectNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.list, box.type, ctx)
end

function link!(n::WhereNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.condition, box.type, ctx)
end

