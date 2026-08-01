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

Shared memory objects are rolled up as well. A process may hold a great
many that print the same, anonymous ones having nothing to tell them
apart but their size and what else holds them, so only the first of them
is printed, with the number left off tacked onto the FD.

    40u+43 SHM  262.144k

Defaults to 0, false.

=head4 dont_resolv

Don't resolve PTR addresses.

Defaults to 0, false.

=head4 fifo

Print FIFOs.

Defaults to 1, true.

=head4 human_size

Print the size of a open file as a readable value rather than the raw
number of bytes, in the same manner as the process VSZ and RSS.

    SIZE/OFF
    823.640k

Only the SIZE/OFF values that are a size are touched, a offset being a
position rather than a amount.

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

For each pipe, FIFO, unix socket, and shared memory object printed, show
the command holding the far end of it.

    FD  TYPE DEVICE             SIZE/OFF NODE      NAME
    7u  unix 0xfffff80022630400 0                  ->0xfffff80022635000 (dbus-daemon --session(51092))
    14u unix 0xfffff80052dee800 0                  /tmp/dbus-nWRW4XDDoD (xfce4-panel(63471))
    3r  FIFO 0xe6               0t0      299839014 /tmp/testfifo (cat(12593))
    17u SHM                     288876   0         (firefox -contentproc...(7375, 24844, 32640, + 26 more))

The far end is found either by way of the endpoint this one points at,
by way of whatever points at this one, or by way of what else has the
same one open. The second is what covers the unix sockets lsof names
after the path they are bound to, such as the accepted end of a
connection, and the third the FIFOs, shared memory objects, and pipes
that both ends hold the same object for.

Commands longer than 40 characters are truncated. A endpoint whose far
end can not be looked up, such as one held by another user's process when
not running as root, is shown as a ?. Nothing is shown for one that has
no far end to speak of, such as a unix socket that is only bound and
listening or a FIFO no one else has open.

A endpoint may be held by any number of other processes, such as a shared
memory object inherited across a pile of forks, so the PIDs are gathered
up under the command they are running and at most 8 commands and 8 PIDs
per command are printed, with the rest noted as a count.

Tying the two ends together requires a system wide lsof, so it is only
run when a pipe, FIFO, unix socket, or shared memory object is actually
going to be printed, and only once per call to run.

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
				sizeColors=>[
							 'GREEN',
							 'YELLOW',
							 'RED',
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
				human_size=>1,
				peer_command_length=>40,
				peer_max=>8,
				pipe_chain_max=>16,
				pipe_chain_max_depth=>32,
				};
    bless $self;

	my @arg_feed=(
				  'txt', 'pipe', 'unix', 'vregroot', 'dont_dedup', 'dont_resolv',
				  'fifo', 'a_inode', 'memreglib', 'pipe_chains', 'peers',
				  'human_size'
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
	if ( defined( $proc_keys_hash{euid} ) ){
		delete( $proc_keys_hash{euid} );
	}
	if ( defined( $proc_keys_hash{egid} ) ){
		delete( $proc_keys_hash{egid} );
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
		push( @data, [
					  color( $self->{varColor} ).'UID'.color('reset'),
					  $self->_userString( $proc->{uid} ).' '.color('reset')
					  ]);

		#
		# EUID
		#
		if ( defined( $proc->{euid} ) ){
			push( @data, [
						  color( $self->{varColor} ).'EUID'.color('reset'),
						  $self->_userString( $proc->{euid} ).' '.color('reset')
						  ]);
		}

		#
		# GID
		#
		push( @data, [
					  color( $self->{varColor} ).'GID'.color('reset'),
					  $self->_groupString( $proc->{gid} ).' '.color('reset')
					  ]);

		#
		# EGID
		#
		if ( defined( $proc->{egid} ) ){
			push( @data, [
						  color( $self->{varColor} ).'EGID'.color('reset'),
						  $self->_groupString( $proc->{egid} ).' '.color('reset')
						  ]);
		}

		#
		# Groups
		#
		if ( defined( $proc->{groups} ) ){
			my @groups;
			foreach my $current_group ( @{ $proc->{groups} } ){
				push( @groups, $self->_groupString( $current_group ) );
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
				$mem=($self->_procMem( $proc->{rss} ) / $total_mem)*100;
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
					  $self->memString( $self->_procMem( $proc->size ), 'vsz' )
					  ]);

		#
		# RSS
		#
		push( @data, [
					  color( $self->{varColor} ).'RSS'.color('reset'),
					  $self->memString( $self->_procMem( $proc->rss ), 'rss' )
					  ]);

		#
		# the open files are gathered in here as the total shared memory
		# is worked out from them, which belongs with the rest of the
		# memory bits rather than down with the table of them
		#
		my $pid=$proc->pid;
		my $files=$self->_lsof( '-p '.$pid );

		#
		# total SHM
		#
		my $shm_total=$self->_shmTotal( $files );
		if ( $shm_total > 0 ){
			push( @data, [
						  color( $self->{varColor} ).'Total SHM'.color('reset'),
						  $self->memString( $shm_total, 'size' )
						  ]);
		}

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
			my %shm_alike;

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

				# tie the far end of a pipe, FIFO, unix socket, or shared
				# memory object to whatever is holding it, which is only
				# worth the system wide lsof it takes for one that is going
				# to be printed
				if (
					( ! $dont_add ) &&
					( $self->{peers} ) &&
					(
					 ( $self->_isUnix( $type ) ) ||
					 ( $self->_isPipe( $type ) ) ||
					 ( $self->_isShm( $type ) )
					 )
					){
					my $peer=$self->_peerCommands( $file, \%commands );
					if ( defined( $peer ) ){
						# a shared memory object has no name to speak of, so
						# there is nothing for this to trail after
						my $spacer=' ';
						if ( $file_name =~ /^$/ ){
							$spacer='';
						}
						$name=$name.$spacer.color( $self->{valColor} ).'('.$peer.')'.color( 'reset' );
					}
				}

				my $size_string=$self->_sizeString( $file );

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
					}elsif ( $self->_isShm( $type ) ){
						# a process may hold a pile of shared memory objects
						# that all print the same, anonymous ones having
						# nothing to tell them apart but their size and what
						# else holds them, which are worth a single line and
						# a count of the rest
						if (! defined( $shm_alike{ $size_string."\0".$name } ) ) {
							$shm_alike{ $size_string."\0".$name } = 1;
						} else {
							$shm_alike{ $size_string."\0".$name }++;
						}
					}
				}

				if ( ! $dont_add ) {
					push( @fdata, [
								   color( $self->{file_colors}[0] ).$fd.color( 'reset' ),
								   color( $self->{file_colors}[1] ).$type.color( 'reset' ),
								   color( $self->{file_colors}[2] ).$device.color( 'reset' ),
								   $size_string,
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
				my %shm_dedup;
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
					}elsif ( $line->[1] =~ /[Ss][Hh][Mm]/ ){
						# the ones that print the same are rolled up into the
						# first of them, with the number left off tacked onto
						# the FD in the same manner as a duplicate handle
						my $key=$line->[3]."\0".$line->[5];
						if ( !defined( $shm_dedup{$key} ) ){
							$shm_dedup{$key}=1;
							if ( $shm_alike{$key} > 1 ){
								$line->[0]=$line->[0].'+'.( $shm_alike{$key} - 1 );
							}
							push( @final_fdata, \@{ $line } );
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
# type, device, size_off, node, node_id, share_count, name, and
# match_name. Undef is returned should lsof fail.
#
sub _lsof{
	my $self=$_[0];
	my $args=$_[1];

	if ( !defined( $args ) ){
		$args='';
	}

	# The field output is used rather than the columns as the latter may
	# only be picked apart via the widths worked out from the header, run
	# together when a value overflows, and have no place for the node
	# identifier and share count. lsof also has a habit of warning about
	# things of no interest here, such as rebuilding its device cache or
	# a directory it could not read, so stderr is sent off to be
	# forgotten about.
	my $output_raw=`lsof -n -l -P -F0 $args 2> /dev/null`;
	if (
		( $? != 0 ) &&
		!(
		  ( $^O =~ /linux/ ) &&
		  ( $? == 256 )
		  )
		){
		return undef;
	}

	my @files;
	my $pid='';
	my $file;

	# Every field is NUL terminated and the first one of each set has a
	# newline stuck onto the front of it. A set beginning with p is a
	# process and one beginning with f a file belonging to the last
	# process seen.
	foreach my $field ( split( /\0/, $output_raw ) ){
		$field=~s/^\n//;

		# the newline the last set of all ends with is left sitting on its
		# own once taken off, with nothing to it beyond that
		if ( $field =~ /^$/ ){
			next;
		}

		my $id=substr( $field, 0, 1 );
		my $value=substr( $field, 1 );

		if ( $id eq 'p' ){
			$pid=$value;
		}elsif ( $id eq 'f' ){
			if ( defined( $file ) ){
				push( @files, $self->_lsofFile( $file ) );
			}
			$file={
				   pid=>$pid,
				   fd=>$value,
				   type=>'',
				   device=>'',
				   size=>'',
				   offset=>'',
				   node=>'',
				   node_id=>'',
				   share_count=>'',
				   name=>'',
				   };
		}elsif ( defined( $file ) ){
			# the access and lock characters are printed as a part of the
			# FD column, which is what the rest of this expects them in
			if (
				( $id eq 'a' ) ||
				( $id eq 'l' )
				){
				if (
					( $value !~ /^[\ \t]*$/ ) &&
					( $value ne '-' )
					){
					$file->{fd}=$file->{fd}.$value;
				}
			}elsif ( $id eq 't' ){
				$file->{type}=$value;
			}elsif ( $id eq 'd' ){
				$file->{device}=$value;
			}elsif ( $id eq 'D' ){
				# the device character code is the better of the two and
				# only some types have one
				if ( $file->{device} =~ /^$/ ){
					$file->{device}=$value;
				}
			}elsif ( $id eq 's' ){
				$file->{size}=$value;
			}elsif ( $id eq 'o' ){
				$file->{offset}=$value;
			}elsif ( $id eq 'i' ){
				$file->{node}=$value;
			}elsif ( $id eq 'N' ){
				$file->{node_id}=$value;
			}elsif ( $id eq 'C' ){
				$file->{share_count}=$value;
			}elsif ( $id eq 'n' ){
				$file->{name}=$value;
			}
		}
	}

	if ( defined( $file ) ){
		push( @files, $self->_lsofFile( $file ) );
	}

	return \@files;
}

#
# Finishes off a file gathered by _lsof, filling in the values that are
# worked out from the fields rather than taken from one of them.
#
sub _lsofFile{
	my $self=$_[0];
	my $file=$_[1];

	# lsof prints the size when it has one and falls back to the offset,
	# which is what the SIZE/OFF column amounts to
	$file->{size_off}=$file->{size};
	if ( $file->{size_off} =~ /^$/ ){
		$file->{size_off}=$file->{offset};
	}

	# lsof appends the file system, device, or the like to the name for
	# some types, which is not wanted when matching on the name
	my $match_name=$file->{name};
	$match_name=~s/[\ \t]+\([^\)]*\)$//;
	$file->{match_name}=$match_name;

	return $file;
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
# Renders the SIZE/OFF column for a file from _lsof. Only a size is worth
# making readable, a offset being a position rather than a amount, and
# lsof marks those out by printing them as 0t<decimal> or 0x<hex>.
#
sub _sizeString{
	my $self=$_[0];
	my $file=$_[1];

	if (
		( $self->{human_size} ) &&
		( $file->{size} =~ /^[0-9]+$/ )
		){
		return $self->memString( $file->{size}, 'size' );
	}

	return color( $self->{file_colors}[3] ).$file->{size_off}.color( 'reset' );
}

#
# Renders a UID as the user it belongs to with the number after it,
# falling back to just the number for any that can't be looked up.
#
sub _userString{
	my $self=$_[0];
	my $uid=$_[1];

	my $user=getpwuid( $uid );
	if ( !defined( $user ) ){
		return color( $self->{idColors}[0] ).$uid.color('reset');
	}

	return color( $self->{idColors}[0] ).$user.
	color( $self->{idColors}[1] ).'('.
	color( $self->{idColors}[2] ).$uid.
	color( $self->{idColors}[1] ).')'
	.color('reset');
}

#
# The same as _userString, for a GID and the group it belongs to.
#
sub _groupString{
	my $self=$_[0];
	my $gid=$_[1];

	my $group=getgrgid( $gid );
	if ( !defined( $group ) ){
		return color( $self->{idColors}[0] ).$gid.color('reset');
	}

	return color( $self->{idColors}[0] ).$group.
	color( $self->{idColors}[1] ).'('.
	color( $self->{idColors}[2] ).$gid.
	color( $self->{idColors}[1] ).')'
	.color('reset');
}

#
# Proc::ProcessTable works the memory sizes out in a 32 bit integer on
# some systems, FreeBSD included, so anything past 2G comes back having
# wrapped around into the negative. Adding the 4G it lost back on puts
# that right for any process that has not gone past 4G, which is as far
# as what is reported may be taken.
#
sub _procMem{
	my $self=$_[0];
	my $mem=$_[1];

	if ( !defined( $mem ) ){
		return 0;
	}

	if ( $mem < 0 ){
		$mem=$mem + 2**32;
	}

	# past 4G there is nothing left to work with
	if ( $mem < 0 ){
		return 0;
	}

	return $mem;
}

#
# Adds up the size of the shared memory objects in a list of files from
# _lsof. One held on more than one FD is only counted the once, the
# object being what takes up the memory rather than the handle on it.
#
sub _shmTotal{
	my $self=$_[0];
	my $files=$_[1];

	if ( !defined( $files ) ){
		return 0;
	}

	my $total=0;
	my %seen;
	foreach my $file ( @{ $files } ){
		if (
			( ! $self->_isShm( $file->{type} ) ) ||
			( $file->{size} !~ /^[0-9]+$/ )
			){
			next;
		}

		# lsof gives most things a node identifier, which is the only way
		# of telling one anonymous object from another
		if ( $file->{node_id} !~ /^$/ ){
			if ( defined( $seen{ $file->{node_id} } ) ){
				next;
			}
			$seen{ $file->{node_id} }=1;
		}

		$total=$total + $file->{size};
	}

	return $total;
}

#
# Returns true if the lsof type passed to it is a shared memory object.
#
sub _isShm{
	my $self=$_[0];
	my $type=$_[1];

	if ( $type =~ /^[Ss][Hh][Mm]$/ ){
		return 1;
	}

	return 0;
}

#
# Works out the IDs used to tie the two ends of a pipe, FIFO, unix
# socket, or shared memory entry from _lsof together, returning a hash
# ref with the keys id and peer_id. The peer_id is undef when the entry
# neither names a far end of its own nor is the sort shared by way of
# both ends holding it, such as a unix socket lsof names after the path
# it is bound to, and undef is returned for anything that has no ID at
# all.
#
sub _peerIDs{
	my $self=$_[0];
	my $file=$_[1];

	my $class;
	if ( $self->_isUnix( $file->{type} ) ){
		$class='unix';
	}elsif ( $self->_isPipe( $file->{type} ) ){
		$class='pipe';
	}elsif ( $self->_isShm( $file->{type} ) ){
		$class='shm';
	}else{
		return undef;
	}

	# The node identifier names the object itself, which is what both ends
	# of one have in common, with the device and inode falling in for it
	# on anything lsof reports no identifier for.
	my $id;
	if ( $file->{node_id} !~ /^$/ ){
		$id=$class.':'.$file->{node_id};
	}elsif (
			( $file->{device} !~ /^$/ ) &&
			( $file->{node} =~ /^[0-9]+$/ )
			){
		$id=$class.':'.$file->{device}.':'.$file->{node};
	}elsif ( $file->{device} !~ /^$/ ){
		$id=$class.':'.$file->{device};
	}else{
		return undef;
	}

	# Systems such as FreeBSD point at the far end of a pipe or connected
	# unix socket via the name, where the address named is the ID of the
	# object on the other side of it.
	my $peer_id;
	if ( $file->{match_name} =~ /^\-\>(\S+)/ ){
		$peer_id=$class.':'.$1;
	}elsif ( $class ne 'unix' ){
		# a pipe, FIFO, or shared memory object is instead shared by way
		# of both ends holding the same one, which unix sockets do not do,
		# tying those together on Linux meaning lsof +E or ss -x
		$peer_id=$id;
	}

	return {
			id=>$id,
			peer_id=>$peer_id,
			};
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
		# A endpoint lsof points somewhere with is known to have a far end,
		# as is one held more than once, so say that it could not be
		# reached. Anything else may just be a FIFO or socket nothing else
		# has open, where there is nothing to say.
		if (
			(
			 ( defined( $ids->{peer_id} ) ) &&
			 ( $ids->{peer_id} ne $ids->{id} )
			 ) ||
			(
			 ( $file->{share_count} =~ /^[0-9]+$/ ) &&
			 ( $file->{share_count} > 1 )
			 )
			){
			return '?';
		}
		return undef;
	}

	# Something like a shared memory object may be held by a great many
	# processes, which for the most part are copies of each other, so the
	# PIDs are gathered up under the command they are running rather than
	# printing that over and over. Both how many commands are printed and
	# how many PIDs are printed for any one of them are capped, as even
	# grouped up it may be more than is worth reading through.
	my %groups;
	my @order;
	foreach my $peer_pid ( sort { $a <=> $b } @peer_pids ){
		my $command=$self->_peerCommandName( $peer_pid, $commands );
		if ( !defined( $groups{$command} ) ){
			$groups{$command}=[];
			push( @order, $command );
		}
		push( @{ $groups{$command} }, $peer_pid );
	}

	my $more_commands=0;
	if ( $#order >= $self->{peer_max} ){
		$more_commands=$#order + 1 - $self->{peer_max};
		@order=@order[ 0 .. $self->{peer_max} - 1 ];
	}

	my @rendered;
	foreach my $command ( @order ){
		my @group_pids=@{ $groups{$command} };

		my $more_pids=0;
		if ( $#group_pids >= $self->{peer_max} ){
			$more_pids=$#group_pids + 1 - $self->{peer_max};
			@group_pids=@group_pids[ 0 .. $self->{peer_max} - 1 ];
		}

		my $rendered=$command.'('.join( ', ', @group_pids );
		if ( $more_pids > 0 ){
			$rendered=$rendered.', + '.$more_pids.' more';
		}
		push( @rendered, $rendered.')' );
	}

	my $toReturn=join( ', ', @rendered );
	if ( $more_commands > 0 ){
		$toReturn=$toReturn.', + '.$more_commands.' more';
	}

	return $toReturn;
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
# Renders the command used for a PID on the far end of a endpoint,
# truncating it as needed. A ? is used for any process that can't be
# looked up.
#
sub _peerCommandName{
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

	return $command;
}

#
# The same as _peerCommandName, with the PID it belongs to tacked onto
# the end of it.
#
sub _peerCommand{
	my $self=$_[0];
	my $pid=$_[1];
	my $commands=$_[2];

	return $self->_peerCommandName( $pid, $commands ).'('.$pid.')';
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
