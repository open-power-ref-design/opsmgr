#!/usr/bin/perl
# nagios: -epn
# icinga: -epn
#
# check_multi - nagios plugin
#
# Copyright (c) 2007-2011 Matthias Flacke (matthias.flacke at gmx.de)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling);
use vars qw(
$MYSELF @cmds %opt $returncode %def %rc $no $VERSION $tmp_stdout $tmp_stderr $xml $check_multi
$NAGIOS $nagios $Nagios $status_dat $livestatus_service $livestatus_host $timezero
$OK $WARNING $CRITICAL $UNKNOWN
$DETAIL_LIST $DETAIL_LIST_FULL $DETAIL_HTML $DETAIL_STDERR $DETAIL_PERFORMANCE
$DETAIL_PERFORMANCE_CLASSIC $DETAIL_STATUS $DETAIL_PERFORMANCE_LINK $DETAIL_XML $DETAIL_NAGIOS2
$DETAIL_NOTES_LINK $DETAIL_SERVICE_DEFINITION $DETAIL_SEND_NSCA $DETAIL_FEED_PASSIVE
$DETAIL_ENCODE_COMMANDS $DETAIL_HIDEIFOK $DETAIL_SEND_GEARMAN
*DEBUG0 *DEBUG1 *DEBUG2 *DEBUG3 *DEBUG4
);
BEGIN {
	#--- OMD environment? Then we have to be sure that vars are defined
	#--- otherwise somebody copied check_multi from OMD to remote hosts
        if (0 && (!$ENV{OMD_SITE} || !$ENV{OMD_ROOT})) {
                print "Error: OMD_SITE or OMD_ROOT variables not found.\n".
                	"If you're running check_multi outside of OMD environment,\n".
			"add OMD_ROOT and OMD_SITE to the environment\n";
                exit 3;
	#--- add OMD_ROOT and OMD_SITE vars to check_multi internal environment
	#--- then $OMD_ROOT$ and $OMD_SITE$ can be used in command files
        } elsif (0) {
		$ENV{MULTI_OMD_ROOT}=$ENV{OMD_ROOT};
		$ENV{MULTI_OMD_SITE}=$ENV{OMD_SITE};
	}
	#--- if hires timer available, use it
	eval("use Time::HiRes qw(time sleep)");
	if (! $@) {
		$opt{set}{use_time_hires}=1;
	}
	#--- if FindBin module available, use it for finding plugins
	if (1) {
		eval("use FindBin");
		if (! $@) {
			$opt{set}{libexec}="$FindBin::Bin";
			unshift @INC, "$FindBin::Bin";
		}
	}
}
use lib "/usr/local/nagios/libexec";
#-------------------------------------------------------------------------------
#--- vars ----------------------------------------------------------------------
#-------------------------------------------------------------------------------
$timezero=time;
$MYSELF="check_multi";
$nagios=lc("nagios");
$NAGIOS=uc("nagios");
$Nagios=ucfirst(lc("nagios"));
$VERSION='check_multi_0.26_506_2011-11-18-20:28'.
	"\nconfigure ";
#
#--- RC defines
$OK=0;
$WARNING=1;
$CRITICAL=2;
$UNKNOWN=3;
#
#--- report defines
$DETAIL_LIST=1;
$DETAIL_HTML=2;
$DETAIL_STDERR=4;
$DETAIL_PERFORMANCE=8;
$DETAIL_LIST_FULL=16;
$DETAIL_PERFORMANCE_CLASSIC=32;
$DETAIL_STATUS=64;
$DETAIL_PERFORMANCE_LINK=128;
$DETAIL_XML=256;
$DETAIL_NAGIOS2=512;
$DETAIL_NOTES_LINK=1024;
$DETAIL_SERVICE_DEFINITION=2048;
$DETAIL_SEND_NSCA=4096;
$DETAIL_FEED_PASSIVE=8192;
$DETAIL_ENCODE_COMMANDS=16384;
$DETAIL_HIDEIFOK=32768;
$DETAIL_SEND_GEARMAN=65536;
#
#--- vars
$no=0;
$returncode=0;
$status_dat=undef;
$livestatus_host=undef;
$livestatus_service=undef;
$tmp_stdout="";
$tmp_stderr="";
%def=(
	label	=> { $OK  => "OK", $WARNING  => "WARNING", $CRITICAL  => "CRITICAL", $UNKNOWN  => "UNKNOWN", },
	llabel	=> { $OK  => "ok", $WARNING  => "warning", $CRITICAL  => "critical", $UNKNOWN  => "unknown", },
	code	=> { "OK" => $OK,  "WARNING" => $WARNING,  "CRITICAL" => $CRITICAL,  "UNKNOWN" => $UNKNOWN,
		     "ok" => $OK,  "warning" => $WARNING,  "critical" => $CRITICAL,  "unknown" => $UNKNOWN,  },
	s2r	=> { 0    => $OK,  2         => $WARNING,  3          => $CRITICAL,  1         => $UNKNOWN,  },
	r2s	=> { $OK  => 0,    $WARNING  => 2,         $CRITICAL  => 3,          $UNKNOWN  => 1,         },
	color	=> { $OK => "#33FF00", $WARNING => "#FFFF00", $CRITICAL => "#F83838", $UNKNOWN => "#FF9900", },
	bgcolor	=> { $OK => "#33FF00", $WARNING => "#FEFFC1", $CRITICAL => "#FFBBBB", $UNKNOWN => "#FFDA9F", },
);
my %opt=(
	"commands"	=> {
		"attribute"	=> 1,
		"command"	=> 1,
		"cumulate"	=> 1,
		"eval"		=> 1,
		"eeval"		=> 1,
		"livestatus"	=> 1,
		"snmp"		=> 1,
		"statusdat"	=> 1,
		"state"		=> 1,
		"output"	=> 1,
	},
	"execute"	=> [],
	"filename"	=> [],
	"help"		=> 0,
	"set"		=> {
		# mouse_over & action_url: shows PNP chart popup triggered by mouse
		action_mouseover => 0,
		# place tags at the beginning of list entries (e.g. tag_host_servicedesc)
		add_tag_to_list_entries => 1,
		# cancel child check before it can reach global timeout
		cancel_before_global_timeout => 0,
		# checkresults_dir
		checkresults_dir => "/usr/local/nagios/var/spool/checkresults",
		# child_interval
		child_interval => "0.0",
		# update config file (if HTTP/FTP/etc) once a day (in seconds)
		cmdfile_update_interval	=> 86400,
		# should check_multi collapse child check_multi checks per default?
		collapse	=> 1,
		# complain about undefined macros instead of only silently removing
		complain_unknown_macros => 1,
		# path to check_multi config directory
		config_dir	=> "/usr/local/nagios/etc/check_multi",
		# how many rows should be displayed for cumulate statement?
		cumulate_max_rows => 5,
		# should cumulate ignore zero values?
		cumulate_ignore_zero => 1,
		# don't complain about being root etc.
		dont_be_paranoid => 0,
		# should empty output be flagged as UNKNOWN?
		empty_output_is_unknown => 1,
		# use open3 method to exec child checks
		exec_open3	=> 0,
		# show child checks also in status view (only in HTML mode)
		extinfo_in_status => "0",
		# print extended perfdata, count of states and overall state
		extended_perfdata => "0",
		# flag which determines if feed_passive services should be autocreated
		# based on multi-child tags
		feed_passive_autocreate => "1",
		# directory to contain automatically created service definitions 
		# for passive feeded check_multi services
		feed_passive_dir_permissions => "41777",
		# directory to contain automatically created service definitions 
		# for passive feeded check_multi services
		feed_passive_dir => "/usr/local/nagios/etc/check_multi/feed_passive",
		# standard extension of check_multi command files,
		# to be searched in directories
		file_extension	=> "cmd",
		# if set, return UNKNOWN if command file is not found
		ignore_missing_cmd_file => 0,
		# characters to cleanup from command files
		illegal_chars	=> "",
		# path to Nagios images
		image_path	=> "/nagios/images",
		# indentation character(s)
		indent		=> " ",
		# child checks indented?
		indent_label	=> 1,
		# plugin directory to be added to check_multi search path
		libexec		=> "/usr/local/nagios/libexec",
		# livestatus socket
		livestatus	=> "/usr/local/nagios/var/rw/live",
		# loose (German) performance data (replace commata by decimal points)
		loose_perfdata => "1",
		# pnp_version needed for mouseover: 0.6,0,4
		perfdata_pass_through => "0",
		# pnp_version needed for mouseover: 0.6,0,4
		pnp_version	=> "0.6",
		# label to be shown in output: <name> OK, ...
		name		=> "",
		# what RC should be returned if no checks are defined
		no_checks_rc	=> 3,
		# see tag_notes_link: URL to be added
		notes_url	=> "",
		# objects.cache path
		objects_cache	=> "/usr/local/nagios/var/objects.cache",
		# objects.cache delimiter character
		objects_cache_delimiter	=> ",",
		# omd environment
		omd_environment => 0,
		# create persistent data
		persistent	=> 0,
		# path to additional plugins
		plugin_path	=> "/usr/local/nagios/libexec",
		# PNP URL addon
		pnp_add2url	=> "",
		# PNP URL
		pnp_url		=> "/pnp4nagios",
		# report option, binary coded as sum of detail options
		report		=> 13,
		# report option, binary coded as sum of detail options
		report_inherit_mask => -1,
		#--- send_gearman: path to binary
		send_gearman	=> "/usr/local/bin/send_gearman",
		#--- send_gearman: encryption (0|1)
		send_gearman_encryption => 1,
		#--- send_gearman key: either string or file
		send_gearman_key => "should_be_changed",
		#--- send_gearman result queue name, default:empty
		send_gearman_resultqueue => "",
		#--- send_gearman_srv: worker server
		send_gearman_srv => "localhost",
		#--- send_nsca: path to binary
		send_nsca	=> "/usr/local/nagios/sbin/send_nsca",
		#--- send_nsca_cfg: path to config file
		send_nsca_cfg	=> "/usr/local/nagios/etc/send_nsca.cfg",
		#--- send_nsca_srv: nsca server name
		send_nsca_srv	=> "localhost",
		#--- send_nsca_port: nsca server port
		send_nsca_port	=> 5667,
		#--- send_nsca_timeout
		send_nsca_timeout => 11,
		#--- send_nsca_opts: options to provide to send_nsca
		send_nsca_delim => ";",
		# name of the file which contains template for '-r 2048'
		service_definition_template => "",
		# service definition template default
		service_definition_template_default => 
			"# service \'\$THIS_NAME\$\' for host \'\$HOSTNAME\$\'\n".
			"define service {\n".
			" service_description \$THIS_NAME\$\n".
			" host_name \$HOSTNAME\$\n".
			" passive_checks_enabled 1\n".
			" active_checks_enabled 0\n".
			" check_command check_dummy!3 'Error: passive check has been called actively - check your config'\n".
			" use local-service\n".
			"}\n\n",
		# signals to cover
		signals		=> ["DUMMY","INT","TERM","QUIT","HUP","__WARN__"],
		# which RC if caught signal
		signal_rc	=> 3,
		# snmp_community
		snmp_community	=> "public",
		# snmp_community
		snmp_port	=> "161",
		# path to status.dat
		status_dat	=> "/usr/local/nagios/var/status.dat",
		# style of plus/minus char
		style_plus_minus => "style='color:#4444FF;line-height:0.3em;font-size:1.5em;cursor:crosshair'",
		# documentation URL to be added to child check tags
		tag_notes_link	=> "",
		# frame target for action_url and notes_url
		target		=> "_self",
		# internal development and test mode
		test		=> 0,
		# child check timeout (small t)
		timeout		=> 11,
		# global check_multi timeout (BIG T)
		TIMEOUT		=> 60,
		# directory where check_multi stores its temporary output files
		tmp_dir		=> "/tmp/check_multi",
		# temporary etc dir for local copies of configuration files
		tmp_etc		=> "/tmp/check_multi/etc",
		# octal permissions of tmp_dir
		tmp_dir_permissions => "41777",
		# characters which are allowed in macros
		valid_macro_chars => 'A-Za-z0-9\.\@\-\_\:',
		# characters which are allowed in tags
		valid_tag_chars => 'A-Za-z0-9\-\.\@\_\:\$',
		# verbosity, from 1 (less verbose) to 3 (much verbose)
		verbose		=> 0,
		# elements to be added to XML structure
		eml_elements	=> "name,rc,output,error,plugin,command,performance,starttime,endtime,runtime,type",
	},
	"variable" 	=> {
	},

);

#--- Array of commands
my @cmds = (
	#--- 0: parent check
	{
		command		=> "none",	# no command for parent
		critical	=> "",		# state definition: CRITICAL
		endtime		=> 0.0,		# end timestamp
		error		=> [ ],		# stderr and other errors
		state_default	=> [		# state definitions
					"1",			# OK
					"COUNT(WARNING) > 0", 	# WARNING
					"COUNT(CRITICAL) > 0", 	# CRITICAL
					"COUNT(UNKNOWN) > 0"	# UNKNOWN
				],
		state		=> [
					"1",			# OK
					"COUNT(WARNING) > 0", 	# WARNING
					"COUNT(CRITICAL) > 0", 	# CRITICAL
					"COUNT(UNKNOWN) > 0"	# UNKNOWN
				],
		hash		=> "",		# hash for all child checks
		nallchecks	=> 0,		# number of all child checks (with non-displayed checks)
		name		=> "",		# no predefined name for parent (-n option)
		nchecks		=> 0,		# number of child checks (displayed)
		number		=> 0,		# current number of check (0 for head)
		ok		=> "",		# state definition: OK
		output		=> "",		# output
		rc		=> $OK,		# return code
		runtime		=> 0.0,		# runtime in seconds
		sleeped		=> 0.0,		# time sleeped between child checks
		starttime	=> 0.0,		# start timestamp
		timeouttime	=> 0.0,		# timeout timestamp
		type		=> "head",	# this is the master of disaster
		unknown		=> "",		# state definition: UNKNOWN
		warning		=> "",		# state definition: WARNING
	}
	#--- elements 1..x will be added by parse_lines / parse_header
);
my %rc = (
	count		=> [ 0, 0, 0, 0,  ],	# count displayed RCs
	count_all	=> [ 0, 0, 0, 0,  ],	# cound all RCs
	list		=> [ [],[],[],[], ],	# list of displayed child checks
	list_all	=> [ [],[],[],[], ],	# list of all child checks
	match		=> [ 0, 0, 0, 0,  ],	#
);
my $check_multi = {
	cmds	=> \@cmds,
	rc	=> \%rc,
	opt	=> \%opt
};

#--- DEBUG typeglobs: 1. verbose 2. errors 3. detailed 4. programmers debugging
*DEBUG1=($opt{set}{verbose}>=1) ? \&debug_message : sub {};
*DEBUG2=($opt{set}{verbose}>=2) ? \&debug_message : sub {};
*DEBUG3=($opt{set}{verbose}>=3) ? \&debug_message : sub {};
*DEBUG4=($opt{set}{verbose}>=3) ? \&debug_message : sub {};

#-------------------------------------------------------------------------------
#--- subs ----------------------------------------------------------------------
#-------------------------------------------------------------------------------

#---
#--- process command line parameters and STDIN (if any)
#---
sub process_input {

	my @SAVEARGV=@ARGV;
	my $stdin="";

	#--- check version of modules
	if ($Getopt::Long::VERSION < 2.27) {
		print "Error: module Getopt::Long version $Getopt::Long::VERSION is too old, minimum version is 2.27\n";
		return $UNKNOWN;
	}

	if (! GetOptions(
		"f|filename=s"	=> \@{$opt{filename}},
		"h|help:+"	=> \$opt{help},
		"i|instant=s"	=> \$opt{set}{instant},
		"l|libexec=s"	=> \$opt{set}{libexec},
		"n|name=s"	=> \$opt{set}{name},
		"r|report=s"	=> \$opt{set}{report},
		"s|set=s"	=> \%{$opt{variable}},
		"t|timeout=i"	=> \$opt{set}{timeout},
		"T|TIMEOUT=i"	=> \$opt{set}{TIMEOUT},
		"v|verbose:+"	=> \$opt{set}{verbose},
		"V|version"	=> \$opt{version},
		"x|execute=s"	=> \@{$opt{execute}},
		"y|inventory:+"	=> \$opt{set}{inventory},
		"o|O|ok=s"	=> \$cmds[0]{state}[0],
		"w|W|warning=s"	=> \$cmds[0]{state}[1],
		"c|C|critical=s"=> \$cmds[0]{state}[2],
		"u|U|unknown=s"	=> \$cmds[0]{state}[3],)
	) {
		short_usage();
		return $UNKNOWN;
	}

	#--- redefine debug typeglobs, if verbose flag has been changed on cmdline
	{ 
	no warnings 'redefine';
	*DEBUG1=($opt{set}{verbose}>=1) ? \&debug_message : sub {};
	*DEBUG2=($opt{set}{verbose}>=2) ? \&debug_message : sub {};
	*DEBUG3=($opt{set}{verbose}>=3) ? \&debug_message : sub {};
	*DEBUG4=($opt{set}{verbose}>=3) ? \&debug_message : sub {};
	}

	#--- -V(ersion) option
	if ($opt{version}) {
		print "Version: $VERSION\n";
		return $UNKNOWN;
	}

	#--- -h/--help shows long usage, -hh extended usage
	DEBUG3("opt{help}=$opt{help}");
	if ($opt{help} == 1) {
		short_usage();
		long_usage();
		return $UNKNOWN;
	} elsif ($opt{help} == 2) {
		short_usage();
		long_usage();
		extended_usage();
		return $UNKNOWN;
	} elsif ($opt{help} > 2) {
		short_usage();
		long_usage();
		extended_usage();
		detailed_usage();
		return $UNKNOWN;
	}

	#--- check command line vars (--set KEY=VAL) and transfer it to $opt{set}
	foreach my $variable (sort keys(%{$opt{variable}})) {
		#--- export MULTI_$variable
		$ENV{"MULTI_".$variable}="$opt{variable}{$variable}";
		#--- if existing, overwrite, otherwise set $opt{set} variable
		if (defined($opt{set}{$variable})) {
			DEBUG3("overwriting \$opt{set}{$variable}:$opt{set}{$variable} with $opt{variable}{$variable}");
		} else {
			DEBUG3("setting \$opt{set}{$variable} with $opt{variable}{$variable}");
		}
		$opt{set}{"$variable"}="$opt{variable}{$variable}";
	}

	#--- determine some settings (user,hostname)
	$opt{set}{uid}=$<;
	if ($^O=~/Win32/) {
		#--- Win32? then use Win32 module
		if (module("Win32")) {
			DEBUG3("Win32 available");
			$opt{set}{user}=&Win32::LoginName;
			if (!$opt{set}{HOSTNAME}) {
				$opt{set}{HOSTNAME}=&Win32::NodeName;
			}
		} else {
			DEBUG2("Win32 not available");
			$opt{set}{user}="unknown";
			if (!$opt{set}{HOSTNAME}) {
				$opt{set}{HOSTNAME}=$ENV{COMPUTERNAME};
			}
		}
	} else {
		$opt{set}{user}=getpwuid($<);
		if (!$opt{set}{HOSTNAME}) {
			$opt{set}{HOSTNAME}=get_hostname("HOSTNAME");
		}
		if (!$opt{set}{HOSTADDRESS}) {
			$opt{set}{HOSTADDRESS}=get_hostname("HOSTADDRESS");
		}
	}

	#--- check_multi uses a temporary directory, per default /tmp/check_multi
	#--- 1. create if not yet done
	if (! my_mkdir("$opt{set}{tmp_dir}", $opt{set}{tmp_dir_permissions})) {
		print "Error: could not create tmp directory $opt{set}{tmp_dir} as user $opt{set}{user}\n";
		return $UNKNOWN;
	}
	#--- 2. check if tmp_dir has correct permissions
	if  ((stat("$opt{set}{tmp_dir}"))[2] != oct("$opt{set}{tmp_dir_permissions}") &&
		! chmod(oct("$opt{set}{tmp_dir_permissions}"), "$opt{set}{tmp_dir}") ) {
		print "Error: could not set tmp directory $opt{set}{tmp_dir} permissions to $opt{set}{tmp_dir_permissions} as user $opt{set}{user}\n";
		return $UNKNOWN;
	#--- 3. and at last: it has to be writeable
	} elsif (! -w "$opt{set}{tmp_dir}") {
		print "Error: cannot write to tmp directory $opt{set}{tmp_dir} as user $opt{set}{user}\n";
		return $UNKNOWN;
	}

	#---
	#--- getting commands - either per command file or per command parameter

	#--- first generate regex which contains all allowed commands (we need it later)
	$opt{cmdregex}=join('|',keys(%{$opt{commands}}));

	#--- allowed characters: 'a-zA-Z0-9_-'
	if ($opt{set}{name}=~/[\[\]]+/) {
		print "$MYSELF error: name \'$opt{set}{name}\' invalid - [ brackets ] are not allowed\n";
		return $UNKNOWN;
	}

	#--- loop over filename / URL / directory array
	for (my $i=0;$i<@{$opt{filename}}; $i++) {


		#--- only read STDIN if feeded by a PIPE, otherwise it would block when empty
		if ($opt{filename}[$i]=~/^-$/) {
			while (<STDIN>) { $stdin.=$_; }
			DEBUG3("found <STDIN> >$stdin<");

			#--- do we have input from check_multi XML report mode? (check_multi as filter)
			if ($stdin=~/check_multi_xml/) {
				#--- try to load module XML::Simple and bail out if not successful
				module("XML::Simple",1);

				#--- read in XML data and feed cmds structure
				my $in=XML::Simple::XMLin(
					$stdin,
					KeyAttr=>["CHILD"=>"no"],	# index: child no
					ForceArray=>["CHILD"],		# force array also for one child
					SuppressEmpty=>"",		# if empty, add "" instead of {} empty hash
				);

				if (module("Data::Dumper")) {
					DEBUG3("Data::Dumper available");
					DEBUG3("XML input after XMLin:\n" . Dumper($in));
				} else {
					$opt{set}{test}=0;
					DEBUG2("Data::Dumper not available");
				}

				if (exists($in->{PARENT})) {
					#--- restore some values from parent
					$cmds[0]{nchecks}=$in->{PARENT}->{nchecks};
					$cmds[0]{nallchecks}=$in->{PARENT}->{nallchecks};

					#--- child values
					for my $i (keys %{$in->{PARENT}->{CHILD}}) {
						$cmds[$i]{no}=$i; # index itself as 'no'
						$cmds[$i]{feeded}=1; # mark this cmd as feeded
						foreach my $att (keys %{$in->{PARENT}->{CHILD}->{$i}}) {
							$cmds[$i]{$att}=$in->{PARENT}->{CHILD}->{$i}->{$att};
						}
					}
				} else {
					#--- child values
					for my $no (keys %{$in->{$MYSELF}->{CHILD}}) {
						$cmds[$no]{no}=$no;	# index itself as 'no'
						$cmds[$no]{feeded}=1;	# mark this cmd as feeded
						foreach my $att (keys %{$in->{$MYSELF}->{CHILD}->{$no}}) {
							$cmds[$no]{$att}=$in->{$MYSELF}->{CHILD}->{$no}->{$att};
						}
						$ENV{"MULTI_${no}_NAME"}="$cmds[$no]{name}";
						$ENV{"MULTI_${no}_STATE"}="$cmds[$no]{rc}";
						$ENV{"MULTI_${no}_LABEL"}="$def{label}{$cmds[$no]{rc}}";
					}
				}
				DEBUG3("\@cmds after filling from XML input\n" . Dumper(\@cmds));
			} elsif ($stdin=~/($opt{cmdregex})\s*\[.*\]\s*=/) {
				DEBUG3("command file in STDIN detected");
				push @{$opt{execute}},split(/\n/,$stdin);
			}
		#--- 2. filename URL found
		} elsif ($opt{filename}[$i]=~/\/\//) {
			DEBUG3("http/ftp URL specified: $opt{filename}[$i]");

			#--- LWP module NOT loaded?
			if (!module("LWP::Simple")) {
				add_error(0,"LWP::Simple module not available, could not get command file $opt{filename}[$i]");
				next;
			}
			#--- split path components of URL
			my ($host,$path,$file)=("","","");
			if ($opt{filename}[$i]=~/.*\/\/([^\/]+)([\/]*.*)/) {
				$host=$1; $path=$2;
				if ($path=~/(.*)\/(.*$opt{set}{file_extension})/) {
					$path=$1; $file=$2;
				}
				chop($path) if ($path && $path=~/\S+\/$/);
				$path=$1 if ($path && $path=~/\/(\S+)$/);
				if ($path eq "" || $file eq "") {
					print "$MYSELF error: empty path or filename specified in URL $opt{filename}[$i]\n";
					return $UNKNOWN;
				}
				DEBUG4("URL:$opt{filename}[$i] hostname:$host path:$path file:$file");
			}

			#--- create directory to store saved config files
			my $cmdfile_path="$opt{set}{tmp_dir}/$opt{set}{tmp_etc}/$host/$path";
			if (! my_mkdir("$cmdfile_path", $opt{set}{tmp_dir_permissions})) {
				add_error(0,"Cannot create config directory path \'$cmdfile_path\':$!");
				return $UNKNOWN;
			}

			#--- use ctime to determine if config file should be updated after
			#--- having reached cmdfile_update_interval
			my $cmdfile_age=time-(stat("$cmdfile_path/$file"))[10] if (-f "$cmdfile_path/$file");
			if (!-f "$cmdfile_path/$file" ||
			    $cmdfile_age>$opt{set}{cmdfile_update_interval}) {
				DEBUG3("$cmdfile_path/$file age is $cmdfile_age, greater than allowed interval $opt{set}{cmdfile_update_interval}");
				my $RC=LWP::Simple::mirror($opt{filename}[$i],"$cmdfile_path/$file");
				if (LWP::Simple::is_success($RC) || $RC == 304) {
					DEBUG3("Mirroring $opt{filename}[$i] to $cmdfile_path/$file OK: RC $RC");
					$opt{filename}[$i]="$cmdfile_path/$file";
					`touch $opt{filename}[$i]`;
				} else {
					DEBUG2("Error: mirroring $opt{filename}[$i] to $cmdfile_path/$file failed: $RC");
				}
			} else {
				DEBUG3("$opt{filename}[$i] is already downloaded $cmdfile_path/$file");
				$opt{filename}[$i]="$cmdfile_path/$file";
			}

		#--- 2. directory found? replace directory with '*cmd' files from these directories
		} elsif (-d $opt{filename}[$i]) {
			splice(@{$opt{filename}},$i,1,glob "$opt{filename}[$i]/*$opt{set}->{file_extension}");

		#--- 3. and at last: the simple filename
		} else {
			if (! -f $opt{filename}[$i] || ! -r $opt{filename}[$i]) {
				DEBUG2("Error: filename $opt{filename}[$i] not existing or not readable");
			}
		}
	}

	#--- none of them? return UNKNOWN
	if (! $opt{filename}[0] && ! $opt{execute}[0] && !$stdin && (!$opt{set}{persistent})) {
		print "$MYSELF error: no config file(s) or command parameters specified\n";
		short_usage();
		return $UNKNOWN;
	}

	#--- inherit report settings from parent check_multi
	if ($opt{set}{report_inherit_mask} && defined($ENV{MULTI_set_report}) && "$ENV{MULTI_set_report}") {
		$opt{set}{report}=$ENV{MULTI_set_report} & $opt{set}{report_inherit_mask};
		DEBUG3("inherited reportstring $opt{set}{report} from parent check_multi, derived from $ENV{MULTI_set_report} with mask $opt{set}{report_inherit_mask}");
	}

	#--- report option candy - allow speaking strings '1+2+4+8' instead of bare '15'
	if ($opt{set}{report}=~/[0-9+]/) {
		my $sum=0;
		for (split(/\+/,$opt{set}{report})) {
			$sum+=$_;
		}
		DEBUG3("reportstring $opt{set}{report} converted into numerical value $sum");
		$opt{set}{report}=$sum;
	} elsif ($opt{set}{report}=~/[0-9]/) {
		# normal numeric value - do nothing
	} else {
		print "$MYSELF error: report option \'$opt{set}{report}\' contains invalid characters, allowed are numbers or 0-9+\n";
		return $UNKNOWN;
	}
	#--- report options - name
	if ($opt{set}{report} & $DETAIL_PERFORMANCE_LINK && !$opt{set}{name}) {
		$opt{set}{name}=$MYSELF;
		DEBUG3("performance report option set and no name defined: taking $MYSELF as name");
	}

	#--- report option - notes_url
	if ($opt{set}{report} & $DETAIL_NOTES_LINK && !$opt{set}{notes_url}) {
		if ($ENV{"MULTI_SERVICENOTESURL"}) {
			$opt{set}{notes_url}=$ENV{"MULTI_SERVICENOTESURL"};
			DEBUG3("notes report option set - taking SERVICENOTESURL ".$ENV{"MULTI_SERVICENOTESURL"});
		} elsif ($ENV{"${NAGIOS}_SERVICENOTESURL"}) {
			$opt{set}{notes_url}=$ENV{"${NAGIOS}_SERVICENOTESURL"};
			DEBUG3("notes report option set - taking $Nagios SERVICENOTESURL ".$ENV{"${NAGIOS}_SERVICENOTESURL"});
		} else {
			add_error(0,"process_input: Notes link report option chosen, but no environment variable SERVICENOTESURL found and no parameter notes_url specified");
		}
	}

	#--- Initialize empty PATH if none defined
	$ENV{PATH}="" unless ($ENV{PATH});
	my $path_sep=($^O=~/Win32/)?';':':';

	#--- set plugin_path at 2nd position of PATH variable
	$ENV{PATH}="$opt{set}{plugin_path}${path_sep}$ENV{PATH}" if ($opt{set}{plugin_path});

	#--- set libexec directory at the beginning of PATH variable
	$ENV{PATH}="$opt{set}{libexec}${path_sep}$ENV{PATH}" if ($opt{set}{libexec});

	#--- be sure that there is no newline at state definitions end
	foreach my $state (sort numerically keys %{$def{s2r}}) {
		chomp($cmds[0]{state}[$state]);
	}

	#--- timeout checking: overall TIMEOUT has to be greater than child check timeout
	if ($opt{set}{timeout} && $opt{set}{TIMEOUT} && $opt{set}{timeout} > $opt{set}{TIMEOUT}) {
		print "$MYSELF: error - child timeout $opt{set}{timeout}s must not be greater than parent timeout $opt{set}{TIMEOUT}s\n";
		return $UNKNOWN;
	}

	#--- add _the_ parent pid as indicator of the absolute first instance in a check_multi tree
	#--- there can be multiple recursive called instances and they need to detect which is the first
	$ENV{"MULTI_PPID"}=$$ if (!defined($ENV{"MULTI_PPID"}));

	#--- persistency - on the way to check_multi 2.0
	if ($opt{set}{test} && $opt{set}{persistent}) {

		#--- try to load module XML::Simple
		$opt{set}{use_xml_simple} = 1;
		unless (eval "require XML::Simple;1") {
			$opt{set}{use_xml_simple} = 0;
			DEBUG2("XML::Simple not available:$@");
		}

		#--- successful load?
		if ($opt{set}{use_xml_simple}) {

			#--- take filename to store persistent data from HOSTNAME-SERVICEDESC
			if ($ENV{MULTI_HOSTNAME} && $ENV{MULTI_SERVICEDESC}) {
				$cmds[0]{key}="$ENV{MULTI_HOSTNAME}-$ENV{MULTI_SERVICEDESC}";
			} elsif ($ENV{MULTI_HOSTNAME} && $ENV{"${NAGIOS}_SERVICEDESC"}) {
				$cmds[0]{key}="$ENV{MULTI_HOSTNAME}-".$ENV{"${NAGIOS}_SERVICEDESC"};
			} else {
				print "process_input: need HOSTNAME and SERVICEDESC for persistent mode.\nPlease specify -s HOSTNAME=<hostname> -s SERVICEDESC=<service description>\n";
				return $UNKNOWN;
			}

			#--- replace whitechar with underscore
			$cmds[0]{key}=~s/\s+/_/g;
			DEBUG3("command key: $cmds[0]{key}");

			#--- read persistent data
			my $in;
			my @xmlfiles=dir_entries("$opt{set}{tmp_dir}/$opt{set}{HOSTNAME}_$opt{set}{SERVICEDESC}",1);
			if ($#xmlfiles == 1) {
				DEBUG3("reading file $xmlfiles[0].xml");
				$in=XML::Simple::XMLin("$opt{set}{tmp_dir}/$opt{set}{HOSTNAME}_$opt{set}{SERVICEDESC}/".$xmlfiles[0].".xml",KeyAttr => [ ]);
			} else {
				DEBUG2("no persistency file found in $opt{set}{tmp_dir}/$opt{set}{HOSTNAME}_$opt{set}{SERVICEDESC}");
			}

			#--- read persistent data

			#--- debug output per Data::Dumper
			if (module("Data::Dumper")) {
				DEBUG3("loaded persistent data:");
				DEBUG3(Dumper($in));
			} else {
				$opt{set}{test}=0;
			}
		}
	}

	#--- do some debug output
	DEBUG3("$MYSELF - $VERSION");
	DEBUG3("command line: $0 >".join('< >',@SAVEARGV)."<");

	#--- any remaining parameters are orphaned - tell the caller what's going wrong here
	if (@ARGV) {
		print "Error: orphaned parameters found on command line:";
		for (my $i=1; $#ARGV>-1; $i++) {
			print " ARG$i:",shift(@ARGV);
		}
		print "\n";
		return $UNKNOWN;
	}

	#--- just debugging: print options
	foreach my $option (sort keys(%opt)) {
		DEBUG4("\$opt{$option}=$opt{$option}") if (defined($opt{$option}));
	}
	foreach my $option (sort keys(%{$opt{set}})) {
		DEBUG4("\$opt{set}{$option}=$opt{set}{$option}") if (defined($opt{set}{$option}));
	}

	return $OK;
}

#---
#--- short usage as quick reference
#---
sub short_usage {
print <<SHORTEOF;
Usage:
$MYSELF -f <config file> [-n name] [-t timeout] [-T TIMEOUT]
	[-r level] [-l libexec_path] [-s option=value]
$MYSELF [-h | --help] [-hh extended help] [-hhh complete help]
$MYSELF [-v | --verbose]
$MYSELF [-V | --version]

[ more infos on http://my-plugin.de/check_multi ]

SHORTEOF
}

#---
#--- long usage as detailed help (if anything else fails: read the instruction)
#---
sub long_usage {
print <<LONGEOF;
Common options:
-f, --filename
   config file which contains commands to be executed
   multiple files can be specified serially
   if filename is a directory, all '.cmd' files will be taken
   (file format follows nrpe style: command[tag]=plugin command line)
-n, --name
   multi plugin name (shown in output), default:$opt{set}{name}
-r, --report <level>
   specify level of details in output (level is binary coded, just sum up all options)
   default:$opt{set}{report}
   see more details with extended help option -hh
-s, --set <option>=<value>
   <KEY>=<VALUE> - set multi variable \$<KEY>\$ to <VALUE>
   see more details with complete help option -hhh
-t, --timeout
   timeout for one command, default:$opt{set}{timeout}
-T, --TIMEOUT
   TIMEOUT for all commands, default:$opt{set}{TIMEOUT}
-l, --libexec
   path to plugins, default:$opt{set}{libexec}
-h, --help
   print detailed help screen (extended help with -hh, complete help with -hhh)
-v, --verbose
   prints debug output (multiple -v extend debug level)
-V, --version
   print version information

Extended command line - command file options also available on command line:
-x, --execute "command [ tag ] = check_xyz"
-i, --instant "tag"
-y, --inventory
-w, --warning  <expression>
-c, --critical <expression>
-u, --unknown  <expression>
-o, --ok       <expression>

LONGEOF

}

#---
#--- extended usage - report options
#---
sub extended_usage {
print <<EXTENDED_EOF;
Extended options:
-r, --report <level>
   specify level of details in output (level is binary coded, just sum up all options)
   default:$opt{set}{report}
        1: mention service names in plugin_output, e.g.
           "24 plugins checked, 1 critical (http), 0 warning, 0 unknown, 23 ok"
        2: add HTML coloring of output for extinfo
        4: show STDERR (if any) in each line of plugin output
        8: show performance data (with check_multi_style)
       16: show full list of states, normally '0 warning' is omitted
       32: show old type of performance data (without check_multi style)
       64: add explicit status (OK,WARNING,CRITICAL,UNKNOWN) in front of output
      128: add action link if performance data available
      256: XML: print structured XML output
      512: Nagios 2 compatibility: one summary line of output only
     1024: show notes_url
     2048: print Nagios service definition for passive check feeded by check_multi
     4096: send_nsca: all child checks will be reported to Nagios via send_nsca
     8192: checkresults_file: all child checks are reported to Nagios via checkresults_file
    16384: print commands encoded (alternative to config files)
    32768: hide OK state child checks

EXTENDED_EOF
}

#---
#--- details for set options
#---
sub detailed_usage {
print <<DETAILED_EOF;
Set options:
-s, --set <option>=<value>
   <KEY>=<VALUE> - set multi variable \$<KEY>\$ to <VALUE>
   action_mouseover=<0|1> - mouse triggers PNP popup chart
   add_tag_to_list_entries=<0|1> - add tag as a prefix to list entries (default:$opt{set}{add_tag_to_list_entries})
   checkresults_dir=<path> - path to Nagios checkresults directory (direct insertion of checkresults)
   child_interval=<time> - time in seconds to sleep between child_checks, may be fraction of seconds (default:$opt{set}{child_interval})
   cmdfile_update_interval=<seconds> - update config file (if HTTP/FTP/...), default:$opt{set}{cmdfile_update_interval}
   collapse=<0|1> - should check_multi collapse child check_multi checks? default:$opt{set}{collapse}
   complain_unknown_macros=<0|1> - flag defines if check_multi shall complain about undefined macros, default:$opt{set}{complain_unknown_macros}
   config_dir=</path/to/config_dir> - path to check_multi config directory, default:$opt{set}{config_dir}
   cumulate_max_rows=<N> - number of rows which cumulate [ TAG ] should display
   cumulate_ignore_zero=<0|1> - should cumulate ignore zero values? default:$opt{set}{cumulate_ignore_zero}
   empty_output_is_unknown=<0|1> - should empty output be flagged as UNKNOWN?, default:$opt{set}{empty_output_is_unknown}
   exec_open3=<0|1> - use open3 method to exec child checks (to be tested though), default:$opt{set}{exec_open3}
   extinfo_in_status=<0|1> - show child checks also in Nagios status.cgi (HTML), default:$opt{set}{extinfo_in_status}
   feed_passive_autocreate=<0|1> - determines if passive feeded service descriptions should be created automatically, default:$opt{set}{feed_passive_autocreate}
   feed_passive_dir=<path> - path to passive service definition tree, default:$opt{set}{feed_passive_dir}
   file_extension=<ext> - standard file extension for config files, default:$opt{set}{file_extension}
   ignore_missing_cmd_file=<0|1> - do not complain if config file missing, default:$opt{set}{ignore_missing_cmd_file}
   illegal_chars=<characters> - specify characters to cleanup from command files
   image_path=</path/to/imagefiles> - relative path to Nagios imagefiles: default:$opt{set}{image_path}
   indent=<characters> - string to indent child checks, default:$opt{set}{indent}
   indent_label=<0|1> - indentation width is child check label width (HTML), default:$opt{set}{indent_label}
   libexec=</path/to/plugins> - directory to be added to search path: default:$opt{set}{libexec}
   livestatus=<livestatus_path> - Where is the livestatus Unix / TCP socket? default:$opt{set}{livestatus}
   loose_perfdata=<0|1> - accept non standard performance data, e.g. german commata, default:$opt{set}{loose_perfdata}
   name=<string> - label to be shown in output: <name> OK, default:$opt{set}{name}
   no_checks_rc=<RC> - which RC should be returned if no checks are defined, default:$opt{set}{no_checks_rc}
   notes_url=<URL> - URL to be added to child check, see Nagios notes_url
   objects_cache=</path/to/objects.cache> - position of nagios objects.cache file, default:$opt{set}{objects_cache}
   objects_cache_delimiter=<delimiter character> - character to separate object cache results, default:$opt{set}{objects_cache_delimiter}
   persistent=<0|1> - run check_multi in persistent mode, default:$opt{set}{persistent}
   pnp_url=</path/to/PNP-CGIs> - specify PNP URL, default:$opt{set}{pnp_url}
   pnp_add2url=<string> - PNP URL addon string, default:$opt{set}{pnp_add2url}
   pnp_version=<0.6|0.4> - pnp_version needed for mouseover popups? default:$opt{set}{pnp_version}
   report=<number> - binary coded report option, default:$opt{set}{report}
   report_inherit_mask=<0|1> - report option will be inherited and masked, default:$opt{set}{report_inherit_mask}
   send_nsca=<path/to/send_nsca> - path to send_nsca binary, default:$opt{set}{send_nsca}
   send_nsca_cfg=</path/to/send_nsca.cfg> -  path to send_nsca cfg file, default:$opt{set}{send_nsca_cfg}
   send_nsca_srv=<NSCA server> - server to send NSCA messages to, default:$opt{set}{send_nsca_srv}
   send_nsca_port=<port number> - port where NSCA daemon runs on NSCA server, default:$opt{set}{send_nsca_port}
   send_nsca_timeout=<seconds> -  timeout for send_nsca, default:$opt{set}{send_nsca_timeout}
   send_nsca_delim=<string> - delimiter characters to separate NSCA fields, default:$opt{set}{send_nsca_delim}
   service_definition_template=</path/to/template> - template for passive service definition
   status_dat=</path/to/status.dat> - where is Nagios status.dat? default:$opt{set}{status_dat}
   style_plus_minus=<HTML style> - style of HTML plus/minus characters
   suppress_perfdata=<tag1>[,<tag2>][,...] - do not provide perfdata for check tag1,tag2...
   suppress_service=<tag1>[,<tag2>][,...] - do not report service data for check tag1,tag2...
   tag_notes_link=<0|1> - notes URL as link in the child checks TAG (default:$opt{set}{tag_notes_link}
   target=<target> - frame target for action_url and notes_url, default:$opt{set}{target}
   timeout=<seconds> - child check timeout (small t), default:$opt{set}{timeout}
   TIMEOUT=<seconds> - global check_multi timeout (BIG T), default:$opt{set}{TIMEOUT}
   tmp_dir=<directory> - path for temporary files, default:$opt{set}{tmp_dir}
   tmp_dir_permissions=<octal> - permissions of temporary directory, default:$opt{set}{tmp_dir_permissions}
   tmp_etc=<directory> - path for local copies of command files, default:$opt{set}{tmp_etc}
   verbose=<0|1|2> - level of verbosity, from 1 (less verbose) to 3 (much verbose), default:$opt{set}{verbose}

DETAILED_EOF
}

#---
#--- load perl module and set variable for state
#---
sub module {
	my $module_name=shift;
	my $fatal=shift;
	my $module_parameters="";

	#--- split module name and parameters
	if ($module_name=~/(\S+)\s+(.*)\s+/) {
		$module_name=$1;
		$module_parameters=$2;
	}

	#--- check if module already loaded
	if (defined($opt{set}{"use_$module_name"}) && $opt{set}{"use_$module_name"}) {
		DEBUG3("Module \'$module_name\' already loaded");
	#--- load module
	} elsif (eval("use $module_name $module_parameters;1")) {
		#--- if successful
		$opt{set}{"use_$module_name"}=1;
		DEBUG3("Module \'$module_name\' loaded");
		return 1;
	} else {
		fatal("Perl module \'$module_name\' not available: $@") if ($fatal);
		$opt{set}{"use_$module_name"}=0;
		DEBUG3("Module \'$module_name\' not available");
		return 0;
	}
}

#---
#--- numerical sort
#---
sub numerically { $a <=> $b }

#---
#--- trim input string if found any chars from trim string
#---
sub mytrim {
	my ($src, $trim)=@_;
	DEBUG3("src:\'$src\' trim:\'$trim\'");
	return ($src=~/[$trim]*(.*)[$trim]*/) ? $1 : $src;
}

#---
#--- simple hexdump function
#---
sub hexdump {
	my $bytes_per_line=shift;
	my @bytes=map { sprintf("%02x", $_) } unpack('C*', join(' ',@_));
	my $hexstr="";
	my $line=0;
	while (@bytes) {
		$hexstr.=sprintf "\n%08o %s", $bytes_per_line*$line++, join(' ', splice(@bytes,0,$bytes_per_line));
	}
	return $hexstr;
}

#---
#--- human readable timestamp with japanese format, therefore sortable
#---
sub readable_sortable_timestamp {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(shift);
	return sprintf "%04d-%02d-%02d_%02d:%02d:%02d", 
		$year+1900, $mon+1, $mday,
		$hour, $min, $sec;
}

#---
#--- set alarm timeout for child checks
#---
sub set_alarm {
	my $no=shift;
	my $timeout=shift;

	#--- if timeout exceeds global timeout, reduce it accordingly
	if (int(time+$timeout) > int($cmds[0]{timeouttime})) {
		$timeout=int($cmds[0]{timeouttime})-int(time);
		$timeout=1 if ($timeout <= 0);
		DEBUG2(sprintf("set_alarm: $no - time exceeds global timeout with %d seconds, adjusting alarm to $timeout seconds", 
			int(time)+int($timeout)-int($cmds[0]{timeouttime})));
		add_error($no,"timeout reduced to $timeout seconds due to global timeout");
	}
	DEBUG3("$no - alarm set to $timeout seconds");
	$cmds[$no]{timeout}=$timeout;
	alarm($timeout);
}

#---
#--- create unique hash from input
#---
sub my_hash {
	my $string=shift;
	my $hash=crypt($string,"hash_$MYSELF");
	$hash=~s/(.)/sprintf("%02x", ord($1))/seg;
	DEBUG3("inputstring \'$string\' -> $hash");
	return $hash;
}

#--- 
#--- detection of numbers / strings in input
#--- gracefully taken from perlmonks (no 408607)
#---
sub seems_like_number {
	my $thing = shift;
	use warnings qw/FATAL all/;	# Promote warnings to fatal, so
					# they can be trapped. The effect is
					# lexically scoped.
	eval {
		$thing += 0;
	};
	DEBUG4(sprintf "input >$thing< has %sbeen identified as a number", $@ ? "not " : "");
	return $@ ? 0 : 1;
}

#---
#--- directories should not have separator characters
#---
sub valid_dir {
	my $dir=shift;
	my $separator=($^O eq "Win32") ? "\\" : "/";
	$dir=~s#$separator#_#g;
	return $dir;
}

#---
#--- creates directory (including leading paths) with given permissions
#---
sub my_mkdir {
	my ($directory,$perms)=@_;
	$perms="0755" if (!defined($perms));
	my $path="";
	my $separator=($^O eq "Win32") ? "\\" : "/";
	foreach my $part (split($separator,$directory)) {
		$path.=$part.$separator;
		if (! -d "$path") {
			return 0 if (! mkdir("$path", oct("$perms")));
		}
	}
	return 1;
}

#---
#--- return list of n files from a directory
#---
sub dir_entries {
	my $dir=shift;
	my $n=shift;

	#--- open directory
	opendir(my $dirhandle, $dir) || die "can't opendir $dir: $!";

	#--- read all existing files 
	my @entries = grep { ! /^\./ && -f "$dir/$_" } readdir($dirhandle);
	closedir $dirhandle;

	#--- return last n files
	return (sort { $b<=>$a } @entries)[0..$n-1];
}


#---
#--- creates string from all checks: name+type+command
#---
sub config_string {
	my $cmds=shift;
	my $string="";
	my $len=0;
	#--- add numnber, name, type and command to string
	for (my $i=0;$i<=$#{$cmds};$i++) {
		$string.=join('_',"_$i",$$cmds[$i]{name},$$cmds[$i]{type},$$cmds[$i]{command});
	}
	#--- replace all non alphanumerical characters with underscores
	$string=~s/[^A-Za-z0-9_-]+/_/g;
	#--- make sure, that there are no duplicate underscores
	$string=~s/__/_/g;
	return $string;
}

#---
#--- taken from perl cookbook: trim
#---
sub trim {
	my @output = @_;
   	for (@output) {
		s/^\s+//;	
		s/\s+$//;
	}
	return wantarray ? @output : $output[0];
}

#---
#--- substitute macros a la $HOSTNAME$ from environment
#---
sub substitute_macros {
	my ($input)=@_;


	if (! $input) {
		DEBUG3("empty input - nothing to do");
		return $input;
	}

	#--- first pass: replace 'normal' vars (without ':')
	#--- to prepare objects.cache substitution after that
	DEBUG3("checking expression \'$input\'");
	foreach my $match_var (($input=~/\$([$opt{set}{valid_macro_chars}]+)(?=\$)/gi)) {
 		if ($ENV{"MULTI_${match_var}"}) {
			DEBUG3("1st run: var - replacing var \'$match_var\' with \'$ENV{\"MULTI_${match_var}\"}\'");
			$input=~s/\$${match_var}\$/$ENV{"MULTI_${match_var}"}/gi;
		} elsif ($ENV{"${NAGIOS}_${match_var}"}) {
			DEBUG3("1st run: var - replacing var \'$match_var\' with \'$ENV{\"${NAGIOS}_${match_var}\"}\'");
			$input=~s/\$${match_var}\$/$ENV{"${NAGIOS}_${match_var}"}/gi;
		} else {
			DEBUG3("1st run: var - var \'$match_var\' matching neither MULTI_var nor ${NAGIOS}_var!");
		}
	}
	DEBUG3("expression \'$input\' after 1st run (nagios var substitution)");

	#--- NOT case insensitive macro checking (Nagios does not either :-/)
	#--- Note: due to blanks and other separating characters its possible, that 
	#--- eval statements with '$' are interpreted as variables. To include
	#--- the last '$' as potential character of the new macro, the backtrack
	#--- operator ?= is used.
	while ($input=~/\$([$opt{set}{valid_macro_chars}]+)(?=\$)/g) {
		my $var=$1;

		DEBUG3("checking var \'$var\'");
		#--- 1. check for MULTI var
		if (defined($ENV{"MULTI_${var}"})) {
			DEBUG3("2nd run - replacing env var \'MULTI_${var}\' with \'$ENV{\"MULTI_${var}\"}\'");
			$input=~s/\$$var\$/$ENV{"MULTI_${var}"}/g;
		#--- 2. check for nagios var
		} elsif (defined($ENV{"${NAGIOS}_${var}"})) {
			DEBUG3("2nd run - replacing env var \'${NAGIOS}_${var} with \'$ENV{\"${NAGIOS}_${var}\"}\'");
			$input=~s/\$$var\$/$ENV{"${NAGIOS}_${var}"}/g;
		#--- 3. check for own variable $opt{set}{VAR}
		} elsif (defined($opt{set}{"${var}"})) {
			DEBUG3("2nd run - replacing var \'${var}\' with \'$opt{set}{${var}}\'");
			$input=~s/\$$var\$/$opt{set}{"${var}"}/g;
		#--- 4. objects.cache substitution
		} elsif ($var=~/^[a-z_]+:[a-z_]+:[a-z_]+:/) {
			DEBUG3("2nd run - checking objects_cache var \'$var\'");
			my $query=objects_cache_query($var);
			my $substitution=parse_objects_cache($opt{set}{objects_cache},$query);
			DEBUG3("2nd run - replacing objects_cache var \'$var\' with \'$substitution\'");
			$input=~s/\$$var\$/$substitution/g;
		} else {
			DEBUG3("2nd run - \'$var\' was not handled - remove var");
			add_error($no, "Macro \$$var\$ not found") if ($opt{set}{complain_unknown_macros});
			$input=~s/\$$var\$//g;
		}
	}
	DEBUG3("expression \'$input\' after 2nd run: MULTI/NAGIOS/objects.cache substitution");
	return $input;
}

#---
#--- creates query object to search in objects.cache
#--- macro format: $type:return-field:search-field:search-value$
#--- 
sub objects_cache_query {
	my ($input)=@_;
	my $query=undef;
	if ($input=~/([a-z_]+):([a-z_]+):([a-z_]+:\S+.*)/) {
		$query->{type}=$1;
		$query->{target}=$2;
		$input=$3;
		while ($input=~/([^:]+):([^:]+)(.*)/) {
			$query->{expr}->{$1}=$2;
			$input=$3;
		}
		DEBUG4("searching for $query->{type} returning field $query->{target}");
		foreach my $key (keys %{$query->{expr}}) {
			DEBUG4("-> key:$key value:$query->{expr}->{$key}");
		}
	} else {
		add_error(0,"objects_cache_query: invalid query expression $input, should be \$type:return-field:key:expr[:key:expr]\$");
	}
	return $query;
}

#---
#--- parses objects.cache for all objects matching query object
#---
sub parse_objects_cache {
	my ($filename,$query)=@_;

	my %typelist=();
	my $objectcount=0;
	my $type="";
	my @results=();
	my $temp=undef;
	unless (open(OBJECTS_CACHE,"$filename")) {
		add_error(0,"parse_objects_cache: error opening file $filename:$!");
		return "";
	}
	while (<OBJECTS_CACHE>) {
		#--- begin of object, determine type
		if (/^define ([a-z0-9\_\-]+) {$/) {
			$type="$1";
			$typelist{$type}++;
			$objectcount++;
		} else {
			next;
		}

		#--- wrong object? continue search
		next if ("$type" ne "$query->{type}");

		#--- parse particular object
		while (<OBJECTS_CACHE>) {
			if (/^\t([a-z0-9\_\-]+)\s+(.*)$/) {
				$temp->{"$1"}="$2";
			} elsif (/^\t}$/) {
				#--- check if all query elements fit to current object
				my $match=1;
				foreach my $key (keys(%{$query->{expr}})) {
					DEBUG4("searching field $key for match of $query->{expr}->{$key}");
					if (!defined($temp->{$key})) {
						DEBUG4("type $type - field $key not found");
						$match=0;
						last;
					} elsif ($temp->{$key}!~/$query->{expr}->{$key}/) {
						DEBUG4("type $type - $temp->{$key} did not match $query->{expr}->{$key}");
						$match=0;
						last;
					} else {
						DEBUG4("type $type - $temp->{$key} matched");
					}
				}
				if ($match) {
					if (defined($temp->{"$query->{target}"})) {
						push @results, $temp->{"$query->{target}"};
					} else {
						add_error(0,"parse_objects_cache: could not find target field \"".$query->{target}."\"");
					}
				}
				$temp=undef;
				last;
			}
		}
	}
	if (!defined($typelist{$query->{type}})) {
		add_error(0,"parse_objects_cache: unknown object type \"$query->{type}\" - valid types are ".join(',',sort keys %typelist));
	} else {
		DEBUG3("$objectcount objects parsed");
		foreach my $type (sort keys %typelist) {
			DEBUG3("$typelist{$type} of $type");
		}
	}
	return (join($opt{set}{objects_cache_delimiter},@results));
}
#---
#--- replaces keywords with real results
#---
sub substitute_states {
	my ($input)=@_;

	#--- empty input?
	if (! $input) {
		DEBUG3("empty input - nothing to do");
		return $input;
	}

	#--- 1. replace COUNT(WARNING)
	$input=~s/\bCOUNT\s*\(\s*(OK)\s*\)/$rc{count}[$OK]/ig;
	$input=~s/\bCOUNT\s*\(\s*(WARNING)\s*\)/$rc{count}[$WARNING]/ig;
	$input=~s/\bCOUNT\s*\(\s*(CRITICAL)\s*\)/$rc{count}[$CRITICAL]/ig;
	$input=~s/\bCOUNT\s*\(\s*(UNKNOWN)\s*\)/$rc{count}[$UNKNOWN]/ig;
	$input=~s/\bCOUNT\s*\(\s*(ALL)\s*\)/$#cmds/ig;

	#--- 2. replace all STATES (OK)
	$input=~s/\b(OK)\b/$OK/ig;
	$input=~s/\b(WARNING)\b/$WARNING/ig;
	$input=~s/\b(CRITICAL)\b/$CRITICAL/ig;
	$input=~s/\b(UNKNOWN)\b/$UNKNOWN/ig;

	#--- 3. replace all vars with RC
	for (my $no=1;$no<=$#cmds;$no++) {
		$input=~s/\b($cmds[$no]{name})\b/$cmds[$no]{rc}/ig;
	}
	#--- 4. replace IGNORE
	$input=~s/\b(IGNORE)\b/(0==1)/ig;
	return $input;
}


#---
#--- sets settings as environment variables
#---
sub set_env_settings {
	#--- add all set options as environment variables, so client scripts can use it
	foreach my $option (sort keys(%{$opt{set}})) {
		$ENV{"MULTI_set_".$option}=$opt{set}{$option} if defined($opt{set}{$option});
	}
}

#---
#--- sets result environment variables
#---
sub set_env_vars {
	my ($no)=@_;

	my $name=($no==0)?"head":$cmds[$no]{name};

	if (defined($cmds[$no]{output})) {
		$ENV{"MULTI_$name"}="$cmds[$no]{output}";
	} elsif (defined(error($no))) {
		$ENV{"MULTI_$name"}=error($no);
	}
	$ENV{"MULTI_ERROR_$name"}=error($no);
	$ENV{"MULTI_STATE_$name"}="$cmds[$no]{rc}";
	$ENV{"MULTI_LABEL_$name"}="$def{label}{$cmds[$no]{rc}}";
	$ENV{"MULTI_${no}"}="$cmds[$no]{output}";
	$ENV{"MULTI_${no}_STATE"}="$cmds[$no]{rc}";
	$ENV{"MULTI_${no}_RC"}="$cmds[$no]{rc}";
	$ENV{"MULTI_${no}_LABEL"}="$def{label}{$cmds[$no]{rc}}";
	$ENV{"MULTI_${no}_RC_LABEL"}=($cmds[$no]{rc}<=$UNKNOWN)?$def{label}{$cmds[$no]{rc}}:"INVALID";

	DEBUG4(
		sprintf "environment vars set\n".
      "1. MULTI_$name=%s\n".
		"2. MULTI_STATE_$name=%s\n".
		"3. MULTI_ERROR_$name=%s\n".
		"4. MULTI_LABEL_$name=%s\n".
		"5. MULTI_${no}=%s\n".
		"6. MULTI_${no}_STATE=%s\n".
		"7. MULTI_${no}_LABEL=%s\n", 
			defined($ENV{"MULTI_$name"})?$ENV{"MULTI_$name"}:"undef",
			defined($ENV{"MULTI_STATE_$name"})?$ENV{"MULTI_STATE_$name"}:"undef",
			defined($ENV{"MULTI_ERROR_$name"})?$ENV{"MULTI_ERROR_$name"}:"undef",
			defined($ENV{"MULTI_LABEL_$name"})?$ENV{"MULTI_LABEL_$name"}:"undef",
			defined($ENV{"MULTI_${no}"})?$ENV{"MULTI_${no}"}:"undef",
			defined($ENV{"MULTI_${no}_STATE"})?$ENV{"MULTI_${no}_STATE"}:"undef",
			defined($ENV{"MULTI_${no}_LABEL"})?$ENV{"MULTI_${no}_LABEL"}:"undef",
	);
}

#---
#--- get environment vars
#---
sub get_env_vars {
	my ($pattern)=@_;
	my @result=();
	foreach my $key (sort keys(%ENV)) {
		push @result, "$key=$ENV{$key}" if ($key=~/$pattern/);
	}
	@result;
}

#---
#--- determines hostname from env vars or parameters
#---
sub get_hostname {
	my ($trigger)=shift || "ALL";
	my $hostname="";
	my $origin="";
	if ($trigger=~/HOSTNAME|ALL/ && $ENV{"MULTI_HOSTNAME"}) {
		$hostname=$ENV{"MULTI_HOSTNAME"};
		$origin="MULTI_HOSTNAME";
	} elsif ($trigger=~/HOSTADDRESS|ALL/ && $ENV{"MULTI_HOSTADDRESS"}) {
		$hostname=$ENV{"MULTI_HOSTADDRESS"};
		$origin="MULTI_HOSTADDRESS";
	} elsif ($trigger=~/HOSTNAME|ALL/ && $ENV{"${NAGIOS}_HOSTNAME"}) {
		$hostname=$ENV{"${NAGIOS}_HOSTNAME"};
		$origin="${NAGIOS}_HOSTNAME";
	} elsif ($trigger=~/HOSTADDRESS|ALL/ && $ENV{"${NAGIOS}_HOSTADDRESS"}) {
		$hostname=$ENV{"${NAGIOS}_HOSTADDRESS"};
		$origin="${NAGIOS}_HOSTADDRESS";
	} elsif ($trigger=~/HOSTNAME|ALL/) {
		$hostname=`uname -n`;
		$origin="uname -n";
	} elsif ($trigger=~/HOSTADDRESS/) {
		$hostname="127.0.0.1";
		$origin="localhost";
	}
	chomp($hostname);
	DEBUG3("Hostname is derived from $origin: $hostname");
	return $hostname;
}

#---
#--- print debug message (see Macro DEBUG)
#---
sub debug_message {
	#my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller(1);
	my @c0=caller(0); my @c1=caller(1);
	foreach (@_) {
		if ($opt{set}{verbose}>2) {
			printf "%08.5f %s ($c0[2]): ", time-$timezero, ($c1[3])?$c1[3]:"";
		}
		print "$_\n";
	}
}

#---
#--- install signal handlers
#---
sub install_signal_handler {
	my ($handler, @signals)=@_;
	my $all_signals=join(' ',sort keys %SIG);
	#print("install_signal_handler: signals to install: ".join(' ',@signals)."\n");
	#print("install_signal_handler: signals available: $all_signals\n");
	foreach my $signal (@signals) {
		if ($all_signals=~/$signal/) {
			#print("install_signal_handler: installing handler for signal $signal\n");
			$SIG{$signal} = \&signal_handler;
		} else {
			#print("install_signal_handler: signal $signal not existing\n");
		}
	}
}

#---
#--- got signal? report what we have and terminate savely
#---
sub signal_handler {
	my $signal=$_[0]; chomp $signal;
	my @loc=caller(1);

	#--- reinstall signal_handler (just paranoid ;)
	install_signal_handler(\install_signal_handler, $signal);

	#--- do reports before quitting
	add_error(0,"$signal generated at line $loc[2] in $loc[1] ($loc[3])");
	DEBUG4("with message $signal");
	&global_result_rating;
	DEBUG4("RC code $cmds[0]{rc}");
	&report_all;

	#--- cleanup end exit
	unlink $tmp_stdout, $tmp_stderr if (!$opt{set}{exec_open3});

	#--- exit with predefined exit code or with rc of parent
	my $RC=(defined($opt{set}{signal_rc})) ? $opt{set}{signal_rc} : $cmds[0]{rc};
	DEBUG4("signal_rc is $opt{set}{signal_rc} - exiting with RC code $RC");
	exit($RC);
}

#---
#--- add error(s) to error list
#---
sub add_error {
	my ($no)=shift;
	while (@_) {
		my $error=shift;
		next if (!$error);	# skip empty entries
		$error=~s/[$opt{set}{illegal_chars}]*//g if ($opt{set}{illegal_chars}); 
		$error=~s/\n//g;
		chomp($error);
		HTML::Entities::encode_entities($error) 
			if ($opt{set}{report} & $DETAIL_HTML && module("HTML::Entities"));

		if ($no >= 0 && $no <= $#cmds) {
			push @{$cmds[$no]{error}}, $error;
			debug_message("check [$no] - added error message \'$error\'") if ($opt{set}{verbose}>=3);
		} else {
			add_error(0,"add_error: invalid check index $no encountered");
		}
	}
}

#---
#--- return error from error list
#---
sub error {
	my ($no)=shift;
	my ($separator)=shift || ',';
	return "" if ($no < 0 || $no > $#cmds || ! ref($cmds[$no]{error}));
        my $errmsg=join($separator,@{$cmds[$no]{error}});
	return ($errmsg)?" [$errmsg]":"";
}

#---
#--- fatal - immediate exit with UNKNOWN state
#---
sub fatal {
	DEBUG3("exit with error message \'@_\'");
	print "$MYSELF fatal error: @_\n";
	exit $UNKNOWN;
}

#---
#--- create unique tmpfile and try to create it
#---
sub get_tmpfile {
	my ($path,$prefix)=@_;
	my $attempt=0;
	my $tmpfile="";

	#--- check existance of path and create it if necessary
	if (! my_mkdir($path,$opt{set}{tmp_dir_permissions})) {
		add_error(0,"get_tmpfile: error creating tmp_path $path with permissions $opt{set}{tmp_dir_permissions}:$!");
		return "";
	}

	#--- do 5 attempts to create tmpfile
	while ($attempt++ < 5) {
		my $suffix=int(rand(89999))+10000;
		$tmpfile="$path/$prefix.$suffix";
		next if (-f $tmpfile);
		if (open(TMP,">$tmpfile")) {
			close TMP;
			DEBUG4("created $tmpfile");
			return $tmpfile;
		}
	}
	fatal("get_tmpfile: giving up creating $tmpfile:$!");
}

#---
#--- read file and return its contents
#---
sub readfile {
	my ($filename)=@_;
	unless (open(FILE,$filename)) {
		add_error(0,"readfile: error opening $filename:$!");
	       	return "";
	}
	my @lines=<FILE>;
	close(FILE);
	return join("", @lines);
}

#---
#--- writes file and return its contents
#---
sub writefile {
	my ($filename,@lines)=@_;
	unless (open(FILE,">$filename")) {
		add_error(0,"writefile: error opening $filename:$!");
	       	return "";
	}
	print FILE @lines;
	close(FILE);
	return join("", @lines);
}

#---
#--- parse command file and call line parser
#---
sub parse_files {
	my ($filenames)=@_;	# allow multiple filenames (array reference)
	my (@lines)=();

	#--- loop over filenames
	foreach my $filename (@{$filenames}) {

		#--- encoded flat file
		if ($filename=~/%0A/) {
			$filename=~s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
			@lines=(split(/\n/,$filename));
			push @lines, ""; # add empty line to avoid last line eval problem
			DEBUG3("-" x 80);
			DEBUG3("parsing encoded $filename with $#lines lines");
			DEBUG3("-" x 80);
		#--- error opening file
		} elsif (!open(FILE, $filename)) {
			next if ($opt{set}{ignore_missing_cmd_file});
			add_error(0,"parse_files: cannot open config file $filename: $!");
			$cmds[0]{rc}=$UNKNOWN;	# head RC to UNKNOWN
			$cmds[0]{state}[$OK]="0==1";	# OK: false
			next;
		#--- read file
		} else {
			@lines=<FILE>;
			push @lines, ""; # add empty line to avoid last line eval problem
			close FILE;
			DEBUG3("-" x 80);
			DEBUG3("parsing file $filename with $#lines lines");
			DEBUG3("-" x 80);
		}

		parse_lines(@lines);

	}
	return $#cmds+1;
}


#---
#--- parse command array and fill %cmds structure
#---
sub parse_lines {
	my @lines=@_;
	my ($line,$cmd,$type,$name,$plugin,$pplugin,$expr,$lineno,$i,$last_command);

	$lineno=0;	# count sourcefile lines
	DEBUG4("starting with " . $#cmds . " command(s)");
	LINE: while (@lines) {

		$line = shift(@lines);
		chomp($line);
		$line = trim($line);

		#--- encode lines
		if ($opt{set}{report} & $DETAIL_ENCODE_COMMANDS) {
			$line=~s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			print $line;
			next LINE;
		}

		#--- count lines
		$lineno++;

		#--- skip empty lines and comments
		next LINE if ($line=~/^\s*$/);
		next LINE if ($line=~/^\s*#/);

		#--- remove unwanted characters from input line
		if ($opt{set}{illegal_chars} && $line=~/$opt{set}{illegal_chars}/) {
			DEBUG2("found illegal characters in line $lineno, removing them");
			$line=~s/$opt{set}{illegal_chars}//g;
		}

		#--- remove trailing backslash if any (compatibility mode)
		$line=~s/\\\s*$// if ($line=~/\\\s*/);

		#--- header line (regex contains all allowed commands)
		if (($type,$name,$cmd)=($line=~/^\s*($opt{cmdregex})\s*\[\s*(\S[$opt{set}{valid_tag_chars}]*\S|\S{1})\s*\]\s*=\s*(.*)\s*/i)) {

			DEBUG4("command detected: command:$1 tag:$2 rest:$3");
			#--- remove remaining blanks 
			$name=trim($name);

			#--- macros?
			$name=substitute_macros($name);

			#--- still macro '$' in name? then macro was not substituted
			if ($name=~/\$([^\$]+)\$/) {
				add_error(0,"parse_lines: tag \'$name\' is invalid - macro \$$1\$ not found");
				next LINE;
			} elsif ($name eq "") {
				add_error(0,"parse_lines: empty tag \'\' is invalid");
				next LINE;
			} elsif ($name=~/^[0-9]+$/) {
				add_error(0,"parse_lines: pure numerical tag \'$name\' is invalid");
				next LINE;
			} elsif ($name=~/[\[\]]+/) {
				add_error(0,"parse_lines: tag \'$name\' is invalid - [ brackets ] are not allowed");
				next LINE;
			}

			#--- store vars, last_command contains index of cmd or name of state
			$last_command=parse_header($type,$name,$cmd,$lineno);

		#--- proper header line with invalid keyword
		} elsif ($line=~/^\s*(\w+)\s*\[\s*(\S[$opt{set}{valid_tag_chars}]*\S|\S{1})\s*\]\s*=\s*(.*)\s*/) {
			DEBUG4("invalid keyword detected: $1");
			add_error(0,"Invalid keyword \'$1\' specified, valid are \'$opt{cmdregex}\'");
			return;

		#--- continuation line for previous command
		} else {
			if (!defined($last_command)) {
				DEBUG4("continuation line detected - no allowed header before: $line");
				add_error(0,"parse_lines: invalid format in line $lineno: $line");
				next LINE;
			} elsif ($last_command=~/OK|UNKNOWN|WARNING|CRITICAL/i) {
				DEBUG4("continuation line detected: state continuation for ".lc($last_command).": $line");
				$cmds[0]{state}[$def{code}{lc($last_command)}].=$line;
			} elsif ($last_command > 0) {
				DEBUG4("continuation line detected, appending \'$line\' to command \'$cmds[$last_command]{command}\'");
				$cmds[$last_command]{command}.=' '.$line;
			} else {
				DEBUG4("continuation line detected: invalid format: $line");
				add_error(0,"parse_lines: invalid format in line $lineno: $line");
				next LINE;
			}
		}
	}
	DEBUG4("end - now we have " . $#cmds . " command(s)");
}

#---
#--- fills child check attributes related to the type of check
#---
sub parse_header {
	my ($type,$name,$cmd,$lineno)=@_;
	my ($i,$key,$host,$service);

	#--- split name::key. If key is not available, its empty.
	($name,$key)=split(/::/,$name);
	$key="" if (!defined($key));
	$key=lc($key);	# force lower key for keys
	DEBUG4("type:$type name:$name key:$key cmd:$cmd lineno:$lineno");

	#--- $name = 'head'? then $i = 0
	if ($name eq "HEAD") {
		DEBUG4("head specified - settings values for \$cmds[0]");
		$i=0;

	#--- overloading: if child check with same name exists,
	#--- overload its attributes. Otherwise append new check
	} elsif ($type=~/($opt{cmdregex})/) {
		for ($i=1; $i<=$#cmds;$i++) {
			last if ($cmds[$i]{name} eq $name);
		}
		if (defined($cmds[$i])) {
			DEBUG2(defined($cmds[$i]{command})
				? "parse_header: overloaded \'$name\' with type $type \'$cmd\'"
				: "parse_header: added \'$name\' with type $type \'$cmd\'"
			);
		}
	}

	#--- format: 'attribute [ tag::variable ] = value'
	if ($type eq "attribute") {
		#--- 1. 'attribute [ variable ] = value' - update set variable
		if ($key eq "") {
			if (!defined($opt{set}{$name})) {
				DEBUG2("created variable \$opt{set}{$name}=$cmd");
			} else {
				DEBUG2("updated variable \$opt{set}{$name}=$cmd");
			}
			$opt{set}{$name}=$cmd;
		#--- 2. 'attribute [ tag::variable ] = value' - tag not found
		} elsif (! defined($cmds[$i]) || !defined($cmds[$i]{name})) {
			add_error(0,"parse_header: attribute [ ${name}::${key} ] can not be set: child check with name \'$name\' not found");
			return undef;
		#--- 3. 'attribute [ tag::variable ] = value' - update attribute
		} else {
			if (!defined($cmds[$i]{$key})) {
				DEBUG2("key $key attribute \'$cmd\' inserted into object $name (\$cmds[$i])");
			} else {
				DEBUG2("key $key attribute \'$cmd\' changed in object $name (\$cmds[$i]), was: \'$cmds[$i]{$key}\'");
			}
			$cmds[$i]{$key}=$cmd;
		}
	#--- format: 'command [ tag[::plugin] ] = plugin command line'
	} elsif ($type eq "command") {

		#--- increase counters if no overload
		if (!defined($cmds[$i]{number})) {
			$cmds[0]{nallchecks}++;
			$cmds[0]{nchecks}++;
			$cmds[$i]{number}=$cmds[0]{nchecks};
		}

		#--- normally the plugin name is the first token of $cmd
		my $plugin="";
		if ($cmd=~/\s+/) {
			$plugin=(split(/\s+/,"$cmd"))[0];
		} else {
			$plugin=$cmd;
		}
		$plugin=~s/.*\///g; 	# basename(plugin) (thx Gerhard)

		$cmds[$i]{type}=$type;
		$cmds[$i]{name}=$name;
		$cmds[$i]{command}=$cmd;
		$cmds[$i]{plugin}=$plugin;
		$cmds[$i]{pplugin}=($key)?$key:$plugin;
		$cmds[$i]{ok}="";
		$cmds[$i]{warning}="";
		$cmds[$i]{critical}="";
		$cmds[$i]{unknown}="";
		$cmds[$i]{rc}=$OK;
		$cmds[$i]{displayed}=1;
		$cmds[$i]{output}="";
		$cmds[$i]{error}=[];
		$cmds[$i]{runtime}=0;
		if ($opt{set}{suppress_perfdata} &&
			$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
			$cmds[$i]{process_perfdata}=0;
			DEBUG2("perfdata of [ $name ] will be suppressed");
		} else {
			$cmds[$i]{process_perfdata}=1;
		}

	#--- format: 'cumulate  [ tag[::plugin] ] = expression'
	} elsif ($type eq "cumulate") {

		#--- increase counters if no overload
		if (!defined($cmds[$i]{number})) {
			$cmds[0]{nallchecks}++;
			$cmds[0]{nchecks}++;
			$cmds[$i]{number}=$cmds[0]{nchecks};
		}

		$cmds[$i]{type}=$type;
		$cmds[$i]{name}=$name;
		$cmds[$i]{command}=$cmd;
		$cmds[$i]{plugin}=$type;
		$cmds[$i]{pplugin}="";
		$cmds[$i]{ok}="";
		$cmds[$i]{warning}="";
		$cmds[$i]{critical}="";
		$cmds[$i]{unknown}="";
		$cmds[$i]{rc}=$OK;
		$cmds[$i]{displayed}=1;
		$cmds[$i]{output}="";
		$cmds[$i]{error}=[];
		$cmds[$i]{runtime}=0;
		if ($opt{set}{suppress_perfdata} &&
			$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
			$cmds[$i]{process_perfdata}=0;
			DEBUG2("perfdata of [ $name ] will be suppressed");
		} else {
			$cmds[$i]{process_perfdata}=1;
		}

	#--- format: 'eval    [ tag[::plugin] ] = expression'
	} elsif ($type eq "eval") {

		$cmds[$i]{type}=$type;
		$cmds[$i]{name}=$name;
		$cmds[$i]{command}=$cmd;
		$cmds[$i]{plugin}="eval";
		$cmds[$i]{pplugin}=($key)?$key:"eval";
		$cmds[$i]{ok}="";
		$cmds[$i]{warning}="";
		$cmds[$i]{critical}="";
		$cmds[$i]{unknown}="";
		$cmds[$i]{rc}=$OK;
		$cmds[0]{nallchecks}++;
		$cmds[$i]{displayed}=0;
		$cmds[$i]{output}="";
		$cmds[$i]{error}=[];
		$cmds[$i]{runtime}=0;
		if ($opt{set}{suppress_perfdata} &&
			$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
			$cmds[$i]{process_perfdata}=0;
			DEBUG2("perfdata of [ $name ] will be suppressed");
		} else {
			$cmds[$i]{process_perfdata}=1;
		}

	#--- format: 'eeval   [ tag[::plugin] ] = expression'
	} elsif ($type eq "eeval") {
		#--- increase counters if no overload
		if (!defined($cmds[$i]{number})) {
			$cmds[0]{nallchecks}++;
			$cmds[0]{nchecks}++;
			$cmds[$i]{number}=$cmds[0]{nchecks};
		}

		$cmds[$i]{type}=$type;
		$cmds[$i]{name}=$name;
		$cmds[$i]{command}=$cmd;
		$cmds[$i]{plugin}="eval";
		$cmds[$i]{pplugin}=($key)?$key:"eval";
		$cmds[$i]{ok}="";
		$cmds[$i]{warning}="";
		$cmds[$i]{critical}="";
		$cmds[$i]{unknown}="";
		$cmds[$i]{rc}=$OK;
		$cmds[$i]{displayed}=1;
		$cmds[$i]{output}="";
		$cmds[$i]{error}=[];
		$cmds[$i]{runtime}=0;
		if ($opt{set}{suppress_perfdata} &&
			$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
			$cmds[$i]{process_perfdata}=0;
			DEBUG2("perfdata of [ $name ] will be suppressed");
		} else {
			$cmds[$i]{process_perfdata}=1;
		}

	#--- format: 'livestatus [ tag[::plugin] ] = host'
	#--- format: 'livestatus [ tag[::plugin] ] = host:service'
	} elsif ($type eq "livestatus") {

		if (!$opt{set}{use_monitoring_livestatus}) {
			#--- try to load module Monitoring::Livestatus
			$opt{set}{use_monitoring_livestatus}=1;
			unless (eval "require Monitoring::Livestatus;1") {
				$opt{set}{use_monitoring_livestatus} = 0;
				add_error(0,"parse_header: perl module Monitoring::Livestatus is not installed, could not add check");
				DEBUG2("Monitoring::Livestatus not available:$@");
				return -1;
			}
		}
		#--- livestatus: split host and service from command, format: host:service
		if ((my $host,$service)=($cmd=~/\s*([^:]*)\s*\:\s*(.*)\s*/)) {
			$host=substitute_macros($host);
			$service=substitute_macros($service);

			DEBUG4("expanding livestatus host:service \'$host:$service\'");
			my @result=expand_livestatus_service($opt{set}{livestatus}, $host, $service);

			if (!defined($result[0])) {
				add_error(0,"Could not expand host:service \'$host:$service\' from livestatus $opt{set}{livestatus}");
				return -1;
			}
			while(@result) {
				#--- increase counters if no overload
				if (!defined($cmds[$i]{number})) {
					$cmds[0]{nallchecks}++;
					$cmds[0]{nchecks}++;
					$cmds[$i]{number}=$cmds[0]{nchecks};
				}

				$cmds[$i]{type}=$type;
				$cmds[$i]{command}=$cmd;
				$cmds[$i]{ok}="";
				$cmds[$i]{warning}="";
				$cmds[$i]{critical}="";
				$cmds[$i]{unknown}="";
				$cmds[$i]{displayed}=1;
				$cmds[$i]{runtime}=0;
				$cmds[$i]{error}=[];
				$cmds[$i]{host}=shift(@result);
				$cmds[$i]{service}=shift(@result);
				$cmds[$i]{rc}=shift(@result);
				$cmds[$i]{output}=shift(@result);
				$cmds[$i]{performance}=shift(@result);
				$cmds[$i]{plugin}="lifestatus";
				$cmds[$i]{pplugin}=shift(@result);
				if ($cmds[$i]{host} eq "-1") {
					$cmds[$i]{host}="UNKNOWN";
					$cmds[$i]{service}="UNKNOWN";
				}
				$cmds[$i]{name}=($opt{set}{add_tag_to_list_entries})?"${name}_":"";
				$cmds[$i]{name}.="$cmds[$i]{host}_$cmds[$i]{service}";
				$cmds[$i]{name}=~s/[^A-Z0-9_-]+/_/gi;
				if ($opt{set}{suppress_perfdata} &&
					$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
					$cmds[$i]{process_perfdata}=0;
					DEBUG2("perfdata of [ $name ] will be suppressed");
				} else {
					$cmds[$i]{process_perfdata}=1;
				}
				DEBUG4("added host:$cmds[$i]{host} / service:$cmds[$i]{service} / output:$cmds[$i]{output}");
				$i++;
			}
		} elsif (($host)=($cmd=~/\s*([^:]*)\s*/)) {
			$host=substitute_macros($host);
			DEBUG4("expanding livestatus host \'$host\'");
			my @result=expand_livestatus_host($opt{set}{livestatus}, $host);

			if (!defined($result[0])) {
				add_error(0,"Could not expand host \'$host\' from livestatus $opt{set}{livestatus}");
				return -1;
			}
			while(@result) {
				#--- increase counters if no overload
				if (!defined($cmds[$i]{number})) {
					$cmds[0]{nallchecks}++;
					$cmds[0]{nchecks}++;
					$cmds[$i]{number}=$cmds[0]{nchecks};
				}

				$cmds[$i]{type}=$type;
				$cmds[$i]{command}=$cmd;
				$cmds[$i]{ok}="";
				$cmds[$i]{warning}="";
				$cmds[$i]{critical}="";
				$cmds[$i]{unknown}="";
				$cmds[$i]{displayed}=1;
				$cmds[$i]{runtime}=0;
				$cmds[$i]{error}=[];
				$cmds[$i]{host}=shift(@result);
				$cmds[$i]{rc}=shift(@result);
				$cmds[$i]{output}=shift(@result);
				$cmds[$i]{performance}=shift(@result);
				$cmds[$i]{plugin}="lifestatus";
				$cmds[$i]{pplugin}=shift(@result);
				if ($cmds[$i]{host} eq "-1") {
					$cmds[$i]{host}="UNKNOWN";
				}
				$cmds[$i]{name}=($opt{set}{add_tag_to_list_entries})?"${name}_":"";
				$cmds[$i]{name}.="$cmds[$i]{host}";
				$cmds[$i]{name}=~s/[^A-Z0-9_-]+/_/gi;
				if ($opt{set}{suppress_perfdata} &&
					$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
					$cmds[$i]{process_perfdata}=0;
					DEBUG2("perfdata of [ $name ] will be suppressed");
				} else {
					$cmds[$i]{process_perfdata}=1;
				}
				DEBUG4("added host:$cmds[$i]{host} / output:$cmds[$i]{output}");
				$i++;
			}
		} else {
			add_error(0,"parse_header: invalid host or service in livestatus line \'$lineno\', format should be \'livestatus [ name ] = host[:service]\'");
			return -1;
		}

	#--- format: 'snmp   [ tag ] = OID'
	} elsif ($type eq "snmp") {
		#--- increase counters if no overload
		if (!defined($cmds[$i]{number})) {
			$cmds[0]{nallchecks}++;
			$cmds[0]{nchecks}++;
			$cmds[$i]{number}=$cmds[0]{nchecks};
		}

		$cmds[$i]{type}=$type;
		$cmds[$i]{name}=$name;
		$cmds[$i]{translate}=0xff;
		if ($cmd=~/\s*([^:]*)\s*\:\s*(.*)\s*\:\s*(.*)\s*/) {
			$cmds[$i]{host}=$1;
			$cmds[$i]{host}=substitute_macros($cmds[$i]{host});
			$cmds[$i]{command}=$2;
			$cmds[$i]{translate}=$3;
		} elsif ($cmd=~/\s*([^:]*)\s*\:\s*(.*)\s*/) {
			$cmds[$i]{host}=$1;
			$cmds[$i]{host}=substitute_macros($cmds[$i]{host});
			$cmds[$i]{command}=$2;
		} else {
			$cmds[$i]{host}=$opt{set}{HOSTNAME};
			$cmds[$i]{command}=$cmd;
		}
		$cmds[$i]{plugin}="snmp";
		$cmds[$i]{pplugin}=($key)?$key:"snmp";
		$cmds[$i]{rc}=$OK;
		$cmds[$i]{ok}="";
		$cmds[$i]{warning}="";
		$cmds[$i]{critical}="";
		$cmds[$i]{unknown}="";
		$cmds[$i]{displayed}=1;
		$cmds[$i]{output}="";
		$cmds[$i]{error}=[];
		$cmds[$i]{runtime}=0;
		if ($opt{set}{suppress_perfdata} &&
			$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
			$cmds[$i]{process_perfdata}=0;
			DEBUG2("perfdata of [ $name ] will be suppressed");
		} else {
			$cmds[$i]{process_perfdata}=1;
		}

	#--- format: 'statusdat [ tag[::plugin] ] = host'
	#--- format: 'statusdat [ tag[::plugin] ] = host, service'
	} elsif ($type eq "statusdat") {

		$cmd=substitute_macros($cmd);

		#--- statusdat service: split host and service from command, format: host:service
		if ($cmd=~/\s*([^:]*)\s*\:\s*(.*)\s*/) {
			DEBUG4("host:service format - expanding $1:$2");
			my @result=expand_status_dat_service($opt{set}{status_dat}, $1, $2);
			if (!defined($result[0])) {
				add_error(0,"Could not expand host:service $1:$2 from status_dat $opt{set}{status_dat}");
				return -1;
			}
			while(@result) {
				#--- increase counters if no overload
				if (!defined($cmds[$i]{number})) {
					$cmds[0]{nallchecks}++;
					$cmds[0]{nchecks}++;
					$cmds[$i]{number}=$cmds[0]{nchecks};
				}

				$cmds[$i]{type}=$type;
				$cmds[$i]{command}=$cmd;
				$cmds[$i]{plugin}=undef;
				$cmds[$i]{pplugin}=undef;
				$cmds[$i]{ok}="";
				$cmds[$i]{warning}="";
				$cmds[$i]{critical}="";
				$cmds[$i]{unknown}="";
				$cmds[$i]{displayed}=1;
				$cmds[$i]{output}="";
				$cmds[$i]{error}=[];
				$cmds[$i]{runtime}=0;
				$cmds[$i]{rc}=$OK;
				$cmds[$i]{host}=shift(@result);
				$cmds[$i]{service}=shift(@result);
				$cmds[$i]{performance}="";
				$cmds[$i]{pplugin}="";
				$cmds[$i]{plugin}="statusdat";
				if ($cmds[$i]{host} eq "-1") {
					$cmds[$i]{host}="UNKNOWN";
					$cmds[$i]{service}="UNKNOWN";
				}
				$cmds[$i]{name}=($opt{set}{add_tag_to_list_entries})?"${name}_":"";
				$cmds[$i]{name}.="$cmds[$i]{host}_$cmds[$i]{service}";
				$cmds[$i]{name}=~s/[^A-Z0-9_-]+/_/gi;
				if ($opt{set}{suppress_perfdata} &&
					$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
					$cmds[$i]{process_perfdata}=0;
					DEBUG2("perfdata of [ $name ] will be suppressed");
				} else {
					$cmds[$i]{process_perfdata}=1;
				}
				DEBUG4("added host:$cmds[$i]{host} / service:$cmds[$i]{service}");
				if (module("Data::Dumper")) {
					DEBUG4(Dumper($cmds[$i]));
				}
				$i++;
			}
		#--- statusdat host: split host from command, format: host
		} elsif ($cmd=~/\s*([^:]*)\s*/) {
			DEBUG4("host format - expanding $1");
			my @result=expand_status_dat_host($opt{set}{status_dat}, $1);
			if (!defined($result[0])) {
				add_error(0,"Could not expand host $1 from status_dat $opt{set}{status_dat}");
				return -1;
			}
			while(@result) {
				#--- increase counters if no overload
				if (!defined($cmds[$i]{number})) {
					$cmds[0]{nallchecks}++;
					$cmds[0]{nchecks}++;
					$cmds[$i]{number}=$cmds[0]{nchecks};
				}

				$cmds[$i]{type}=$type;
				$cmds[$i]{command}=$cmd;
				$cmds[$i]{plugin}=undef;
				$cmds[$i]{pplugin}=undef;
				$cmds[$i]{ok}="";
				$cmds[$i]{warning}="";
				$cmds[$i]{critical}="";
				$cmds[$i]{unknown}="";
				$cmds[$i]{rc}=$OK;
				$cmds[$i]{displayed}=1;
				$cmds[$i]{output}="";
				$cmds[$i]{error}=[];
				$cmds[$i]{runtime}=0;
				$cmds[$i]{host}=shift(@result);
				$cmds[$i]{performance}="";
				$cmds[$i]{pplugin}="";
				$cmds[$i]{plugin}="statusdat";
				if ($cmds[$i]{host} eq "-1") {
					$cmds[$i]{host}="UNKNOWN";
				}
				$cmds[$i]{name}=($opt{set}{add_tag_to_list_entries})?"${name}_":"";
				$cmds[$i]{name}.="$cmds[$i]{host}";
				$cmds[$i]{name}=~s/[^A-Z0-9_-]+/_/gi;
				if ($opt{set}{suppress_perfdata} &&
					$opt{set}{suppress_perfdata}=~/\b$name\b/i) {
					$cmds[$i]{process_perfdata}=0;
					DEBUG2("perfdata of [ $name ] will be suppressed");
				} else {
					$cmds[$i]{process_perfdata}=1;
				}
				DEBUG4("added host:$cmds[$i]{host}");
				$i++;
			}
		} else {
			add_error(0,"parse_header: invalid host [or service] in statusdat line \'$lineno\', format should be \'statusdat [ name ] = host[:service]\'");
			return -1;
		}

	#--- format: state [ {UNKNOWN,WARNING,CRITICAL,OK} ] = <perl expression>
	} elsif ($type eq "state") {
		#DEBUG1("def{code}{$name}:$def{code}{$name}");
		if (!defined($def{code}{$name})) {
			add_error(0,"parse_header: invalid state code specified in line $lineno: $cmd");
			return -1;
		}
		#--- store state expression only if NOT set via commandline
		if (!defined($opt{lc($name)})) {
			DEBUG3("added state{$def{code}{$name}} expression: $cmd");
			$cmds[0]{state}[$def{code}{$name}]=$cmd;
		} else {
			DEBUG3("command line precedence over state expression. Using \$opt{$name}: $opt{$name}");
		}
		$i=$name;

	#--- format: output [ tag ] = formatstr, parm1, parm2, ...
	} elsif ($type eq "output") {
		my $found=0;
		if ($name=~/^(\d+)$/ && $name<=$#cmds) {
			($cmds[$1]{fmtstr},@{$cmds[$1]{parms}})=split(',',$cmd);
			$found=1;
		} elsif ($name=~/head/i) {
			($cmds[0]{fmtstr},@{$cmds[0]{parms}})=split(',',$cmd);
			$found=1;
		} else {
			for ($i=0; $found==0 && $i<=$#cmds;$i++) {
				if ($cmds[$i]{name} eq $name) {
					($cmds[$i]{fmtstr},@{$cmds[$i]{parms}})=split(',',$cmd);
					$found=1;
				}
			}
		}
		if (!$found) {
			add_error("parse_header: invalid tag output [ $name ] specified in line $lineno, " .
				"possible reason: defined output statement before command / eval statement");
			return -1;
		}

	#--- no type found? then its invalid
	} else {
		add_error(0,"store_header: unknown command type \'$type\'");
		return -1;
	}

	#--- return value: either number of changed command or name of state
	return $i;
}

#---
#--- execute command number $no from %cmds
#---
sub exec_command {
	my ($no)=@_;

	#--- start with proper RC
	$?=0;

	#--- at runtime: substitute $MACRO$ macros and states
	$cmds[$no]{command}=substitute_macros($cmds[$no]{command});
	chomp($cmds[$no]{command});
	$ENV{"MULTI_${no}_NAME"}=$cmds[$no]{name};
	DEBUG4("[$no] = >$cmds[$no]{command}<");

	#--- measure command runtime;
	$cmds[$no]{starttime}=time;

	if ($cmds[$no]{type} eq "command" || $cmds[$no]{type} eq "cumulate") {

		eval {
			set_alarm($no,$opt{set}{timeout});

			#--- classic execution with temporary files
			if (!$opt{set}{exec_open3}) {

				#--- prepare tmpfiles for stdout and stderr
				$tmp_stdout=&get_tmpfile("$opt{set}{tmp_dir}", "${MYSELF}_stdout_$$");
				$tmp_stderr=&get_tmpfile("$opt{set}{tmp_dir}", "${MYSELF}_stderr_$$");

				#--- execute command and store stdout/stderr/return code
				if (!defined(my $child=fork())) {
					fatal("cannot fork: $!");
				#--- child: execute command
				} elsif ($child==0) {
					#--- assign own process group for child check, thx Henry Rolofs
					setpgrp(0,0) if ($^O!~/Win32/);
					exec("$cmds[$no]{command} 1>$tmp_stdout 2>$tmp_stderr");
				#--- parent - start timeout for child
				} else {
					$SIG{'ALRM'} = sub {
						add_error($no,"timeout encountered after $cmds[$no]{timeout}s");
						$cmds[$no]{rc}=$UNKNOWN;
						#--- kill both ways: with prepended minus some perl versions kill the
						#--- whole process group while positive numbers kill exact one process
						#--- we want to end all child check processes in order to clean up
						#--- properly after timeouts
						kill -15,$child;
						kill 15,$child;
						sleep 1;
						kill -9,$child;
						kill 9,$child;
					};
					waitpid($child,0);
					alarm(0);
				}
				$cmds[$no]{rc}=($cmds[$no]{rc})?$cmds[$no]{rc}:$? >> 8;

				#--- store stdout/stderr and cleanup tmpfiles
				$cmds[$no]{output}=readfile($tmp_stdout);
				$cmds[$no]{output}=~s/[$opt{set}{illegal_chars}]*//g if ($opt{set}{illegal_chars});
				chomp $cmds[$no]{output};
				DEBUG3("raw output >$cmds[$no]{output}<");
				DEBUG3("hex output:".hexdump(16,$cmds[$no]{output}));
				add_error($no,readfile($tmp_stderr));
				DEBUG3("raw stderr >".join(',',@{$cmds[$no]{error}})."<");
				DEBUG3("hex stderr:".hexdump(16,join(',',@{$cmds[$no]{error}})));
				unlink $tmp_stdout, $tmp_stderr;

			#--- new open3 exec (to be tested carefully before getting standard ;-))
			} elsif (module("IPC::Open3",1) && module("IO::Select",1)) {
				my $pid=open3(*CIN,*COUT,*CERR,$cmds[$no]{command});
				close(CIN); # not needed: close STDIN filehandle
				$SIG{CHLD}=sub {
					$cmds[$no]{rc}=$?>>8 if waitpid($pid, 0) > 0;
					DEBUG4("REAPER status $cmds[$no]{rc} on $pid");
				};

				my $sel=IO::Select->new();
				$sel->add(*CERR,*COUT);
				while (my @ready = $sel->can_read) {
					foreach my $fh (@ready) {
						if (fileno($fh) == fileno(CERR)) {
							add_error($no,scalar <CERR>);
						} else {
							$cmds[$no]{output}.=scalar <COUT>;
						}
						$sel->remove($fh) if eof($fh);
					}
				}
				close(COUT);
				close(CERR);
				chomp $cmds[$no]{output};
				DEBUG3("open3 raw output >$cmds[$no]{output}<");
				DEBUG3("open3 raw stderr >".join(',',$cmds[$no]{error})."<");
			}

			#--- unknown return code? change it explicitly to UNKNOWN and add error
			#---    this prevents the result rating routine from dealing with erraneous RCs
			#---    but keeps the information
			if (! defined($def{r2s}{$cmds[$no]{rc}})) {
				add_error($no,"RC was $cmds[$no]{rc}!");
				$cmds[$no]{rc}=$UNKNOWN;
			}

			#--- remove white chars from output (Wolfgang Barth)
			$cmds[$no]{stdout}=HTML::Entities::encode_entities($cmds[$no]{stdout}) 
				if ($opt{set}{report} & $DETAIL_HTML && module("HTML::Entities") && $cmds[$no]{stdout});

			#--- split performance data from standard output
			if ($cmds[$no]{output}=~/\|/ && ! $opt{set}{perfdata_pass_through}) {
				DEBUG4("(1) - output contains \|");
				#--- multiline perfdata
				if ($cmds[$no]{output}=~/([^\n]*)\n(.*)/s) {
					DEBUG4("(2) - output contains \\n");
					my $rest=$2;
					DEBUG4("(3) - \$1:$1");
					DEBUG4("(4) - \$2:$2");
					($cmds[$no]{output},$cmds[$no]{performance})=split(/\|/,$1);
					DEBUG4("(5) - rest:>$rest<");
					if ($rest=~/(.*)\|(.*)/s) {
						$cmds[$no]{output}.="\n$1";
						$cmds[$no]{performance}.=" " if ($cmds[$no]{performance});
						$cmds[$no]{performance}.=join(' ', split(/\n/,$2));
					} else {
						$cmds[$no]{output}.="\n$rest";
					}
					DEBUG4("(6) - output:$cmds[$no]{output} performance:$cmds[$no]{performance}");
				#--- error: multiple '|' in performance data
				} elsif ($cmds[$no]{output}=~/(.*)\|(.*\|.*)/) {
						add_error($no,"Invalid perfdata discarded - multiple pipe chars: \'$2\'");
						$cmds[$no]{output}=$1;
						$cmds[$no]{performance}=undef;
				#--- single line perfdata
				} else {
					($cmds[$no]{output},$cmds[$no]{performance})=split(/\|/,$cmds[$no]{output});
					DEBUG4("performance string: $cmds[$no]{performance}");
					$cmds[$no]{performance}=mytrim($cmds[$no]{performance},"\\s");
				}

				#--- check performance data and suppress if found errors
				if (($opt{set}{report} & $DETAIL_PERFORMANCE) && $cmds[$no]{process_perfdata}) {
					if (my $errstr=parse_perfdata($cmds[$no]{performance})) {
						add_error($no,"$cmds[$no]{name} perfdata discarded for $errstr");
						$cmds[$no]{performance}=undef;
					}
				}
				#--- silently supress empty or blank perfdata
				$cmds[$no]{performance}=undef if (defined($cmds[$no]{performance}) && $cmds[$no]{performance}=~/^\s*$/);
			}

			alarm(0);
		};
	} elsif ($cmds[$no]{type} eq "eval" || $cmds[$no]{type} eq "eeval") {
		local $SIG{ALRM} = sub {
			add_error($no,"timeout after $opt{set}{timeout}s");
			$?=$UNKNOWN<<8;
		};
		set_alarm($no,$opt{set}{timeout});
		$cmds[$no]{output}=eval($cmds[$no]{command});
		if ($cmds[$no]{type} eq "eeval") {
			$cmds[$no]{rc}=$?>>8;
			#--- unknown return code? change it explicitly to UNKNOWN
			if (! defined($def{r2s}{$cmds[$no]{rc}})) {
				add_error($no,"RC was $cmds[$no]{rc}!");
				$cmds[$no]{rc}=$UNKNOWN;
			}
		} elsif ($cmds[$no]{type} eq "eval") {
			$cmds[$no]{rc}=$OK;
		}
		if ($@) {
			chomp($@);
			$cmds[$no]{output}.="[$@]";
			$cmds[$no]{rc}=$WARNING;
		} else {
			if (!defined($cmds[$no]{output})) {
				$cmds[$no]{output}="";
			} else {
				chomp($cmds[$no]{output});
			}
			#--- split performance data from standard output
			if ($cmds[$no]{output}=~/\|/&& ! $opt{set}{perfdata_pass_through}) {
				($cmds[$no]{output},$cmds[$no]{performance})=split(/\|/,$cmds[$no]{output});
				$cmds[$no]{performance}=mytrim($cmds[$no]{performance},"\\s");

				#--- check performance data and suppress if found errors
				if (($opt{set}{report} & $DETAIL_PERFORMANCE) && $cmds[$no]{process_perfdata}) {
					if (my $errstr=parse_perfdata($cmds[$no]{performance})) {
						add_error($no,"$cmds[$no]{name} perfdata discarded for $errstr");
						$cmds[$no]{performance}=undef;
					}
				}
			}
			DEBUG4("environment var MULTI_$cmds[$no]{name}=$cmds[$no]{output}");
		}
		$cmds[$no]{endtime}=time;
		$cmds[$no]{runtime}=$cmds[$no]{endtime}-$cmds[$no]{starttime};
		alarm(0);

		#--- set environment variable states
		set_env_vars($no);

		#--- evaluate single command RC rating
		single_result_rating($no);

		#--- set environment variable states
		set_env_vars($no);

		#--- prior exit
		return $cmds[$no]{rc};

	} elsif ($cmds[$no]{type} eq "statusdat") {
		local $SIG{ALRM} = sub {
			add_error($no,"$cmds[$no]{name}: timeout after $opt{set}{timeout}s");
			$?=$UNKNOWN<<8;
		};
		set_alarm($no,$opt{set}{timeout});
		#--- service check
		if (defined($cmds[$no]{service})) {
			($cmds[$no]{rc}, $cmds[$no]{output}, $cmds[$no]{plugin}, $cmds[$no]{performance})=
				get_status_dat_service($opt{set}{status_dat},$cmds[$no]{host},$cmds[$no]{service});
			if ($cmds[$no]{rc} == -1) {
				add_error($no,"statusdat $cmds[$no]{name}: cannot find service \'$cmds[$no]{service}\' on host \'$cmds[$no]{host}\' in \'$opt{set}{status_dat}\'");
				$cmds[$no]{rc}=$UNKNOWN;
			}
		#--- host check
		} else {
			($cmds[$no]{rc}, $cmds[$no]{output}, $cmds[$no]{plugin}, $cmds[$no]{performance})=
				get_status_dat_host($opt{set}{status_dat},$cmds[$no]{host});
			if ($cmds[$no]{rc} == -1) {
				add_error($no,"statusdat $cmds[$no]{name}: cannot find host \'$cmds[$no]{host}\' in \'$opt{set}{status_dat}\'");
				$cmds[$no]{rc}=$UNKNOWN;
			#--- DOWN host becomes CRITICAL check_multi service
			} elsif ($cmds[$no]{rc} == 1) {
				$cmds[$no]{rc}=$CRITICAL;
			#--- UNREACHABLE host becomes UNKNOWN check_multi service
			} elsif ($cmds[$no]{rc} == 2) {
				$cmds[$no]{rc}=$UNKNOWN;
			}
		}
	} elsif ($cmds[$no]{type} eq "snmp") {
		local $SIG{ALRM} = sub {
			add_error($no,"$cmds[$no]{name}: timeout after $opt{set}{timeout}s");
			$?=$UNKNOWN<<8;
		};
		set_alarm($no,$opt{set}{timeout});
		($cmds[$no]{rc},$cmds[$no]{output})=get_snmp($cmds[$no]{host},$opt{set}{snmp_port},$opt{set}{snmp_community},$cmds[$no]{command},$cmds[$no]{translate});
		alarm(0);
	}

	$cmds[$no]{endtime}=time;
	$cmds[$no]{runtime}=$cmds[$no]{endtime}-$cmds[$no]{starttime};

	#--- any oddities during command execution?
	if ($@) {
		#--- timeout encountered: store status
		if ($@ =~ /timeout/) {
			$cmds[$no]{output}="UNKNOWN - $cmds[$no]{plugin} cancelled after timeout ($opt{set}{timeout}s)";
			$cmds[$no]{rc}=$UNKNOWN;
			$cmds[$no]{output}.=readfile($tmp_stdout);
			add_error($no,readfile($tmp_stderr));
		#--- catchall for unknown errors
		} else {
			alarm(0);
			$cmds[$no]{rc}=$UNKNOWN;
			add_error($no,"unexpected exception encountered:$@");
		}
		unlink $tmp_stdout, $tmp_stderr;
	} else {
		#--- if there is neither output nor any error message: return UNKNOWN because there went something wrong
		#--- probably the temporary directory is full ;)
		if ($opt{set}{empty_output_is_unknown} &&
			$cmds[$no]{output} eq "" &&
			error($no) eq "" ) {
			$cmds[$no]{rc}=$UNKNOWN;
			add_error($no,"$cmds[$no]{name}: no output, no stderr - check your plugin and the tmp directory $opt{set}{tmp_dir}]");
		}
		#--- postprocessing for cumulate
		if ($cmds[$no]{type} eq "cumulate") {
			#--- now output contains rows of 'key value' pairs
			#--- and some top rows will be placed into @top
			my @top=get_cumulated_top($cmds[$no]{output},$opt{set}{cumulate_max_rows});
			if ($#top<0) {
				$cmds[$no]{output}="No output.";
				$cmds[$no]{rc}=$UNKNOWN;
			} else {
				#--- fill new array members hashes
				for (my $i=0;$i<=$#top;$i++) {
					#--- name and output already set
					$top[$i]{command}=$cmds[$no]{command};
					$top[$i]{plugin}=$cmds[$no]{type};
					$top[$i]{pplugin}=$cmds[$no]{plugin};
					$top[$i]{ok}="";
					$top[$i]{warning}="";
					$top[$i]{critical}="";
					$top[$i]{unknown}="";
					$top[$i]{rc}=$OK;
					$top[$i]{number}=$no+$i;
					$top[$i]{displayed}=1;
					$top[$i]{error}=[];
					$top[$i]{feeded}=1;
					$top[$i]{runtime}=0;
					$top[$i]{type}=$cmds[$no]{type};
					$top[$i]{process_perfdata}=1;
					$top[$i]{performance}="$cmds[$no]{name}::$cmds[$no]{type}::$top[$i]{name}=$top[$i]{output}";
				}
				#--- replace original part with new array
				splice(@cmds,$no,1,@top);
				$cmds[0]{nallchecks}+=$#top;
				$cmds[0]{nchecks}+=$#top;
			}
		}

		#--- set environment variable states
		set_env_vars($no);

		#--- evaluate single command RC rating
		single_result_rating($no);

		#--- set environment variable states
		set_env_vars($no);

		#--- suppress_perfdata set? ignore perfdata
		if ($cmds[$no]{process_perfdata} && $cmds[$no]{performance}) {
			$ENV{"MULTI_PERFDATA_".$cmds[$no]{name}}="$cmds[$no]{performance}";
			DEBUG4("environment var MULTI_PERFDATA_$cmds[$no]{name}=$cmds[$no]{performance}");
		}
	}
	return $cmds[$no]{rc};
}

#---
#--- read output and cumulate
#---
sub get_cumulated_top {
	my ($output, $max_row)=@_;
	my %c=();
	foreach my $line (split('\n',$output)) {
		if ($line=~/\s*(\S*)\s+([\d\.]+)\s*/) {
			#--- zero value? count it if cumulate_ignore_zero=0
			if ($opt{set}{cumulate_ignore_zero}) {
				$c{"$1"}+=$2 if ($2);
				DEBUG4("$1 += $2 -> $c{$1}\n") if ($2);
			} else {
				$c{"$1"}+=$2;
				DEBUG4("$1 += $2 -> $c{$1}\n");
			}
		} else {
			DEBUG2("invalid line format: $line\n");
		}
	}
	my @top_keys = sort { $c{$b}<=>$c{$a} } keys(%c);
	my @result=();
	foreach my $key (@top_keys) {
		last if (--$max_row<0);
		push @result, {};
		$result[$#result]{name}=$key;
		$result[$#result]{output}=$c{$key};
	}
	@result;
}

#---
#--- get attributes of a particular status.dat service
#---
sub get_status_dat_host {
	my ($statusdat_path, $host_name)=@_;

	if (!$host_name) {
		add_error(0,"get_status_dat_host: empty host_name=$host_name specified");
		return (-1,"");
	}
	if (!defined($status_dat) || !$status_dat) {
		DEBUG4("1st read, creating service tree");
		$status_dat=read_status_dat($statusdat_path);
		if (!defined($status_dat) || !$status_dat) {
			add_error(0,"get_status_dat_host: could not read $statusdat_path");
			return (-1,"");
		}
	} else {
		DEBUG4("subsequent read, reading from service tree");
	}
	if (! defined($status_dat->{hoststatus}->{$host_name})) {
		DEBUG2("did not found RC and output for $host_name");
		return (-1,"");
	} else {
		DEBUG4("found data for $host_name: RC $status_dat->{hoststatus}->{$host_name}->{last_hard_state} and output \'$status_dat->{hoststatus}->{$host_name}->{plugin_output}\', long_output \'$status_dat->{hoststatus}->{$host_name}->{long_plugin_output}\'");
		my $output=$status_dat->{hoststatus}->{$host_name}->{plugin_output}."\n".
         $status_dat->{hoststatus}->{$host_name}->{long_plugin_output};
		chomp $output;
		return (
			$status_dat->{hoststatus}->{$host_name}->{last_hard_state},
			$output,
			$status_dat->{hoststatus}->{$host_name}->{check_command},
			$status_dat->{hoststatus}->{$host_name}->{performance_data},
		);
	}
}

#---
#--- reads list of status.dat hosts and returns all hosts which match host name
#---
sub expand_status_dat_host {
	my ($statusdat_path, $host_name)=@_;

	DEBUG4("expanding $host_name");
	if (!$host_name) {
		add_error(0,"expand_status_dat_host: empty host_name=$host_name specified");
		return (undef,undef);
	}
	if (!defined($status_dat) || !$status_dat) {
		DEBUG4("1st read, creating tree");
		$status_dat=read_status_dat($statusdat_path);
		if (!defined($status_dat) || !$status_dat) {
			add_error(0,"expand_status_dat_host: could not read $statusdat_path");
			return (undef,undef);
		}
	} else {
		DEBUG4("subsequent read, reading from tree");
	}

	#--- expand simple tokens to REGEX, if necessary
	$host_name=($host_name=~/\/(.*)\//)?$1:'^'.$host_name.'$';
	DEBUG4("$host_name after REGEX preparation");

	my @result=();
	foreach my $host (sort keys(%{$status_dat->{hoststatus}})) {
		#--- proceed if host and service names do fit
		if ($host=~/$host_name/) {
			push @result,$host;
			DEBUG4("$host matched $host_name");
		} else {
			DEBUG4("$host did not match $host_name");
		}
	}
	DEBUG4("returns " . ($#result+1)/2 . " results");
	return @result;
}

#---
#--- get attributes of a particular status.dat service
#---
sub get_status_dat_service {
	my ($statusdat_path, $host_name, $service_description)=@_;

	if (!defined($host_name) || !$host_name) {
		add_error(0,"get_status_dat_service: empty host_name specified");
		return (-1,"");
	}
	if (!defined($service_description) || !$service_description) {
		add_error(0,"get_status_dat_service: empty service_description specified");
		return (-1,"");
	}
	if (!$status_dat) {
		DEBUG4("1st read, creating service tree");
		$status_dat=read_status_dat($statusdat_path);
		if (!$status_dat) {
			add_error(0,"get_status_dat_service: could not read $statusdat_path");
			return (-1,"");
		}
	} else {
		DEBUG4("subsequent read, reading from service tree");
	}
	if (! defined($status_dat->{servicestatus}->{$host_name}->{$service_description})) {
		DEBUG2("did not found RC and output for $host_name:$service_description");
		return (-1,"");
	} else {
		DEBUG4("found data for $host_name:$service_description: RC $status_dat->{servicestatus}->{$host_name}->{$service_description}->{last_hard_state} and output \'$status_dat->{servicestatus}->{$host_name}->{$service_description}->{plugin_output}\', long_output \'$status_dat->{servicestatus}->{$host_name}->{$service_description}->{long_plugin_output}\'");
		my $output=
			$status_dat->{servicestatus}->{$host_name}->{$service_description}->{plugin_output}."\n".
        	$status_dat->{servicestatus}->{$host_name}->{$service_description}->{long_plugin_output};
		chomp $output;
		return (
			$status_dat->{servicestatus}->{$host_name}->{$service_description}->{last_hard_state},
			$output,
			$status_dat->{servicestatus}->{$host_name}->{$service_description}->{check_command},
			$status_dat->{servicestatus}->{$host_name}->{$service_description}->{performance_data},
		);
	}
}

#---
#--- reads list of status.dat services and returns all services which match host and service name
#---
sub expand_status_dat_service {
	my ($statusdat_path, $host_name, $service_description)=@_;

	DEBUG4("expanding $host_name:$service_description");
	if (!defined($host_name) || !$host_name) {
		add_error(0,"expand_status_dat_service: empty host_name specified");
		return (undef,undef);
	}
	if (!defined($service_description) || !$service_description) {
		add_error(0,"expand_status_dat_service: empty service_description specified");
		return (undef,undef);
	}
	if (!$status_dat) {
		DEBUG4("1st read, creating service tree");
		$status_dat=read_status_dat($statusdat_path);
		if (!$status_dat) {
			add_error(0,"expand_status_dat_service: could not read $statusdat_path");
			return (undef,undef);
		}
	} else {
		DEBUG4("subsequent read, reading from service tree");
	}

	#--- expand simple tokens to REGEX, if necessary
	$host_name=($host_name=~/\/(.*)\//)?$1:'^'.$host_name.'$';
	$service_description=($service_description=~/\/(.*)\//)?$1:'^'.$service_description.'$';
	DEBUG4("$host_name:$service_description after REGEX preparation");

	my @result=();
	foreach my $host (sort keys(%{$status_dat->{hoststatus}})) {
		foreach my $service (sort keys(%{$status_dat->{servicestatus}->{$host}})) {
			#--- proceed if host and service names do fit
			if ($host=~/$host_name/ && $service=~/$service_description/) {
				push @result,$host;
				push @result,$service;
				DEBUG4("$host:$service matched $host_name:$service_description");
			} else {
				DEBUG4("$host:$service did not match $host_name:$service_description");
			}
		}
	}
	DEBUG4("returns " . ($#result+1)/2 . " results");
	return @result;
}

#---
#--- status.dat parsing routing
#---
sub read_status_dat {
	my ($statusdat_path)=@_;

	if (!open(DAT,$statusdat_path)) {
		add_error(0,"read_status_dat: cannot open $statusdat_path:$!");
		return undef;
	}

	#--- outer loop: look for type ${type}status
	while (<DAT>) {
		#--- read hosts
		if (/^hoststatus\s+\{/) {
			my %r=();
			while (<DAT>) {
				NEXT: if (/^\thost_name=(.+)$/) {
					$r{host_name}=$1;
				} elsif (/^\tcheck_command=([^!]+)/) {
					$r{check_command}=$1;
					chomp($r{check_command});
				} elsif (/^\tlast_hard_state=(.*)/) {
					$r{last_hard_state}=$1;
				} elsif (/^\tplugin_output=(.*)/) {
					$r{plugin_output}=$1;
				} elsif (/^\tlong_plugin_output=(.*)/) {
					chomp($r{long_plugin_output}=$1);
					while (<DAT>) {
						if (/^\t/) {
							goto NEXT;
						} else {
							chomp;
							$r{long_plugin_output}.="\n$_";
						}
					}
				} elsif (/^\tperformance_data=(.*)/) {
					$r{performance_data}=$1;
				} elsif (/^\t\}$/) {
					$status_dat->{hoststatus}->{"$r{host_name}"}->{check_command}=$r{check_command};
					$status_dat->{hoststatus}->{"$r{host_name}"}->{last_hard_state}=$r{last_hard_state};
					$status_dat->{hoststatus}->{"$r{host_name}"}->{long_plugin_output}=$r{long_plugin_output};
					$status_dat->{hoststatus}->{"$r{host_name}"}->{performance_data}=$r{performance_data};
					$status_dat->{hoststatus}->{"$r{host_name}"}->{plugin_output}=$r{plugin_output};
					last;
				}
			}
		#--- read services
		} elsif (/^servicestatus\s+\{/) {
			my %r=();
			while (<DAT>) {
				NEXT: if (/^\thost_name=(.+)$/) {
					$r{host_name}=$1;
				} elsif (/^\tservice_description=(.+)$/) {
					$r{service_description}=$1;
				} elsif (/^\tcheck_command=([^!]+)/) {
					$r{check_command}=$1;
					chomp($r{check_command});
				} elsif (/^\tlast_hard_state=(.*)/) {
					$r{last_hard_state}=$1;
				} elsif (/^\tplugin_output=(.*)/) {
					$r{plugin_output}=$1;
				} elsif (/^\tlong_plugin_output=(.*)/) {
					chomp($r{long_plugin_output}=$1);
					while (<DAT>) {
						if (/^\t/) {
							goto NEXT;
						} else {
							chomp;
							$r{long_plugin_output}.="\n$_";
						}
					}
				} elsif (/^\tperformance_data=(.*)/) {
					$r{performance_data}=$1;
				} elsif (/^\t\}$/) {
					$status_dat->{servicestatus}->{"$r{host_name}"}->{"$r{service_description}"}->{check_command}=$r{check_command};
					$status_dat->{servicestatus}->{"$r{host_name}"}->{"$r{service_description}"}->{last_hard_state}=$r{last_hard_state};
					$status_dat->{servicestatus}->{"$r{host_name}"}->{"$r{service_description}"}->{performance_data}=$r{performance_data};
					$status_dat->{servicestatus}->{"$r{host_name}"}->{"$r{service_description}"}->{plugin_output}=$r{plugin_output};
					$status_dat->{servicestatus}->{"$r{host_name}"}->{"$r{service_description}"}->{long_plugin_output}=$r{long_plugin_output};
					last;
				}
			}
		#--- skip other records
		} elsif (/^(\S+)/) {
			DEBUG4("skipping $1");
		}
	}
	close DAT;
	if (module("Data::Dumper")) {
		DEBUG4(Dumper($status_dat));
	}
	return $status_dat;
}

#---
#--- reads list of livestatus services and returns all services which match host and service name
#---
sub expand_livestatus_service {
	my ($livestatus_path, $host_name, $service_description)=@_;

	DEBUG4("expanding $host_name:$service_description");
	if (!$host_name || !$service_description) {
		add_error(0,"expand_livestatus_service: empty host_name=$host_name or service_description=$service_description specified");
		return (undef,undef);
	}
	if (!$livestatus_service) {
		DEBUG4("1st read, creating service tree");

		$livestatus_service=read_livestatus($livestatus_path,"GET services\nColumns: host_name description last_hard_state plugin_output long_plugin_output perf_data check_command\n");
		if (!$livestatus_service) {
			add_error(0,"expand_livestatus_service: could not read $livestatus_path");
			return (undef,undef);
		}
		DEBUG4("$#{$livestatus_service} results");
	} else {
		DEBUG4("subsequent read, reading from service tree");
	}

	#--- expand simple tokens to REGEX, if necessary
	$host_name=($host_name=~/\/(.*)\//)?$1:'^'.$host_name.'$';
	$service_description=($service_description=~/\/(.*)\//)?$1:'^'.$service_description.'$';
	DEBUG4("$host_name:$service_description after REGEX preparation");

	my @result=();
	#--- $service points to an array item
	foreach my $service (@{$livestatus_service}) {
		if ($service->{host_name}=~/$host_name/ && $service->{description}=~/$service_description/) {
			push @result,$service->{host_name};
			push @result,$service->{description};
			push @result,$service->{last_hard_state};
			my $output=defined($service->{plugin_output})?$service->{plugin_output}:"";
			chomp($output);
			$output.=defined($service->{long_plugin_output})?"\n$service->{long_plugin_output}":"";
			chomp($output);
			push @result,$output;
			push @result,defined($service->{perf_data})?$service->{perf_data}:"";
			if ($service->{check_command}=~/([^!]+)!/) {
				push @result, $1;
			} else {
				push @result, $service->{check_command};
			}
			DEBUG4("$service->{host_name}:$service->{description} matched $host_name:$service_description:$service->{last_hard_state}");
		} else {
			DEBUG4("$service->{host_name}:$service->{description} did not match $host_name:$service_description");
		}
	}
	DEBUG4("returns " . ($#result+1)/5 . " results:" . join('|',@result) );
	return @result;
}

#---
#--- reads list of livestatus hosts and returns all matching hosts
#---
sub expand_livestatus_host {
	my ($livestatus_path, $host_name)=@_;

	DEBUG4("expanding $host_name");
	if (!$host_name) {
		add_error(0,"expand_livestatus_host: empty host_name=$host_name specified");
		return (undef,undef);
	}
	if (!$livestatus_host) {
		DEBUG4("1st read, creating host tree");

		$livestatus_host=read_livestatus($livestatus_path,"GET hosts\nColumns: host_name last_hard_state plugin_output long_plugin_output perf_data check_command\n");
		if (!$livestatus_host) {
			add_error(0,"expand_livestatus_host: could not read $livestatus_path");
			return (undef,undef);
		}
		DEBUG4("$#{$livestatus_host} results");
	} else {
		DEBUG4("subsequent read, reading from host tree");
	}

	#--- expand simple tokens to REGEX, if necessary
	$host_name=($host_name=~/\/(.*)\//)?$1:'^'.$host_name.'$';
	DEBUG4("$host_name after REGEX preparation");

	my @result=();
	#--- $host points to an array item
	foreach my $host (@{$livestatus_host}) {
		if ("$host->{host_name}"=~/$host_name/) {
			push @result,$host->{host_name};
			push @result,$host->{last_hard_state};
			my $output=defined($host->{plugin_output})?$host->{plugin_output}:""; 
			chomp($output);
			$output.=defined($host->{long_plugin_output})?"\n$host->{long_plugin_output}":"";
			chomp($output);
			push @result,$output;
			push @result,defined($host->{perf_data})?$host->{perf_data}:"";
			if ($host->{check_command}=~/([^!]+)!/) {
				push @result, $1;
			} else {
				push @result, $host->{check_command};
			}
			DEBUG4("$host->{host_name} matched $host_name, state $host->{last_hard_state}");
		} else {
			DEBUG4("$host->{host_name} did not match $host_name");
		}
	}
	DEBUG4("returns " . ($#result+1)/5 . " results");
	return @result;
}

sub read_livestatus {
	my ($livestatus_path, $query)=@_;

	my $ml=Monitoring::Livestatus->new(
        	peer=>$livestatus_path,
	);
	if($Monitoring::Livestatus::ErrorCode) {
		add_error(0,"read_livestatus: $Monitoring::Livestatus::ErrorMessage");
		return undef;
	}
	$ml->errors_are_fatal(0);
	my $livestatus=$ml->selectall_arrayref($query,{Slice => 1});
	if($Monitoring::Livestatus::ErrorCode) {
		add_error(0,"read_livestatus: $Monitoring::Livestatus::ErrorMessage");
		return undef;
	}
	DEBUG4("$#{$livestatus} elements read");
	if (module("Data::Dumper")) {
		DEBUG4(Dumper($livestatus));
	}
	return $livestatus;
}

#---
#--- read SNMP with Net::SNMP
#---
sub get_snmp {
	my ($host,$port,$community,$oid,$translate)=@_;

	#--- Net::SNMP is mandatory, exit fatal if not available
	module("Net::SNMP",1);

	my ($session, $error) = Net::SNMP->session(
		-hostname=>$host,
		-community=>$community,
		-translate=>$translate,
	);
	if (!defined $session) {
		DEBUG3("error creating Net::SNMP session: $error");
		return (3,"error creating Net::SNMP session: $error");
	}

	my $result = $session->get_request(-varbindlist => [ $oid ],);

	if (!defined $result) {
		$error=$session->error();
		$session->close();
		DEBUG3("Net::SNMP session error: $error");
		return (3,"Net::SNMP session error: $error");
	}

	DEBUG3("result for $host($port)-$oid: $result->{$oid}");
	$session->close();

	return (0,$result->{$oid});
}

#---
#--- eval state rules
#---
sub eval_result {
	my ($input)=@_;
	my $input_org=$input;
	my $message="";

	#--- empty input?
	if (! $input) {
		DEBUG3("empty input - nothing to do");
		return ($UNKNOWN, "eval_result: invalid empty input");
	}

	#--- at runtime: substitute $MACRO$ macros and $STATES$
	DEBUG4("input before substituting macros: $input");
	$input=substitute_macros($input);
	$input=substitute_states($input);
	DEBUG4("input after substituting macros: $input");

	#--- evaluate expression
	my $result=eval "($input)";

	#--- catch error
	if ($@) {
		$message="Evaluation error in \'$input_org\': $@\n";
		$message=~s/\n/ /g;
		DEBUG4("eval error $message");
		return (-1,$message);
	#--- return result
	} else {
		$message="eval_result: input:>$input_org< parsed:>$input< result:>$result<\n";
		$message=~s/\n/ /g;
		DEBUG4($message);
		return ($result,$message);
	}
}


#---
#--- split state string into token and return
#--- array of hashes with start,end,token
#---
sub get_state_token {
	my ($state)=@_;
	#
	my @token=();
	my $tno=0;
	my $pos=0;
	my $start=0;
	my $end=0;
	my $instring=0;

	#--- read string (and one char more for handling of last token)
	for (my $pos=0; $pos<=length($state); $pos++) {

		my $char=substr($state,$pos,1);
		my $nextchar=($pos<length($state)-1) ? substr($state,$pos+1,1) : "";

		#--- skip white characters ' ' and '()'
		if ($char=~/[ ()]/) {
			if (!$instring) {
				$start++;
			}

		#--- '||' or '&&' found: token end detected
		} elsif (($char eq "|" && $nextchar eq "|") ||
		 	($char eq "&" && $nextchar eq "&") ||
		 	($char eq ""  && $nextchar eq "" )) {
			$token[$tno]{start}=$start;
			$token[$tno]{end}=$end;
			$token[$tno]{token}=substr($state,$start,$end-$start+1);
			$token[$tno]{substituted}=substitute_macros($token[$tno]{token});
			$token[$tno]{substituted}=substitute_states($token[$tno]{substituted});
			($token[$tno]{substate},$token[$tno]{message})=eval_result($token[$tno]{substituted});

			$tno++;
			$pos+=2;
			$start=$pos;
			$end=$pos;
			$instring=0;

		#--- normal token char
		} else {
			#--- token init
			if (!$instring) {
				$instring=1;
				$start=$pos;
				$end=$pos;
			} else {
				$end=$pos;
			}
		}
	}
	my $output="\n" . "0123456789" x 8 ."\n$state\n\n";
	$output.=sprintf "%3s %5s %5s   %s\n", "No", "Start", "End", "Token";

	for ($tno=0;$tno<=$#token;$tno++) {

		#--- squeeze blanks to beautify output
		$token[$tno]{token}=~s/  / /g;

		$output.=sprintf "%3d %5d %5d   >%s<\n",
			$tno,
			$token[$tno]{start},
			$token[$tno]{end},
			$token[$tno]{token};
	}
	#--- debugging
	DEBUG3($output);

	#--- return array
	@token;
}

#---
#--- calculate sums from %cmds and %rc
#---
sub global_result_rating {

	#--- measure runtime without reporting ;-)
	$cmds[0]{runtime}=time - $cmds[0]{starttime};

	#--- count return codes
	for ($no=1;$no<=$#cmds;$no++) {
		#--- count only displayed (without eval)
		if ($cmds[$no]{displayed}) {
			$rc{count}[$cmds[$no]{rc}]++; # count displayed return codes
			push @{$rc{list}[$cmds[$no]{rc}]},$cmds[$no]{name}; # add plugin to displayed list
		}
		#--- count all child checks
		$rc{count_all}[$cmds[$no]{rc}]++;	# count all return codes
		push @{$rc{list_all}[$cmds[$no]{rc}]},$cmds[$no]{name}; # add plugin to all list
	}

	#--- sort in severity order
	foreach my $index ($OK..$UNKNOWN) {
		$ENV{"MULTI_$def{label}{$index}_COUNT"}=$rc{count}[$index];
		$ENV{"MULTI_$def{label}{$index}_LIST"}=join(',',@{$rc{list}[$index]});
		$ENV{"MULTI_$def{label}{$index}_COUNT_ALL"}=$rc{count_all}[$index];
		$ENV{"MULTI_$def{label}{$index}_LIST_ALL"}=join(',',@{$rc{list_all}[$index]});

		my $state=$def{s2r}{$index};

		my ($result,$message)=eval_result($cmds[0]{state}[$state]);
		if (! defined($result) || $result eq "") {
			; # do nothing
		} elsif ($result < 0) {
			add_error(0,"global_result_rating: parsing error ($message)");
		} else {
			$rc{match}[$state]=1;
			$cmds[0]{rc}=$state;

		}
	}
	#--- set several environment vars for 'head'
	set_env_vars(0);
}

#---
#--- behave like check_generic: evaluate RCs for single command
#---
sub single_result_rating {
	my $no=shift;
	my $old_rc=$cmds[$no]{rc};

	#--- sort in severity order
	foreach my $index (0..3) {

		#--- getting state
		my $state=$def{s2r}{$index};
		DEBUG4("examining state $state ($def{llabel}{$state})");

		#--- did we got a child check RC?
		if ($state == $old_rc) {
			$cmds[$no]{rc}=$old_rc;
			DEBUG4("original RC was $old_rc -> moving this RC to child check RC");
		}

		#--- no special settings for evaluation? then do not evaluate!
		if (!$cmds[$no]{$def{llabel}{$state}}) {
			DEBUG4("no expression for $def{llabel}{$state} -> no evaluation");
			next;
		} else {
			DEBUG4("expression found for $def{llabel}{$state}: >>>$cmds[$no]{$def{llabel}{$state}}<<<");
		}

		#my ($result,$message)=eval_result("\'$cmds[$no]{output}\'$cmds[$no]{$def{llabel}{$state}}");
		my ($result,$message)=eval_result("$cmds[$no]{$def{llabel}{$state}}");
		DEBUG4("evaluating expression \"$cmds[$no]{$def{llabel}{$state}}\", result is $result");

		if (! defined($result) || $result eq "") {
			; # do nothing
		} elsif ($result < 0) {
			add_error(0,"single_result_rating: parsing error $message");
			DEBUG4("parsing error expresstion ($cmds[$no]{output}$cmds[$no]{$state})->($message)");
		} else {
			$cmds[$no]{rc}=$state;
			add_error($no,"$def{label}{$state}: output matched rule \'$cmds[$no]{$def{llabel}{$state}}\'");
			DEBUG4("setting RC of cmds[$no] to $state");
		}
	}
}

#---
#--- start different report routines
#---
sub report_all {

	#--- some debugging first
	DEBUG4("MULTI Environment (sorted):\n\t".join("\n\t",get_env_vars('^MULTI')));
	DEBUG4("${NAGIOS} Environment (sorted):\n\t".join("\n\t",get_env_vars('^${NAGIOS}')));

	#--- construction site for persistence
	if ($opt{set}{test} && $opt{set}{persistent}) {
		#unless (eval "use Data::Dumper;1") {
		#	$opt{set}{test}=0;
		#	DEBUG2("report_all: Data::Dumper not available");
		#} else {
		#	DEBUG3("report_all: Data::Dumper module loaded");
		#	DEBUG4("report_all:" . Dumper($check_multi));
		#}
		module("XML::Simple",1);

		#my $pdir="$opt{set}{tmp_dir}/".valid_dir($cmds[0]{hash});
		my $pdir="$opt{set}{tmp_dir}/$opt{set}{HOSTNAME}_$opt{set}{SERVICEDESC}";
		if (! my_mkdir("$pdir", $opt{set}{tmp_dir_permissions})) {
			add_error(0,"report_all: cannot create persistent directory $pdir:$!");
		} else {
			DEBUG1("pdir:$pdir MYSELF:$MYSELF starttime:".readable_sortable_timestamp($cmds[0]{starttime})." name:$cmds[0]{names}");
			writefile(
				">$pdir/".time.".xml",
				XML::Simple::XMLout(
					$check_multi,
					NoAttr=>1,
					KeepRoot=>1,
					RootName=>"$MYSELF",
					SuppressEmpty=>undef,
				)
			);
		}
	} else {
		#add_error(0,"report_all: persistent problem - persistent:$opt{set}{persistent} - use_xml_simple:$opt{set}{use_xml_simple}");
	}

	#--- print service definition
	if ($opt{set}{report} & $DETAIL_SERVICE_DEFINITION) {
		&report_service_definition;
		return; # 	no normal output here
	}

	#--- classical report
	if (!($opt{set}{report} & $DETAIL_HTML) &&
	    !($opt{set}{report} & $DETAIL_XML)) {
		&report_ascii;
	}
	#--- report HTML output (and not XML)
	if (($opt{set}{report} & $DETAIL_HTML) &&
	   !($opt{set}{report} & $DETAIL_XML)) {
		&report_html;
	}
	#--- report XML output (and not HTML)
	if (($opt{set}{report} & $DETAIL_XML) &&
	   !($opt{set}{report} & $DETAIL_HTML)) {
		&report_xml;
	}
	#--- report to nsca (send_nsca wrapper)
	if ($opt{set}{report} & $DETAIL_SEND_NSCA) {
		&report_send_nsca;
	}
	#--- report to nsca (send_nsca wrapper)
	if ($opt{set}{report} & $DETAIL_SEND_GEARMAN) {
		&report_send_gearman;
	}
	#--- report to nsca (send_nsca wrapper)
	if ($opt{set}{report} & $DETAIL_FEED_PASSIVE) {
		&report_checkresult_file;
	}

	#--- at last: perfdata
	&report_perfdata;

	#--- final '\n' - dedicated to Wolfgang Barth ;-)
	if (	!($opt{set}{report} & $DETAIL_NAGIOS2) &&
		!($opt{set}{report} & $DETAIL_HTML) &&
		!($opt{set}{report} & $DETAIL_XML)) {
		print "\n";
	}
}

#---
#--- report results stored in %cmds (ASCII report)
#---
sub report_ascii {

	DEBUG1("\n","-" x 80);
	DEBUG1("Plugin output");
	DEBUG1("-" x 80);

	if (defined($cmds[0]{fmtstr})) {
		my $output="printf " . $cmds[0]{fmtstr};
	 	$output.="," . join(",",@{$cmds[0]{parms}}) if (defined($cmds[0]{parms}));
		$output=substitute_macros($output);
		DEBUG4("output [ head ] = \'$output\'");
		eval($output);
	} elsif ($opt{set}{report} & $DETAIL_NAGIOS2) {
		print "$opt{set}{name} " if $opt{set}{name};
		print "$def{label}{$cmds[0]{rc}}";
	} else {
		#--- print header line (1): name, state, number of plugins
		print "$opt{set}{name} " if $opt{set}{name};
		print "$def{label}{$cmds[0]{rc}} - $cmds[0]{nchecks} plugins checked, ";

		#--- print header line (2): summary for particular states
		if ($opt{set}{report} & $DETAIL_LIST_FULL) {
			print	"$rc{count}[$CRITICAL] critical" . ((@{$rc{list}[$CRITICAL]}) ? " (" . join(', ',@{$rc{list}[$CRITICAL]}) . ')' : "") . ", " .
				"$rc{count}[$WARNING] warning"   . ((@{$rc{list}[$WARNING]})  ? " (" . join(', ',@{$rc{list}[$WARNING]})  . ')' : "") . ", " .
				"$rc{count}[$UNKNOWN] unknown"   . ((@{$rc{list}[$UNKNOWN]})  ? " (" . join(', ',@{$rc{list}[$UNKNOWN]})  . ')' : "") . ", " .
				"$rc{count}[$OK] ok";
		} elsif ($opt{set}{report} & $DETAIL_LIST) {
			my @r=();
			push @r, "$rc{count}[$CRITICAL] critical (" . join(', ',@{$rc{list}[$CRITICAL]}) . ")" if (@{$rc{list}[$CRITICAL]});
			push @r, "$rc{count}[$WARNING] warning ("   . join(', ',@{$rc{list}[$WARNING]})  . ")" if (@{$rc{list}[$WARNING]});
			push @r, "$rc{count}[$UNKNOWN] unknown ("   . join(', ',@{$rc{list}[$UNKNOWN]})  . ")" if (@{$rc{list}[$UNKNOWN]});
			push @r, "$rc{count}[$OK] ok" if (@{$rc{list}[$OK]});
			print join(", ", @r);
		} else {
			print	"$rc{count}[$CRITICAL] critical, " .
				"$rc{count}[$WARNING] warning, " .
				"$rc{count}[$UNKNOWN] unknown, " .
				"$rc{count}[$OK] ok";
		}
		foreach my $s (sort numerically keys %{$def{s2r}}) {
			#--- if state matches
			if (($cmds[0]{state}[$def{s2r}{$s}] ne $cmds[0]{state_default}[$def{s2r}{$s}] && $rc{match}[$def{s2r}{$s}]) ||
			     $opt{set}{report} & $DETAIL_LIST_FULL ) {
				printf " [%s - %s - %s]", $def{label}{$def{s2r}{$s}}, $rc{match}[$def{s2r}{$s}]?"TRUE":"FALSE", $cmds[0]{state}[$def{s2r}{$s}];
			} else {
				DEBUG3("No match ($def{s2r}{$s} - $def{s2r}{$def{s2r}{$s}}): $rc{match}[$def{s2r}{$def{s2r}{$s}}]");
			}
		}
	}
	#--- print general errors if any occured
	print error(0);

	#--- loop over commands: report particular results for long plugin output
	for ($no=1;$no<=$#cmds;$no++) {

		#--- special output statement defined?
		if (defined($cmds[$no]{fmtstr})) {
			my $output="printf " . $cmds[$no]{fmtstr};
	 		$output.="," . join(",",@{$cmds[$no]{parms}}) if (defined($cmds[$no]{parms}));
			$output=substitute_macros($output);
			DEBUG4("output [ $cmds[$no]{name} ] = \'$output\'");
			eval($output);
			next;
		}

		#--- skip eval
		next if ($cmds[$no]{type} eq "eval");

		#--- if NAGIOS2 output: skip $OK results
		if ($opt{set}{report} & $DETAIL_NAGIOS2) {
			next if ($cmds[$no]{rc} == $OK);
			$cmds[$no]{output}=~s/\n//g;
			printf ", %s %s%s",
				$cmds[$no]{name},
				$cmds[$no]{output},
				($opt{set}{report} & $DETAIL_STDERR) ?  error($no) : "";
		} else {
			$cmds[$no]{output}=~s/\n/\n$opt{set}{indent}/g;

			#--- hide all OK results if there is any check not OK
			next if ($opt{set}{report} & $DETAIL_HIDEIFOK && $cmds[$no]{rc} == $OK);

			printf "%s[%2.d] %s %s%s%s",
				($opt{set}{report} & $DETAIL_NAGIOS2) ? ", " : "\n",
				$cmds[$no]{number},
				$cmds[$no]{name},
				($opt{set}{report} & $DETAIL_STATUS &&
				$cmds[$no]{output}!~/\b$def{label}{$cmds[$no]{rc}}\b/)
					? "$def{label}{$cmds[$no]{rc}} "
					: "",
				($cmds[$no]{output}=~/\<!--(.*?)--\>/sg) ? $1 : $cmds[$no]{output},
				($opt{set}{report} & $DETAIL_STDERR) ? error($no) : "";
		}
	}

	my $maxcmdlen=0;
	for ($no=1;$no<=$#cmds;$no++) {
		$maxcmdlen=length($cmds[$no]{name}) if (length($cmds[$no]{name})>$maxcmdlen);
	}

	#--- print results
	DEBUG1("\n","-" x 80);
	DEBUG1(sprintf("No   Name%sRuntime  RC Output", ' ' x ($maxcmdlen-3)));
	DEBUG1("-" x 80);
	for ($no=1;$no<=$#cmds;$no++) {
		DEBUG1(sprintf "[%2.d] %-${maxcmdlen}s %6.4fs %3d %s", $no, $cmds[$no]{name}, $cmds[$no]{runtime}, $cmds[$no]{rc}, $cmds[$no]{output});
		DEBUG1(sprintf "%s%-12s%s", ' ' x ($maxcmdlen+6), $cmds[$no]{type}, $cmds[$no]{command});
	}

	#--- print state settings and RC evaluation result
	DEBUG1("\n","-" x 80);
	DEBUG1(sprintf "%-8s %-55s %s", "State","Expression","Evaluates to");
	DEBUG1("-" x 80);
	foreach my $s (sort numerically keys %{$def{s2r}}) {
		DEBUG1(sprintf "%-8s %-55s %s", $def{label}{$def{s2r}{$s}}, $cmds[0]{state}[$def{s2r}{$s}], ($rc{match}[$def{s2r}{$s}]) ? "TRUE" : "FALSE");
		DEBUG2(state_string_ascii($cmds[0]{state}[$def{s2r}{$s}]));
		#--- if state matches
		if (($cmds[0]{state}[$def{s2r}{$s}] ne $cmds[0]{state_default}[$def{s2r}{$s}] && $rc{match}[$def{s2r}{$s}]) ||
		     $opt{set}{report} & $DETAIL_LIST_FULL ) {
			printf "\n[%2.2s] %-5s - %s", $def{label}{$def{s2r}{$s}}, $rc{match}[$def{s2r}{$s}]?"TRUE":"FALSE", $cmds[0]{state}[$def{s2r}{$s}];
		} else {
			DEBUG3("No match ($def{s2r}{$s} - $def{s2r}{$def{s2r}{$s}}): $rc{match}[$def{s2r}{$def{s2r}{$s}}]");
		}
	}
	DEBUG1("-" x 80);
	DEBUG1(sprintf "%8s %55s %s", "", "Overall state =>", $def{label}{$cmds[0]{rc}});
	DEBUG1("-" x 80);
}

#---
#--- helper routine which provides single child check result
#---
sub state_string_ascii {
	my ($state)=@_;
	my $output="";
	my @token=get_state_token($state);
	for (my $tno=0;$tno<=$#token;$tno++) {
		$output.=sprintf "%11s. %-52s %s\n",
			chr(97+$tno), 	# 'a'+$tno
			"'".$token[$tno]{token}."'" . " -> " .  "'".$token[$tno]{substituted}."'",
			($token[$tno]{substate}) ? "TRUE" : "FALSE";
	}
	$output;
}

#---
#--- report results stored in %cmds (HTML report)
#---
sub report_html {
	my $output="";

	if (defined($cmds[0]{fmtstr})) {
		$output.="sprintf " . $cmds[0]{fmtstr};
	 	$output.="," . join(",",@{$cmds[0]{parms}}) if (defined($cmds[0]{parms}));
		$output=substitute_macros($output);
		DEBUG4("output [ head ] =  \'$output\'");
		$output=eval($output);
	} else {
		#--- print header line (1): name, state, number of plugins
		$output.="$opt{set}{name} " if $opt{set}{name};
		$output.="$def{label}{$cmds[0]{rc}} - $cmds[0]{nchecks} plugins checked, ";

		#--- print header line (2): summary for particular states
		if ($opt{set}{report} & $DETAIL_LIST_FULL) {
			$output.="$rc{count}[$CRITICAL] critical" . ((@{$rc{list}[$CRITICAL]}) ? " (" . join(', ',@{$rc{list}[$CRITICAL]}) . ')' : "") . ", " .
				"$rc{count}[$WARNING] warning"   . ((@{$rc{list}[$WARNING]})  ? " (" . join(', ',@{$rc{list}[$WARNING]})  . ')' : "") . ", " .
				"$rc{count}[$UNKNOWN] unknown"   . ((@{$rc{list}[$UNKNOWN]})  ? " (" . join(', ',@{$rc{list}[$UNKNOWN]})  . ')' : "") . ", " .
				"$rc{count}[$OK] ok";
		} elsif ($opt{set}{report} & $DETAIL_LIST) {
			my @r=();
			push @r, "$rc{count}[$CRITICAL] critical (" . join(', ',@{$rc{list}[$CRITICAL]}) . ")" if (@{$rc{list}[$CRITICAL]});
			push @r, "$rc{count}[$WARNING] warning ("   . join(', ',@{$rc{list}[$WARNING]})  . ")" if (@{$rc{list}[$WARNING]});
			push @r, "$rc{count}[$UNKNOWN] unknown ("   . join(', ',@{$rc{list}[$UNKNOWN]})  . ")" if (@{$rc{list}[$UNKNOWN]});
			push @r, "$rc{count}[$OK] ok" if (@{$rc{list}[$OK]});
			$output.=join(", ", @r);
		} else {
			$output.="$rc{count}[$CRITICAL] critical, " .
				"$rc{count}[$WARNING] warning, " .
				"$rc{count}[$UNKNOWN] unknown, " .
				"$rc{count}[$OK] ok";
		}
		foreach my $s (sort numerically keys %{$def{s2r}}) {
			#--- if state matches
			if (($cmds[0]{state}[$def{s2r}{$s}] ne $cmds[0]{state_default}[$def{s2r}{$s}] && $rc{match}[$def{s2r}{$s}]) ||
			     $opt{set}{report} & $DETAIL_LIST_FULL ) {
				$output.=sprintf " [%s - %s - %s]", $def{label}{$def{s2r}{$s}}, $rc{match}[$def{s2r}{$s}]?"TRUE":"FALSE", $cmds[0]{state}[$def{s2r}{$s}];
			} else {
				DEBUG3("No match ($def{s2r}{$s} - $def{s2r}{$def{s2r}{$s}}): $rc{match}[$def{s2r}{$def{s2r}{$s}}]");
			}
		}
	}

	#--- print general errors if any occured
	$output.=error(0);
	$output.=($opt{set}{extinfo_in_status})?"<br />":"\n";

	#--- collapse of contents with javascript
	if ($opt{set}{collapse} == 1) {
		$output.="<script language='JavaScript'> function Toggle(node) { if (node.nextSibling.style.display == 'none') { if (node.childNodes.length > 0) { node.childNodes.item(0).replaceData(0,1,String.fromCharCode(8211)) } node.nextSibling.style.display = 'block' } else { if (node.childNodes.length > 0) { node.childNodes.item(0).replaceData(0,1,'+') } node.nextSibling.style.display = 'none' } } </script>";
		if (($cmds[0]{rc} == $OK && $ENV{"MULTI_PPID"} != $$) ||
		    ($cmds[0]{rc} == $OK && $opt{set}{extinfo_in_status})) {
			$output.="<a onclick='Toggle(this)' ".$opt{set}{style_plus_minus}.">+</a>";
			$output.="<div style='display:none'>";
		} else {
			$output.="<a onclick='Toggle(this)' ".$opt{set}{style_plus_minus}.">&ndash;</a>";
			$output.="<div style='display:block'>";
		}
	}

	#--- loop over commands: report particular results for long plugin output
	$output.="<div><table style='border-left-width:1px; border-right-width:0px; border-left-style:dotted' id='multi_table'>";
	for ($no=1;$no<=$#cmds;$no++) {
		#--- skip eval
		next if ($cmds[$no]{type} eq "eval");

		#--- hide all OK results if there is any check not OK  (by Timo Kempkens)
		next if (($opt{set}{report} & $DETAIL_HIDEIFOK) && ($cmds[$no]{rc} == $OK && $cmds[0]{rc} != $OK));

		#--- allow commands to get tag name
		$ENV{"MULTI_TAG"}=$cmds[$no]{name};

		$output.=sprintf "<tr style='font-size:8pt' title='%s'><td nowrap><table style='background-color:%s'><tr style='vertical-align:middle'><td style='font-size:6pt' title='%s'>%2.d</td></tr></table></td>",
			xml_encode(error($no)),
			$def{color}{$cmds[$no]{rc}},
			xml_encode(error($no)),
			$cmds[$no]{number};
		#--- Action url (standard version)
		if (	($opt{set}{report} & ($DETAIL_PERFORMANCE | $DETAIL_PERFORMANCE_CLASSIC)) &&
			($opt{set}{report} & $DETAIL_PERFORMANCE_LINK) &&
			defined($cmds[$no]{performance}) &&
			$cmds[$no]{process_perfdata} &&
			!$opt{set}{action_mouseover}) {

			my $hostname=get_hostname();
			DEBUG3("hostname is $hostname");
			my $pnp_url=substitute_macros($opt{set}{pnp_url});
			my $pnp_cgi=($opt{set}{pnp_version}=~/0.6/)?"graph":"index.php";
			my $image_path=substitute_macros($opt{set}{image_path});
			$output.=sprintf "<td nowrap>%s</td>",
				"<a target=\'$opt{set}{target}\' href=\'$pnp_url/$pnp_cgi?host=${hostname}&srv=$cmds[$no]{name}\'> " .
				"<img src=\'$image_path/action.gif\' width=\'20\' height=\'20\' border=\'0\' align=top alt='Show performance chart for $hostname / $cmds[$no]{plugin}' /></a>";
		#--- Action url (mouseover version)
		} elsif (($opt{set}{report} & ($DETAIL_PERFORMANCE | $DETAIL_PERFORMANCE_CLASSIC)) &&
			($opt{set}{report} & $DETAIL_PERFORMANCE_LINK) &&
			defined($cmds[$no]{performance}) &&
			$cmds[$no]{process_perfdata} &&
			$opt{set}{action_mouseover}) {

			my $hostname=get_hostname();
			DEBUG3("hostname is $hostname");
			my $pnp_url=substitute_macros($opt{set}{pnp_url});
			my $image_path=substitute_macros($opt{set}{image_path});
			DEBUG4(">>>$opt{set}{target}:$pnp_url:${hostname}:$cmds[$no]{name}:${hostname}:$cmds[$no]{name}:$image_path:$hostname:$cmds[$no]{name}<<<");
			my $mouseover_url="";
			if ($opt{set}{pnp_version}=~/0.6/) {
				$mouseover_url="$opt{set}{pnp_url}/graph?host=$opt{set}{HOSTNAME}&srv=$cmds[$no]{name}$opt{set}{pnp_add2url}\' class=\'tips\' rel=\'$opt{set}{pnp_url}/popup?host=$opt{set}{HOSTNAME}&srv=$cmds[$no]{name}$opt{set}{pnp_add2url}";
			} elsif ($opt{set}{pnp_version}=~/0.4/) {
				$mouseover_url="$opt{set}{pnp_url}/index.php?host=${hostname}&srv=$cmds[$no]{name}$opt{set}{pnp_add2url}\' onmouseout=\'clear_g()\' onmouseover=\"get_g(\'$opt{set}{HOSTNAME}\',\'$cmds[$no]{name}\')\"";
			} else {
				add_error(0,"Invalid mouseover URL type $opt{set}{pnp_version}, allowed are '0.6' and '0.4'");
				$mouseover_url="$pnp_url/graph?host=${hostname}&srv=$cmds[$no]{name}$opt{set}{pnp_add2url}";
			}
			$output.=sprintf "<td nowrap>%s</td>",
				"<a href=\'$mouseover_url\' target=\'$opt{set}{target}\'>" .
				"<img src=\'$image_path/action.gif\' width=\'20\' height=\'20\' border=\'0\' align=top alt='Show performance chart for $hostname / $cmds[$no]{name}' /></a>";
		} else {
			$output.="<td></td>";
		}
		#--- Notes url
		if (	($opt{set}{report} & $DETAIL_NOTES_LINK) &&
			defined($opt{set}{notes_url}) &&
			!$opt{set}{tag_notes_link}) {
			my $notes_url=substitute_macros($opt{set}{notes_url});
			my $image_path=substitute_macros($opt{set}{image_path});
			$output.=sprintf "<td nowrap>%s</td>",
				"<a href=\'$notes_url\' target=\'$opt{set}{target}\'>" .
				"<img src=\'$image_path/notes.gif\' width=\'20\' height=\'20\' border=\'0\' align=top alt='Show notes for $cmds[$no]{plugin}' /></a>";
		} else {
			$output.="<td></td>";
		}
		#--- and the rest...
		if (!$opt{set}{tag_notes_link}) {
			$output.=sprintf "<td>%s</td>", ($cmds[$no]{name}) ? $cmds[$no]{name} : "";
		} else {
			my $notes_url=substitute_macros($opt{set}{notes_url});
			$output.=sprintf "<td><a href=\'$notes_url\' target=\'$opt{set}{target}\'>%s</a></td>", ($cmds[$no]{name}) ? $cmds[$no]{name} : "";
		}
		DEBUG3("output:$cmds[$no]{output}");
		DEBUG3("HTML check_multi recursive levels: " . scalar ($cmds[$no]{output}=~s/multi_table/multi_table/g));
		if (defined($cmds[$no]{fmtstr})) {
			my $tmp="sprintf " . $cmds[$no]{fmtstr};
	 		$tmp.="," . join(",",@{$cmds[$no]{parms}}) if (defined($cmds[$no]{parms}));
			$tmp=substitute_macros($tmp);
			DEBUG4("output [ $cmds[$no]{name} ] = \'$tmp\'");
			$tmp=eval($tmp);
			$output.=sprintf "<td>%s</td>",
					($tmp=~/^([^\n]+)\n(.*)/is)
					? (($opt{set}{indent_label})
						? "$1</td></tr><tr style='font-size:8pt'><td colspan='4'></td><td colspan='1'>$2"
						: "$1</td></tr><tr><td></td><td colspan='5'>$2")
					: $tmp;
		} else {
			my $rclabel=($opt{set}{report} & $DETAIL_STATUS &&
				$cmds[$no]{output}!~/\b$def{label}{$cmds[$no]{rc}}\b/)
					? "$def{label}{$cmds[$no]{rc}} "
					: "";
			$output.=sprintf "<td>%s</td>",
					($cmds[$no]{output}=~/^([^\n]+)\n(.*)/is)
					? (($opt{set}{indent_label})
						? "${rclabel}$1</td></tr><tr style='font-size:8pt'><td colspan='4'></td><td colspan='1'>$2"
						: "${rclabel}$1</td></tr><tr><td></td><td colspan='5'>$2")
					: "${rclabel}$cmds[$no]{output}";
		}
		$output.="</tr>";
	}
	foreach my $s (sort numerically keys %{$def{s2r}}) {
		#--- if state matches
		if (($cmds[0]{state}[$def{s2r}{$s}] ne $cmds[0]{state_default}[$def{s2r}{$s}] && $rc{match}[$def{s2r}{$s}]) ||
		     $opt{set}{report} & $DETAIL_LIST_FULL ) {
			$output.=sprintf "<tr style='font-size:8pt'><td nowrap colspan='3'><table style='background-color:%s'><tr style='vertical-align:middle'><td style='font-size:6pt'>%4.4s</td></tr></table></td>",
				$def{color}{$def{s2r}{$s}},
				$def{label}{$def{s2r}{$s}};
			$output.=sprintf "<td>%s</td><td>%s</td>", $rc{match}[$def{s2r}{$s}]?"TRUE":"FALSE", $cmds[0]{state}[$def{s2r}{$s}];
			$output.="</tr>";
		}
	}
	$output.="</table></div>";
	$output.="</div>" if ($opt{set}{collapse} == 1 && ! $opt{set}{extinfo_in_status});

	#--- print state evaluation if verbose flag set
	if ($opt{set}{verbose} >= 2) {
		if ($ENV{"MULTI_PPID"} != $$) {
			$output.="<a onclick='Toggle(this)' style='".$opt{set}{style_plus_minus}."'>+</a>";
			$output.="<div style='display:none'><h4>Child check overview</h4>";
		}
		my @colors=("silver","lightgrey");
		my $flipflop=0;
		$output.="<table><tr style='text-align:left' bgcolor='" . $colors[$flipflop] . "'><th>No</th><th>Name</th><th>Runtime</th><th>RC</th><th>Output</th></tr>";
		for ($no=1;$no<=$#cmds;$no++) {
			$flipflop=!$flipflop;
			$output.=sprintf "<tr bgcolor='" . $colors[$flipflop] . "'><td>%d</td><td>%s</td><td>%7.5f</td><td>%d</td><td>%s</td></tr>", $no, $cmds[$no]{name}, $cmds[$no]{runtime}, $cmds[$no]{rc}, $cmds[$no]{output};
			$output.=sprintf "<tr bgcolor='" . $colors[$flipflop] . "'><td></td><td></td><td>%s</td><td></td><td>%s</td></tr>", $cmds[$no]{type}, $cmds[$no]{command};
		}
		$output.="</table></div>";

		#--- print state settings and RC evaluation result
		if ($ENV{"MULTI_PPID"} != $$) {
			$output.="<a onclick='Toggle(this)' style='".$opt{set}{style_plus_minus}."'>+</a>";
			$output.="<div style='display:none'><h4>State evaluation</h4>";
		}
		$flipflop=0;
		$output.="<table><tr style='text-align:left' bgcolor='" . $colors[$flipflop] . "'><th>State</th><th>Expression</th><th>Evaluates to</th></tr>";
		foreach my $s (sort numerically keys %{$def{s2r}}) {
			$flipflop=!$flipflop;
			$output.=sprintf "<tr bgcolor='" . $colors[$flipflop] . "'><td>%s</td><td>%s</td><td>%s</td></tr>", $def{label}{$def{s2r}{$s}}, $cmds[0]{state}[$def{s2r}{$s}], ($rc{match}[$def{s2r}{$s}]) ? "TRUE" : "FALSE";
		}
		$flipflop=!$flipflop;
		$output.="<tr bgcolor='" . $colors[$flipflop] . "'><td></td><td style='text-align:right'>Overall state</td><td style='font-weight:bold'>$def{label}{$cmds[0]{rc}}</td></tr>";
		$output.="</table></div>";
	}

	#--- verbose mode - add some tables
	if ($opt{set}{verbose} >=2) {

		if ($ENV{"MULTI_PPID"} != $$) {
			$output.="<a onclick='Toggle(this)' style='".$opt{set}{style_plus_minus}."'>+</a>";
			$output.="<div style='display:none'><h4>Child check details</h4>";
		}
		my @colors=("silver","lightgrey");
		my $flipflop=0;
		for ($no=1;$no<=$#cmds;$no++) {
			$output.="<h5>$no - $cmds[$no]{name}</h5>";
			$output.="<table><tr style='text-align:left' bgcolor='" . $colors[$flipflop] . "'><th></th><th>Attribute</th><th>Value</th></tr>";
			my %vars=(
				1 => {
					att => "\$no",
					val => $no,
				},
				2 => {
					att => "tag",
					val => $cmds[$no]{name},
				},
				3 => {
					att => "\$STATE_$cmds[$no]{name}\$",
					val => $cmds[$no]{rc},
				},
				4 => {
					att => "\$$cmds[$no]{name}\$",
					val => $cmds[$no]{output},
				},
				5 => {
					att => "type",
					val => $cmds[$no]{type},
				},
				6 => {
					att => "command",
					val => $cmds[$no]{command},
				},
				7 => {
					att => "runtime",
					val => $cmds[$no]{runtime},
				},
			);

			foreach my $i (sort keys %vars) {
				$flipflop=!$flipflop;
				$output.=sprintf "<tr bgcolor='" . $colors[$flipflop] . "'><td>%d</td><td>%s</td><td>%s</td></tr>", $i, $vars{$i}{att}, $vars{$i}{val};
			}
			$output.="</table>";
		}
		$output.="</div>";
	}

	#--- status_in_extinfo? escape newlines by '<br>'
	if ($opt{set}{extinfo_in_status}) {
		#--- status_in_extinfo? escape newlines by '<br>'
		$output=~s/\n/<br \/>/g; 
		#--- close div if collapsed
		$output.="</div>" if ($opt{set}{collapse} == 1); 
	}

	#--- last not least: output ;-)
	print $output;
}

#---
#--- report in XML (at the moment hidden in HTML comment)
#---
sub report_xml {

	#--- xml header
	my $xmlstr="<?xml version=\"1.0\"?>\n";
	$xmlstr.="<?xml-stylesheet type=\"text/xsl\" href=\"extinfo.xsl\"?>\n";
	$xmlstr.="<div id=\"check_multi_xml\" style='display:none'>\n";

	#--- begin with cmds[0] - parent
	my $no=0;
	$xmlstr.="<$MYSELF>\n";
	$xmlstr.="\t<CHILD>\n";
	$xmlstr.="\t\t<no>$no</no>\n";
	foreach my $token (sort keys %{$cmds[$no]}) {
		next if ($token=~/output|error/);
		if (defined($cmds[$no]{$token})) {
			if (ref($cmds[$no]{$token}) eq "ARRAY") {
				foreach my $subtoken (@{$cmds[$no]{$token}}) {
					$xmlstr.=sprintf "\t\t<%s>%s</%s>\n",$token,xml_encode($subtoken),$token;
				}
			} else {
				$xmlstr.=sprintf "\t\t<%s>%s</%s>\n",$token,xml_encode($cmds[$no]{$token}),$token;
			}
		}
	}
	#--- extra: output
	$xmlstr.="\t\t<output>";
	if (defined($cmds[0]{fmtstr})) {
		my $output="sprintf " . $cmds[0]{fmtstr};
	 	$output.="," . join(",",@{$cmds[0]{parms}}) if (defined($cmds[0]{parms}));
		$output=substitute_macros($output);
		DEBUG4("output [ head ] = \'$output\'");
		$xmlstr.=xml_encode(eval($output));
	} else {
		#--- print header line (2): summary for particular states
		if ($opt{set}{report} & $DETAIL_LIST_FULL) {
			$xmlstr.="$rc{count}[$CRITICAL] critical" . ((@{$rc{list}[$CRITICAL]}) ? " (" . join(', ',@{$rc{list}[$CRITICAL]}) . ')' : "") . ", " .
				"$rc{count}[$WARNING] warning"   . ((@{$rc{list}[$WARNING]})  ? " (" . join(', ',@{$rc{list}[$WARNING]})  . ')' : "") . ", " .
				"$rc{count}[$UNKNOWN] unknown"   . ((@{$rc{list}[$UNKNOWN]})  ? " (" . join(', ',@{$rc{list}[$UNKNOWN]})  . ')' : "") . ", " .
				"$rc{count}[$OK] ok";
		} elsif ($opt{set}{report} & $DETAIL_LIST) {
			my @r=();
			push @r, "$rc{count}[$CRITICAL] critical (" . join(', ',@{$rc{list}[$CRITICAL]}) . ")" if (@{$rc{list}[$CRITICAL]});
			push @r, "$rc{count}[$WARNING] warning ("   . join(', ',@{$rc{list}[$WARNING]})  . ")" if (@{$rc{list}[$WARNING]});
			push @r, "$rc{count}[$UNKNOWN] unknown ("   . join(', ',@{$rc{list}[$UNKNOWN]})  . ")" if (@{$rc{list}[$UNKNOWN]});
			push @r, "$rc{count}[$OK] ok" if (@{$rc{list}[$OK]});
			$xmlstr.=join(", ", @r);
		} else {
			$xmlstr.="$rc{count}[$CRITICAL] critical, " .
				"$rc{count}[$WARNING] warning, " .
				"$rc{count}[$UNKNOWN] unknown, " .
				"$rc{count}[$OK] ok";
		}
	}
	$xmlstr.="</output>\n";
	$xmlstr.="\t\t<error>" . join("</error>\n\t\t<error>",error(0)) . "</error>\n" if (error(0) ne "");
	$xmlstr.="\t</CHILD>\n";

	#--- loop over child checks
	for ($no=1;$no<=$#cmds;$no++) {
		next if (!$cmds[$no]{displayed});
		$xmlstr.="\t<CHILD>\n";
		$xmlstr.="\t\t<no>$cmds[$no]{number}</no>\n";
		foreach my $token (sort keys %{$cmds[$no]}) {
			if (defined($cmds[$no]{$token})) {
				if (ref($cmds[$no]{$token}) eq "ARRAY") {
					$xmlstr.="\t\t<$token>" . join("</$token>\n\t\t<$token>",@{$cmds[$no]{$token}}) . "</$token>\n";
				} else {
					$xmlstr.=sprintf "\t\t<%s>%s</%s>\n",$token,xml_encode($cmds[$no]{$token}),$token;
				}
			} else {
				add_error($no,"report_xml: XML element $token not found");
			}
		}
		$xmlstr.="\t</CHILD>\n";
	}
	$xmlstr.="</$MYSELF>\n</div>\n";
	print $xmlstr;
}

#---
#--- inventory report in XML
#---
sub report_inventory {

	#--- xml header
	my $xmlstr="<?xml version=\"1.0\"?>\n";
	$xmlstr.="<?xml-stylesheet type=\"text/xsl\" href=\"extinfo.xsl\"?>\n";
	$xmlstr.="<div id=\"check_multi_xml\" style='display:none'>\n";

	#--- begin with cmds[0] - parent
	my $no=0;
	$xmlstr.="<$MYSELF>\n";
	$xmlstr.="\t<CHILD>\n";
	$xmlstr.="\t\t<no>$no</no>\n";
	foreach my $token (sort keys %{$cmds[$no]}) {
		next if ($token!~/^name$|^rc$|^type$/);
		if (defined($cmds[$no]{$token})) {
			$xmlstr.=sprintf "\t\t<%s>%s</%s>\n",$token,xml_encode($cmds[$no]{$token}),$token;
		}
	}
	$xmlstr.="\t</CHILD>\n";

	#--- loop over child checks
	for ($no=1;$no<=$#cmds;$no++) {
		$cmds[$no]{rc}=$OK;
		next if (!$cmds[$no]{displayed});
		$xmlstr.="\t<CHILD>\n";
		$xmlstr.="\t\t<no>$no</no>\n";
		foreach my $token (sort keys %{$cmds[$no]}) {
			next if ($token!~/^name$|^rc$|^type$/);
			if (defined($cmds[$no]{$token})) {
				$xmlstr.=sprintf "\t\t<%s>%s</%s>\n",$token,xml_encode($cmds[$no]{$token}),$token;
			} else {
				add_error($no,"report_xml: XML element $token not found");
			}
		}
		$xmlstr.="\t</CHILD>\n";
	}
	$xmlstr.="</$MYSELF>\n</div>\n";
	print $xmlstr;
}

#---
#--- helper routine which encodes several XML specific characters
#---
sub xml_encode {
	my $input=shift;
	my %transtab=(
		'\''	=> '&#039;',
		'&'	=> '&amp;',
		'<'	=> '&lt;',
		'>'	=> '&gt;',
		'\|'	=> '&#124;',
	);
	for (keys(%transtab)) {
		$input=~s/$_/$transtab{$_}/g;
	}
	$input;
}

#---
#--- print out all perfdata
#---    if its compliant to developers guidelines ;)
#---
sub report_perfdata {
	if (!$opt{set}{report} & $DETAIL_HTML) {
		DEBUG1("\n","-" x 80);
		DEBUG1("Plugin performance data");
		DEBUG1("-" x 80);
	}
	#--- report performance data?
	if ($opt{set}{report} & $DETAIL_PERFORMANCE) {

		#--- take name and - if empty - check_multi
		my $name=($opt{set}{name})?$opt{set}{name}:$MYSELF;
		#--- if whitespace within name, wrap it with single quotes
		my $delim=($name=~/\s+/)?"'":"";
		my $perftmp="";
		DEBUG3("(DETAIL_PERFORMANCE): name=" . ($opt{set}{name}) ? $opt{set}{name} : $MYSELF);
		print "\|";
		printf "$delim%s::%s::plugins$delim=%d time=%f ",
			$name,
		       	$MYSELF,
			$cmds[0]{nallchecks},
			$cmds[0]{runtime};
		#--- extended performance data output for check_multi
		if ($opt{set}{extended_perfdata}) {
			printf "$delim%s_extended::check_multi_extended::count_ok$delim=%d count_warning=%d count_critical=%d count_unknown=%d overall_state=%d ",
				$name,
				$rc{count}[$OK],
				$rc{count}[$WARNING],
				$rc{count}[$CRITICAL],
				$rc{count}[$UNKNOWN],
				$cmds[0]{rc};
		}
		#--- one line per command, format: tag=output
		for ($no=1;$no<=$#cmds;$no++) {

			#--- suppress_perfdata set? ignore perfdata
			next if (! $cmds[$no]{process_perfdata});

			if (defined($cmds[$no]{performance})) {

				#--- macros found? substitute
				$cmds[$no]{performance}=substitute_macros($cmds[$no]{performance});

				#--- prevent concatenation of multi-labels if called recursively
				if ($cmds[$no]{performance}=~/check_multi::check_multi::(.*)/) {
					$perftmp="${name}::check_multi::$1 ";
				} elsif ($cmds[$no]{performance}=~/::check_multi::/) {
					$perftmp="$cmds[$no]{performance} ";
				#--- cumulate perfdata: pass through
				} elsif ($cmds[$no]{performance}=~/::cumulate::/) {
					$perftmp="$cmds[$no]{performance} ";
				} else {
					#--- do we have an explicit plugin specification? take it
					my $plugin=(defined($cmds[$no]{pplugin}) && $cmds[$no]{pplugin} ne "") 
						? $cmds[$no]{pplugin} 
						: $cmds[$no]{plugin};
					DEBUG4("plugin is $plugin");

					#--- perflabel already with single quotes? then keep it
					if ($cmds[$no]{performance}=~/^\s*\'([^']*)\'=(\S+)(.*)/) {
						$perftmp="\'$cmds[$no]{name}::${plugin}::$1\'=$2$3 ";
						DEBUG4("quoting detection: already quoted before:" .$perftmp);
					#--- child check name with spaces? then use single quotes
					} elsif ($cmds[$no]{name}=~/\s+/) {
						$cmds[$no]{performance}=~/([^=]*)=(.*)\s*/;
						$perftmp="\'$cmds[$no]{name}::${plugin}::$1\'=$2 ";
						DEBUG4("quoting detection: blanks found:" .$perftmp);
					} else {
						$cmds[$no]{performance}=~s/\s*(.*)/$1/;
						$perftmp="$cmds[$no]{name}::${plugin}::$cmds[$no]{performance} ";
						DEBUG4("quoting detection: standard without blanks:" .$perftmp);
					}
				}
				$cmds[$no]{performance}="";
				DEBUG4("before splitting: $perftmp");
				#--- preserve '::' as multi delimiter - replace all '::' with '_'
				while ($perftmp=~/\s*([^=]+)=(\S+)\s*(.*)/) {
					my $label=$1;
					my $data=$2;
					$perftmp=$3;

					my @tmparr=split(/::/,$label);
					DEBUG4("token before splitting: $label [0-$#tmparr]:" . join("|",@tmparr));
					if ($#tmparr > 1) {
						$cmds[$no]{performance}.=shift(@tmparr)."::".shift(@tmparr)."::";
						$cmds[$no]{performance}.=join("_",@tmparr);
					} else {
						$cmds[$no]{performance}.=$label;
					}
					$cmds[$no]{performance}.="=$data ";
					DEBUG4("remaining perftmp: $perftmp");
				}
				DEBUG4("complete after splitting: $cmds[$no]{performance}");
				print $cmds[$no]{performance};
			}
		}
	} elsif ($opt{set}{report} & $DETAIL_PERFORMANCE_CLASSIC) {
		print "\|";

		#--- one line per command, format: tag=output
		for ($no=1;$no<=$#cmds;$no++) {

			#--- suppress_perfdata set? ignore perfdata
			next if (! $cmds[$no]{process_perfdata});

			#--- macros found? substitute
			$cmds[$no]{performance}=substitute_macros($cmds[$no]{performance});

			if (defined($cmds[$no]{performance})) {
				if (my $errstr=parse_perfdata($cmds[$no]{performance})) {
					add_error($no,"$cmds[$no]{name} perfdata discarded for $errstr");
				} else {
					print "$cmds[$no]{performance} ";
				}
			}
		}
	}
}

#---
#--- find errors in perfdata
#---
sub parse_perfdata {
	my $perfdata=shift;
	my $label="";
	my $data="";
	my $error="";
	my $uom="";

	#--- accepting loose perfdata
	if ($opt{set}{loose_perfdata}) {
		DEBUG4("loose_perfdata=1");
		#--- replace decimal comma with decimal point
		if (defined($ENV{LANG}) && $ENV{LANG} =~ /de_DE/) {
			DEBUG4("LANG is $ENV{LANG}, replacing commata by decimal points");
			($perfdata) =~ s/,/./g;
		}
	}

	#---
	#--- 'label'=value[UOM];[warn];[crit];[min];[max]
	#---
	#--- loop over perfdata
	while ($perfdata) {
		DEBUG4("parsing perfdata:$perfdata");
		#--- label w/ \'
		if ($perfdata=~/^\s*(\'[^']*\')=([^ ]+)(.*)/) {
			$label=$1;
			$data=$2;
			$perfdata=$3;
			DEBUG4("parsed perfdata -'label':$1 data:$2 rest:$3");
		#--- label w/o \'
		} elsif ($perfdata=~/^\s*([^\s=']+)=([^ ]+)(.*)/) {
			$label=$1;
			$data=$2;
			$perfdata=$3;
			DEBUG4("parsed perfdata - label:$1 data:$2 rest:$3");
		} else {
			DEBUG2("general parsing error - invalid perfdata");
			return "general error in '$perfdata'";
		}
		$perfdata=~s/^\s+//; $perfdata=~s/\s+$//;

		#--- perfdata has label and data, now do detailed checks
		my ($value,$warning,$critical,$min,$max)=split(/;/,$data);
		return "$label: no value in data \'$data\'" if ($value eq "");
		if ($value=~/([-0-9.]+)([^0-9-.]*)/) {
			$value=$1;
			$uom=$2;
		}

		#--- invalid perfdata with trailing ';' after max value
		if (($data=~tr/;//)>=5) {
			DEBUG2("invalid ';' after max value $max");
			return "error in '$data': invalid ';' after max value $max" if (! $opt{set}{loose_perfdata});
		} else {
			DEBUG4("number of ';' ok in $data: " . scalar($data=~tr/;//));
		}

		$error.= "$label: bad value \'$value\' in data \'$data\' " if ($value && $value !~/^[-0-9.]+$/);
		$error.= "$label: bad UOM \'$uom\' in data \'$data\' " if ($uom ne "" && ($uom!~/^[um]*s$/i && $uom!~/^%$/ && $uom!~/^[kmgt]*b$/i && $uom!~/^c$/i));
		$error.= "$label: bad warning \'$warning\' in data \'$data\' " if ($warning && $warning !~/^[\@\~]?[-0-9.:]+$/);
		$error.= "$label: bad critical \'$critical\' in data \'$data\' " if ($critical && $critical !~/^[\@\~]?[-0-9.:]+$/);
		$error.= "$label: bad min \'$min\' in data \'$data\' " if ($min && $min !~/^[-0-9.]+$/);
		$error.= "$label: bad max \'$max\' in data \'$data\' " if ($max && $max !~/^[-0-9.]+$/);
		return $error if ($error);

		#--- done: perfdata is ok
	}
	DEBUG3("no errors found");
	return undef;
}

#---
#--- helper routine to generate Nagios service check definitions
#---    mostly needed for 'check_multi_feeds_passive'
sub report_service_definition {
	my @tpl="";
	#--- search for template file and read contents
	if (defined($opt{set}{service_definition_template}) && $opt{set}{service_definition_template}) {
		if (-f "$opt{set}{service_definition_template}") {
			if (open(DEF, $opt{set}{service_definition_template})) {
				@tpl=<DEF>;
				close DEF;
			} else {
				print "#--- Error: cannot open $opt{set}{service_definition_template}:$?\n";
				return 2;
			}
		} else {
			print "#--- Error: service definition template file \'$opt{set}{service_definition_template}\' not found\n";
			return 1;
		}
	#--- check_for default template variable
	} elsif (defined($opt{set}{service_definition_template_default})) {
		@tpl=$opt{set}{service_definition_template_default};
	#--- bail out with error message
	} else {
		print "#--- Error: variable \'service_definition_template_default\' not defined\n";
		return 1;
	}
	#--- bail out if HOSTNAME are not set
	if (! $opt{set}{HOSTNAME} && ! $ENV{"${NAGIOS}_HOSTNAME"}) {
		print "#--- Error: need HOSTNAME for service definition.\n";
		print "#--- Please specify -s HOSTNAME=<hostname> or provide environment variable HOSTNAME\n";
		return 3;
	} else {
		DEBUG4(sprintf "HOSTNAME specified: \'%s\'", ($opt{set}{HOSTNAME}) ? $opt{set}{HOSTNAME} : $ENV{"${NAGIOS}_HOSTNAME"});
	}

	my $output="";
	for($no=1;$no<=$#cmds;$no++) {
		next if ($cmds[$no]{type} eq "eval");
		my @svc=@tpl;
		foreach my $line (@svc) {
			DEBUG4("before substitution: $line");
			$line=~s/THIS/$no/g;
			$line=substitute_macros($line);
			DEBUG4("after substitution: $line");
			$output.=$line;
		}
	}
	print $output;
}



#---
#--- send check_multi results to NSCA daemon
#---
sub report_send_nsca {
	#
	# NSCA Client 2.5
	# Copyright (c) 2000-2006 Ethan Galstad (www.nagios.org)
	# Last Modified: 01-21-2006
	# License: GPL v2
	# Encryption Routines: NOT AVAILABLE
	#
	# Usage: /usr/local/nagios/sbin/send_nsca -H <host_address> [-p port] [-to to_sec] [-d delim] [-c config_file]
	#
	# Options:
	#  <host_address> = The IP address of the host running the NSCA daemon
	#  [port]         = The port on which the daemon is running - default is 5667
	#  [to_sec]       = Number of seconds before connection attempt times out.
	#                   (default timeout is 10 seconds)
	#  [delim]        = Delimiter to use when parsing input (defaults to a tab)
	#  [config_file]  = Name of config file to use
	#
	# Note:
	# This utility is used to send passive check results to the NSCA daemon.  Host and
	# Service check data that is to be sent to the NSCA daemon is read from standard
	# input. Input should be provided in the following format (tab-delimited unless
	# overriden with -d command line argument, one entry per line):
	#
	# Service Checks:
	# <host_name>[tab]<svc_description>[tab]<return_code>[tab]<plugin_output>[newline]
	#
	# Host Checks:
	# <host_name>[tab]<return_code>[tab]<plugin_output>[newline]
	#
	my $sent=0;

	if (! -x "$opt{set}{send_nsca}") {
		add_error(0,"report_send_nsca: $opt{set}{send_nsca} not found or not executable:$!");
		return $sent;
	}
	if (! -f "$opt{set}{send_nsca_cfg}") {
		add_error(0,"report_send_nsca: $opt{set}{send_nsca_cfg} not found or not readable for UID $>:$!");
		return $sent;
	}
	my $hostname=get_hostname();
	my $nsca_cmdline=
		"$opt{set}{send_nsca} " .
		"-H $opt{set}{send_nsca_srv} " .
		"-p $opt{set}{send_nsca_port} " .
		"-to $opt{set}{send_nsca_timeout} " .
		"-d \'$opt{set}{send_nsca_delim}\' " .
		"-c $opt{set}{send_nsca_cfg}";
	DEBUG3("cmdline is \'$nsca_cmdline\'");
	for (my $i=1; $i<=$#cmds; $i++) {

		#--- service will be suppressed if its mentioned in '-s suppress_service=<service1>,<service2>,...
		if ($opt{set}{suppress_service} &&
		    $opt{set}{suppress_service}=~/\b$cmds[$i]{name}\b/i) {
			DEBUG2("checkresult file of [ $cmds[$i]{name} ] will be suppressed");
			next;
		}

		#--- call send_ncsa
		if (!open(SEND_NSCA, "|$nsca_cmdline >/dev/null")) {
			add_error(0,"report_send_nsca: error calling command line $nsca_cmdline");
			return $sent;
		}
		printf SEND_NSCA "%s;%s;%s;%s\n",
			$hostname,
			$cmds[$i]{name},
			$cmds[$i]{rc},
			$cmds[$i]{output};
		if ($?) {
			add_error(0,"report_send_nsca: error sending data to nsca:$?");
		} else {
			$sent++;
		}
		close SEND_NSCA;
	}
	return $sent;
}

#---
#--- report child checks as check_result files
#---
sub report_checkresult_file {

	#--- use File::Temp for generation of temp file, its available in standard perl
	module ("File::Temp qw(tempfile)",1);

	#--- loop over child checks
	for (my $i=1; $i<=$#cmds; $i++) {

		#--- service will be suppressed if its mentioned in '-s suppress_service=<service1>,<service2>,...
		if ($opt{set}{suppress_service} &&
		    $opt{set}{suppress_service}=~/\b$cmds[$i]{name}\b/i) {
			DEBUG2("checkresult file of [ $cmds[$i]{name} ] will be suppressed");
			next;
		}

		#--- create service definition file (if enabled)
		if ($opt{set}{feed_passive_autocreate}) {
			check_and_create_service_definition($opt{set}{HOSTNAME}, $cmds[$i]{name});
		}

		#--- create checkresults file
		my ($th,$tf)=File::Temp::tempfile("cXXXXXX",DIR=>"$opt{set}{checkresults_dir}");
		my $escaped_output=$cmds[$i]{output}; $escaped_output=~s/\n/\\n/g;
		if ($cmds[$i]{process_perfdata} && defined($cmds[$i]{performance}) && $cmds[$i]{performance}) {
			$escaped_output.='|'.$cmds[$i]{performance}.' ['.$cmds[$i]{plugin}.']';
		}
		$escaped_output="(No output returned from plugin)" if ($escaped_output eq "");
		DEBUG4("escaped_output:\'$escaped_output\'");
		my $content=checkresult(
			"host_name=$opt{set}{HOSTNAME}",
			"service_description=$cmds[$i]{name}",
			"start_time=".sprintf("%17.6f",$cmds[$i]{starttime}),
			"finish_time=".sprintf("%17.6f",$cmds[$i]{endtime}),
			"return_code=".$cmds[$i]{rc},
			"output=".$escaped_output,
		);
		DEBUG4("file content is >$content<");
		print $th $content;
		close $th;

		#--- write OK file
		if (!open(OKFILE, ">$tf.ok")) {
			 add_error(0,"report_checkresult_file: Cannot write OK file to $tf.ok:$!");
		} else {
			DEBUG4("$tf.ok written");
			close OKFILE;
		}
	}
}

#---
#--- helper routine to build up checkresult output
#---
sub checkresult {
	my (@parms)=@_;

	my %att=(
		"host_name"		=> undef,
		"service_description"	=> undef,
		"check_type"		=> 1,
		"check_options"		=> 0,
		"scheduled_check"	=> 0,
		"reschedule_check"	=> 0,
		"latency"		=> 0,
		"start_time"		=> undef,
		"finish_time"		=> undef,
		"early_timeout"		=> 0,
		"exited_ok"		=> 1,
		"return_code"		=> undef,
		"output"		=> undef,
	);
	#--- read and check parameter pairs (should be key=value)
	foreach my $parameter (@parms) {
		if (my ($key,$val)=($parameter=~/\s*([^=]+)\s*=\s*(.*)\s*/)) {
			#--- perform only allowed (= already defined) pairs
			if (exists($att{$key})) {
				$att{$key}=$val;
				DEBUG4("add key $key ($val) to attributes");
			} else {
				add_error(0,"checkresult: unknown attribute $key");
			}
		} else {
			add_error(0,"checkresult: unknown attribute specification $parameter");
		}
	}

	#--- create checkresult content
	my $checkresult=sprintf(
		"### check_multi passive check result file ###\n".
		"file_time=%ld\n\n".
		"### child check result ###\n".
		"# Time: %s\n",
			int(time),
			scalar(localtime($att{start_time}))
	);
	#--- add attributes, output at last
	foreach my $attribute (sort keys %att) {
		#--- skip output, append later
		next if ($attribute eq "output");
		#--- add attribute to checkresult
		$checkresult.="$attribute=$att{$attribute}\n" if (defined($att{$attribute}));
	}
	#--- at last: output
	$checkresult.="output=$att{output}";
	return $checkresult;
}

#---
#--- send check_multi results to send_gearman
#---
sub report_send_gearman {
	# Usage:
	# 
	# send_gearman [ --debug=<lvl>                ]
	#              [ --help|-h                    ]
	# 
	#              [ --config=<configfile>        ]
	# 
	#              [ --server=<server>            ]
	# 
	#              [ --encryption=<yes|no>        ]
	#              [ --key=<string>               ]
	#              [ --keyfile=<file>             ]
	# 
	#              [ --host=<hostname>            ]
	#              [ --service=<servicename>      ]
	#              [ --result_queue=<queue>       ]
	#              [ --message|-m=<pluginoutput>  ]
	#              [ --returncode|-r=<returncode> ]
	# 
	# for sending active checks:
	#              [ --active                     ]
	#              [ --starttime=<unixtime>       ]
	#              [ --finishtime=<unixtime>      ]
	#              [ --latency=<seconds>          ]
	# 
	# plugin output is read from stdin unless --message is used.
	# 
	my $sent=0;
	if (! -x "$opt{set}{send_gearman}") {
		add_error(0,"report_send_gearman: $opt{set}{send_gearman} not found or not executable:$!");
		return $sent;
	}
	#if (! -f "$opt{set}{send_gearman_cfg}") {
	#add_error(0,"report_send_gearman: $opt{set}{send_gearman_cfg} not found or not readable for UID $>:$!");
	#return $sent;
	#}
	#--- determine hostname
	my $hostname=get_hostname();
	my $keyoption=(-f $opt{set}{send_gearman_key}) ? "keyfile" : "key";
	my $resultqueueoption=($opt{set}{send_gearman_resultqueue})? "--result_queue=" : "";
	my $encryption=($opt{set}{send_gearman_encryption}) ? "yes" : "no";
	my $gearman_cmdline=
		"$opt{set}{send_gearman} " .
		"--server=$opt{set}{send_gearman_srv} " .
		"--encryption=$encryption " .
		"--$keyoption=$opt{set}{send_gearman_key} " .
		"${resultqueueoption}$opt{set}{send_gearman_resultqueue} ";
	DEBUG3("cmdline is \'$gearman_cmdline\'");
	for (my $i=1; $i<=$#cmds; $i++) {

		#--- service will be suppressed if its mentioned in '-s suppress_service=<service1>,<service2>,...
		if ($opt{set}{suppress_service} &&
		    $opt{set}{suppress_service}=~/\b$cmds[$i]{name}\b/i) {
			DEBUG2("checkresult file of [ $cmds[$i]{name} ] will be suppressed");
			next;
		}

		#--- call send_gearman
		unless (open(SEND_GEARMAN, 
			"|$gearman_cmdline ".
			"--returncode=$cmds[$i]{rc} " . 
			"--host=\'$hostname\' " . 
			"--service=\'$cmds[$i]{name}\'" )) {
			add_error(0,"report_send_gearman: error calling command line $gearman_cmdline");
			return $sent;
		}
		print SEND_GEARMAN "$cmds[$i]{output}";
		if (!close SEND_GEARMAN) {
			add_error(0,"report_send_gearman: error sending data to gearman:$?");
		} else {
			$sent++;
		}
	}
	return $sent;
}

#
# helper routine which automatically creates 
# service definitions for passive feeded services
#
sub check_and_create_service_definition {
	my ($hostname, $service_definition)=@_;

	#--- check / create directory for passive feeded services
	if (! my_mkdir("$opt{set}{feed_passive_dir}/$hostname",$opt{set}{feed_passive_dir_permissions})) {
		add_error(0,"check_and_create_service_definition: cannot create directory $opt{set}{feed_passive_dir}/$hostname: $!");
	}
	#--- check age of service definition file and recreate if too old
	my $cfgfile_age=time-(stat("$opt{set}{feed_passive_dir}/$hostname/${service_definition}.cfg"))[10] 
		if (-f "$opt{set}{feed_passive_dir}/$hostname/${service_definition}.cfg");

	#--- create in any case if it does not exist
	if (! -f "$opt{set}{feed_passive_dir}/$hostname/${service_definition}.cfg" || 
		$cfgfile_age>$opt{set}{cmdfile_update_interval}) {

		my $content=$opt{set}{service_definition_template_default};
		$content=~s/\$HOSTNAME\$/$hostname/g;
		$content=~s/\$SERVICEDESC\$/$service_definition/g;
		writefile(
			"$opt{set}{feed_passive_dir}/$hostname/${service_definition}.cfg", 
			($content)
		);
		DEBUG4("created service definition file for service ${service_definition}");
		return 1;
	} else {
		DEBUG4("service definition file $opt{set}{feed_passive_dir}/$hostname/${service_definition}.cfg already there");
		return 0;
	}
}

#-------------------------------------------------------------------------------
#--- main ----------------------------------------------------------------------
#-------------------------------------------------------------------------------

#--- take care against signals
install_signal_handler(\install_signal_handler, @{$opt{set}{signals}});

#--- parse command line options and STDIN
exit $UNKNOWN if (&process_input != $OK);

#--- don't run this as root ;-)
add_error(0,"please don't run plugins as root!") if ($opt{set}{user}=~/root/ && !$opt{set}{dont_be_paranoid});

#--- parse command file (nrpe format)
&parse_files($opt{filename});

#--- parse single command lines
&parse_lines(@{$opt{execute}});

#--- provide settings as env variables
&set_env_settings;

#--- quick exit if only encoding of commands requested
if ($opt{set}{report} & $DETAIL_ENCODE_COMMANDS) {
	print "%0A\n";	# end up with NEWLINE
	exit $OK;
}

#--- no child checks defined yet? Throw UNKNOWN
if ($#cmds<1) {
	add_error(0,"no checks defined");
	$cmds[0]{rc}=$opt{set}{no_checks_rc};
	$cmds[0]{state}[$OK]="0==1" if ($opt{set}{no_checks_rc} != $OK);
} else {
	DEBUG4(($#cmds - 1) . " child checks running");
	if (module("Data::Dumper")) {
		DEBUG4(Dumper(@cmds));
	}

}

#--- create unique hash for check
$cmds[0]{hash}=&my_hash(&config_string(\@cmds));

#--- initialize timer for overall timeout
$cmds[0]{starttime}=time;
$cmds[0]{timeouttime}=$cmds[0]{starttime} + $opt{set}{TIMEOUT};

#--- instant check execution defined? then do it right now
if ($opt{set}{instant}) {
	DEBUG4("Instant execution of \'$opt{set}{instant}\' requested");
	for ($no=1;$no<=$#cmds;$no++) {
		if ($cmds[$no]{name} eq $opt{set}{instant}) {
			exec_command($no);
			DEBUG4("Instant execution of \'$opt{set}{instant}\': $cmds[$no]{output}, RC:$cmds[$no]{rc}");
			print "$cmds[$no]{output}\n";	
			exit $cmds[$no]{rc};
		}
	}
	#--- instant tag not found: bail out with error
	print "UNKNOWN - tag \'$opt{set}{instant}\' not found for instant execution\n";
	exit $UNKNOWN;
}

#--- inventory defined? then do it right now
if ($opt{set}{inventory}) {
	report_inventory();
	exit $OK;
}

#--- loop over commands in order of config file
$no=1;
while ($no<=$#cmds) {

	#--- if total timeout is going to be exceeded, cancel next commands
	if ($opt{set}{cancel_before_global_timeout} && time + $opt{set}{timeout} > $cmds[0]{timeouttime}) {
		$cmds[$no]{output}="UNKNOWN - execution cancelled due to global timeout ($opt{set}{TIMEOUT}s)";
		$cmds[$no]{rc}=$UNKNOWN;
		$cmds[$no]{runtime}=0;
	} elsif (time > $cmds[0]{timeouttime}) {
		$cmds[$no]{output}="UNKNOWN - execution cancelled due to global timeout ($opt{set}{TIMEOUT}s)";
		$cmds[$no]{rc}=$UNKNOWN;
		$cmds[$no]{runtime}=0;
	} elsif ($cmds[$no]{feeded}) {
		#--- do nothing - this cmd has been feeded in via STDIN
	} else {
		#--- wait interval between child checks if more than one check
		if ($no>1) {
			sleep($opt{set}{child_interval});
			DEBUG3("-> sleeping $opt{set}{child_interval} seconds before child[$no]");
			$cmds[0]{sleeped}+=$opt{set}{child_interval};
		}
		#--- execute command
		&exec_command($no);
		#DEBUG4("Executed command $no: $cmds[$no]{output}, RC:$cmds[$no]{rc}");
	}

	$no++;
}
$cmds[0]{endtime}=time;

#--- prepare output
&global_result_rating;

#--- report
&report_all;

#--- return rc with highest severity
DEBUG4("This is the end - with RC $cmds[0]{rc}");
exit $cmds[0]{rc};
