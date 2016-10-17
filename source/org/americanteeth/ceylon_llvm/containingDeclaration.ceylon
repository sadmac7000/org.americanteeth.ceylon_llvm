import com.redhat.ceylon.model.typechecker.model {
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

AllocatingScope? nearestAllocatingScope(DeclarationModel|ScopeModel? s)
    => if (is AllocatingScope? s)
       then s
       else nearestAllocatingScope(s.container);

DeclarationModel? containingDeclaration(DeclarationModel d) {
    value s = if (is SpecificationModel c = d.container)
       then c.declaration
       else d.container;

    value ret = nearestAllocatingScope(s);

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

