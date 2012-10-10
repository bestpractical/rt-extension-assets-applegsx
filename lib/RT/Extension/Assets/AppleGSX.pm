use strict;
use warnings;
package RT::Extension::Assets::AppleGSX;

our $VERSION = '0.01';

my $client;

sub InitClient {
    my $class = shift;
    require RT::Extension::Assets::AppleGSX::Client;
    $client =
      RT::Extension::Assets::AppleGSX::Client->new(
        RT->Config->Get('AppleGSXOptions'),
      );
}

sub Client {
    InitClient() unless $client;
    return $client;
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

Only run this the first time you install this module.

If you run this twice, you may end up with duplicate data
in your database.

If you are upgrading this module, check for upgrading instructions
in case changes need to be made to your database.

=item Edit your /opt/rt4/etc/RT_SiteConfig.pm

Add this line:

    Set(@Plugins, qw(RT::Extension::Assets::AppleGSX));

or add C<RT::Extension::Assets::AppleGSX> to your existing C<@Plugins> line.

Config Apple GSX:

    Set(
        %AppleGSXOptions,
        UserId           => 'foo@example.com',
        Password         => 'secret',
        ServiceAccountNo => 12345,
    );

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=back

=head1 AUTHOR

sunnavy <sunnavy@bestpractical.com>

=head1 BUGS

All bugs should be reported via
L<http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-Assets-AppleGSX>
or L<bug-RT-Extension-Assets-AppleGSX@rt.cpan.org>.


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2012 by Best Practical Solutions

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
