import ceylon.collection {
    HashMap,
    HashSet,
    ArrayList
}

import com.redhat.ceylon.model.typechecker.model {
    ClassModel=Class,
    FunctionModel=Function,
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
        parameterListToLLVMValues(func.firstParameterList)
            .map((x) => x.type)
            .follow(ptr(i64))
            .sequence();
    return FuncType(ptr(i64), argTypes);
}

"Get the vtable setup function and interface resolver function for a given class."
[LLVMFunction, LLVMFunction, LLVMGlobal<I64Type>*] vtSetupFunction(ClassModel model) {
    value parent = model.extendedType.declaration;
    value ret = LLVMFunction(setupName(model), null, "private", []);
    value interfaceResolver =
        LLVMFunction(resolverName(model), i64, "", [loc(ptr(i64), ".target")]);
    value originalSatisfiers = getOriginalSatisfiers(model);
    value ifacePositions = HashMap<InterfaceModel,I64>();
    value ifacePositionStorage = ArrayList<LLVMGlobal<I64Type>>();

    variable value vtSize = ret.loadGlobal(i64, vtSizeName(parent));
    value vtParentSize = vtSize;

    "Perform the actual vtable allocation."
    function allocateVTable() {
        value vtSizeBytes = ret.mul(vtSize, 8);
        value vtable = ret.call(ptr(i64), "malloc", vtSizeBytes);

        value vtParentSizeBytes = ret.mul(vtParentSize, 8);
        value parentVtable = ret.loadGlobal(ptr(i64), vtableName(parent));
        ret.callVoid("llvm.memcpy.p0i64.p0i64.i64", vtable,
                parentVtable, vtParentSizeBytes, I32Lit(8), I1Lit(0));
        return vtable;
    }

    value ifaceTarget = interfaceResolver.register(ptr(i64), ".target");

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

        value [trueBlock, falseBlock] = interfaceResolver.branch(comp);

        interfaceResolver.block = trueBlock;
        value pos = interfaceResolver.loadGlobal(i64, positionName);
        interfaceResolver.ret(pos);
        interfaceResolver.block = falseBlock;
    }

    value parentInterfaceResolution = interfaceResolver.call(i64,
            resolverName(parent), ifaceTarget);
    interfaceResolver.ret(parentInterfaceResolution);

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
    I64 getVtPosition(FunctionModel member) {
        if (! member.\iactual) {
            value position = nextEntry;
            ret.storeGlobal(vtPositionName(member),
                    position);
            nextEntry = ret.add(nextEntry, I64Lit(1));
            return position;
        }

        value original = member.refinedDeclaration;
        value container = original.container;
        value position = ret.loadGlobal(i64,
                vtPositionName(original));

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

        "We only support functions in vtables for now."
        assert(is FunctionModel member);

        value position = getVtPosition(member);
        value pointer = ret.global(llvmTypeOf(member), dispatchName(member));
        ret.store(vtable, ret.toI64(pointer), position);
    }

    for (member in model.members) {
        setVtEntry(member);
    }

    return [ret, interfaceResolver, *ifacePositionStorage];
}

"Get an LLVM Function for a Ceylon function that simply dispatches from the
 vtable."
LLVMFunction vtDispatchFunction(FunctionModel model) {
    value func = llvmFunctionForCeylonFunction(model);
    value context = func.register(ptr(i64), ".context");
    value vtable = func.toPtr(func.load(context, I64Lit(1)), i64);
    value vtPosition = func.loadGlobal(i64, vtPositionName(model.refinedDeclaration));
    value container = model.refinedDeclaration.container;
    I64 correctedPosition;

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

    value target = func.toPtr(func.load(vtable, correctedPosition),
            func.llvmType);
    func.tailCallPtr(target, *func.arguments);

    return func;
}
