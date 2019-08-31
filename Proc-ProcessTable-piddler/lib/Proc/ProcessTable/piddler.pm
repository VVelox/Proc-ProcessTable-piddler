package Proc::ProcessTable::piddler;

use 5.006;
use strict;
use warnings;
use Proc::ProcessTable;
use Text::ANSITable;
use Term::ANSIColor;
use Proc::ProcessTable::InfoString;
use Sys::MemInfo qw(totalmem freemem totalswap);
use Net::Connection::ncnetstat;

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
	my %args;
	if (defined($_[1])) {
		%args= %{$_[1]};
	}

	my $self = {
				colors=>[
						 'BRIGHT_YELLOW',
						 'BRIGHT_CYAN',
						 'BRIGHT_MAGENTA',
						 'BRIGHT_BLUE'
						 ],
				nextColor=>0,
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
				file_colors=>[
							  'BRIGHT_YELLOW',
							  'BRIGHT_CYAN',
							  'BRIGHT_MAGENTA',
							  'BRIGHT_BLUE',
							  'MAGENTA',
							  'BRIGHT_RED'
                         ],
				processColor=>'BRIGHT_RED',
				varColor=>'GREEN',
				valColor=>'WHITE',
				pidColor=>'BRIGHT_CYAN',
				cpuColor=>'BRIGHT_MAGENTA',
				memColor=>'BRIGHT_BLUE',
				zero_time=>1,
				zero_flt=>1,
				files=>1,
				idColors=>[
						   'WHITE',
						   'BRIGHT_BLUE',
						   'MAGENTA',
						   ],
				is=>Proc::ProcessTable::InfoString->new,
				colors=>[
						 'BRIGHT_YELLOW',
						 'BRIGHT_CYAN',
						 'BRIGHT_MAGENTA',
						 'BRIGHT_BLUE'
						 ],
				txt=>0,
				pipe=>0,
				unix=>0,
				vregroot=>0,
				};
    bless $self;

	my @arg_feed=(
				  'txt', 'pipe', 'unix', 'vregroot'
				   );

	foreach my $feed ( @arg_feed ){
		$self->{$feed}=$args{$feed};
	}

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

	# figure out what all keys the process table is reporting
	my @proc_keys=keys( %{ $pt->[0] } );
	my %proc_keys_hash;
	foreach my $proc_key ( @proc_keys ){
		$proc_keys_hash{$proc_key}=1;
	}
	# remove the ones we actually use
	delete( $proc_keys_hash{pctcpu} );
	delete( $proc_keys_hash{uid} );
	delete( $proc_keys_hash{pid} );
	delete( $proc_keys_hash{gid} );
	delete( $proc_keys_hash{vmsize} );
	delete( $proc_keys_hash{rss} );
	delete( $proc_keys_hash{state} );
	delete( $proc_keys_hash{wchan} );
	delete( $proc_keys_hash{cmndline} );
	delete( $proc_keys_hash{size} );
	delete( $proc_keys_hash{time} );
	if( defined( $proc_keys_hash{pctmem} ) ){
		delete( $proc_keys_hash{pctmem} );
	}
	if( defined( $proc_keys_hash{groups} ) ){
		delete( $proc_keys_hash{groups} );
	}
	if ( defined( $proc_keys_hash{cmdline} ) ){
		delete( $proc_keys_hash{cmdline} );
	}
	@proc_keys=sort(keys( %proc_keys_hash ));

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
	my $first=1;
	foreach my $proc ( @procs ){
        my $tb = Text::ANSITable->new;
        $tb->border_style('Default::none_ascii');
        $tb->color_theme('Default::no_color');
		$tb->show_header(0);
        $tb->set_column_style(0, pad => 0);
        $tb->set_column_style(1, pad => 1);
		$tb->columns( ['var','val'] );

		#
		# PID
		#
		my @data;
		push( @data, [
					  color( $self->{varColor} ).'PID'.color('reset'),
					  color( $self->{pidColor} ).$proc->pid.color('reset')
					  ]);

		#
		# UID
		#
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
					  $user.' '.color('reset')
					  ]);

		#
		# GID
		#
		my $group=getgrgid($proc->{gid});
		if ( ! defined( $group ) ) {
			$group=color( $self->{idColors}[0] ).$proc->{gid}.color('reset');
		}else{
			$group=color( $self->{idColors}[0] ).$group.
			color( $self->{idColors}[1] ).'('.
			color( $self->{idColors}[2] ).$proc->{gid}.
			color( $self->{idColors}[1] ).')'
			.color('reset');
		}

		push( @data, [
					  color( $self->{varColor} ).'GID'.color('reset'),
					  $group.' '.color('reset')
					  ]);

		#
		# Groups
		#
		if ( defined( $proc->{groups} ) ){
			my @groups;
			foreach my $current_group ( @{ $proc->{groups} } ){
				$group=getgrgid( $current_group );
				if ( ! defined( $group ) ) {
					$group=color( $self->{idColors}[0] ).$current_group.color('reset');
				}else{
					$group=color( $self->{idColors}[0] ).$group.
					color( $self->{idColors}[1] ).'('.
					color( $self->{idColors}[2] ).$current_group.
					color( $self->{idColors}[1] ).')'
					.color('reset');
				}
				push( @groups, $group );
			}

			push( @data, [
						  color( $self->{varColor} ).'Groups'.color('reset'),
						  join( ' ', @groups )
						  ]);
		}

		#
		# PCT CPU
		#
		push( @data, [
					  color( $self->{varColor} ).'CPU%'.color('reset'),
					  color( $self->{valColor} ).$proc->pctcpu.color('reset')
					  ]);

		#
		# PCT mem
		#
		my $mem;
		if ( !defined( $proc->{pctmem} ) ) {
			$mem=($proc->{rss} / totalmem)*100;
			$mem=sprintf('%.2f', $mem);
		} else {
			$mem=sprintf('%.2f', $proc->{pctmem});
		}
		push( @data, [
					  color( $self->{varColor} ).'MEM%'.color('reset'),
					  color( $self->{valColor} ).$mem.color('reset')
					  ]);

		#
		# VSZ
		#
		push( @data, [
					  color( $self->{varColor} ).'VSZ'.color('reset'),
					  $self->memString( $proc->size, 'vsz' )
					  ]);

		#
		# RSS
		#
		push( @data, [
					  color( $self->{varColor} ).'RSS'.color('reset'),
					  $self->memString( $proc->rss, 'rss' )
					  ]);

		#
		# time
		#
		push( @data, [
					  color( $self->{varColor} ).'Time'.color('reset'),
					  $self->timeString( $proc->time )
					  ]);

		#
		# info
		#
		push( @data, [
					  color( $self->{varColor} ).'Info'.color('reset'),
					  color( $self->{valColor} ).$self->{is}->info( $proc ).color('reset')
					  ]);

		#
		# misc ones...
		#
		foreach my $key ( @proc_keys ){
			if ( $proc->{$key} !~ /^$/ ){
				my $print_it=1;
				my $value;

				if (
					( $key =~ /time$/ ) &&
					( $proc->{$key} =~ /\.0*$/ ) &&
					( $self->{zero_time} )
					){
					$print_it=0;
				}elsif( $key =~ /time$/ ){
					$value=$self->timeString( $proc->{$key} );
				}

				if (
					( $key =~ /flt$/ ) &&
					( $proc->{$key} eq 0 ) &&
					( $self->{zero_flt} )
					){
					$print_it=0;
				}

				if ( $key =~ /^start$/ ){
					$value=$self->startString( $proc->{start} );
				}

				if ( !defined( $value ) ){
					$value=color( $self->{valColor} ).$proc->{$key}.color('reset');
				}

				if ( $print_it ){
					push( @data, [
								  color( $self->{varColor} ).$key.color('reset'),
								  $value,
								  ]);
				}
			}
		}

		#
		# cmndline
		#
		if ( $proc->{cmndline} !~ /^$/ ){
			push( @data, [
						  color( $self->{varColor} ).'Cmndline'.color('reset'),
						  color( $self->{processColor} ).$proc->{cmndline}.color('reset')
						  ]);
		}

		#
		# gets the open files
		#
		my $open_files='';
		my $pid=$proc->pid;
		my $output_raw=`lsof -n -l -P -p $pid`;
		if (
			( $? eq 0 ) ||
			(
			 ( $^O =~ /linux/ ) &&
			 ( $? eq 256 )
			 )
			){

			my $ftb = Text::ANSITable->new;
			$ftb->border_style('Default::none_ascii');
			$ftb->color_theme('Default::no_color');
			$ftb->show_header(1);
			$ftb->set_column_style(0, pad => 0);
			$ftb->set_column_style(1, pad => 1);
			$ftb->set_column_style(2, pad => 0);
			$ftb->set_column_style(3, pad => 1);
			$ftb->set_column_style(4, pad => 0);
			$ftb->columns([
						   color( $self->{varColor} ).'FD'.color('reset'),
						   color( $self->{varColor} ).'TYPE'.color('reset'),
						   color( $self->{varColor} ).'DEVICE'.color('reset'),
						   color( $self->{varColor} ).'SIZE/OFF'.color('reset'),
						   color( $self->{varColor} ).'NODE'.color('reset'),
						   color( $self->{varColor} ).'NAME'.color('reset')
						 ]);

			my @fdata;

			my @lines=split(/\n/, $output_raw);
			my $line_int=1;
			while ( defined( $lines[$line_int] ) ){
				my $line=substr $lines[$line_int], 10;
				my @line_split=split(/[\ \t]+/, $line );

				if ( !defined( $line_split[7] )){
					$line_split[7]='';
				}

				# checks if it is a line we don't want
				my $dont_add=0;
				if (
					# IP stuff... handled by ncnetstat
					( $line_split[3] =~ /^IPv/ ) ||
					# library... spammy... only print if asked
					(
					 ( $line_split[2] =~ /^txt$/ ) &&
					 ( ! $self->{txt} )
					 ) ||
					# pipe... spammy... only print if asked
					(
					 ( $line_split[3] =~ /^[Pp][Ii][Pp][Ee]$/ ) &&
					 ( ! $self->{pipe} )
					 ) ||
					# unix... spammy... only print if asked
					(
					 ( $line_split[3] =~ /^[Uu][Nn][Ii][Xx]$/ ) &&
					 ( ! $self->{unix} )
					 ) ||
					# vreg /....can by spammy with somethings like firefox
					(
					 ( $line_split[3] =~ /^[Vv][Rr][Ee][Gg]$/ ) &&
					 ( $line_split[7] =~ /^\/$/ ) &&
					 ( ! $self->{vregroot} )
					 )
					){
					$dont_add=1;
				}

				if ( ! $dont_add ){
					push( @fdata, [
								   color( $self->{file_colors}[0] ).$line_split[2].color( 'reset' ),
								   color( $self->{file_colors}[1] ).$line_split[3].color( 'reset' ),
								   color( $self->{file_colors}[2] ).$line_split[4].color( 'reset' ),
								   color( $self->{file_colors}[3] ).$line_split[5].color( 'reset' ),
								   color( $self->{file_colors}[4] ).$line_split[6].color( 'reset' ),
								   color( $self->{file_colors}[5] ).$line_split[7].color( 'reset' ),
								   ]);
				}

				$line_int++;
			}

			$ftb->add_rows( \@fdata );
			$open_files=$ftb->draw;
		}

		#
		# handle the netconnection
		#
		my $netstat='';
		my @filters=(
					 {
					  type=>'PID',
					  invert=>0,
					  args=>{
							 pids=>[$proc->pid],
							 }
					  }
					 );
		my $ncnetstat=Net::Connection::ncnetstat->new(
													  {
													   ptr=>1,
													   command=>0,
													   command_long=>0,
													   wchan=>0,
													   pct_show=>0,
													   no_pid_user=>1,
													   match=>{
															   checks=>\@filters,
															   }
													   }
													  );
		$netstat=$ncnetstat->run;


		#
		# adds the new item
		#
		$tb->add_rows( \@data );
		if ( $first ){
			$first=0;
			$toReturn=$toReturn.$tb->draw.$open_files.$netstat;
		}else{
			$toReturn=$toReturn.$open_files."\n\n".$tb->draw;
		}
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
	#$seconds=sprintf('%.f',$seconds);

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

=head2 startString

Generates a short time string based on the supplied unix time.

=cut

sub startString{
	my $self=$_[0];
	my $startTime=$_[1];

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($startTime);
	my ($csec,$cmin,$chour,$cmday,$cmon,$cyear,$cwday,$cyday,$cisdst) = localtime(time);

	#add the required stuff to make this sane
	$year += 1900;
	$cyear += 1900;
	$mon += 1;
	$cmon += 1;

	#find the most common one and return it
	if ( $year ne $cyear ) {
		return $year.sprintf('%02d', $mon).sprintf('%02d', $mday).'-'.sprintf('%02d', $hour).':'.sprintf('%02d', $min);
	}
	if ( $mon ne $cmon ) {
		return sprintf('%02d', $mon).sprintf('%02d', $mday).'-'.sprintf('%02d', $hour).':'.sprintf('%02d', $min);
	}
	if ( $mday ne $cmday ) {
		return sprintf('%02d', $mday).'-'.sprintf('%02d', $hour).':'.sprintf('%02d', $min);
	}

	#just return this for anything less
	return sprintf('%02d', $hour).':'.sprintf('%02d', $min);
}

=head2 nextColor

Returns the next color.

=cut

sub nextColor{
	my $self=$_[0];

	my $color;

	if ( defined( $self->{colors}[ $self->{nextColor} ] ) ) {
		$color=$self->{colors}[ $self->{nextColor} ];
		$self->{nextColor}++;
	} else {
		$self->{nextColor}=0;
		$color=$self->{colors}[ $self->{nextColor} ];
		$self->{nextColor}++;
	}

	return $color;
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
