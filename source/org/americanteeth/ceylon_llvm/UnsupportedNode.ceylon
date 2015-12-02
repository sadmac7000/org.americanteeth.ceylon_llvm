import ceylon.language.meta { type }
import ceylon.ast.core { Node }

class UnsupportedNode(Node n) extends Exception(type(n).string) {}
