import org.eclipse.ceylon.common.tools {
    RepoUsingTool
}

import org.eclipse.ceylon.common {
    ModuleUtil
}

/*import org.eclipse.ceylon.cmr.api {
    ModuleQuery
}*/

import org.eclipse.ceylon.common.tool {
    argument=argument__SETTER
}

shared class RunTool() extends RepoUsingTool(null) {
    shared variable argument {
        argumentName = "module";
        multiplicity = "1";
        order = 1;
    }
    String moduleString = "";

    shared actual void run() {
        String moduleName = ModuleUtil.moduleName(moduleString);
        /*String? moduleVersion =
            checkModuleVersionsOrShowSuggestions(repositoryManager, moduleName,
                ModuleUtil.moduleVersion(moduleString),
                ModuleQuery.Type.\iALL, null, null, null, null, null);*/
        print(moduleName);
        //print(moduleVersion);
    }
}
