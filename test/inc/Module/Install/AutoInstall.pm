#line 1
package Module::Install::AutoInstall;

use strict;
use Module::Install::Base ();

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '0.91';
	@ISA     = 'Module::Install::Base';
	$ISCORE  = 1;
}

sub AutoInstall { $_[0] }

sub run {
    my $self = shift;
    $self->auto_install_now(@_);
}

sub write {
    my $self = shift;
    $self->auto_install(@_);
}

sub auto_install {
    my $self = shift;
    return if $self->{done}++;

    # Flatten array of arrays into a single array
    my @core = map @$_, map @$_, grep ref,
               $self->build_requires, $self->requires;

    my @config = @_;

    # We'll need Module::AutoInstall
    $self->include('Module::AutoInstall');
    require Module::AutoInstall;

    Module::AutoInstall->import(
        (@config ? (-config => \@config) : ()),
        (@core   ? (-core   => \@core)   : ()),
        $self->features,
    );

    $self->makemaker_args( Module::AutoInstall::_make_args() );

    my $class = ref($self);
    $self->postamble(
        "# --- $class section:\n" .
        Module::AutoInstall::postamble()
    );
}

sub auto_install_now {
    my $self = shift;
    $self->auto_install(@_);
    Module::AutoInstall::do_install();
}

1;
