use strict;
use warnings;
package RT::Extension::Assets::AppleGSX;
use RT::Extension::Assets::AppleGSX::Client;

our $VERSION = '0.02';

sub Client {
    my $config = RT->System->FirstAttribute('AppleGSXOptions');
    return
        RT::Extension::Assets::AppleGSX::Client->new(
            $config ? $config->Content : {},
        );
}

=head1 NAME

RT-Extension-Assets-AppleGSX - Apple GSX for RT Assets

=head1 INSTALLATION

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

=item Add additional configuration options

You must configure the authentication information used to connect to GSX
via the web UI, at Tools -> Configuration -> Assets -> Apple GSX.  This
menu option is only available to SuperUsers.

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


=item Run F</opt/rt4-assets/local/plugins/RT-Extension-Assets-AppleGSX/bin/rt-apple-gsx-set-warranty>

You will likely wish to configure this script to run regularly, via a cron job.

=head1 AUTHOR

sunnavy <sunnavy@bestpractical.com>

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
