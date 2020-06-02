#include <gtest/gtest.h>

#include <sstream>
#include <vector>

#include "log_lines.hpp"
#include "helper.hpp"

using namespace std;
using namespace NCBI::Logging;

struct SLogGCPEvent
{
    int64_t     time;
    string      ip;
    int64_t     ip_type;
    string      ip_region;
    string      method;
    string      uri;
    int64_t     status;
    int64_t     request_bytes;
    int64_t     result_bytes;
    int64_t     time_taken;
    string      host;
    string      referrer;
    string      agent;
    string      request_id;
    string      operation;
    string      bucket;
    string      object;

    SLogGCPEvent( const LogGCPEvent &ev )
    {
        time        = ev . time;
        ip          = ToString( ev . ip );
        ip_type     = ev . ip_type;
        ip_region   = ToString( ev . ip_region );
        method      = ToString( ev . method );
        uri         = ToString( ev . uri );
        status      = ev . status;
        request_bytes = ev . request_bytes;
        result_bytes = ev . result_bytes;
        time_taken  = ev. time_taken;
        host        = ToString( ev . host );
        referrer    = ToString( ev . referrer );
        agent       = ToString( ev . agent );
        request_id  = ToString( ev . request_id );
        operation   = ToString( ev . operation );
        bucket      = ToString( ev . bucket );
        object      = ToString( ev . object );
    }
};

struct TestLogLines : public GCP_LogLines
{
    virtual int unrecognized( const t_str & text )
    {
        m_unrecognized . push_back( ToString( text ) );
        return 0;
    }

    virtual int acceptLine( const LogGCPEvent & event )
    {
        last_accepted = new SLogGCPEvent( event );
        return 0;
    }

    virtual int rejectLine( const LogGCPEvent & event )
    {
        last_rejected = new SLogGCPEvent( event );
        return 0;
    }

    virtual int headerLine( const LogGCPHeader & hdr )
    {
        return 0;
    }

    vector< string > m_unrecognized;
    SLogGCPEvent * last_accepted = nullptr;
    SLogGCPEvent * last_rejected = nullptr;

    virtual ~TestLogLines()
    {
        delete last_accepted;
        delete last_rejected;
    }
};

TEST ( TestParse, InitDestroy )
{
    TestLogLines lines;
    GCP_Parser p( lines );
}

class TestParseFixture : public ::testing::Test
{
public:
    virtual void SetUp() {}
    virtual void TearDown() {}

    const SLogGCPEvent * parse_gcp( const char * input )
    {
        std::istringstream inputstream( input );
        {
            GCP_Parser p( m_lines, inputstream );
            //p.setDebug( true );
            if ( !p.parse() ) throw logic_error( "parsing failed" );
            if ( nullptr == m_lines.last_accepted ) throw logic_error( "last_accepted is null" );
            return m_lines . last_accepted;
        }
    }

    TestLogLines m_lines;
};

TEST_F ( TestParseFixture, Empty )
{
    std::istringstream input ( "" );
    {
        GCP_Parser p( m_lines, input );
        ASSERT_TRUE( p.parse() );
    }
}

// GCP
TEST_F ( TestParseFixture, GCP )
{
    const char * InputLine =
    "\"1589759989434690\","
    "\"35.245.177.170\","
    "\"1\","
    "\"\","
    "\"GET\","
    "\"/storage/v1/b/sra-pub-src-9/o/SRR1371108%2FCGAG_2.1.fastq.gz?fields=name&alt=json&userProject=nih-sra-datastore&projection=noAcl\","
    "\"404\","
    "\"0\","
    "\"291\","
    "\"27000\","
    "\"www.googleapis.com\","
    "\"\","
    "\"apitools gsutil/4.37 Python/2.7.13 (linux2) \\\"google\\\"-cloud-sdk/237.0.0 analytics/disabled,gzip(gfe)\","
    "\"AAANsUmaKBTw9gqOSHDOdr10MW802XI5jlNu87rTHuxhlRijModRQnNlwOd-Nxr0EHWq4iVXXEEn9LW4cHb7D6VK5gs\","
    "\"storage.objects.get\","
    "\"sra-pub-src-9\","
    "\"SRR1371108/CGAG_2.1.fastq.gz\""
    "\n";

    const SLogGCPEvent &e = *( parse_gcp( InputLine ) );

    ASSERT_EQ( 1589759989434690, e.time );
    ASSERT_EQ( "35.245.177.170", e.ip );
    ASSERT_EQ( 1, e.ip_type );
    ASSERT_EQ( "", e.ip_region );
    ASSERT_EQ( "GET", e.method );
    ASSERT_EQ( "/storage/v1/b/sra-pub-src-9/o/SRR1371108%2FCGAG_2.1.fastq.gz?fields=name&alt=json&userProject=nih-sra-datastore&projection=noAcl", e . uri );
    ASSERT_EQ( 404, e . status );
    ASSERT_EQ( 0, e . request_bytes );
    ASSERT_EQ( 291, e . result_bytes );
    ASSERT_EQ( 27000, e . time_taken );
    ASSERT_EQ( "www.googleapis.com", e . host );
    ASSERT_EQ( "", e . referrer );
    ASSERT_EQ( "apitools gsutil/4.37 Python/2.7.13 (linux2) \"google\"-cloud-sdk/237.0.0 analytics/disabled,gzip(gfe)", e . agent );
    ASSERT_EQ( "AAANsUmaKBTw9gqOSHDOdr10MW802XI5jlNu87rTHuxhlRijModRQnNlwOd-Nxr0EHWq4iVXXEEn9LW4cHb7D6VK5gs", e . request_id );
    ASSERT_EQ( "storage.objects.get", e . operation );
    ASSERT_EQ( "sra-pub-src-9", e . bucket );
    ASSERT_EQ( "SRR1371108/CGAG_2.1.fastq.gz", e . object );
}

// TODO test for specified ip-region
// TODO test with referrer present
// TODO quoted string with escaped quotes inside

extern "C"
{
    int main ( int argc, const char * argv [], const char * envp []  )
    {
        testing :: InitGoogleTest ( & argc, ( char ** ) argv );
        return RUN_ALL_TESTS ();
    }
}