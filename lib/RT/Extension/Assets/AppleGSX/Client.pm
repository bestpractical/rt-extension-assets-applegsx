use strict;
use warnings;

package RT::Extension::Assets::AppleGSX::Client;

use LWP::UserAgent;

use XML::Simple;
my $xs = XML::Simple->new;

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(
    qw/UserAgent UserSessionId UserSessionTimeout UserId UserTimeZone
      ServiceAccountNo LanguageCode CertFilePath KeyFilePath/
);

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? shift @_ : {@_};
    my $self  = $class->SUPER::new($args);
    $ENV{HTTPS_CERT_FILE} = $self->CertFilePath;
    $ENV{HTTPS_KEY_FILE} = $self->KeyFilePath;
    $self->UserAgent( LWP::UserAgent->new() ) unless $self->UserAgent;
    return $self;
}

sub Authenticate {
    my $self = shift;

    my $xml = $self->PrepareXML(
        'Authenticate',
        {
            userId           => $self->UserId,
            serviceAccountNo => $self->ServiceAccountNo,
            languageCode     => $self->LanguageCode,
            userTimeZone     => $self->UserTimeZone,
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
        warn "Failed to authenticate to Apple GSX: " . $res->status_line;
        warn "Full response: " . $res->content;
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
            'unitDetail'  => { serialNumber  => $serial,
                               shipTo        => $self->ServiceAccountNo }
        }
    );

    for my $try (1..5) {
        my $res = $self->SendRequest($xml);
        unless ($res->is_success) {
            my $data = eval {$xs->parse_string( $res->decoded_content, NoAttr => 1, SuppressEmpty => undef ) };
            my $fault = $data ? $data->{"S:Body"}{"S:Fault"}{"faultstring"} : $res->status_line;
            if ($fault =~ /^The serial number entered has been marked as obsolete/) {
                # no-op
            } elsif ($fault =~ /^The serial you entered is not valid/) {
                # no-op
            } else {
                warn "Failed to get Apple GSX warranty status of serial $serial: $fault";
            }
            return;
        }

        my $ret = $self->ParseResponseXML( 'WarrantyStatus', $res->decoded_content );
        return $ret if $ret->{warrantyDetailInfo} and $ret->{warrantyDetailInfo}{serialNumber};
    }
    warn "Repeatedly failed to get complete response from Apple GSX for serial $serial";
    return;
}

sub PrepareXML {
    my $self   = shift;
    my $method = shift;
    my $args   = shift || {};

    my $xml = $xs->XMLout(
        {
            'soapenv:Body' =>
              { "glob:$method" => { "${method}Request" => $args, }, },
        },
        NoAttr   => 1,
        KeyAttr  => [],
        RootName => '',
    );
    return <<"EOF",
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
xmlns:glob="http://gsxws.apple.com/elements/global">
<soapenv:Header/>
$xml
</soapenv:Envelope>
EOF

}

sub ParseResponseXML {
    my $self   = shift;
    my $method = shift;
    my $xml    = shift;
    my $ret    = $xs->XMLin( $xml, NoAttr => 1, SuppressEmpty => undef, NSExpand => 1 );
    return $ret->{'{http://schemas.xmlsoap.org/soap/envelope/}Body'}
        ->{"{http://gsxws.apple.com/elements/global}${method}Response"}
        ->{"${method}Response"};
}

sub SendRequest {
    my $self = shift;
    my $xml  = shift;
    my $res  = $self->UserAgent->post(
        'https://gsxapi.apple.com/gsx-ws/services/am/asp',
        'Content-Type' => 'text/xml; charset=utf-8',
        Content        => $xml,
    );
    return $res;
}

1;
