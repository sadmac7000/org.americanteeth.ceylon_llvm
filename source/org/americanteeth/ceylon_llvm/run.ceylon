import ceylon.ast.core {
    Node
}

import ceylon.ast.redhat {
    anyCompilationUnitToCeylon,
    RedHatTransformer,
    SimpleTokenFactory
}
import ceylon.interop.java {
    CeylonIterable,
    JavaList,
    javaString
}

import ceylon.file {
    parsePath,
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
import com.redhat.ceylon.common {
    Backend
}
import com.redhat.ceylon.common.tool {
    argument,
    option
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

import java.util { List, ArrayList }
import java.lang { JString = String }

"Options for formatting code output"
FormattingOptions formatOpts = FormattingOptions {
    maxLineLength = 80;
};

"Recover the source from the AST"
void printNodeAsCode(Node node) {
    TCNode tcNode(Node node)
    =>  node.transform(
            RedHatTransformer(
                SimpleTokenFactory()));

    print(format(tcNode(node), formatOpts));
}

"Compiler utility for LLVM compilation"
shared class LLVMCompilerTool() extends OutputRepoUsingTool(null) {
    variable List<JString> moduleOrFile_ = ArrayList<JString>();
    shared List<JString> moduleOrFile => moduleOrFile_;

    argument{argumentName = "moduleOrFile"; multiplicity = "*";}
    assign moduleOrFile { moduleOrFile_ = moduleOrFile; }

    shared actual void initialize(CeylonTool mt) {}

    shared actual void run() {
        value roots = DefaultToolOptions.compilerSourceDirs;
        value resources = DefaultToolOptions.compilerResourceDirs;
        value resolver = SourceArgumentsResolver(roots, resources, ".ceylon");

        resolver.cwd(cwd).expandAndParse(moduleOrFile, Backend.\iNone);
        value builder = TypeCheckerBuilder();

        for (root in CeylonIterable(roots)) {
            builder.addSrcDirectory(root);
        }

        builder.setSourceFiles(resolver.sourceFiles);

        value typeChecker = builder.typeChecker;
        typeChecker.process(true);

        // print typechecker messages
        CeylonIterable(typeChecker.messages).each(
                compose(process.writeErrorLine, Object.string));

        value phasedUnits = CeylonIterable(
                typeChecker.phasedUnits.phasedUnits);

        for (phasedUnit in phasedUnits) {
            value unit = anyCompilationUnitToCeylon(
                    phasedUnit.compilationUnit,
                    augmentNode);

            value visitor = LLVMBackendVisitor();
            unit.visit(visitor);
            value result = unit.get(llvmData);
            if (! exists result) { continue; }
            assert(exists result);

            assert(is File|Nil f = parsePath("./out.ll").resource);
            try (w = createFileIfNil(f).Overwriter()) {
                w.write(result.string);
            }
        }
    }
}
