#include <gtest/gtest.h>

#include "AWS_Interface.cpp"

using namespace std;
using namespace NCBI::Logging;

TEST( AWSFormatterTest, Create )
{
    AWSFormatter fmt;
}

TEST( AWSFormatterTest, FormatEmptyObj )
{
    AWSFormatter fmt;
    ASSERT_EQ( "", fmt.format() );
}

TEST( AWSFormatterTest, FormatStrings )
{
    AWSFormatter fmt;
    fmt . addNameValue( "ignored", "value1" );
    fmt . addNameValue( "ignored", "value2" );
    fmt . addNameValue( "ignored", "value3" );
    fmt . addNameValue( "ignored", 100 );
    t_str s{ "tvalue", 6, false };
    fmt . addNameValue( "ignored", s );
    ASSERT_EQ( "value1 value2 value3 100 tvalue", fmt.format() );
    ASSERT_EQ( "", fmt.format() );
}

TEST( AWSFormatterTest, FormatNulltstr )
{
    AWSFormatter fmt;
    fmt . addNameValue( "ignored", "value1" );
    t_str s = { nullptr, 0, false };
    fmt . addNameValue( "ignored", s );
    ASSERT_EQ( "value1", fmt.format() );
}

TEST( AWSReverseBlockTest, Create )
{
    AWSReverseBlockFactory factory;
    auto pb = factory . MakeParseBlock();
    ASSERT_TRUE( pb );
}

TEST( AWSReverseBlockTest, ReverseEmptyLine )
{
    // if an empty lines is given ( is in the json-source-file ) we want it to be in the unrecog-file
    AWSReverseBlockFactory factory;
    auto pb = factory . MakeParseBlock();
    string line( "" );
    bool res = pb -> format_specific_parse( line.c_str(), line . size() );
    ASSERT_FALSE( res );
}

TEST( AWSReverseBlockTest, ReverseEmptyJson )
{
    // if an empty json is given ( is in the json-source-file ) we want it to be in the unrecog-file
    AWSReverseBlockFactory factory;
    auto pb = factory . MakeParseBlock();
    string line( "{}" );
    bool res = pb -> format_specific_parse( line.c_str(), line . size() );
    ASSERT_FALSE( res );
}

TEST( AWSReverseBlockTest, ReverseBadJson )
{
    // if an empty json is given ( is in the json-source-file ) we want it to be in the unrecog-file
    AWSReverseBlockFactory factory;
    auto pb = factory . MakeParseBlock();
    string line( "{" );
    bool res = pb -> format_specific_parse( line.c_str(), line . size() );
    ASSERT_FALSE( res );
}

TEST( AWSReverseBlockTest, ReverseGoodJson )
{
    AWSReverseBlockFactory factory;
    auto pb = factory . MakeParseBlock();
    string line( "{\"accepted\":\"true\",\"accession\":\"SRR10868496\",\"agent\":\"aws-cli/1.18.13 Python/2.7.18 Linux/4.14.186-110.268.amzn1.x86_64 botocore/1.15.13\",\"auth_type\":\"AuthHeader\",\"bucket\":\"sra-pub-run-2\",\"cipher_suite\":\"ECDHE-RSA-AES128-GCM-SHA256\",\"error\":\"\",\"extension\":\".1\",\"filename\":\"SRR10868496\",\"host_header\":\"sra-pub-run-2.s3.amazonaws.com\",\"host_id\":\"t8FlcJOJAG3BrX2fV+sKmIEJORnHX3sEx/vrIOT6TBGVn/Hj+ZyjP3y0jhr10w6kwfF6J4A02Ec=\",\"ip\":\"3.236.215.75\",\"key\":\"SRR10868496/SRR10868496.1\",\"method\":\"PUT\",\"obj_size\":\"8388608\",\"operation\":\"REST.PUT.PART\",\"owner\":\"922194806485875312b252374a3644f1feecd16802a50d4729885c1d11e1fd37\",\"path\":\"/SRR10868496/SRR10868496.1?partNumber=5312&uploadId=eCBqLXk7jmcJG1FqaYKg5saIW0au0xZ3deTnVUDp8Xg4j981rHK6X9HUNrsntwo.F9szQ_KY1Nbjykzj45NP5rhbId5W.wyWxp_JV5Wok6lrs1KmDAjwIcTokTU01Rb7lNSxiAYxjqgtDRo9vaD1QA--\",\"referer\":\"\",\"request_id\":\"CA5DAE26B8645A60\",\"requester\":\"arn:aws:sts::783971887864:assumed-role/sra-developer-instance-profile-role/i-020cde5f07895bac2\",\"res_code\":\"200\",\"res_len\":\"\",\"sig_ver\":\"SigV4\",\"source\":\"S3\",\"time\":\"[02/Sep/2020:06:00:57 +0000]\",\"tls_version\":\"TLSv1.2\",\"total_time\":\"940\",\"turnaround_time\":\"105\",\"vdb_libc\":\"\",\"vdb_os\":\"\",\"vdb_phid_compute_env\":\"\",\"vdb_phid_guid\":\"\",\"vdb_phid_session_id\":\"\",\"vdb_release\":\"\",\"vdb_tool\":\"\",\"vers\":\"HTTP/1.1\",\"version_id\":\"\"}" );
    bool res = pb -> format_specific_parse( line.c_str(), line . size() );
    ASSERT_TRUE( res );
    ReceiverInterface &rec = pb -> GetReceiver();
    FormatterInterface &fmt = rec . GetFormatter();
    std::string s = fmt . format();
    ASSERT_EQ( "922194806485875312b252374a3644f1feecd16802a50d4729885c1d11e1fd37 sra-pub-run-2 [02/Sep/2020:06:00:57 +0000] 3.236.215.75 arn:aws:sts::783971887864:assumed-role/sra-developer-instance-profile-role/i-020cde5f07895bac2 CA5DAE26B8645A60 REST.PUT.PART SRR10868496/SRR10868496.1 \"PUT /SRR10868496/SRR10868496.1?partNumber=5312&uploadId=eCBqLXk7jmcJG1FqaYKg5saIW0au0xZ3deTnVUDp8Xg4j981rHK6X9HUNrsntwo.F9szQ_KY1Nbjykzj45NP5rhbId5W.wyWxp_JV5Wok6lrs1KmDAjwIcTokTU01Rb7lNSxiAYxjqgtDRo9vaD1QA-- HTTP/1.1\" 200 - - 8388608 940 105 - \"aws-cli/1.18.13 Python/2.7.18 Linux/4.14.186-110.268.amzn1.x86_64 botocore/1.15.13\" - t8FlcJOJAG3BrX2fV+sKmIEJORnHX3sEx/vrIOT6TBGVn/Hj+ZyjP3y0jhr10w6kwfF6J4A02Ec= SigV4 ECDHE-RSA-AES128-GCM-SHA256 AuthHeader sra-pub-run-2.s3.amazonaws.com TLSv1.2", s );
}

//Todo test for 2-part host-id

extern "C"
{
    int main ( int argc, const char * argv [], const char * envp []  )
    {
        testing :: InitGoogleTest ( & argc, ( char ** ) argv );
        return RUN_ALL_TESTS ();
    }
}
