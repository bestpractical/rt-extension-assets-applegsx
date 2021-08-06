use strict;
use warnings;
package RT::Extension::Assets::AppleGSX;
use RT::Extension::Assets::AppleGSX::Client;

our $VERSION = '2.03';

my $CLIENT;
my $CLIENT_CACHE;
sub Client {
    my $config = RT->System->FirstAttribute('AppleGSXOptions');
    undef $CLIENT
        if $CLIENT_CACHE and $config and $config->LastUpdatedObj->Unix > $CLIENT_CACHE;

    unless ($CLIENT) {
        $CLIENT = RT::Extension::Assets::AppleGSX::Client->new(
            $config ? $config->Content : {},
        );
        $CLIENT_CACHE = $config ? $config->LastUpdatedObj->Unix : -1;
    }
    return $CLIENT;
}

sub SerialCF {
    return RT->Config->Get('AppleGSXSerialCF') || "Serial Number";
}

sub Fields {
    return RT->Config->Get('AppleGSXMap') || {
        'Warranty Status'     => 'warrantyStatusCode',
        'Warranty Start Date' => 'coverageStartDate',
        'Warranty End Date'   => 'coverageEndDate',
    };
}

sub Checks {
    return RT->Config->Get('AppleGSXChecks') || {
        'Trademark' => qr/\bApple(Care)?\b/i,
    }
}

{
    my $old_create = \&RT::Asset::Create;
    no warnings 'redefine';
    *RT::Asset::Create = sub {
        my $self = shift;
        my @ret = $old_create->($self, @_);
        return @ret unless $ret[0] and $self->GSXApplies;

        my ($ok, @extra) = $self->UpdateGSX;
        push @ret, @extra unless $ok;
        return @ret;
    };
}

package RT::Asset;

sub GSXApplies {
    my $self = shift;
    my $CHECKS = RT::Extension::Assets::AppleGSX->Checks;

    for my $check (keys %$CHECKS) {
        next unless $self->LoadCustomFieldByIdentifier( $check )->id;
        my $value = $self->FirstCustomFieldValue($check);
        return 1 if defined $value and $value =~ /$CHECKS->{$check}/;
    }
    return 0;
}

sub UpdateGSX {
    my $self = shift;

    my $serial_name = RT::Extension::Assets::AppleGSX->SerialCF;
    my $FIELDS_MAP = RT::Extension::Assets::AppleGSX->Fields;
    my $CHECKS = RT::Extension::Assets::AppleGSX->Checks;

    return (0, "GSX does not apply (check ".join(", ",sort keys %$CHECKS)."?)")
        unless $self->GSXApplies;

    RT::Extension::Assets::AppleGSX->Client;

    return (0, "Apple GSX authentication failed; cannot import data")
        unless $CLIENT->Authenticate;

    if ( my $serial = $self->FirstCustomFieldValue( $serial_name ) ) {
        my( $ret, $msg, $device ) = $CLIENT->GetDataForSerial( $serial );
        if( ! $ret ) {
            return (0, $msg)
        }

        my @results;
        for my $field ( keys %$FIELDS_MAP ) {
            my $old = $self->FirstCustomFieldValue($field);
            # data is either at device level or in $device->{warrantyInfo}
            # the old mapping doesn't know about those 2 levels so we look in both places
            my $new = $device->{ $FIELDS_MAP->{$field} } || $device->{warrantyInfo}{ $FIELDS_MAP->{$field} };
            if ( defined $new ) {
                # Canonicalize date and datetime CFs
                if ($self->LoadCustomFieldByIdentifier($field)->Type =~ /^date(time)?/i) {
                    my $datetime = $1;
                    my $date = RT::Date->new( RT->SystemUser );
                    $date->Set( Format => 'unknown', Value => $new );
                    $new = $datetime ? $date->DateTime : $date->Date;
                }
                $old = '' unless defined $old;
                if ($old ne $new) {
                    my ($ok, $msg) = $self->AddCustomFieldValue(
                        Field => $field,
                        Value => $new,
                    );
                    push @results, $msg;
                }
            } elsif (defined $old) {
                my ($ok, $msg) = $self->DeleteCustomFieldValue(
                    Field => $field,
                    Value => $old,
                );
                push @results, $msg;
            }
        }

        return (1, @results);
    }
    else {
        my @results;
        for my $field ( keys %$FIELDS_MAP ) {
            my $old = $self->FirstCustomFieldValue($field);
            if ( defined $old ) {
                my ($ok, $msg) = $self->DeleteCustomFieldValue(
                    Field => $field,
                    Value => $old,
                );
                push @results, $msg;
            }
        }
        return (1, @results);
    }
}

=head1 NAME

RT-Extension-Assets-AppleGSX - Apple GSX for RT Assets

=head1 INSTALLATION

Note that starting with version 2 of this extension, it works only
with the Apple GSX API version 2.

=over

=item perl Makefile.PL

=item make

=item make install

May need root permissions

=item make initdb

Only run this the first time you install this module; this will create
several custom fields for assets.  If you already have custom fields for
serial numbers and warantee information, this step is unnecessary.

Running C<make initdb> twice will cause duplicate custom fields.

=item Edit your /opt/rt4/etc/RT_SiteConfig.pm

Add this line:

    Set(@Plugins, qw(RT::Extension::Assets::AppleGSX));

or add C<RT::Extension::Assets::AppleGSX> to your existing C<@Plugins> line.

=item Add configuration options to C<RT_SiteConfig.pm>

See L<CONFIGURATION> below for options.

=item Run F</opt/rt4-assets/local/plugins/RT-Extension-Assets-AppleGSX/bin/rt-apple-gsx-set-warranty>

You will likely wish to configure this script to run regularly, via a cron job.

=back

=head1 CONFIGURATION

To connect to Apple's GSX service, you must first contact Apple to
create an account. Once you have an account with a user ID and service
account number, you must then get certificate and key files from Apple
and your server IP addresses must be whitelisted by Apple.

The configuration for the service uses the following variables:

    # test server
    Set( $AppleGSXApiBase,  'https://partner-connect-uat.apple.com');
    Set( $AppleGSXGetToken, 'https://gsx2-uat.apple.com/gsx/api/login');

or

    # production server
    Set( $AppleGSXApiBase,  'https://partner-connect.apple.com');
    Set( $AppleGSXGetToken, 'https://gsx2.apple.com/gsx/api/login');

Once you have done this, you can configure the authentication information
used to connect to GSX via the web UI, at Tools -> Configuration ->
Assets -> Apple GSX. This menu option is only available to SuperUsers.
Depending on the services you are using, the RT webserver user and
the user running any cron jobs will need read access to the certificate
and key files on your server.

Additionally, if you are not using the supplied custom fields, you may
wish to Set one or more of the following in your F<RT_SiteConfig.pm>
(their defaults are shown):

    # Name of custom field containing serial number
    Set( $AppleGSXSerialCF => "Serial Number" )

    # CFs to import from GSX, and their names there
    Set( %AppleGSXMap,
        'Warranty Status'     => 'warrantyStatus',
        'Warranty Start Date' => 'coverageStartDate',
        'Warranty End Date'   => 'coverageEndDate',
    );

    # Only attempt to import data from GSX for assets matching the
    # following CF values:
    Set( %AppleGSXChecks,
        'Trademark' => qr/\bApple(Care)?\b/i,
    );

=head1 AUTHOR

Best Practical Solutions <modules@bestpractical.com>

=head1 BUGS

All bugs should be reported via
L<http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-Assets-AppleGSX>
or L<bug-RT-Extension-Assets-AppleGSX@rt.cpan.org>.


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2013 by Best Practical Solutions

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
