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

import ceylon.file {
    parsePath,
    lines,
    createFileIfNil,
    File,
    Nil
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
import com.redhat.ceylon.common.tools {
    CeylonTool,
    SourceArgumentsResolver
}
import com.redhat.ceylon.common.config {
    DefaultToolOptions
}
import com.redhat.ceylon.cmr.ceylon {
    OutputRepoUsingTool
}

import ceylon.formatter { format }
import ceylon.formatter.options { FormattingOptions }

import java.io {
    InputStream,
    ByteArrayInputStream,
    JFile=File
}
import java.util {
    List,
    ArrayList,
    HashSet
}


"Recover the source from the AST"
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

"Compiler utility for LLVM compilation"
shared class LLVMCompilerTool() extends OutputRepoUsingTool(null) {
    shared actual void initialize(CeylonTool mt) {}
    shared actual void run() {
        String listing;

        if (process.arguments.size != 1) {
            if (process.arguments.empty) {
                process.writeErrorLine("No module given");
            } else {
                process.writeErrorLine("Too many arguments");
            }

            process.exit(1);
            return;
        }

        value resolver =
            SourceArgumentsResolver(DefaultToolOptions.getCompilerSourceDirs(null),
                    DefaultToolOptions.getCompilerResourceDirs(null), ".ceylon");

        assert(exists path = process.arguments.first);

        if (is File file = parsePath(path).resource) {
            listing = lines(file).fold("")((x,y) => x + y);
        } else {
            process.writeErrorLine("Could not find file");
            process.exit(1);
            return;
        }

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
            value visitor = LLVMBackendVisitor();
            unit.visit(visitor);
            value result = unit.get(llvmData);
            assert(exists result);
            print(result);

            assert(is File|Nil f = parsePath("./out.ll").resource);
            try (w = createFileIfNil(f).Overwriter()) {
                w.write(result.string);
            }
        }
    }
}
