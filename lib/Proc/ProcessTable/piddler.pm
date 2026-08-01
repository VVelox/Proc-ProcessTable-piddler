package Proc::ProcessTable::piddler;

use 5.006;
use strict;
use warnings;
use Proc::ProcessTable;
use Text::ANSITable;
use Term::ANSIColor;
use Proc::ProcessTable::InfoString;
use Sys::MemInfo qw(totalmem);
use Net::Connection::ncnetstat;

=head1 NAME

Proc::ProcessTable::piddler - Display all process table, open files, and network connections for a PID.

=head1 VERSION

Version 0.3.0

=cut

our $VERSION = '0.3.0';


=head1 SYNOPSIS

    use Proc::ProcessTable::piddler;

    # skip over the less useful stuff for less spammy output
    my $args={
              txt=>0,
              unix=>0,
              pipe=>0,
              fifo=>0,
              vregroot=>0,
              dont_dedup=>0,
              dont_resolv=>0,
              };

    my $piddler = Proc::ProcessTable::piddler->new( $args );

    print $piddler->run( [ 0, 1432 ] );

=head1 METHODS

=head2 new

Initiates the object.

One argument is taken and that is a option hash reference
of options.

    my $args={
              txt=>0,
              unix=>0,
              pipe=>0,
              fifo=>0,
              vregroot=>0,
              dont_dedup=>0,
              dont_resolv=>0,
              };

    my $piddler = Proc::ProcessTable::piddler->new( $args );

=head3 args hash

=head4 a_inode

Print a_inode types.

Defaults to 0, false.

=head4 dont_dedup

Don't dedup the file descriptor list.

When deduping a list it checks if a file is open in
rw, r, or w, only showing it once for any of those modes.
Any file with more than one open FD of that mode will have
+ appended to the value in the FD column.

The modes below are all also RW and considered that.

    u
    ur
    uw

Defaults to 0, false.

=head4 dont_resolv

Don't resolve PTR addresses.

Defaults to 0, false.

=head4 fifo

Print FIFOs.

Defaults to 1, true.

=head4 memreglib

Print memory mapped libraries that are of the type REG.

The following are used to match libraries.

    /\.so$/
    /\.so\.[0-9]+$/
    /\.so\.[0-9]+\.[0-9]+$/
    /\.so\.[0-9]+\.[0-9]+\.[0-9]+$/
    /\.jar$/

Defaults to 0, false.

=head4 peers

For each pipe, FIFO, and unix socket printed, show the command holding
the far end of it.

    FD  TYPE DEVICE             SIZE/OFF NODE      NAME
    7u  unix 0xfffff80022630400 0                  ->0xfffff80022635000 (dbus-daemon --session(51092))
    14u unix 0xfffff80052dee800 0                  /tmp/dbus-nWRW4XDDoD (xfce4-panel(63471))
    3r  FIFO 0,230              0t0      299839014 /tmp/testfifo (cat(12593))

The far end is found either by way of the endpoint this one points at,
by way of whatever points at this one, or by way of what else has the
same one open. The second is what covers the unix sockets lsof names
after the path they are bound to, such as the accepted end of a
connection, and the third the FIFOs and, on Linux, pipes that both ends
share a inode for.

Commands longer than 40 characters are truncated. A endpoint whose far
end can not be looked up, such as one held by another user's process when
not running as root, is shown as a ?. Nothing is shown for one that has
no far end to speak of, such as a unix socket that is only bound and
listening or a FIFO no one else has open. A endpoint may be held by more
than one process, such as after a fork, in which case all of them are
listed.

Tying the two ends together requires a system wide lsof, so it is only
run when a pipe, FIFO, or unix socket is actually going to be printed,
meaning turning L</pipe>, L</fifo>, and L</unix> all off turns this off
as well, and only once per call to run.

Unix sockets are only tied together on systems whose lsof points at the
far end of one, such as FreeBSD.

Defaults to 1, true.

=head4 pipe

Print pipes.

Defaults to 1, true.

=head4 pipe_chains

Print the pipelines the process is a part of, showing the commands in
the order the data flows through them, oldest to newest.

    PIPE CHAINS
    ps auxw(4821) | grep foo(4822) | wc -l(4823)

Commands longer than 40 characters are truncated. Any process that can
not be looked up, such as one belonging to another user when not running
as root, is shown as a ?. A process may sit on more than one pipe, so at
most 16 chains are shown for any one of them.

Tying the two ends of a pipe together requires a system wide lsof, so it
is only run for processes that actually have a pipe open, and only once
per call to run.

The direction of a pipe is taken from the r and w access characters when
lsof reports them. Systems such as FreeBSD report pipes as being open
read/write instead, in which case the descriptor number is used, 0 being
the input and 1 and 2 being the output. On those systems that means only
pipes on stdin, stdout, and stderr may be chained together.

Defaults to 1, true.

=head4 txt

Print the linked libraries used by the binary.

Defaults to 0, false.

=head4 unix

Print unix sockets.

Defaults to 1, true.

=head4 vregroot

Show VREG entries for /.

Defaults to 0, false.

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
				environ=>'BRIGHT_MAGENTA',
				txt=>0,
				pipe=>1,
				unix=>1,
				vregroot=>0,
				dont_dedup=>0,
				dont_resolv=>0,
				fifo=>1,
				a_inode=>0,
				memreglib=>0,
				pipe_chains=>1,
				peers=>1,
				peer_command_length=>40,
				pipe_chain_max=>16,
				pipe_chain_max_depth=>32,
				};
    bless $self;

	my @arg_feed=(
				  'txt', 'pipe', 'unix', 'vregroot', 'dont_dedup', 'dont_resolv',
				  'fifo', 'a_inode', 'memreglib', 'pipe_chains', 'peers'
				   );

	foreach my $feed ( @arg_feed ){
		if ( defined( $args{$feed} ) ){
			$self->{$feed}=$args{$feed};
		}
	}

	return $self;
}

=head2 run

This runs it and returns a string.

One option is taken and that is a array ref of PIDs
to do.

    print $piddler->run( [ 0, 1432 ] );

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

	if ( !defined( $pt->[0] ) ){
		return '';
	}

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

	# the endpoints are only good for as long as the processes holding
	# them are, so the caches do not outlive the run they were built for
	$self->{all_files}=undef;
	$self->{pipe_endpoints}=undef;
	$self->{peer_pids}=undef;

	# what the PIDs in a pipe chain or on the far end of a endpoint get
	# printed as
	my %commands;
	if (
		( $self->{pipe_chains} ) ||
		( $self->{peers} )
		){
		foreach my $current_proc ( @{ $pt } ){
			my $command;
			if (
				( defined( $current_proc->{cmndline} ) ) &&
				( $current_proc->{cmndline} !~ /^[\ \t]*$/ )
				){
				$command=$current_proc->{cmndline};
			}elsif ( defined( $current_proc->{fname} ) ){
				$command=$current_proc->{fname};
			}
			if ( defined( $command ) ){
				# a command line may contain newlines and the like, which
				# would tear apart the single line a chain is printed on
				$command=~s/\s+/ /g;
				$command=~s/^\s+//;
				$command=~s/\s+$//;
				$commands{ $current_proc->pid }=$command;
			}
		}
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
			my $total_mem=totalmem;
			if ( $total_mem > 0 ){
				$mem=($proc->{rss} / $total_mem)*100;
			}else{
				$mem=0;
			}
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
			if (
				( defined( $proc->{$key} ) ) &&
				( $proc->{$key} !~ /^$/ )
				){
				my $print_it=1;
				my $value;

				# anything that is entirely zero, be it 0, 0.0, or the like
				my $is_zero=0;
				if (
					( $proc->{$key} =~ /^[0-9]+(\.[0-9]+)?$/ ) &&
					( $proc->{$key} == 0 )
					){
					$is_zero=1;
				}

				if (
					( $key =~ /time$/ ) &&
					( $is_zero ) &&
					( $self->{zero_time} )
					){
					$print_it=0;
				}elsif( $key =~ /time$/ ){
					$value=$self->timeString( $proc->{$key} );
				}

				if (
					( $key =~ /^environ$/ ) &&
					( ref( $proc->{environ} ) eq 'ARRAY' )
					){
					$value=join( color( $self->{environ} ).', '.color('reset') , @{ $proc->{environ} } );
				}

				if (
					( $key =~ /flt$/ ) &&
					( $is_zero ) &&
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
		if (
			( defined( $proc->{cmndline} ) ) &&
			( $proc->{cmndline} !~ /^$/ )
			){
			push( @data, [
						  color( $self->{varColor} ).'Cmndline'.color('reset'),
						  color( $self->{processColor} ).$proc->{cmndline}.color('reset')
						  ]);
		}

		#
		# gets the open files
		#
		my $open_files='';
		my $has_pipes=0;
		my $pid=$proc->pid;
		my $files=$self->_lsof( '-p '.$pid );
		if ( defined( $files ) ){

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

			#
			my %rw_filehandles;
			my %r_filehandles;
			my %w_filehandles;
			my %mem_filehandles;

			foreach my $file ( @{ $files } ){
				my $fd=$file->{fd};
				my $type=$file->{type};
				my $device=$file->{device};
				my $size_off=$file->{size_off};
				my $node=$file->{node};
				my $file_name=$file->{name};
				my $match_name=$file->{match_name};

				# noted so the pipe chains may be skipped entirely, and
				# the system wide lsof they require avoided, for any
				# process that does not have a pipe open
				if ( $self->_isPipe( $type ) ){
					$has_pipes=1;
				}

				# checks if it is a line we don't want
				my $dont_add=0;
				if (
					# IP stuff... handled by ncnetstat
					( $type =~ /^IPv/ ) ||
					# library... spammy... only print if asked
					(
					 ( $fd =~ /^txt$/ ) &&
					 ( ! $self->{txt} )
					 ) ||
					# pipe... spammy... only print if asked
					(
					 ( $type =~ /^[Pp][Ii][Pp][Ee]$/ ) &&
					 ( ! $self->{pipe} )
					 ) ||
					# unix... spammy... only print if asked
					(
					 ( $type =~ /^[Uu][Nn][Ii][Xx]$/ ) &&
					 ( ! $self->{unix} )
					 ) ||
					# fifo... spammy with elasticsearch and the like... only print if asked...
					(
					 ( $type =~ /^[Ff][Ii][Ff][Oo]$/ ) &&
					 ( ! $self->{fifo} )
					 ) ||
					# memory mapped libraries with REG type....
					# spammy.... ES tends to have lots of these
					(
					 ( $type =~ /^[Rr][Ee][Gg]$/ ) &&
					 (
					  ( $match_name =~ /\.so$/ ) ||
					  ( $match_name =~ /\.so\.[0-9]+$/ ) ||
					  ( $match_name =~ /\.so\.[0-9]+\.[0-9]+$/ ) ||
					  ( $match_name =~ /\.so\.[0-9]+\.[0-9]+\.[0-9]+$/ ) ||
					  ( $match_name =~ /\.jar$/ )
					  ) &&
					 ( ! $self->{memreglib} )
					 ) ||
					# a_inode... spammy with elasticsearch and the like... only print if asked...
					(
					 ( $type =~ /^a\_inode$/ ) &&
					 ( ! $self->{a_inode} )
					 ) ||
					# vreg /....can by spammy with somethings like firefox
					(
					 ( $type =~ /^[Vv][Rr][Ee][Gg]$/ ) &&
					 ( $match_name =~ /^\/$/ ) &&
					 ( ! $self->{vregroot} )
					 )
					){
					$dont_add=1;
				}

				# begin deduping
				my $name= color( $self->{file_colors}[5] ).$file_name.color( 'reset' );

				# tie the far end of a pipe, FIFO, or unix socket to whatever
				# is holding it, which is only worth the system wide lsof it
				# takes for one that is going to be printed
				if (
					( ! $dont_add ) &&
					( $self->{peers} ) &&
					(
					 ( $self->_isUnix( $type ) ) ||
					 ( $self->_isPipe( $type ) )
					 )
					){
					my $peer=$self->_peerCommands( $file, \%commands );
					if ( defined( $peer ) ){
						$name=$name.' '.color( $self->{valColor} ).'('.$peer.')'.color( 'reset' );
					}
				}
				if (
					( ! $self->{dont_dedup} ) &&
					( ! $dont_add )
					){
					if (
						( $type =~ /[Vv][Rr][Ee][Gg]/ ) ||
						( $type =~ /[Rr][Ee][Gg]/ ) ||
						( $type =~ /[Vv][Dd][Ii][Dd]/ ) ||
						( $type =~ /[Vv][Cc][Hh][Rr]/ )
						) {
						if (
							( $fd =~ /u/ ) ||
							( $fd =~ /rw/ ) ||
							( $fd =~ /wr/ )
							) {
							if (! defined( $rw_filehandles{ $name } ) ) {
								$rw_filehandles{ $name } = 1;
							} else {
								$rw_filehandles{ $name }++;
							}
						} elsif ( $fd =~ /r/ ) {
							if (! defined( $r_filehandles{ $name } ) ) {
								$r_filehandles{ $name } = 1;
							} else {
								$r_filehandles{ $name }++;
							}
						} elsif ( $fd =~ /w/ ) {
							if (! defined( $w_filehandles{ $name } ) ) {
								$w_filehandles{ $name } = 1;
							} else {
								$w_filehandles{ $name }++;
							}
						}else{
							if (! defined( $mem_filehandles{ $name } ) ) {
								$mem_filehandles{ $name } = 1;
							} else {
								$mem_filehandles{ $name }++;
							}
						}
					}
				}

				if ( ! $dont_add ) {
					push( @fdata, [
								   color( $self->{file_colors}[0] ).$fd.color( 'reset' ),
								   color( $self->{file_colors}[1] ).$type.color( 'reset' ),
								   color( $self->{file_colors}[2] ).$device.color( 'reset' ),
								   color( $self->{file_colors}[3] ).$size_off.color( 'reset' ),
								   color( $self->{file_colors}[4] ).$node.color( 'reset' ),
								   $name,
								   ]);
				}
			}

			# finalize deduping
			my @final_fdata;
			if ( ! $self->{dont_dedup} ){
				my %rw_dedup;
				my %r_dedup;
				my %w_dedup;
				my %mem_dedup;
				foreach my $line ( @fdata ){
					if (
						( $line->[1] =~ /[Vv][Rr][Ee][Gg]/ ) ||
						( $line->[1] =~ /[Rr][Ee][Gg]/ ) ||
						( $line->[1] =~ /[Vv][Dd][Ii][Dd]/ ) ||
						( $line->[1] =~ /[Vv][Cc][Hh][Rr]/ )
						){
						my $add_line=1;
						if (
							( $line->[0] =~ /u/ ) ||
							( $line->[0] =~ /rw/ ) ||
							( $line->[0] =~ /wr/ )
							) {
							if( defined( $rw_dedup{ $line->[5] } ) ){
								$add_line=0;
							}else{
								if ($rw_filehandles{ $line->[5] } > 1){
									$line->[0]=$line->[0].'+';
								}
								$rw_dedup{ $line->[5] } = 1;
							}
						} elsif ( $line->[0] =~ /r/ ) {
							if( defined( $r_dedup{ $line->[5] } ) ){
								$add_line=0;
							}else{
								if ($r_filehandles{ $line->[5] } > 1){
									$line->[0]=$line->[0].'+';
								}
								$r_dedup{ $line->[5] } = 1;
							}
						} elsif ( $line->[0] =~ /w/ ) {
							if( defined( $w_dedup{ $line->[5] } ) ){
								$add_line=0;
							}else{
								if ($w_filehandles{ $line->[5] } > 1){
									$line->[0]=$line->[0].'+';
								}
								$w_dedup{ $line->[5] } = 1;
							}
						}else{
							if( defined( $mem_dedup{ $line->[5] } ) ){
								$add_line=0;
							}else{
								if ($mem_filehandles{ $line->[5] } > 1){
									$line->[0]=$line->[0].'+';
								}
								$mem_dedup{ $line->[5] } = 1;
							}
						}

						if ( $add_line ){
							push( @final_fdata, [
												 $line->[0],
												 $line->[1],
												 $line->[2],
												 $line->[3],
												 $line->[4],
												 $line->[5],
												 ]);
						}
					}else{
						push( @final_fdata, \@{ $line } );
					}
				}
				$ftb->add_rows( \@final_fdata );
			}else{
				$ftb->add_rows( \@fdata );
			}


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
		my $ptr=1;
		if ( $self->{dont_resolv} ){
			$ptr=0;
		}
		my $ncnetstat=Net::Connection::ncnetstat->new(
													  {
													   ptr=>$ptr,
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
		# handle the pipe chains
		#
		my $pipe_chains='';
		if (
			( $self->{pipe_chains} ) &&
			( $has_pipes )
			){
			$pipe_chains=$self->_pipeChainTable( $pid, \%commands );
		}

		#
		# adds the new item
		#
		$tb->add_rows( \@data );
		if ( $first ){
			$first=0;
		}else{
			$toReturn=$toReturn."\n\n";
		}
		$toReturn=$toReturn.$tb->draw.$open_files.$netstat.$pipe_chains;
	}

	return $toReturn;
}

#
# Runs lsof with the additional arguments passed to it and returns a
# array ref of hash refs, one per open file, with the keys pid, fd,
# type, device, size_off, node, name, and match_name. Undef is returned
# should lsof fail.
#
sub _lsof{
	my $self=$_[0];
	my $args=$_[1];

	if ( !defined( $args ) ){
		$args='';
	}

	# lsof has a habit of warning about things of no interest here, such
	# as rebuilding its device cache or a directory it could not read, so
	# stderr is sent off to be forgotten about
	my $output_raw=`lsof -n -l -P $args 2> /dev/null`;
	if (
		( $? != 0 ) &&
		!(
		  ( $^O =~ /linux/ ) &&
		  ( $? == 256 )
		  )
		){
		return undef;
	}

	my @lines=split(/\n/, $output_raw);

	# lsof pads its columns out to fit the widest value in this run, so
	# where each one starts and stops may only be worked out from the
	# header of this batch of output. Offsets are used instead of
	# splitting on whitespace as the width of the COMMAND column varies
	# with the command name, DEVICE may overflow into the padding to the
	# left of it, and NAME may contain whitespace.
	my $header_int=0;
	while (
		   ( defined( $lines[$header_int] ) ) &&
		   ( $lines[$header_int] !~ /^COMMAND[\ \t]/ )
		   ){
		$header_int++;
	}
	my @header_columns;
	if ( defined( $lines[$header_int] ) ){
		while ( $lines[$header_int] =~ /(\S+)/g ){
			push( @header_columns, { start=>$-[1], end=>$+[1] } );
		}
	}

	# The columns of interest, counted back from NAME as it is always the
	# last one. FD is not given a offset of its own as the access and
	# lock characters are printed past the end of that column, placing it
	# in the same region as TYPE.
	my $last_column=$#header_columns;
	if ( $last_column < 7 ){
		return [];
	}
	my $pid_end=$header_columns[ $last_column - 7 ]{end};
	my $user_end=$header_columns[ $last_column - 6 ]{end};
	my $type_end=$header_columns[ $last_column - 4 ]{end};
	my $device_end=$header_columns[ $last_column - 3 ]{end};
	my $size_end=$header_columns[ $last_column - 2 ]{end};
	my $node_end=$header_columns[ $last_column - 1 ]{end};
	my $name_start=$header_columns[ $last_column ]{start};

	my @files;
	my $line_int=$header_int + 1;
	while ( defined( $lines[$line_int] ) ){
		my $line=$lines[$line_int];
		$line_int++;

		my ( $fd, $type )=split( /[\ \t]+/, $self->_column( $line, $user_end, $type_end ) );
		if ( !defined( $fd ) ){
			$fd='';
		}
		if ( !defined( $type ) ){
			$type='';
		}

		my $file_name=$self->_column( $line, $name_start );

		# lsof appends the file system, device, or the like to the name
		# for some types, which is not wanted when matching on the name
		my $match_name=$file_name;
		$match_name=~s/[\ \t]+\([^\)]*\)$//;

		# the PID is the trailing part of the region it shares with
		# COMMAND, which is used as the command name may contain spaces
		my $file_pid='';
		if ( $self->_column( $line, 0, $pid_end ) =~ /([0-9]+)$/ ){
			$file_pid=$1;
		}

		push( @files, {
					   pid=>$file_pid,
					   fd=>$fd,
					   type=>$type,
					   device=>$self->_column( $line, $type_end, $device_end ),
					   size_off=>$self->_column( $line, $device_end, $size_end ),
					   node=>$self->_column( $line, $size_end, $node_end ),
					   name=>$file_name,
					   match_name=>$match_name,
					   } );
	}

	return \@files;
}

#
# Pulls a column out of a line of lsof output using the offsets worked
# out from the header and trims the padding off of it. If no end offset
# is given, everything from the start offset on is returned, which is
# what is wanted for NAME as it is the last column and may contain
# whitespace.
#
sub _column{
	my $self=$_[0];
	my $line=$_[1];
	my $start=$_[2];
	my $end=$_[3];

	my $value='';
	if ( length( $line ) > $start ){
		if ( defined( $end ) ){
			$value=substr( $line, $start, $end - $start );
		}else{
			$value=substr( $line, $start );
		}
	}

	$value=~s/^[\ \t]+//;
	$value=~s/[\ \t]+$//;

	return $value;
}

#
# Returns a array ref of every open file on the system, as per _lsof.
# This is what the endpoint lookups are built from, so it is cached for
# the duration of the run, keeping the system wide lsof it takes to a
# single one.
#
sub _allFiles{
	my $self=$_[0];

	if ( defined( $self->{all_files} ) ){
		return $self->{all_files};
	}

	my $files=$self->_lsof;
	if ( !defined( $files ) ){
		$files=[];
	}

	$self->{all_files}=$files;

	return $self->{all_files};
}

#
# Returns true if the lsof type passed to it is a pipe of some sort.
#
sub _isPipe{
	my $self=$_[0];
	my $type=$_[1];

	if (
		( $type =~ /^[Pp][Ii][Pp][Ee]$/ ) ||
		( $type =~ /^[Ff][Ii][Ff][Oo]$/ )
		){
		return 1;
	}

	return 0;
}

#
# Turns a pipe entry from _lsof into a endpoint, which is a hash ref with
# the keys pid, fd, id, peer_id, and direction. Undef is returned if the
# entry can't be tied to the far end of the pipe.
#
sub _pipeEndpoint{
	my $self=$_[0];
	my $file=$_[1];

	my $ids=$self->_peerIDs( $file );
	if (
		( !defined( $ids ) ) ||
		( !defined( $ids->{peer_id} ) ) ||
		( $file->{pid} =~ /^$/ )
		){
		return undef;
	}
	my $id=$ids->{id};
	my $peer_id=$ids->{peer_id};

	# The access characters are not printed for pipes on all systems, so
	# the descriptor number is used as a fallback, 0 being the input and
	# 1 and 2 being the output.
	my $direction='';
	if ( $file->{fd} =~ /w/ ){
		$direction='w';
	}elsif ( $file->{fd} =~ /r/ ){
		$direction='r';
	}elsif ( $file->{fd} =~ /^([0-9]+)/ ){
		my $fd_number=$1;
		if ( $fd_number == 0 ){
			$direction='r';
		}elsif (
				( $fd_number == 1 ) ||
				( $fd_number == 2 )
				){
			$direction='w';
		}
	}

	return {
			pid=>$file->{pid},
			fd=>$file->{fd},
			id=>$id,
			peer_id=>$peer_id,
			direction=>$direction,
			};
}

#
# Returns a hash ref of every pipe endpoint on the system, keyed by id,
# so the far end of a pipe may be looked up by its peer_id. This requires
# a system wide lsof, so the result is cached for the duration of the run.
#
sub _allPipeEndpoints{
	my $self=$_[0];

	if ( defined( $self->{pipe_endpoints} ) ){
		return $self->{pipe_endpoints};
	}

	my %endpoints;
	foreach my $file ( @{ $self->_allFiles } ){
		if ( $self->_isPipe( $file->{type} ) ){
			my $endpoint=$self->_pipeEndpoint( $file );
			if ( defined( $endpoint ) ){
				push( @{ $endpoints{ $endpoint->{id} } }, $endpoint );
			}
		}
	}

	$self->{pipe_endpoints}=\%endpoints;

	return $self->{pipe_endpoints};
}

#
# Returns true if the lsof type passed to it is a unix socket.
#
sub _isUnix{
	my $self=$_[0];
	my $type=$_[1];

	if ( $type =~ /^[Uu][Nn][Ii][Xx]$/ ){
		return 1;
	}

	return 0;
}

#
# Works out the IDs used to tie the two ends of a pipe, FIFO, or unix
# socket entry from _lsof together, returning a hash ref with the keys id
# and peer_id. The peer_id is undef when the entry names no far end of
# its own, such as a unix socket lsof names after the path it is bound
# to, and undef is returned for anything that has no ID at all.
#
sub _peerIDs{
	my $self=$_[0];
	my $file=$_[1];

	my $class;
	if ( $self->_isUnix( $file->{type} ) ){
		$class='unix';
	}elsif ( $self->_isPipe( $file->{type} ) ){
		$class='pipe';
	}else{
		return undef;
	}

	# Systems such as FreeBSD point at the address of the far end via the
	# name. Linux does so for neither, but does give both ends of a pipe
	# or FIFO the same inode via the node, which unix sockets do not
	# share, working those out there meaning lsof +E or ss -x.
	if (
		( $file->{match_name} =~ /^\-\>(\S+)/ ) &&
		( $file->{device} !~ /^$/ )
		){
		return {
				id=>$class.':'.$file->{device},
				peer_id=>$class.':'.$1,
				};
	}elsif (
			( $class eq 'pipe' ) &&
			( $file->{node} =~ /^[0-9]+$/ )
			){
		my $id=$class.':'.$file->{device}.':'.$file->{node};
		return {
				id=>$id,
				peer_id=>$id,
				};
	}elsif ( $file->{device} !~ /^$/ ){
		return {
				id=>$class.':'.$file->{device},
				peer_id=>undef,
				};
	}

	return undef;
}

#
# Returns a hash ref with the keys holders and pointers, both of which
# are hash refs of PIDs keyed by a endpoint ID. The holders are the PIDs
# with that endpoint open and the pointers the PIDs whose endpoint points
# at it, which are the two ways the far end of one may be found. This
# requires a system wide lsof, so the result is cached for the duration
# of the run.
#
sub _allPeers{
	my $self=$_[0];

	if ( defined( $self->{peer_pids} ) ){
		return $self->{peer_pids};
	}

	my %holders;
	my %pointers;
	# a endpoint may be open on more than one FD in a process, which is
	# worth mentioning no more than once
	my %seen_holder;
	my %seen_pointer;
	foreach my $file ( @{ $self->_allFiles } ){
		my $ids=$self->_peerIDs( $file );
		if (
			( !defined( $ids ) ) ||
			( $file->{pid} =~ /^$/ )
			){
			next;
		}

		if ( !defined( $seen_holder{ $ids->{id} }{ $file->{pid} } ) ){
			$seen_holder{ $ids->{id} }{ $file->{pid} }=1;
			push( @{ $holders{ $ids->{id} } }, $file->{pid} );
		}

		if (
			( defined( $ids->{peer_id} ) ) &&
			( !defined( $seen_pointer{ $ids->{peer_id} }{ $file->{pid} } ) )
			){
			$seen_pointer{ $ids->{peer_id} }{ $file->{pid} }=1;
			push( @{ $pointers{ $ids->{peer_id} } }, $file->{pid} );
		}
	}

	$self->{peer_pids}={
						holders=>\%holders,
						pointers=>\%pointers,
						};

	return $self->{peer_pids};
}

#
# Renders the commands holding the far end of a pipe, FIFO, or unix
# socket entry from _lsof. Undef is returned if there is nothing to be
# said about the far end and a ? if the entry has one that is out of
# reach.
#
sub _peerCommands{
	my $self=$_[0];
	my $file=$_[1];
	my $commands=$_[2];

	my $ids=$self->_peerIDs( $file );
	if ( !defined( $ids ) ){
		return undef;
	}

	my $peers=$self->_allPeers;

	my @peer_pids;
	my %seen;
	# both ends share a ID on systems that tie them together via the node,
	# where the process itself is always one of the holders, which says
	# nothing worth printing
	if ( defined( $ids->{peer_id} ) && ( $ids->{peer_id} eq $ids->{id} ) ){
		$seen{ $file->{pid} }=1;
	}

	# whatever holds the endpoint this one points at is on the far end
	if (
		( defined( $ids->{peer_id} ) ) &&
		( defined( $peers->{holders}{ $ids->{peer_id} } ) )
		){
		foreach my $peer_pid ( @{ $peers->{holders}{ $ids->{peer_id} } } ){
			if ( !defined( $seen{$peer_pid} ) ){
				$seen{$peer_pid}=1;
				push( @peer_pids, $peer_pid );
			}
		}
	}

	# and so is whatever points at this endpoint, which is the only way
	# around for the unix sockets lsof names after the path they are bound
	# to, such as the accepted end of a connection
	if ( defined( $peers->{pointers}{ $ids->{id} } ) ){
		foreach my $peer_pid ( @{ $peers->{pointers}{ $ids->{id} } } ){
			if ( !defined( $seen{$peer_pid} ) ){
				$seen{$peer_pid}=1;
				push( @peer_pids, $peer_pid );
			}
		}
	}

	if ( !defined( $peer_pids[0] ) ){
		# a endpoint lsof points somewhere with is known to have a far end,
		# so say that it could not be reached, while one that shares a ID
		# with the far end or is named after a path may just be a FIFO or
		# socket nothing else has open, where there is nothing to say
		if (
			( defined( $ids->{peer_id} ) ) &&
			( $ids->{peer_id} ne $ids->{id} )
			){
			return '?';
		}
		return undef;
	}

	my @rendered;
	foreach my $peer_pid ( @peer_pids ){
		push( @rendered, $self->_peerCommand( $peer_pid, $commands ) );
	}

	return join( ', ', @rendered );
}

#
# Walks the pipe edges out from the PID, returning a array ref of the
# paths found, each of which includes the PID it started from. The seen
# hash ref is what keeps it from looping back around on itself.
#
sub _pipeWalk{
	my $self=$_[0];
	my $edges=$_[1];
	my $pid=$_[2];
	my $seen=$_[3];

	my %new_seen=%{ $seen };
	$new_seen{$pid}=1;

	# A process may sit on either end of more than one pipe, so the number
	# of paths through a busy set of them can climb fast. Both how many
	# are gathered and how far they are followed are capped to keep that
	# from getting away.
	my @paths;
	if (
		( defined( $edges->{$pid} ) ) &&
		( keys( %new_seen ) < $self->{pipe_chain_max_depth} )
		){
		foreach my $next ( sort keys %{ $edges->{$pid} } ){
			if ( defined( $new_seen{$next} ) ){
				next;
			}
			foreach my $path ( @{ $self->_pipeWalk( $edges, $next, \%new_seen ) } ){
				push( @paths, [ $pid, @{ $path } ] );
				if ( $#paths >= $self->{pipe_chain_max} ){
					return \@paths;
				}
			}
		}
	}

	# a dead end is still a path, just a single item one
	if ( !defined( $paths[0] ) ){
		push( @paths, [ $pid ] );
	}

	return \@paths;
}

#
# Returns a array ref of the pipelines the PID is a part of, each being a
# array ref of PIDs in the order the data flows through them.
#
sub _pipeChains{
	my $self=$_[0];
	my $pid=$_[1];

	my $endpoints=$self->_allPipeEndpoints;

	# every pipe with a writer at one end and a reader at the other is a
	# edge going from the writer to the reader
	my %forward;
	my %backward;
	foreach my $id ( keys %{ $endpoints } ){
		foreach my $endpoint ( @{ $endpoints->{$id} } ){
			if (
				( $endpoint->{direction} ne 'w' ) ||
				( !defined( $endpoints->{ $endpoint->{peer_id} } ) )
				){
				next;
			}
			foreach my $peer ( @{ $endpoints->{ $endpoint->{peer_id} } } ){
				# both ends share a id on systems that tie them together
				# via the node, so the endpoint itself has to be skipped
				if (
					( $peer->{pid} eq $endpoint->{pid} ) &&
					( $peer->{fd} eq $endpoint->{fd} )
					){
					next;
				}
				if ( $peer->{direction} ne 'r' ){
					next;
				}
				$forward{ $endpoint->{pid} }{ $peer->{pid} }=1;
				$backward{ $peer->{pid} }{ $endpoint->{pid} }=1;
			}
		}
	}

	my @chains;
	foreach my $head ( @{ $self->_pipeWalk( \%backward, $pid, {} ) } ){
		foreach my $tail ( @{ $self->_pipeWalk( \%forward, $pid, {} ) } ){
			# both walks start from the PID, so the head is flipped around
			# and the duplicate copy of it dropped off of the tail
			my @chain=( reverse( @{ $head } ), @{ $tail }[ 1 .. $#{ $tail } ] );
			push( @chains, \@chain );
			if ( $#chains >= $self->{pipe_chain_max} ){
				return \@chains;
			}
		}
	}

	return \@chains;
}

#
# Renders the command used for a PID on the far end of a pipe or socket,
# truncating it as needed. A ? is used for any process that can't be
# looked up.
#
sub _peerCommand{
	my $self=$_[0];
	my $pid=$_[1];
	my $commands=$_[2];

	my $command='?';
	if ( defined( $commands->{$pid} ) ){
		$command=$commands->{$pid};
	}

	if ( length( $command ) > $self->{peer_command_length} ){
		$command=substr( $command, 0, $self->{peer_command_length} ).'...';
	}

	return $command.'('.$pid.')';
}

#
# Builds the pipe chain table for a PID, returning a empty string if
# there is nothing worth showing.
#
sub _pipeChainTable{
	my $self=$_[0];
	my $pid=$_[1];
	my $commands=$_[2];

	my @rows;
	foreach my $chain ( @{ $self->_pipeChains( $pid ) } ){
		# a chain of just the process itself says nothing, which is what
		# is left over when the far end of every pipe is out of reach
		if ( $#{ $chain } < 1 ){
			next;
		}

		my @parts;
		foreach my $chain_pid ( @{ $chain } ){
			my $command=$self->_peerCommand( $chain_pid, $commands );
			if ( $chain_pid eq $pid ){
				push( @parts, color( $self->{processColor} ).$command.color('reset') );
			}else{
				push( @parts, color( $self->{valColor} ).$command.color('reset') );
			}
		}

		push( @rows, [ join( color( $self->{varColor} ).' | '.color('reset'), @parts ) ] );
	}

	if ( !defined( $rows[0] ) ){
		return '';
	}

	my $ctb = Text::ANSITable->new;
	$ctb->border_style('Default::none_ascii');
	$ctb->color_theme('Default::no_color');
	$ctb->show_header(1);
	$ctb->set_column_style(0, pad => 0);
	$ctb->columns([ color( $self->{varColor} ).'PIPE CHAINS'.color('reset') ]);
	$ctb->add_rows( \@rows );

	return $ctb->draw;
}

=head2 timeString

Turns the raw run string into something usable.

=cut

sub timeString{
	my $self=$_[0];
	my $time=$_[1];

	if ( !defined( $time ) ){
		$time=0;
	}

	if ( $^O =~ /^linux$/ ) {
		$time=$time/1000000;
	}

	# the fractional part is not wanted and % would quietly drop it anyways
	$time=int( $time );

	my $hours = int( $time / 3600 );
	my $minutes = int( ( $time % 3600 ) / 60 );
	my $seconds = $time % 60;

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

	#process the minutes bit, zero padding it if it follows the hours
	if (
		( $hours > 0 ) ||
		( $minutes > 0 )
		) {
		if ( $hours > 0 ){
			$minutes=sprintf('%02d', $minutes);
		}
		$toReturn=$toReturn.color( $self->{timeColors}->[1] ). $minutes.':';

		$seconds=sprintf('%02d', $seconds);
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

	if ( !defined( $mem ) ){
		$mem=0;
	}

	my $toReturn='';

	if ( $mem < '10000' ) {
		$toReturn=color( $self->{$type.'Colors'}[0] ).$mem;
	} elsif (
			 ( $mem >= '10000' ) &&
			 ( $mem < '1000000' )
			 ) {
		$mem=$mem/1000;
		$mem=sprintf('%.3f', $mem);

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
	if ( $year != $cyear ) {
		return $year.sprintf('%02d', $mon).sprintf('%02d', $mday).'-'.sprintf('%02d', $hour).':'.sprintf('%02d', $min);
	}
	if ( $mon != $cmon ) {
		return sprintf('%02d', $mon).sprintf('%02d', $mday).'-'.sprintf('%02d', $hour).':'.sprintf('%02d', $min);
	}
	if ( $mday != $cmday ) {
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

=item * Repository

L<https://github.com/VVelox/Proc-ProcessTable-piddler>

=back


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2019 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1; # End of Proc::ProcessTable::piddler
