import org.eclipse.ceylon.model.typechecker.model {
    Declaration
}

String partiallyQualifiedName(Declaration d)
    => if (exists index = d.qualifiedNameString.firstInclusion("::"))
       then d.qualifiedNameString[index+2...]
       else d.qualifiedNameString;
