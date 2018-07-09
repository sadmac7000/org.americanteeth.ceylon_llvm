import ceylon.collection {
    HashMap,
    HashSet,
    ArrayList
}

import org.eclipse.ceylon.model.typechecker.model {
    ClassModel=Class,
    FunctionModel=Function,
    FunctionOrValueModel=FunctionOrValue,
    ValueModel=Value,
    InterfaceModel=Interface,
    DeclarationModel=Declaration
}

import ceylon.interop.java {
    CeylonIterable
}

"Position of the interface resolver function in the vtable."
I64 interfaceResolverPosition = I64Lit(0);

"Type for the LLVMType for the interface resolver function."
alias InterfaceResolverType => FuncType<I64Type,[PtrType<I64Type>]>;

"Type of the interface resolver function."
InterfaceResolverType interfaceResolverType = FuncType(i64,[ptr(i64)]);

"Value that stores an interface resolver function."
alias InterfaceResolver => Ptr<InterfaceResolverType>;

"Get the highest class in the supertype hierarchy of `model` to have satisfied
 each type satisfied by `model`."
Map<InterfaceModel,ClassModel> getOriginalSatisfiers(ClassModel model) {
    value ret = HashMap<InterfaceModel,ClassModel>();
    variable ClassModel? current = model;

    while(exists c = current) {
        value queue = ArrayList<InterfaceModel>();
        queue.addAll(CeylonIterable(c.satisfiedTypes)
                .map((x) => x.declaration).narrow<InterfaceModel>());

        while (exists i = queue.pop()) {
            queue.addAll(CeylonIterable(i.satisfiedTypes)
                    .map((x) => x.declaration)
                    .narrow<InterfaceModel>());
            ret.put(i,c);
        }

        assert(is ClassModel? x = c.extendedType?.declaration);
        current = x;
    }

    return ret;
}


"Get the LLVM type for the given LLVM function."
AnyLLVMFunctionType llvmTypeOf(FunctionModel func) {
    value argTypes =
        parameterListToLLVMTypes(func.firstParameterList).withTrailing(ptr(i64));
    return FuncType(ptr(i64), argTypes);
}

"Get the vtable setup function and interface resolver function for a given class."
[AnyLLVMFunction, AnyLLVMFunction, LLVMGlobal<I64Type>*] vtSetupFunction(
        LLVMModule mod, ClassModel model) {
    value parent = model.extendedType?.declaration;
    value ret = LLVMFunction(mod, setupName(model), null, []);
    value interfaceResolver =
        LLVMFunction(mod, resolverName(model), i64, [ptr(i64)]);
    value originalSatisfiers = getOriginalSatisfiers(model);
    value ifacePositions = HashMap<InterfaceModel,I64>();
    value ifacePositionStorage = ArrayList<LLVMGlobal<I64Type>>();

    ret.private = true;

    variable value vtSize = if (exists parent)
        then ret.loadGlobal(i64, vtSizeName(parent))
        else I64Lit(0);
    value vtParentSize = vtSize;

    "Perform the actual vtable allocation."
    function allocateVTable() {
        value vtSizeBytes = ret.mul(vtSize, 8);
        value vtable = ret.call(ptr(i64), "malloc", vtSizeBytes);

        value vtParentSizeBytes = ret.mul(vtParentSize, 8);
        if (exists parent) {
            value parentVtable = ret.loadGlobal(ptr(i64), vtableName(parent));
            ret.callVoid("llvm.memcpy.p0i64.p0i64.i64", vtable,
                    parentVtable, vtParentSizeBytes, I32Lit(8), I1Lit(0));
        }
        return vtable;
    }

    assert(is Ptr<I64Type> ifaceTarget = interfaceResolver.arguments.first);

    for (iface->cls in originalSatisfiers) {
        if (cls != model) {
            continue;
        }

        ifacePositions.put(iface, vtSize);

        value ifSize = ret.loadGlobal(i64, vtSizeName(iface));

        value positionName = package.positionName(model, iface);

        ret.storeGlobal(positionName, vtSize);
        ifacePositionStorage.add(LLVMGlobal(positionName, I64Lit(0)));

        vtSize = ret.add(vtSize, ifSize);

        value ifSizeGlobal = interfaceResolver.global(i64, vtSizeName(iface));
        value comp = interfaceResolver.compareEq(ifaceTarget, ifSizeGlobal);

        let ([trueBlock, falseBlock] = interfaceResolver.branch(comp));

        interfaceResolver.block = trueBlock;
        value pos = interfaceResolver.loadGlobal(i64, positionName);
        interfaceResolver.ret(pos);
        interfaceResolver.block = falseBlock;
    }

    if (exists parent) {
        value parentInterfaceResolution = interfaceResolver.call(i64,
                resolverName(parent), ifaceTarget);
        interfaceResolver.ret(parentInterfaceResolution);
    } else {
        interfaceResolver.callVoid("abort");
        interfaceResolver.unreachable();
    }

    value resolver = ret.global(interfaceResolverType,
            resolverName(model));
    value resolverInt = ret.toI64(resolver);

    value newEntries = HashSet{*CeylonIterable(model.members).collect(
            (x) => !x.\iactual && (x.\iformal || x.\idefault))};

    variable value nextEntry = vtSize;
    vtSize = ret.add(vtSize, newEntries.size);
    ret.storeGlobal(vtSizeName(model), vtSize);

    value vtable = allocateVTable();
    ret.store(vtable, resolverInt, interfaceResolverPosition);
    ret.storeGlobal(vtableName(model), vtable);

    for (iface->pos in ifacePositions) {
        value ifaceVtable = ret.offset(vtable, pos);
        ret.callVoid(setupName(iface), ifaceVtable);
    }

    "Resolve the VT position of an interface."
    I64 resolveInterfacePosition(InterfaceModel container) {
        /* We use the load address of the vtable size to identify the
         * interface. */
        value targetVt = ret.global(i64, vtSizeName(container));
        value result = ret.call(i64, resolverName(model), targetVt);

        ifacePositions.put(container, result);
        return result;
    }

    "Get the vtable position for a given member."
    I64 getOrCreateVtPosition(FunctionOrValueModel member) {
        if (! member.\iactual) {
            value position = nextEntry;
            value slots = if (is ValueModel member, member.\ivariable)
                then 2
                else 1;
            ret.storeGlobal(vtPositionName(member), position);
            nextEntry = ret.add(nextEntry, I64Lit(slots));
            return position;
        }

        value original = member.refinedDeclaration;
        value container = containingDeclaration(original);
        value position = ret.loadGlobal(i64, vtPositionName(original));

        if (is ClassModel container) {
            return position;
        }

        "Container should be a class or interface."
        assert(is InterfaceModel container);

        if (exists ifacePosition = ifacePositions[container]) {
            return ret.add(position, ifacePosition);
        }

        return ret.add(position, resolveInterfacePosition(container));
    }

    "Set an entry in the vtable."
    void setVtEntry(DeclarationModel member) {
        if (! (member.\iformal || member.\iactual || member.\idefault)) {
            return;
        }

        "TODO: Support inner classes etc."
        assert(is FunctionOrValueModel member);

        value position = getOrCreateVtPosition(member);

        if (is FunctionModel member) {
            value pointer = ret.global(llvmTypeOf(member), dispatchName(member));
            ret.store(vtable, ret.toI64(pointer), position);
            return;
        }

        value pointer = ret.global(FuncType(ptr(i64), [ptr(i64)]),
                getterDispatchName(member));
        ret.store(vtable, ret.toI64(pointer), position);

        if (! member.\ivariable) {
            return;
        }

        value setterPosition = ret.add(position, I64Lit(1));
        value setPointer = ret.global(FuncType(ptr(i64), [ptr(i64), ptr(i64)]),
                setterDispatchName(member));
        ret.store(vtable, ret.toI64(setPointer), setterPosition);
    }

    for (member in model.members) {
        setVtEntry(member);
    }

    return [ret, interfaceResolver, *ifacePositionStorage];
}

"Dispatch from a vtable."
void vtDispatch(FunctionOrValueModel model, AnyLLVMFunction func, Integer selector) {
    assert(is Ptr<I64Type> context = func.arguments.first);
    value vtable = func.toPtr(func.load(context, I64Lit(1)), i64);
    value vtPosition = func.loadGlobal(i64, vtPositionName(model.refinedDeclaration));
    value container = containingDeclaration(model.refinedDeclaration);
    I64 correctedPosition;
    I64 offsetPosition;

    if (is InterfaceModel container) {
        value resolver = func.toPtr(func.load(vtable,
                    interfaceResolverPosition), interfaceResolverType);
        value location =
            func.global(i64, vtSizeName(container));
        assert(exists correction = func.callPtr(resolver, location));
        correctedPosition = func.add(vtPosition, correction);
    } else {
        correctedPosition = vtPosition;
    }

    if (selector != 0) {
        offsetPosition = func.add(correctedPosition, I64Lit(selector));
    } else {
        offsetPosition = correctedPosition;
    }

    value target = func.toPtr(func.load(vtable, offsetPosition),
            func.llvmType);
    func.tailCallPtr(target, *func.arguments);
}

AnyLLVMFunction vtDispatchFunction(LLVMModule mod, FunctionModel model) {
    value func = llvmFunctionForCeylonFunction(mod, model);
    vtDispatch(model, func, 0);
    return func;
}

AnyLLVMFunction vtDispatchGetter(LLVMModule mod, ValueModel model) {
    value func = LLVMFunction(mod, getterName(model), ptr(i64),
                if (!model.toplevel) then [ptr(i64)] else []);
    vtDispatch(model, func, 0);
    return func;
}

AnyLLVMFunction vtDispatchSetter(LLVMModule mod, ValueModel model) {
    value func = LLVMFunction(mod, setterName(model), ptr(i64),
                if (!model.toplevel)
                then [ptr(i64), ptr(i64)]
                else [ptr(i64)]);
    vtDispatch(model, func, 1);
    return func;
}
