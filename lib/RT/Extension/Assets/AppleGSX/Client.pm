use strict;
use warnings;

package RT::Extension::Assets::AppleGSX::Client;

use Net::SSL;
use LWP::UserAgent;

use JSON;
use Data::Dumper;
use LWP::ConsoleLogger::Easy qw( debug_ua );

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(
    qw/UserAgent ActivationToken AuthenticationToken UserId UserTimeZone
      ServiceAccountNo LanguageCode CertFilePath KeyFilePath AppleGSXApiBase/
);

sub new {
    my $class = shift;
    my $args  = ref $_[0] eq 'HASH' ? shift @_ : {@_};
    my $self  = $class->SUPER::new($args);

    $ENV{HTTPS_CERT_FILE} = $self->CertFilePath;

    if ( -r $ENV{HTTPS_CERT_FILE} ) {
        RT->Logger->debug("RT can read HTTPS_CERT_FILE: " . $ENV{HTTPS_CERT_FILE});
    }
    else {
        RT->Logger->debug("RT *cannot* read HTTPS_CERT_FILE: " . $ENV{HTTPS_CERT_FILE});
    }

    $ENV{HTTPS_KEY_FILE} = $self->KeyFilePath;

    if ( -r $ENV{HTTPS_KEY_FILE} ) {
        RT->Logger->debug("RT can read HTTPS_KEY_FILE: " . $ENV{HTTPS_KEY_FILE});
    }
    else {
        RT->Logger->debug("RT *cannot* read HTTPS_KEY_FILE: " . $ENV{HTTPS_KEY_FILE});
    }

    my $store_code = sprintf( "%010d", $self->ServiceAccountNo);

    $self->UserAgent( LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 }) ) unless $self->UserAgent;
    my $default_headers = HTTP::Headers->new(
        'X-Apple-SoldTo' => $store_code,
        'X-Apple-ShipTo' => $store_code,
        'X-Apple-Service-Version' => 'v2',
    );
    $self->UserAgent->default_headers( $default_headers );

    # by default use the testing (-uat) URLs for both the API and getting the initial token
    $self->{AppleGSXApiBase}  ||= 'https://partner-connect-uat.apple.com/gsx/api';
    $self->{AppleGSXGetToken} ||= 'https://gsx2-uat.apple.com/gsx/api/login';
    debug_ua($self->UserAgent);
    return $self;
}

# may need a name change, this does not authenticate, but just checks that the API is accessible
sub Authenticate {
    my $self = shift;

    my %headers = ( Accept => 'text/plain' );
    RT->Logger->debug("Calling GSX /authenticate/check with headers: " . $self->UserAgent->default_headers->as_string . " and " . Dumper(\%headers));
    my $res = $self->UserAgent->get( $self->AppleGSXApiBase . "/authenticate/check", %headers );
    if ( $res->is_success ) {
        return 1;
    }
    else {
        RT->Logger->error( "Failed to authenticate to Apple GSX: " . $res->status_line );
        my $string = $res->decoded_content;
        RT->Logger->debug("Response content is: $string");
        return;
    }
}

sub WarrantyStatus {
    my $self = shift;
    my $serial = shift or return;

    my( $ret, $msg, $device )= $self->GetDataForSerial( $serial );
    if( ! $ret ) {
        return( 0, $msg, undef);
    }
    if( ! $device->{warrantyInfo} ) {
        RT->Logger->warning( "no warantyInfo returned (for sn $serial)" );
        return( 0, "no warantyInfo returned" );
    }
    return ( 1, '', $device->{warrantyInfo});
}

sub GetDataForSerial {
    my $self = shift;
    my $serial = shift or return;

    my $token = $self->AuthenticationToken;

    my %headers = (
        'X-Apple-Auth-Token' => $token,
        'Content-Type'       => 'application/json',
        'Accept'             => 'application/json',
    );

    my $args = { "device" => { "id" => $serial } };
    my $json = encode_json( $args );
    my $response;

    # only try if we have a token, otherwise we need to get one first
    if( $token) {
        $response = $self->UserAgent->post( $self->AppleGSXApiBase . "/repair/product/details", Content => $json, %headers );
    }

    if( ! $token || $response->code == 401 ) {
        my( $ret, $msg, $new_token );
        if( $token ) {
            ( $ret, $msg, $new_token )= $self->get_new_authentication_token( $token );
        }
        if( ! $token || ! $ret) {
            ( $ret, $msg, $new_token)= $self->get_new_authentication_token( $self->ActivationToken );
        }

        if( $ret) {
            RT->Logger->debug( "got new authentication token");
            $headers{'X-Apple-Auth-Token'} = $new_token;
            $response = $self->UserAgent->post( $self->AppleGSXApiBase . "/repair/product/details", Content => $json, %headers);
        }
        else {
            return ( 0, "error connecting to the GSX API: $msg", undef);
        }
    }

    if( $response->is_success ) {
        my $product_details = decode_json( $response->decoded_content );
        my $device = $product_details->{device};

        # we set a couple of fields that were named differently in the old API, so old code still workd
        # old warrantyStatus is new warrantyStatusDescription
        $device->{warrantyInfo}->{warrantyStatus} = $device->{warrantyInfo}->{warrantyStatusDescription};
        # old estimatedPurchaseDate is new purchaseDate (in warrantyInfo)
        $device->{estimatedPurchaseDate} = $device->{warrantyInfo}->{purchaseDate};

        return( 1, '', $device);
    }
    else {
        RT->Logger->warning( "Failed to get response from Apple GSX for serial $serial" );
        return( 0, "Failed to get response from Apple GSX for serial $serial" );
    }
}

sub get_new_authentication_token {
    my $self = shift;
    my $old_token= shift;

    my $data = { userAppleId => $self->UserId, authToken => $old_token };
    my $json = encode_json( $data);
    my %headers = (
        'Content-Type' => 'application/json',
        Accept => 'application/json',
    );
    my $response = $self->UserAgent->post( $self->AppleGSXApiBase . "/authenticate/token", Content => $json, %headers );
    if( $response->code == 200 ) {
        my $json_string = $response->decoded_content;
        my $response_json = decode_json( $json_string);

        my $new_authentication_token = $response_json->{authToken};

        $self->AuthenticationToken( $new_authentication_token);

        # save the token in the AppleGSXOptions attribute
        my $config= RT->System->FirstAttribute('AppleGSXOptions');
        my $content = $config->Content;
        $content->{AuthenticationToken} = $new_authentication_token;
        # $config->SetContent( $content);
        RT->System->SetAttribute( Name => 'AppleGSXOptions', Content => $content );

        return ( 1, '', $new_authentication_token);
    }
    else {
        RT->Logger->error( "Failed to get authentication token" );
        return( 0, "cannot get authentication token: " . $response->code, undef);
    }
}

1;
