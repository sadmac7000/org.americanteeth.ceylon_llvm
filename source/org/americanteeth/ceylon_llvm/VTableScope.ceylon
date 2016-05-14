import ceylon.collection {
    ArrayList,
    HashMap
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function,
    ClassModel=Class,
    ClassOrInterfaceModel=ClassOrInterface,
    InterfaceModel=Interface,
    DeclarationModel=Declaration
}

"Floor value for constructor function priorities. We use this just to be well
 out of the way of any C libraries that might get linked with us."
Integer constructorPriorityOffset = 65536;

"Position of the interface resolver function in the vtable."
I64 interfaceResolverPosition = I64Lit(0);

"Type of the interface resolver function."
FuncType<I64Type,[PtrType<I64Type>]> interfaceResolverType =
        FuncType(i64,[ptr(i64)]);

"Scope which is backed by a persistent object with a VTable."
abstract class VTableScope(ClassOrInterfaceModel model)
        extends CallableScope(model, "$init") {
    value vtable = ArrayList<DeclarationModel>();
    value vtableOverrides = ArrayList<DeclarationModel>();
    value parent =
        if (is ClassModel model)
        then model.extendedType.declaration
        else null;

    "Our vtPosition variables that store the vtable offsets in the binary"
    {AnyLLVMGlobal*} vtPositions()
            => vtable.map((x) => LLVMGlobal("``declarationName(x)``$vtPosition",
                        I64Lit(0)));

    "Global variables that se up the vtable"
    {LLVMDeclaration+} globals = [
        LLVMGlobal("``declarationName(model)``$vtsize", I64Lit(0)),
        LLVMGlobal(declarationName(model) + "$vtable", llvmNull)
    ];

    "Our setup function object is passed here before being returned. Overriders
     can perform additional setup tasks here."
    shared default void additionalSetup(LLVMFunction setupFunction) {}

    shared actual default {LLVMDeclaration*} results {
        value setupFunction =
            LLVMFunction(declarationName(model) + "$setupClass",
                null, "private", []);

        I64 vtParentSize;
        variable I64 vtSize;
        value vtInterfaceSizes = HashMap<InterfaceModel,I64>();
        value vtInterfaceLocations = HashMap<InterfaceModel,I64>();

        /* Setup vtable size value */
        if (exists parent) {
            vtParentSize = setupFunction.load(setupFunction.global(i64,
                    "``declarationName(parent)``$vtsize"));
            vtSize = setupFunction.add(vtParentSize, vtable.size);
        } else {
            vtParentSize = I64Lit(0);
            vtSize = I64Lit(vtable.size);
        }

        /* Setup interfaces */
        for (int in model.satisfiedTypes) {
            value mod = int.declaration;

            if (! is InterfaceModel mod) {
                continue;
            }

            value sz = setupFunction.load(setupFunction.global(i64,
                        "``declarationName(mod)``$vtsize"));

            vtInterfaceLocations.put(mod, vtSize);
            vtInterfaceSizes.put(mod, sz);
            vtSize = setupFunction.add(vtSize, sz);
        }

        value vtSizeGlobal = setupFunction.global(i64,
            "``declarationName(model)``$vtsize");

        value vtSizeBytes = setupFunction.mul(vtSize, 8);
        setupFunction.store(vtSizeGlobal, vtSize);

        /* Setup vtable */
        value vt = setupFunction.call(ptr(i64), "malloc", vtSizeBytes);

        if (exists parent) {
            value vtParentSizeBytes = setupFunction.mul(vtParentSize, 8);
            value parentvt = setupFunction.load(setupFunction.global(ptr(i64),
                    "``declarationName(parent)``$vtable"));
            setupFunction.callVoid("llvm.memcpy.p0i64.p0i64.i64", vt, parentvt,
                vtParentSizeBytes, I32Lit(8), I1Lit(0));
        }

        for (int->loc in vtInterfaceLocations) {
            assert(exists sz = vtInterfaceSizes[int]);
            value parentvt = setupFunction.load(setupFunction.global(ptr(i64),
                    "``declarationName(int)``$vtable"));
            value allocPoint = setupFunction.offset(vt, loc);
            setupFunction.callVoid("llvm.memcpy.p0i64.p0i64.i64", allocPoint,
                    parentvt, sz, I32Lit(8), I1Lit(0));
        }

        setupFunction.store(
            setupFunction.global(ptr(i64),
                "``declarationName(model)``$vtable"), vt);

        /* Set up vtPosition variables */
        variable value i = 0;

        void setVtEntry(DeclarationModel decl, I64 vtPosition) {
            "We only have vtable entries for function models now."
            assert (is FunctionModel decl);

            variable DeclarationModel rootDecl = decl;
            while (rootDecl.refinedDeclaration != rootDecl) {
                rootDecl = rootDecl.refinedDeclaration;
            }

            value argTypes =
                parameterListToLLVMValues(decl.firstParameterList)
                    .map((x) => x.type)
                    .follow(ptr(i64))
                    .sequence();
            value funcType = FuncType(ptr(i64), argTypes);
            value func = setupFunction.global(funcType, declarationName(decl));
            value intValue = setupFunction.toI64(func);

            if (rootDecl.container is ClassModel ||
                    rootDecl.container == model) {
                setupFunction.store(vt, intValue, vtPosition);
            } else {
                assert(is InterfaceModel int = rootDecl.container);

                assert(exists offset = vtInterfaceLocations[int]);

                value truePosition = setupFunction.add(vtPosition, offset);
                setupFunction.store(vt, intValue, truePosition);
            }
        }

        for (decl in vtable) {
            value vtIdent = I64Lit(i++);
            value vtPosition =
                if (exists parent)
                then setupFunction.add(vtParentSize, vtIdent)
                else vtIdent;
            setupFunction.store(
                setupFunction.global(i64,
                    "``declarationName(decl)``$vtPosition"), vtPosition);

            setVtEntry(decl, vtPosition);
        }

        /* Set up vtable overrides */
        for (decl in vtableOverrides) {
            variable value rootDecl = decl;

            while (rootDecl.refinedDeclaration != rootDecl) {
                rootDecl = rootDecl.refinedDeclaration;
            }

            value vtPosition = setupFunction.load(setupFunction.global(i64,
                    "``declarationName(rootDecl)``$vtPosition"));

            setVtEntry(decl, vtPosition);
        }

        value vtForGlobals = ArrayList<LLVMGlobal<I64Type>>();

        for (int->pos in vtInterfaceLocations) {
            value name =
                "``declarationName(model)``$vtFor.``declarationName(int)``";
            value global = setupFunction.global(i64, name);
            vtForGlobals.add(LLVMGlobal(name, I64Lit(0)));
            setupFunction.store(global, pos);
        }

        /* Install setup function as a constructor */
        assert (exists priority = declarationOrder[model]);
        setupFunction.makeConstructor(priority + constructorPriorityOffset);

        additionalSetup(setupFunction);

        if (! exists parent) {
            return super.results.chain(globals).chain {
                setupFunction, *vtPositions()
            };
        }

        /* Interface resolver function */
        value resolverFunction =
            LLVMFunction(declarationName(model) + "$resolveInterface",
                i64, "private", [val(ptr(i64), "%.vtable")]);

        value arg = resolverFunction.register(ptr(i64), ".vtable");

        for (int in vtInterfaceLocations.keys) {
            value successBlock = resolverFunction.newBlock();
            value failBlock = resolverFunction.newBlock();
            value targetGlobal = resolverFunction.global(ptr(i64),
                    "``declarationName(int)``$vtable");
            value target = resolverFunction.load(targetGlobal);
            value cmp = resolverFunction.compareEq(arg, target);
            resolverFunction.branch(cmp, successBlock, failBlock);
            resolverFunction.block = successBlock;
            value global = resolverFunction.global(i64,
                "``declarationName(model)``$vtFor.``declarationName(int)``");
            value pos = resolverFunction.load(global);
            resolverFunction.ret(pos);
            resolverFunction.block = failBlock;
        }

        value parentvt = resolverFunction.global(ptr(i64),
                "``declarationName(parent)``$vtable");
        value parentResolver = resolverFunction.toPtr(
                resolverFunction.load(
                    resolverFunction.load(parentvt, interfaceResolverPosition)),
                interfaceResolverType);
        value realValue = resolverFunction.tailCallPtr(parentResolver, arg);
        resolverFunction.ret(realValue);

        value resolverGlobal = setupFunction.global(resolverFunction.llvmType,
                resolverFunction.name);
        value intValue = setupFunction.toI64(resolverGlobal);
        setupFunction.store(vt, intValue, interfaceResolverPosition);

        return super.results.chain(globals).chain {
            setupFunction, resolverFunction, *vtPositions()
        }.chain(vtForGlobals);
    }

    shared actual void vtableEntry(DeclarationModel d) {
        if (!d.\iactual) {
            vtable.add(d);
        } else {
            vtableOverrides.add(d);
        }
    }
}

"Scope of an interface."
class InterfaceScope(InterfaceModel model) extends VTableScope(model) {}
