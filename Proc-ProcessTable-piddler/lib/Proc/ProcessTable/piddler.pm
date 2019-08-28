package Proc::ProcessTable::piddler;

use 5.006;
use strict;
use warnings;
use Proc::ProcessTable;
use Text::ANSITable;
use Term::ANSIColor;


=head1 NAME

Proc::ProcessTable::piddler - 

=head1 VERSION

Version 0.0.0

=cut

our $VERSION = '0.0.0';


=head1 SYNOPSIS

    use Proc::ProcessTable::piddler;

    my $piddler = Proc::ProcessTable::piddler->new();
    ...

=head1 METHODS

=sub new

Initiates the object.

    my $piddler = Proc::ProcessTable::piddler->new();

=cut

sub new{
	my $self = {
				colors=>[
						 'BRIGHT_YELLOW',
						 'BRIGHT_CYAN',
						 'BRIGHT_MAGENTA',
						 'BRIGHT_BLUE'
						 ],
				timeColors=>[
							 'GREEN',
							 'BRIGHT_GREEN',
							 'RED',
							 'BRIGHT_RED'
							 ],
				vszColors=>[
							'GREEN',
							'YELLOW',
							'RED',
							'BRIGHT_BLUE'
							],
				rssColors=>[
							'BRIGHT_GREEN',
							'BRIGHT_YELLOW',
							'BRIGHT_RED',
							'BRIGHT_BLUE'
							],
				processColor=>'BRIGHT_RED',
				varColor=>'GREEN',
				valColor=>'WHITE',
				pidColor=>'BRIGHT_CYAN',
				cpuColor=>'BRIGHT_MAGENTA',
				memColor=>'BRIGHT_BLUE',
				idColors=>[
							  'WHITE',
							  'BRIGHT_BLUE',
							  'MAGENTA',
							  ],
				};
    bless $self;

	return $self;
}

=head2 run

=cut

sub run{
	my $self=$_[0];
	my @pids;
	if (defined($_[1])) {
		@pids= @{$_[1]};
	}

	if ( ! defined( $pids[0] ) ){
		return '';
	}

	my %pids_hash;
	foreach my $pid ( @pids ){
		$pids_hash{$pid}=$pid;
	}

	my $p = Proc::ProcessTable->new;
	my $pt = $p->table;

	my @proc_keys=keys( %{ $pt->[0] } );
	my %proc_keys_hash;
	foreach my $proc_key ( @proc_keys ){
		$proc_keys_hash{$proc_key}=1;
	}
	delete( $proc_keys_hash{pctcpu} );
	delete( $proc_keys_hash{uid} );
	delete( $proc_keys_hash{pid} );

	my @procs;
	foreach my $proc ( @{ $pt } ){
		if ( defined( $pids_hash{ $proc->pid } ) ){
			push( @procs, $proc );
		}
	}

	if (!defined( $procs[0] )){
		return ''
	}

	my $toReturn='';

	foreach my $proc ( @procs ){
        my $tb = Text::ANSITable->new;
        $tb->border_style('Default::none_ascii');
        $tb->color_theme('Default::no_color');
		$tb->show_header(0);
        $tb->set_column_style(0, pad => 0);
        $tb->set_column_style(1, pad => 1);

		my @data;
		push( @data, [
					  color( $self->{varColor} ).'PID'.color('reset'),
					  color( $self->{pidColor} ).$proc->pid.color('reset')
					  ]);


		my $user=getpwuid($proc->{uid});
		if ( ! defined( $user ) ) {
			$user=color( $self->{idColors}[0] ).$proc->{uid}.color('reset');
		}else{
			$user=color( $self->{idColors}[0] ).$user.
			color( $self->{idColors}[1] ).'('.
			color( $self->{idColors}[2] ).$proc->{uid}.
			color( $self->{idColors}[1] ).')'
			.color('reset');
		}

		push( @data, [
					  color( $self->{varColor} ).'UID'.color('reset'),
					  color( $self->{pidColor} ).$user.color('reset')
					  ]);


		push( @data, [
					  color( $self->{varColor} ).'CPU%'.color('reset'),
					  color( $self->{pidColor} ).$proc->pctcpu.color('reset')
					  ]);
	}

	return $toReturn;
}

=head2 timeString

Turns the raw run string into something usable.

=cut

sub timeString{
	my $self=$_[0];
	my $time=$_[1];

	if ( $^O =~ /^linux$/ ) {
		$time=$time/1000000;
	}

	my $hours=0;
	if ( $time >= 3600 ) {
		$hours = $time / 3600;
	}
	my $loSeconds = $time % 3600;
	my $minutes=0;
	if ( $time >= 60 ) {
		$minutes = $loSeconds / 60;
	}
	my $seconds = $loSeconds % 60;

	#nicely format it
	$hours=~s/\..*//;
	$minutes=~s/\..*//;
	$seconds=sprintf('%.f',$seconds);

	#this will be returned
	my $toReturn='';

	#process the hours bit
	if ( $hours == 0 ) {
		#don't do anything if time is 0
	} elsif (
			 $hours >= 10
			 ) {
		$toReturn=color($self->{timeColors}->[3]).$hours.':';
	} else {
		$toReturn=color($self->{timeColors}->[2]).$hours.':';
	}

	#process the minutes bit
	if (
		( $hours > 0 ) ||
		( $minutes > 0 )
		) {
		$toReturn=$toReturn.color( $self->{timeColors}->[1] ). $minutes.':';
	}

	$toReturn=$toReturn.color( $self->{timeColors}->[0] ).$seconds.color('reset');

	return $toReturn;
}

=head2 memString

Turns the raw run string into something usable.

=cut

sub memString{
	my $self=$_[0];
	my $mem=$_[1];
	my $type=$_[2];

	my $toReturn='';

	if ( $mem < '10000' ) {
		$toReturn=color( $self->{$type.'Colors'}[0] ).$mem;
	} elsif (
			 ( $mem >= '10000' ) &&
			 ( $mem < '1000000' )
			 ) {
		$mem=$mem/1000;

		$toReturn=color( $self->{$type.'Colors'}[0] ).$mem.
		color( $self->{$type.'Colors'}[3] ).'k';
	} elsif (
			 ( $mem >= '1000000' ) &&
			 ( $mem < '1000000000' )
			 ) {
		$mem=($mem/1000)/1000;
		$mem=sprintf('%.3f', $mem);
		my @mem_split=split(/\./, $mem);

		$toReturn=color( $self->{$type.'Colors'}[1] ).$mem_split[0].'.'.color( $self->{$type.'Colors'}[0] ).$mem_split[1].
		color( $self->{$type.'Colors'}[3] ).'M';
	} elsif ( $mem >= '1000000000' ) {
		$mem=(($mem/1000)/1000)/1000;
		$mem=sprintf('%.3f', $mem);
		my @mem_split=split(/\./, $mem);

		$toReturn=color( $self->{$type.'Colors'}[2] ).$mem_split[0].'.'.color( $self->{$type.'Colors'}[1] ).$mem_split[1].
		color( $self->{$type.'Colors'}[3] ).'G';
	}

	return $toReturn.color('reset');
}


=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-proc-processtable-piddler at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Proc-ProcessTable-piddler>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Proc::ProcessTable::piddler


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Proc-ProcessTable-piddler>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Proc-ProcessTable-piddler>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/Proc-ProcessTable-piddler>

=item * Search CPAN

L<https://metacpan.org/release/Proc-ProcessTable-piddler>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2019 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1; # End of Proc::ProcessTable::piddler
