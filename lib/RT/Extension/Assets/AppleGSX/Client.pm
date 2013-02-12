use strict;
use warnings;

package RT::Extension::Assets::AppleGSX::Client;

use LWP::UserAgent;

use XML::Simple;
my $xs = XML::Simple->new;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(
    qw/UserAgent UserSessionId UserSessionTimeout UserId Password
      ServiceAccountNo Lang UserTimeZone/
);

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? shift @_ : {@_};
    my $self  = $class->SUPER::new($args);
    $self->UserAgent( LWP::UserAgent->new() ) unless $self->UserAgent;
    return $self;
}

sub Authenticate {
    my $self = shift;

    my $xml = $self->PrepareXML(
        'Authenticate',
        {
            userId           => $self->UserId,
            password         => $self->Password,
            serviceAccountNo => $self->ServiceAccountNo,
            languageCode     => 'en',
            userTimeZone     => 'CEST',
        }
    );

    my $res = $self->SendRequest($xml);
    if ( $res->is_success ) {
        my $ret =
          $self->ParseResponseXML( 'Authenticate', $res->decoded_content );
        $self->UserSessionId( $ret->{'userSessionId'} );

        # official timeout is 30 minutes, minus 5 is to avoid potential
        # out of sync time issue
        $self->UserSessionTimeout( time() + 25 * 60 );
        return $self->UserSessionId;
    }
    else {
        warn "failed to auth gsx: " . $res->status_line;
        return;
    }
}

sub WarrantyStatus {
    my $self = shift;
    my $serial = shift or return;

    $self->Authenticate
      unless $self->UserSessionId && time() < $self->UserSessionTimeout;

    my $xml = $self->PrepareXML(
        'WarrantyStatus',
        {
            'userSession' => { userSessionId => $self->UserSessionId, },
            'unitDetail'  => { serialNumber  => $serial, }
        }
    );

    my $res = $self->SendRequest($xml);
    if ( $res->is_success ) {
        return $self->ParseResponseXML( 'WarrantyStatus',
            $res->decoded_content );
    }
    else {
        my $data = eval { $xs->parse_string( $res->decoded_content, NoAttr => 1, SuppressEmpty => undef ) };
        if ($data) {
            warn "Failed to get Apple GSX warranty status of serial $serial: "
                . $data->{"S:Body"}{"S:Fault"}{"faultstring"};
        } else {
            warn "Failed to get Apple GSX warranty status of serial $serial: ".$res->status_line;
        }
        return;
    }
}

sub PrepareXML {
    my $self   = shift;
    my $method = shift;
    my $args   = shift || {};

    my $xml = $xs->XMLout(
        {
            'SOAP-ENV:Body' =>
              { "ns1:$method" => { "${method}Request" => $args, }, },
        },
        NoAttr   => 1,
        KeyAttr  => [],
        RootName => '',
    );
    return <<"EOF",
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
xmlns:ns1="http://gsxws.apple.com/elements/global">
$xml
</SOAP-ENV:Envelope>
EOF

}

sub ParseResponseXML {
    my $self   = shift;
    my $method = shift;
    my $xml    = shift;
    my $ret    = $xs->XMLin( $xml, NoAttr => 1, SuppressEmpty => undef );
    return $ret->{'S:Body'}{"ns3:${method}Response"}{"${method}Response"};
}

sub SendRequest {
    my $self = shift;
    my $xml  = shift;
    my $res  = $self->UserAgent->post(
        'https://gsxws2.apple.com/gsx-ws/services/am/asp',
        'Content-Type' => 'text/xml; charset=utf-8',
        Content        => $xml,
    );
    return $res;
}

1;
