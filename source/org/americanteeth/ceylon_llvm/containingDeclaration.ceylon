import org.eclipse.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    PackageModel=Package,
    FunctionOrValueModel=FunctionOrValue,
    TypeDeclarationModel=TypeDeclaration,
    ConstructorModel=Constructor,
    SpecificationModel=Specification,
    ScopeModel=Scope
}

alias AllocatingScope
    => TypeDeclarationModel|FunctionOrValueModel|PackageModel;

DeclarationModel|ScopeModel? deriveContainer(DeclarationModel|ScopeModel d)
    => if (is SpecificationModel c = d.container)
       then (c.declaration else c)
       else d.container;

AllocatingScope? nearestAllocatingScope(DeclarationModel|ScopeModel? s)
    => if (is AllocatingScope? s)
       then s
       else nearestAllocatingScope(deriveContainer(s));

DeclarationModel? containingDeclaration(DeclarationModel d) {
    value ret = nearestAllocatingScope(deriveContainer(d));

    if (! is DeclarationModel ret) {
        return null;
    }

    if (is FunctionOrValueModel d,
            d.type.declaration is ConstructorModel) {
        return containingDeclaration(ret);
    }

    if (is ValueModel ret, !ret.transient) {
        return containingDeclaration(ret);
    }

    return ret;
}
