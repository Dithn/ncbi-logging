#include "Tool.hpp"
#include "OP_Interface.hpp"

using namespace NCBI::Logging;

std::string tool_version( "1.1.0" );

int main ( int argc, char * argv [], const char * envp []  )
{
    OPParseBlockFactory pbFact;
    Tool t ( tool_version, pbFact );
    return t.run ( argc, argv );
}
