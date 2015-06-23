import ceylon.ast.core {
    Node
}

import ceylon.ast.redhat {
    compilationUnitToCeylon,
    RedHatTransformer,
    SimpleTokenFactory
}
import ceylon.interop.java {
    createJavaByteArray,
    CeylonIterable,
    CeylonList
}
import ceylon.io.charset {
    utf8
}

import com.redhat.ceylon.compiler.typechecker {
    TypeCheckerBuilder
}
import com.redhat.ceylon.compiler.typechecker.tree {
    TCNode=Node
}
import com.redhat.ceylon.compiler.typechecker.io {
    VirtualFile
}

import ceylon.formatter { format }
import ceylon.formatter.options { FormattingOptions }

import java.io {
    InputStream,
    ByteArrayInputStream
}
import java.util {
    List,
    ArrayList
}


void printNodeAsCode(Node node) {
    TCNode tcNode(Node node)
    =>  node.transform(
            RedHatTransformer(
                SimpleTokenFactory()));

    value fo = FormattingOptions {
        maxLineLength = 80;
    };
    print(format(tcNode(node), fo));
}

shared
void run() {
    value listing = "void run() {}";
    value virtualFile = object satisfies VirtualFile {
        shared actual
        List<out VirtualFile> children
            =>  ArrayList();

        shared actual
        Integer compareTo(VirtualFile other)
            =>  switch (path.compare(other.path))
                case (smaller) -1
                case (larger) 1
                case (equal) 0;

        shared actual
        Boolean folder
            =>  false;

        shared actual
        InputStream inputStream
            =>  ByteArrayInputStream(
                    createJavaByteArray(
                        utf8.encode(listing)));

        shared actual
        String name
            =>  "virtual.ceylon";

        shared actual
        String path
            =>  name;
    };

    value builder = TypeCheckerBuilder();
    builder.addSrcDirectory(virtualFile);

    value typeChecker = builder.typeChecker;
    typeChecker.process();

    // print typechecker messages
    CeylonIterable(typeChecker.messages).each(
            compose(process.writeErrorLine, Object.string));

    value phasedUnits = CeylonIterable(
            typeChecker.phasedUnits.phasedUnits);

    for (phasedUnit in phasedUnits) {
        value unit = compilationUnitToCeylon(
                phasedUnit.compilationUnit,
                augmentNode);
        printNodeAsCode(unit);
        print("========================");
        print("== TC-AST");
        print("========================");
        print(phasedUnit.compilationUnit);
        print("========================");
        print("== AST");
        print("========================");
        print(unit);
        print("========================");
        print("== LLVM");
        print("========================");
        /*try {
            /*value ctx = CompilationContext(phasedUnit.unit, CeylonList(phasedUnit.tokens));
            ctx.init();
            value visitor = DartBackendVisitor(ctx);
            unit.visit(visitor);
            print(ctx.result);*/
        } catch (CompilerBug b) {
            //process.writeError("Compiler bug:\n" + b.message);
        }*/
    }
}
