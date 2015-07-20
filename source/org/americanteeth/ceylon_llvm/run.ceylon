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

import java.util { List, JArrayList = ArrayList }
import java.lang { JString = String }

import ceylon.process {
    createProcess,
    currentOutput,
    currentError
}

import ceylon.collection {
    ArrayList
}

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
    variable List<JString> moduleOrFile_ = JArrayList<JString>();
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
        builder.setRepositoryManager(repositoryManager);

        value typeChecker = builder.typeChecker;
        typeChecker.process();

        value phasedUnits = CeylonIterable(
                typeChecker.phasedUnits.phasedUnits);

        variable value tmpIdx = 0;
        variable value args = ArrayList<String>{"-shared", "-fPIC", "-lceylon", "-otest.so"};

        for (phasedUnit in phasedUnits) {
            value unit = anyCompilationUnitToCeylon(
                    phasedUnit.compilationUnit,
                    augmentNode);

            value visitor = LLVMBackendVisitor();
            unit.visit(visitor);
            value result = unit.get(keys.llvmData);
            if (! exists result) { continue; }
            assert(exists result);

            value file = "/tmp/tmp``tmpIdx++``.ll";
            assert(is File|Nil f = parsePath("``file``").resource);

            args.add(file);
            try (w = createFileIfNil(f).Overwriter()) {
                w.write(result.string);
            }
        }

        if (tmpIdx == 0) { return; }

        createProcess {
            command = "/usr/bin/clang";
            arguments = args;
            output = currentOutput;
            error = currentError;
        }.waitForExit();
    }
}
