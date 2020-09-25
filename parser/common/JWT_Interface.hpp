#pragma once

#include "ReceiverInterface.hpp"
#include "ParserInterface.hpp"

namespace NCBI
{
    namespace Logging
    {
        struct JWTReceiver : public ReceiverInterface
        {
            using ReceiverInterface::set;

            JWTReceiver( std::unique_ptr<FormatterInterface> & fmt );

            void setJwt( const t_str & v );

            size_t m_jwtCount;
        };

        class JWTParseBlock : public ParseBlockInterface
        {
        public:
            JWTParseBlock( JWTReceiver & receiver );
            virtual ~JWTParseBlock();

            virtual ReceiverInterface & GetReceiver() { return m_receiver; }
            virtual bool format_specific_parse( const char * line, size_t line_size );

            virtual void SetDebug( bool onOff );

            //yyscan_t m_sc;
            void * m_sc;
            JWTReceiver & m_receiver;
        };
    }
}
