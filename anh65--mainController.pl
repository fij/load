#!/usr/bin/perl
use strict; use warnings; use Switch; use POSIX;

# ============= parameters ========================

if( 34 != @ARGV )
{
    die "
\tUsage: $0 \\
\t       <absPath_head_rootDir    absolute (full) path of the project's root directory on the head computer of the cluster> \\
\t       <absPath_head_nwIdList   full path of the file containing network IDs (each network ID encodes a topology)> \\
\t       <nameStart_exe           first part of the name of the executable program, which is doing the number crunching> \\
\t       <relDir_node_exe         relative path of the directory in which the executable(s) are on the nodes of the cluster> \\
\t       <clusterName             name of the cluster we are using now (atlasz, piko, qb3, has)> \\
\t       <maxNumRunning           maximum number of jobs that should run simultaneously> \\
\t       <queueResponseRetrySec   if the queue itself is not available, then retry and request the queue again after this number of seconds> \\
\t       <queueSubmitWaitSec      IF   the queue contains more than 'maxNumMyItemsInQueue' jobs from me
\t                                     OR   the only jobs that are left are running,
\t                                THEN wait for this number of seconds before trying to submit jobs again> \\
\t       <absPath_head_parTempl   absolute (full) path of the parameter file template on the head computer> \\
\t       <absPath_head_statTempl  full path of the status file template on the head computer> \\
\t       <file_inputSignalList    Input file containing the list of input signals
\t                                NOTE: the format of input signals is explained in the parameter template file> \\
\t       <absPath_mover           The program that moves a file to a given other location as soon as that file is available, otherwise it waits> \\
\t       <absPath_discretizer     The program that discretizes all responses> \\
\t       <absPath_fastaWriter     The program converting the discretized responses into fasta formatted sequences> \\
\t       <kList                   list of reaction rates to be used> \\
\t       <linkWeightSelMethod     for a given k how to select link weight sets:
\t                                - \"all\": each subset of the links defines one weight set: link weight = k for the subset, link weight = 1 for the other links
\t                                - \"outnode\": there are two link weight sets: 
\t                                  (1) all links have weight 1, (2) incoming regulatory (not basal enz.) links of the output node have weight k, all others have 1> \\
\t                                - \"inside_all\":
\t                                  . the input link and the basal enzyme links have all weights 1,
\t                                  . each subset of the links between the 3 simulated nodes defines one link weight set: links within this link subset have weight k, others 1> \\
\t       <startStateList          list of initial states> \\
\t       <node_maxWallClockTime   maximum wall clock time (in seconds) allowed for one instance of the node controller> \\
\t       <simTimeStepConstant     In an actual simulation the length of the default time step for the simulation updates is computed using this constant 
\t                                See the parameter file for details> \\
\t       <storeDataChangeThresh   Store data if at least one of the three nodes has changed by this amount> \\
\t       <constValBasEnz          Constant value of all basal enzymes> \\
\t       <maxSimTime              The simulation will be stopped when this simulation time is reached> \\
\t       <simStartRelaxTime       Run the simulation for this amount of simulation time before starting the actual measurements> \\
\t       <respDiscr_tN            When discretizing the reponses:
\t                                - between the start (simStartRelaxTime) and end (maxSimTime) time points of the measurement use this number of equal size time windows> \\
\t       <respDiscr_zN            - between the minimum (0) and maximum (1) response function values use this number of equal size intervals> \\
\t       <qb3_useLongQ            Parameter for the 'qb3' cluster only: Submit jobs explicitly to the long queue? (1: yes, 0: no)> \\
\t       <inFile_otherTodoDirs    File listing other 'todo' directories where the main controller should look for jobs still running
\t                                My running jobs listed in these directories are included in the total allowed> \\
\t       <jobNamePrefix           Prefix for the name of jobs in the cluster's queue.
\t                                If the user has more than one project in the queue, then this prefix allows to find the computational jobs belonging to this project> \\
\t       <nwIds_inWhichOrder      In which order should the program take the network IDs 
\t                                0: numerically ascending, 1: num. descending, 2: desc. order of link number of nw., 2_x{number}: use 2, but run the network with ID={nwId} first> \\
\t       <sgeMemFree              Amount of memory that an SGE command file should request> \\
\t       <sgeScratch              Amount of local hard disk space (on the /scratch partition of the computing node) that an SGE command file should request> \\
\t       <sgeNetapp               Amount of hard disk space on netapp that an SGE command file should request> \\
\t       <jobMaxDynMemMB         Maximum number of megabytes that a job is allowed to allocate dynamically> \\
\t       <maxJobNumSubmit         Maximum number of jobs to submit in one batch>

";
}

my %PAR; @PAR{ qw/ absPath_head_rootDir absPath_head_nwIdList nameStart_exe relDir_node_exe clusterName maxNumRunning 
		   queueResponseRetrySec queueSubmitWaitSec absPath_head_parTempl absPath_head_statTempl file_inputSignalList 
		   absPath_mover absPath_discretizer absPath_fastaWriter kList linkWeightSelMethod startStateList
		   node_maxWallClockTime simTimeStepConstant storeDataChangeThresh constValBasEnz maxSimTime simStartRelaxTime
		   respDiscr_tN respDiscr_zN qb3_useLongQ inFile_otherTodoDirs jobNamePrefix nwIds_inWhichOrder sgeMemFree sgeScratch sgeNetapp 
		   jobMaxDynMemMB maxJobNumSubmit /} = @ARGV;

# =============== function definitions ================

sub init
{
    my ($par) = @_;

    # IF the job subdirectory does not yet exist, THEN make it
    -d $$par{"absPath_head_rootDir"} or mkdir $$par{"absPath_head_rootDir"};
    
    # subdirectory for the jobs to do, for the jobs that are already done, and for the SGE command files
    for my $subDir (qw/todo done sge/){ mkdir $$par{"absPath_head_rootDir"}."/".$subDir; }

    # user name on each cluster
    switch($$par{"clusterName"}){
	case "atlasz" { 
	    $$par{"myUserName"} = "fij";
	}
	case "piko" {
	    $$par{"myUserName"} = "fij";
	}
	case "qb3" {
	    $$par{"myUserName"} = "fij";
	}
	# reply in all other cases
	default { die "Sorry, cluster not (yet) implemented: '".$$par{clusterName}."'\n"; }
    }

    # read the parameter file template
    open IN, $$par{"absPath_head_parTempl"}; $$par{"parTempl"} = join("",<IN>); close IN;

    # read the template for the status file
    open IN, $$par{"absPath_head_statTempl"}; $$par{"statTempl"} = join("",<IN>); close IN;
    
    # read the formatted list of input signals
    @{$$par{inputSignalList}} = @{&readDataLinesFromFile($$par{"file_inputSignalList"})};
    $$par{inputSignalList_str} = join("\n",@{$$par{inputSignalList}});
    $$par{nSignal} = scalar @{$$par{inputSignalList}};

    # job name prefix has to start with a letter
    if($$par{jobNamePrefix} !~ /^[a-zA-Z]/){ die "Error, job name prefix is \"".$$par{jobNamePrefix}."\" (without quotes). It should start with a letter: a-z, A-Z\n\n"; }
}

# -----------------------------------------------

sub read_itemList
{
    my ($inFile,$itemList) = @_;

    # clear output data
    @$itemList = ();

    # --- open infile, read data line, skip blank and comment lines ---
    # data line format is: <data item, no whitespaces> [other fields]
    open IN, "<$inFile" || die "Error: cannot read from $inFile\n";
    while(<IN>){ if( !/^\s*$/ && !/^\s*\#/ && /^\s*(\S+)/){
        push @$itemList, $1;
    }}
    close IN;

    # test # print join("\n",@$itemList)."\n";
}

# -----------------------------------------------

sub read_key2value_fromSelectedColumns
{
    my ($inFile,$key2value,$colOfKey,$colOfValue) = @_;

    # --- initialize and clear output data ---
    %$key2value = ();
    
    # --- open infile, read data lines, skip blank and comment lines ---
    # if necessary, unzip input file before opening it
    my $in;
    if(    $inFile =~ /\.(zip|Z|gz)$/){ $in = "gzip -dc ".$inFile." | "; }
    elsif( $inFile =~ /\.7z$/        ){ $in = "7z e ".$inFile." -so | "; }
    else{                               $in = $inFile;                   }
    # data line contains whitespace-separated items
    open IN, "$in" || die "Error: cannot open \"$in\"\n";
    while(<IN>){ if( !/^\s*$/ && !/^\s*\#/ ){
	my ($key,$value) = (split m/\s+/)[$colOfKey-1,$colOfValue-1];
	$$key2value{$key} = $value;
    }}
    close IN;
    
    # test # print join("\n",map{$_."\t".$$key2value{$_}}sort {$a<=>$b} keys%$key2value)."\n";exit(1);
}

# -----------------------------------------------

# if the selected node needs a basal enzyme, then add one to it
# actEnz: name of the activating basal enzyme
# deactEnz: name of the deactivating basal enzyme
sub addBasalEnzymeIfNeeded
{
    my ($node,$linkName2linkSign,$actEnz,$deactEnz) = @_;

    # save the signs of the incoming links of the given node
    my %inLinkSignList; for my $linkName (grep {$node eq substr($_,1,1)} keys %$linkName2linkSign){ ++$inLinkSignList{ $$linkName2linkSign{$linkName} }; }
    # if the incoming links of the node have exactly one sign, then and only then a basal enzyme is needed
    if( 1 == scalar keys %inLinkSignList ){
	# if the incoming links are positive, then add a negative (deactivating) basal enzyme
	if( defined $inLinkSignList{"+"} ){ $$linkName2linkSign{$deactEnz.$node} = "-"; }
	# else: the incoming link(s) are negative and thus, set an activating basal enzyme
	else{ $$linkName2linkSign{$actEnz.$node} = "+"; }
    }
}

# -----------------------------------------------

# for the given network topology ID list the sets of link weight parameters with which the simulation should be run
#
# *** parameters ***
# each link of the network is defined by
# - its two end points (source, target)
# - its sign (positive or negative)
# - and its two parameters:
#   . kcat: catalytic rate constant
#   . Km: substrate concentration at which the reaction rate is at half-maximum
#
# *** input node ***
# - each network has an incoming link, which points from the input to node A (the node with index 0)
# - the sign of the interaction pointing from the input to node A is positive
#
# *** basal enzymes ***
# For each node list its incoming links (includes self-link) and check below, (i) if it has a basal enzyme and (ii) what the sign the action of the basal enzyme is.
#
#    Incoming link(s) | Basal enzyme
#   ------------------+--------------
#    none             | none
#   ------------------+--------------
#    only +           | -
#   ------------------+--------------
#    only -           | +
#   ------------------+--------------
#    both + and -     | none

sub nwId2listOfLinkNameWeightSignSets
{
    my ($par,$nwId) = @_;

    # set the list of link names in the order as they appear in the adjacency matrix
    my @linkNameList = qw/ AA BA CA AB BB CB AC BC CC /;
    
    # ------------------ set links and their signs ----------------------
    # - save the sign of each link as its weight
    # - the adjacency matrix stores link signs: + (positive), - (negative) or . (none)
    # - for the non-zero cases save this link sign by the name of the given directed link
    my %linkName2linkSign;
    my $i=0;
    for my $sign (split m//, $ {$$par{"nwId2adjM"}}{$nwId}){
        # the name of the directed link at the current position in the adjacency matrix
	my $linkName = $linkNameList[$i];
	# if the sign of the link is + or -, then save the sign of the link by the name of the link
	if( $sign =~ /^\+|\-$/ ){ $linkName2linkSign{$linkName} = $sign; }
	# increment counter: move to the next link
	++$i;
    }
    # test: print link names and signs # {local$|=1;print $nwId."\n".("-"x30)."\n".join("\n", map{$_.": ".$linkName2linkSign{$_}} sort keys %linkName2linkSign)."\n";} #exit(0);
    #
    # add input link
    $linkName2linkSign{"IA"} = "+";
    #
    # loop through the list of nodes: the three nodes of the circuit
    # for each node: if necessary, add a basal enzyme link pointing to the node and with the correct (positive or negative) link sign
    for my $node (qw/A B C/){ &addBasalEnzymeIfNeeded($node,\%linkName2linkSign,"E","F"); }

    # ----------------- given the links and their signs save link weight sets ---------------------
    # the list of link weight sets in a hash
    my %lwsh;
    #
    # loop through the list of requested k (coupling constant) values
    for my $k (split m/\s+/,$$par{"kList"}){
	switch($$par{linkWeightSelMethod}){
	    # ------------------------------------------------------
	    # each subset of the links defines one link weight set: 
	    # - the links of the subset have the link weight k
	    # - all other links have weight 1
	    # ------------------------------------------------------
	    case "all" {
		# number the links of the network
		my @linkNum2linkName = sort keys %linkName2linkSign;
		# test # {local$|=1;print join(", ",@linkNum2linkName)."\n";}
		# loop through all possible subsets of the links
		for my $iLinkSet ( 0 .. (2**(scalar @linkNum2linkName)-1) ){
		    # the links of the selected link set will have the selected "k" weight and all other links will have the weight "1.0"
		    my %linkName2linkWeight;
		    for (my $iLink=0; $iLink <= $#linkNum2linkName; ++$iLink) {
			if( $iLinkSet & 2**$iLink ){
			    $linkName2linkWeight{ $linkNum2linkName[$iLink] } = $k; 
			}
			else{
			    $linkName2linkWeight{ $linkNum2linkName[$iLink] } = 1.0; 
			}
		    }
		    # save the current link weight set
		    ++$lwsh{ join(" | ", map{ $_." ".$linkName2linkSign{$_}." ".$linkName2linkWeight{$_} } sort keys %linkName2linkSign ) };
		}
	    }
	    # ------------------------------------------------------
	    # two link weight sets:
	    # (1) all links have weight 1
	    # (2) incoming regulatory (not basal enzyme) links of the output node have weight k, all others have 1
	    # ------------------------------------------------------
	    case "outnode" {
		# (1) 
		my %linkName2linkWeight = map{ $_ => 1 } keys %linkName2linkSign;
		++$lwsh{ join(" | ", map{ $_." ".$linkName2linkSign{$_}." ".$linkName2linkWeight{$_} } sort keys %linkName2linkSign ) };
		# (2) 
		# note: - $nodeSrc and $nodeTarget are the source and target nodes of the given link, respectively
		#       - $_ holds the name of the directed link
		%linkName2linkWeight = map{ my ($nodeSrc,$nodeTarget) = split m//; $_ => ( $nodeSrc =~ /^[ABC]$/ && "C" eq $nodeTarget ) ? $k : 1  }
		                       keys %linkName2linkSign;
		++$lwsh{ join(" | ", map{ $_." ".$linkName2linkSign{$_}." ".$linkName2linkWeight{$_} } sort keys %linkName2linkSign ) };
	    }
	    # ------------------------------------------------------
	    # the input link and the basal enzyme links have all weights 1,
	    # each subset of the links between the 3 simulated nodes defines one link weight set: links within this link subset have weight k, others 1
	    # ------------------------------------------------------
	    case "inside_all" {
		# number the links of the network that are inside, i.e., both end points are on one of the three simulated nodes
		my @insideLinkNum2linkName = sort grep{ /^[ABC]{2}$/ } keys %linkName2linkSign;
		# test #
		# loop through all possible subsets of the links that are inside, i.e., among the three simulated nodes
		for my $iLinkSet ( 0 .. (2**(scalar @insideLinkNum2linkName)-1) ){
		    # the links of the selected link set will have the selected "k" weight and all other links will have the weight "1.0"
		    my %linkName2linkWeight;
		    for (my $iLink=0; $iLink <= $#insideLinkNum2linkName; ++$iLink) {
			if( $iLinkSet & 2**$iLink ){
			    $linkName2linkWeight{ $insideLinkNum2linkName[$iLink] } = $k; 
			}
			else{
			    $linkName2linkWeight{ $insideLinkNum2linkName[$iLink] } = 1.0; 
			}
		    }
		    # links that are outside the network (i.e., input and basal enzyme links) also have the weight 1.0
		    for my $linkName (grep{ !/^[ABC]{2}$/ } keys %linkName2linkSign){ $linkName2linkWeight{ $linkName } = 1.0; }
		    # save the current link weight set
		    ++$lwsh{ join(" | ", map{ $_." ".$linkName2linkSign{$_}." ".$linkName2linkWeight{$_} } sort keys %linkName2linkSign ) };
		}
	    }
	    default {
		die "\nError, no such link weight selection method: ".$$par{linkWeightSelMethod}.". Exiting.\n\n";
	    }
	}
    }
    # save all link weight sets
    my @lws = map{ [ split m/\s+\|\s+/ ] } keys %lwsh;
    # test # {local$|=1;print join("\n",map{join(" | ",@$_)}@lws)."\n-----------------\n";}

    # return the list of link weight sets
    return \@lws;
}

# -----------------------------------------------

sub readDataLinesFromFile
{
    my ($inFile) = @_;

    # a pointer (reference) to this list will be returned
    my @list;

    # open infile, read data lines, skip blank and comment lines
    # if necessary, unzip input file before opening it
    my $in;
    if(    $inFile =~ /\.(zip|Z|gz)$/){ $in = "gzip -dc ".$inFile." | "; }
    elsif( $inFile =~ /\.7z$/        ){ $in = "7z e ".$inFile." -so | "; }
    else{                               $in = $inFile;                   }
    # open input file, discard comment lines and empty lines
    open IN, "$in" || die "Error: cannot open \"$in\"\n";
    while(<IN>){ if( !/^\s*$/ && !/^\s*\#/ ){
	# remove newline character from the end of the line
	chomp;
	# save the data line
	push @list, $_;
    }}
    close IN;
    
    # return value
    return \@list;
}

# -----------------------------------------------

sub listParameters
{
    my ($par,$nwId) = @_;

    # start with the parameter file template
    my $t = $$par{"parTempl"};

    # get the number of links in this network and list the link name/sign/weight sets to be used with the current topology
    @{$$par{"listOf_linkNameWeightSignSets"}} = @{ &nwId2listOfLinkNameWeightSignSets( $par, $nwId ) };
    my $listOf_linkNameWeightSignSets = join( "\n", map{ join(" ",@$_) } @{$$par{"listOf_linkNameWeightSignSets"}} ); 
    $t =~ s/LIST_OF_LINK_NAME_WEIGHT_SIGN_SETS/$listOf_linkNameWeightSignSets/;
    
    # the number of link sets for the current network ID
    my $nLinkSets = scalar @{$$par{"listOf_linkNameWeightSignSets"}};
    
    # the number of links in the current network: the number of upper-case-two-letter substrings in the first link name/weight/sign set
    my @linkListFirst = grep{ /([A-Z]{2})/g } @ { $ {$$par{"listOf_linkNameWeightSignSets"}}[0] };
    my $nLinks = scalar @linkListFirst;
    # test # {local$|=1;print "linkListFirst: ".join(" *** ",@linkListFirst)."\nnLinks: ".$nLinks."\n";}exit(0);

    # number of starting states
    my @startStateList = split m/\s+/, $$par{"startStateList"};
    $$par{nStartStates} = scalar @startStateList;

    # formatted list of starting states
    my $startStateList_formatted = join( "\n", map{ join(" ",split m/_/) } @startStateList );
    
    # insert parameters
    # we are assuming that in the parameter file each of these patterns is at the beginning of a non-comment line and that none of these lines is the first line of the file
    $t =~ s/(\n\s*)NUMBER_OF_LINKS/$1$nLinks/;
    $t =~ s/(\n\s*)NUMBER_OF_LINK_SETS/$1$nLinkSets/;
    $t =~ s/(\n\s*)MAX_SIM_TIME/$1$$par{maxSimTime}/;
    $t =~ s/(\n\s*)SIM_START_RELAX_TIME/$1$$par{simStartRelaxTime}/;
    $t =~ s/(\n\s*)MAX_NUM_WALL_CLOCK_SECONDS/$1$$par{node_maxWallClockTime}/;
    $t =~ s/(\n\s*)SIMULATION_TIME_STEP_CONSTANT/$1$$par{simTimeStepConstant}/;
    $t =~ s/(\n\s*)STORE_DATA_CHANGE_THRESHOLD/$1$$par{storeDataChangeThresh}/;
    $t =~ s/(\n\s*)NUMBER_OF_INPUT_SIGNALS/$1$$par{nSignal}/;
    $t =~ s/(\n\s*)LIST_OF_INPUT_SIGNALS/$1$$par{inputSignalList_str}/;
    $t =~ s/(\n\s*)CONST_VALUE_OF_ALL_BASAL_ENZYMES/$1$$par{constValBasEnz}/;
    $t =~ s/(\n\s*)NUMBER_OF_STARTING_STATES/$1$$par{nStartStates}/;
    $t =~ s/(\n\s*)LIST_OF_SIMULATION_START_VALUE_SETS/$1$startStateList_formatted/;
    $t =~ s/(\n\s*)MAX_DYN_MEM_MB/$1$$par{jobMaxDynMemMB}/;
    
    # save the contents of the parameter file
    $$par{"parFileContents"} = $t;
}

# -----------------------------------------------

sub writeParameterFile_saveParFileName
{
    my ($par,$dir,$nwId,$runId,$parFileName) = @_;

    # full path of the parameter file
    $$parFileName = $dir."/".$nwId."--par--".$runId.".txt";

    # print the parameter file
    open OUT, ">".$$parFileName; print OUT $$par{"parFileContents"}; close OUT;
}
    
# -----------------------------------------------

# knowing the name of a status file return the name of the next status file
sub nextStatusFileName
{
    my ($nameOfStatusFile) = @_;

    # the full path of the name of the file 
    my @path = split m/\//, $nameOfStatusFile;

    # increment the run ID in the name of the status file
    if( $path[-1] =~ /^(.+?)(\d+)(\.txt)$/ ){ $path[-1] = $1.(1+$2).$3; }
    else{ die "Error, wrong name of status file: ".$path[-1]."\n"; }

    # return the name of the next status file
    return join("/",@path);
}

# -----------------------------------------------

sub setStatusToSubm_saveStatusFileNames
{
    my ($par,$dir,$nwId,$runId,$statusFileName_current,$statusFileName_next) = @_;

    # ---------- set the status of the current network: it is now submitted to the cluster's queue manager ---------
    # --- set its value in the data structures of this running program (status->isSubm) ---
    my $status = $ {$$par{"nwId2status"}}{$nwId};
    $$status{"isSubm"} = 1;

    # --- set its value in the last status data file ---
    # set the contents of the status file
    my $t = $$par{"statTempl"};
    $t =~ s/N_TOTAL/$$status{nJobTotal}/;
    $t =~ s/N_FIN/$$status{nJobFin}/;
    $t =~ s/IS_SUBM/$$status{isSubm}/;
    # write the status into the last status file
    open OUT, ">".$$status{"nameOfLastStatusFile"}; print OUT $t; close OUT;

    # save the name of the current status file
    $$statusFileName_current = $$status{"nameOfLastStatusFile"};
    $$statusFileName_next = &nextStatusFileName( $$status{"nameOfLastStatusFile"} );
}

# -----------------------------------------------

sub writePerlSgeCmdFile_submitToQueue
{
    my ($par,$newJobList) = @_;

    # -------- file names and perl code ----------
    my $currentTime = time; # current time (number of seconds since the epoch)
    my @fileList = glob($$par{absPath_head_rootDir}."/sge/".$$par{jobNamePrefix}."--sge--".$currentTime."--*.pl");
    my $currentNum = 0; if( 0 < scalar @fileList ){ $currentNum = 1 + ( map{ $$_[1] } sort{ $$a[0] <=> $$b[0] }  map{ /(\d+)\.pl$/; [ $1, $_ ] } @fileList ) [-1]; }
    my $exeTxt; # the perl code to decide the name of the executable
    my $localDirNameTemplate; # name template of the local directory
    switch($$par{"clusterName"}){
        case "qb3" {
	    $exeTxt .=
		"# Which architecture are we using ?\n".
		"my \$arch = `uname -i`; chomp \$arch;\n".
		"# set name of the exe file accordingly\n".
		"my \$exe = \"/netapp/home/fij/".$$par{"relDir_node_exe"}."/".$$par{"nameStart_exe"}."--\".\$arch;\n";
	    $localDirNameTemplate =
		"/scratch/".$currentTime."--".$currentNum."--COUNTER";
        }
        # default: all other cases
        default { die "Sorry, in \"runExe\" this cluster is not (yet) implemented: '".$$par{clusterName}."'\n"; }
    }
    #
    # temporary output status file, temporary output data file
    my $tmpStat = $localDirNameTemplate."/status-after.txt";
    my $tmpOutDat = $localDirNameTemplate."/dat.fa.7z";
    my $jobCounter;

    # ----------- print the command file and run it -------------
    switch($$par{"clusterName"}){
        case "qb3" {

	    # ------- set name of the SGE command file ----------
	    #
	    # IF no SGE command file exists with the current time stamp,
	    # THEN use the current time and the number zero,
	    # ELSE use the current time and a number that is one larger than the last (=largest) number of the SGE command files with the current time
	    my $sgeCmdFile = $$par{absPath_head_rootDir}."/sge/".$$par{jobNamePrefix}."--sge--".$currentTime."--".$currentNum.".pl";

	    # --------- open file, print file header, print the list of jobs ------------
	    open OUT, ">".$sgeCmdFile or die "Error, cannot write to \'$sgeCmdFile\'\n";
	    print OUT 
		"#!/usr/bin/perl\n".
		"use strict; use warnings;\n".
		"\n".
		"#\$ -S /usr/bin/perl\n".
		"#\$ -o ".$$par{absPath_head_rootDir}."/sge/.o--".$$par{jobNamePrefix}."--sge--".$currentTime."--".$currentNum.".txt\n".
		"#\$ -e ".$$par{absPath_head_rootDir}."/sge/.e--".$$par{jobNamePrefix}."--sge--".$currentTime."--".$currentNum.".txt\n".
		"#\$ -l mem_free=".$$par{sgeMemFree}."\n".
		"#\$ -l scratch=".$$par{sgeScratch}."\n".
		"#\$ -l netapp=".$$par{sgeNetapp}."\n".
		"#\$ -cwd\n".
		"#\$ -l arch=lx24-amd64\n".
		"#\$ -t 1-".(scalar @$newJobList)."\n".
		"\n".
		
		"# Set the absolute (full) path of the executable program\n".
		$exeTxt.
		"\n".
		
		"# Set the list of jobs\n".
		"# Each job contains the following steps:\n".
		"# (0) print current date and the name of node where this script is running\n".
		"# (1) a temporary local directory is made, this directory will be the temporary location of the output status file and the output data file\n".
		"# (2) the simulation program is started, it will write a final status file and will write its output data to its stdout\n".
		"# (3) the discretizer reads the simulation results from the stdout of the simulation program and writes the discretized results to its own stdout\n".
		"# (4) the fasta writer program reads the discretized results and writes the data in fasta sequence format (through a 7z pipe)\n".
		"# (5a) move the status file written by the simulation program to the work directory with its final name\n".
		"# (5b) move the fasta formatted output file from the temporary directory to the work directory with its final name\n".
		"# (6) the local directory is removed\n".
		"my \@jobList=(\n\n".
		join(",\n\n",
		     map{
			 ## final name of the status file
			 #my $statusFileName_next = (split m/\//, $$_{statusFileName_next})[-1];

			 # the text of the job command
			 my $job_text = 

			     "# (0)\n".
			     "\"date; hostname; \".\n".
			     "# (1)\n".
			     "\"rm -rf ".$localDirNameTemplate."; mkdir ".$localDirNameTemplate."; \".\n".
			     "# (2)\n".
			     "\$exe.\" ".$$_{parFileName}." ".$$_{statusFileName_current}." ".$tmpStat." | \".\n".
			     "# (3)\n".		
			     "\"".$$par{"absPath_discretizer"}." ".$$_{nwId}." ".$$par{"simStartRelaxTime"}." ".$$par{"maxSimTime"}." ".$$par{"respDiscr_tN"}." 0 1 ".$$par{"respDiscr_zN"}." | \".\n".
			     "# (4)\n".
			     "\"".$$par{"absPath_fastaWriter"}." | 7z a -si ".$tmpOutDat."; \".\n".
			     "# (5a)\n".
			     "\"mv ".$tmpOutDat." ".$$par{absPath_head_rootDir}."/todo/".$$_{nwId}."/".$$_{nwId}."--response--sequences--".$$_{runId}.".fa.7z; \".\n".
			     "# (5b)\n".
			     "\"mv ".$tmpStat." ".$$par{absPath_head_rootDir}."/todo/".$$_{nwId}."/".((split m/\//, $$_{statusFileName_next})[-1])."; \".\n".
			     "# (6)\n".
			     "\"rm -rf ".$localDirNameTemplate.";\"";
			 
			 # set counter
			 ++$jobCounter;
			 $job_text =~ s/COUNTER/$jobCounter/g;
			 
			 # the return value is the text
			 $job_text;
		    }
		@$newJobList).
		"\n\n);\n".
		"\n".

		"# Execute array of jobs and log that they have been started\n".
		"system(\$jobList[\$ENV{SGE_TASK_ID}-1]);\n".
		"print \$jobList[\$ENV{SGE_TASK_ID}-1].\"\\n\";\n".
		"\n".
		
		"# Log maximum virtual memory used and log this shell command\n".
		"system(\"qstat -j \".\$ENV{JOB_ID}.\" | grep maxvmem | grep \".\$ENV{SGE_TASK_ID});\n".
		"print \"qstat -j \".\$ENV{JOB_ID}.\" | grep maxvmem | grep \".\$ENV{SGE_TASK_ID}.\"\\n\";\n".
		"\n";
	    
	    close OUT;

	    # make the SGE command file executable and readable for all
	    system("chmod a+xr ".$sgeCmdFile);

	    # send the SGE command file to the queue of the QB3 cluster
	    my $shCmd = "qsub".($$par{"qb3_useLongQ"} ? " -q long.q" : "")." ".$sgeCmdFile; # shell command sending the job the queue
	    system($shCmd); # execute this shell command
	    {local$|=1;print $shCmd."\n";} # log this shell command
	    # test # exit(1);

        }
        # default: all other cases
        default { die "Sorry, in \"runExe\" this cluster is not (yet) implemented: '".$$par{clusterName}."'\n"; }
    }

    # test # exit(1);
}

# -----------------------------------------------

sub forTheSelectedNw_getCurrentStatusData
{
    my ($par,$dir,$nwId) = @_;
    
    # default: no information about the status exists
    my $status = $ {$$par{"nwId2status"}}{$nwId};
    for(qw/indexOfLastStatusFile nameOfLastStatusFile isSubm nJobTotal nJobFin/){ delete $$status{$_} }

    # list status files available in the current directory
    # the name of a status file is: <nwId>--status--<runId>.txt
    # <nwId> is the ID of the network, <runId> is the number of times that the job with this network ID has been run so far
    # one status file (with <runId>=0) is produced before first running this job, and one after each run stops
    my @statusFileList = (); if( -d $dir ){ @statusFileList = grep{!/^\s*$/} glob( $dir."/".$nwId."--status--*.txt" ); }

    # IF there is no status file in the current directory, THEN exit with an error message
    if( 0 == scalar @statusFileList ){ die "Error: no status file in dir=\'$dir\' with nwId=\'$nwId\' (get_indexAndName).\n"; }

    # save the index and the name of the last status file
    @$status{qw/indexOfLastStatusFile nameOfLastStatusFile/} = @{ ( sort{ $$a[0] <=> $$b[0] } map{ /\-(\d+)\.txt$/; [ $1, $_ ] } @statusFileList )[ -1 ] };

    # open the last status file and save all non-comment lines
    open IN, $$status{"nameOfLastStatusFile"};
    my $statusData = join( "", grep{!/^\s*\#/} (<IN>) );
    # save the three data items: total number of jobs, number of finished jobs, whether the network is currently submitted to the cluster's queue
    @$status{qw/nJobTotal nJobFin isSubm/} = ($statusData=~/(\S+)/g);
    # close the input
    close IN;

    # test # 
    #{local$|=1;print "glob:".$dir."/".$nwId."--status--*.txt"."\n".
    #                 "statusFileList:\n".join("\n",map{"statusFile: ".$_}@statusFileList)."\n".
    #                 "nwId:".$nwId.", ".join(", ",map{$_.":".$$status{$_}}qw/nJobTotal nJobFin isSubm indexOfLastStatusFile nameOfLastStatusFile/)."\n";}
}

# -----------------------------------------------

sub shortenSeq
{
    my ($seq) = @_;

    # try to shorten the sequence:
    # IF a character in the sequence is repeated at adjacent positions 2 or more times, THEN replace it with a number (the number of repeats) followed by the character
    while( $$seq =~ /(.)(\1{2,})/ ){
	my $char = $1;
	my $repeat = $1.$2;
	my $shortForm = (length $repeat).$char;
	$$seq =~ s/$repeat/$shortForm/;
    }
}

# -----------------------------------------------

sub newFinishedNetworks_moveToDone
{
    my ($par) = @_;

    # loop through the list of those networks that are in the "todo" directory and are already finished
    for my $dir ( grep{ # full path of the current directory below the "todo" subdirectory
	                my $dir = $_;  
                        # the ID of the current network
	                my $nwId = &lastItemInDirPath($dir);
			# the status data structure of the current network
	                my $status = $ {$$par{"nwId2status"}}{ $nwId };

		        # return value: the simulations with this network are finished if
		        # (1) the network has more than 0 finished jobs
		        # AND (2) the network's number of finished jobs is equal to its total number of jobs
		        $$status{"nJobFin"} > 0 && $$status{"nJobFin"} eq $$status{"nJobTotal"};

		        # --- note ---
		        # . the total number of jobs is not defined for networks that have not yet been simulated, this is why we need the first condition
		        # . for not yet simulated networks the 1st part will be false and cause the interpreter not to evaluate the 2nd (undefined) part after the "AND"
	          }
                  glob($$par{"absPath_head_rootDir"}."/todo/*") )
    {
        # move the current network to the "done" subdirectory
	system("mv ".$dir." ".$$par{"absPath_head_rootDir"}."/done/");
    }
}

# -----------------------------------------------

sub lastItemInDirPath
{
    my ($dir) = @_;

    return (grep{!/^\s*$/} split m/\//,$dir)[-1];
}

# -----------------------------------------------

sub updateOrInit_statusOfEachNetwork_restartOfMainControllerAllowed_otherJobDirsAlsoChecked
{
    my ($par,$isInit) = @_;

    # initialize the status of each network: by default no job has been run so far for any of the networks, i.e., in each network has "0" finished jobs and is not submitted (isSubm=0)
    if( $isInit ){
	# networks in the current project
	%{$$par{"nwId2status"}} = map{ $_ => {"isSubm"=>0, "nJobFin"=>0} } keys %{$$par{"nwId2adjM"}};
	# networks in all other projects
	for my $otherProjDir (@{$$par{otherProjDirList}}){
	    %{ $ { $$par{"otherProj2nwId2status"} }{ $otherProjDir } } = map{ $_ => {"isSubm"=>0, "nJobFin"=>0} } keys %{$$par{"nwId2adjM"}};
	}
    }

    # During the simulations only the states of "todo" jobs can change, thus
    # IF we are initializing, THEN check the "todo" and the "done" directories
    # IF we are updating, THEN check only the "todo" directories
    my @sectionList = ("todo"); if( $isInit ){ push @sectionList, "done"; }

    # loop through the list of directories in which the status of a job can have changed
    for my $dir ( map{ glob($$par{"absPath_head_rootDir"}."/".$_."/*") } @sectionList ){
	# the ID of the network in the current directory is the last item in the full path of the directory
	my $nwId = &lastItemInDirPath( $dir );
	# get the status of this network
	&forTheSelectedNw_getCurrentStatusData( $par, $dir, $nwId );
	#
	# test # {local$|=1;my$status= $ {$$par{"nwId2status"}}{$nwId};print"x1 nwId=".$nwId.", dir=".$dir.", ".join(", ",map{$_."= ".$$status{$_}}qw/nameOfLastStatusFile indexOfLastStatusFile nJobTotal nJobFin isSubm/)."\n";}
    } 
    # test # {local$|=1;print join("\n",map{"listing: ".$_}glob($$par{"absPath_head_rootDir"}."/todo/*"))."\n";}
    
    # update the status of each other job ran also by me in other directories
    for my $otherProjDir (@{$$par{otherProjDirList}}){
	# for this other project loop through the list of directories in which the status of a job can have changed
	for my $dir ( map{ glob($otherProjDir."/".$_."/*") } @sectionList ){
	    #
	    # the ID of the network in the current directory is the last item in the full path of the directory
	    my $nwId = &lastItemInDirPath( $dir );
	    #
	    # default: no information available about the status of the current job from the other project's directory
	    my $status = $ { $ { $$par{"otherProj2nwId2status"} }{ $otherProjDir } }{ $nwId };
            for(qw/indexOfLastStatusFile nameOfLastStatusFile isSubm nJobTotal nJobFin/){ delete $$status{$_} }
            #
	    # save the status of the current job from the other project's directory
            # list status files available in the current directory
            # the name of a status file is: <nwId>--status--<runId>.txt
            # <nwId> is the ID of the network, <runId> is the number of times that the job with this network ID has been run so far
            # one status file (with <runId>=0) is produced before first running this job, and one after each run stops
            my @statusFileList = (); if( -d $dir ){ @statusFileList = grep{!/^\s*$/} glob( $dir."/".$nwId."--status--*.txt" ); }

            # IF there is no status file in the current directory, THEN send *warning* message AND set the status to isSubm=0, i.e., this network is not in the cluster's queue any more
            if( 0 == scalar @statusFileList ){
		print STDERR "Warning: no status file in dir=\'$dir\' with nwId=\'$nwId\' (get_indexAndName).\nSetting isSubm=0 for this network.\n";
		$$status{"isSubm"} = 0;
	    }
            # IF there is at least one status file in the current directory, THEN read the status from the latest status file, i.e., the status file with the highest run Id
            else{
		# save the index and the name of the last status file
		@$status{qw/indexOfLastStatusFile nameOfLastStatusFile/} = @{ ( sort{ $$a[0] <=> $$b[0] } map{ /\-(\d+)\.txt$/; [ $1, $_ ] } @statusFileList )[ -1 ] };

		# open the last status file and save all non-comment lines
		open IN, $$status{"nameOfLastStatusFile"};
		my $statusData = join( "", grep{!/^\s*\#/} (<IN>) );
		# save the three data items: total number of jobs, number of finished jobs, whether the network is currently submitted to the cluster's queue
		@$status{qw/nJobTotal nJobFin isSubm/} = ($statusData=~/(\S+)/g);
	    }
	}
    }
}

# -----------------------------------------------

sub ifNetworkNotYetRun_thenMakeDir_setTotalJobNum_setLastStatusFileNameAndIndex_writeStatusFile
{
    my ($par,$dir,$nwId) = @_;

    # IF the directory of the network does not yet exist, THEN make the directory, write the initial (last) status file, set the index and name of the last status file
    if( ! ( -d $dir ) )
    {    
	# make directory
	mkdir $dir;
	
	# the status data structure of the current network
	my $status = $ {$$par{"nwId2status"}}{$nwId};

        # the number of link sets for the current network ID
        my $nLinkSets = scalar @{$$par{"listOf_linkNameWeightSignSets"}};

        # set the total number of jobs
        $$status{"nJobTotal"} = $nLinkSets * $$par{"nStartStates"} * $$par{"nSignal"};

	# set the index and name of the last status file
        my $lastIndex = 0;
	$ { $ {$$par{"nwId2status"}}{$nwId} }{ "indexOfLastStatusFile" } = $lastIndex;
        $ { $ {$$par{"nwId2status"}}{$nwId} }{ "nameOfLastStatusFile"  } = $dir."/".$nwId."--status--".$lastIndex.".txt";

	# set the contents of the status file: start with the template and replace items
	my $t = $$par{"statTempl"};
	$t =~ s/N_TOTAL/$$status{nJobTotal}/;
	$t =~ s/N_FIN/0/;
	$t =~ s/IS_SUBM/0/;
	
	# write the status file
	open OUT, ">".$ { $ {$$par{"nwId2status"}}{$nwId} }{ "nameOfLastStatusFile" }; print OUT $t; close OUT;
    }   
}

# -----------------------------------------------

sub nJobSubmitted
{
    my ($par) = @_;

    # the number of jobs in the current project submitted the cluster's queue
    my $nSubm = scalar grep{ $$_{"isSubm"} } map{ $ {$$par{"nwId2status"}}{$_} } keys %{$$par{"nwId2status"}};
    # test # {local$|=1;print "nSubm local = ".$nSubm."\n";}

    # IF there are other projects, THEN check how many of their jobs are currently submitted to the cluster's queue
    for my $otherProjDir (sort keys %{$$par{"otherProj2nwId2status"}}){
        my $nSubmOtherProj = scalar grep{ $$_{"isSubm"} } map{ $ { $ {$$par{"otherProj2nwId2status"}}{$otherProjDir} }{$_} } keys % { $ {$$par{"otherProj2nwId2status"}}{$otherProjDir}};
        $nSubm += $nSubmOtherProj;
# test # {local$|=1;print "nSubm in ".$otherProjDir." = ".$nSubmOtherProj."\n";}
    }

    # return value: total number of jobs submitted to the cluster's queue
    return $nSubm;
}

# -----------------------------------------------

sub listNwIds_inRequestedOrder
{
    my ($par) = @_;

    # which ordering is requested
    switch($$par{nwIds_inWhichOrder}){
	# numerically ascending order of network IDs
	case 0 {
	    return [ sort {$a<=>$b} keys %{$$par{"nwId2status"}} ];
	}
	# numerically descending order of network IDs
	case 1 {
	    return [ sort {$b<=>$a} keys %{$$par{"nwId2status"}} ];
	}
	# by the numerically descending order of the networks' link numbers
	case 2 {
	    # the number of links in each network is the number of characters in its adjacency matrix that are either + or -
	    my %nwId2nLink = map{ my @list = ($ {$$par{"nwId2adjM"}}{$_} =~ /(\+|\-)/g); $_ => scalar @list } keys %{$$par{"nwId2adjM"}};
	
            # the number of positive links in each network
	    my %nwId2nPlusLink = map{ my @list = ($ {$$par{"nwId2adjM"}}{$_} =~ /(\+)/g); $_ => scalar @list } keys %{$$par{"nwId2adjM"}};

	    # those networks are listed first that have
            # (a) the largest link number
            # (b) with identical link number the largest number of positive links
            # (c) with identical (a) and (b) the lowest network ID (i.e., links are more concentrated in the link positions with the lower indices)
	    return [ sort { $nwId2nLink{$b} <=> $nwId2nLink{$a} || $nwId2nPlusLink{$b} <=> $nwId2nPlusLink{$a} || $a <=> $b } keys %{$$par{"nwId2status"}} ];
	}
        # use 2, but run the network with the ID <nwId> first
        case /^2_x\d+$/ {
	    # the selected network ID
	    $$par{nwIds_inWhichOrder} =~ /^2_x(\d+)$/;
	    my $selNwId = $1;

	    # the number of links in each network is the number of characters in its adjacency matrix that are either + or -
	    my %nwId2nLink = map{ my @list = ($ {$$par{"nwId2adjM"}}{$_} =~ /(\+|\-)/g); $_ => scalar @list } keys %{$$par{"nwId2adjM"}};
	
            # the number of positive links in each network
	    my %nwId2nPlusLink = map{ my @list = ($ {$$par{"nwId2adjM"}}{$_} =~ /(\+)/g); $_ => scalar @list } keys %{$$par{"nwId2adjM"}};

            # test # print join("\n", sort { ($b eq $selNwId) <=> ($a eq $selNwId) || $nwId2nLink{$b} <=> $nwId2nLink{$a} || $nwId2nPlusLink{$b} <=> $nwId2nPlusLink{$a} || $a <=> $b } keys %{$$par{"nwId2status"}})."\n";exit(0);

	    # how to decide priority for listing a network ID in the front of the list:
            # (a) has the selected ID
            # (b) has a larger link number
            # (c) when link numbers are identical: has a larger number of positive links
            # (d) with identical (a) and (b): has a lower network ID (i.e., links are more concentrated in the link positions with the lower indices)
	    return [ sort {    ($b eq $selNwId) <=> ($a eq $selNwId) 
			    || $nwId2nLink{$b} <=> $nwId2nLink{$a} || $nwId2nPlusLink{$b} <=> $nwId2nPlusLink{$a} || $a <=> $b } keys %{$$par{"nwId2status"}} ];
	}
	# the reply in all other cases
	default { die "Sorry, cluster not (yet) implemented: '".$$par{clusterName}."'\n"; }
    }
}

# -----------------------------------------------

sub runJobs
{
    my ($par) = @_;
    
    # initialize the status of all networks, including networks in other projects
    &updateOrInit_statusOfEachNetwork_restartOfMainControllerAllowed_otherJobDirsAlsoChecked( $par, 1 );
    
    # list network IDs in the requested order
    @{$$par{nwIdList_ordered}} = @{listNwIds_inRequestedOrder($par)};
    
    # do this loop as long as there is at least one network that is not finished
    # a network is finished, if its number of finished jobs is > 0 and its number of finished jobs is equal to the total number of jobs
    #
    # (1) for a network that has not yet been simulated, nJobTotal is not defined, but nJobFin = 0, thus, only the part before the "or" is evaluated
    # (2) for a network that has been simulated already, nJobTotal is defined
    while( scalar grep { 0 == $$_{"nJobFin"} or $$_{"nJobTotal"} > $$_{"nJobFin"} } values %{$$par{"nwId2status"}} ){

	# --------- update the status of each network, move newly finished networks to the "done" subdirectory ------------
	# --------- wait until the cluster's queue can accept new items ------
        my $nSubm;
        do{
	    &updateOrInit_statusOfEachNetwork_restartOfMainControllerAllowed_otherJobDirsAlsoChecked( $par, 0 );
            &newFinishedNetworks_moveToDone( $par );

	    # get the number of networks that are currently submitted to the cluster's queue (by the main controller)
	    # and wait if there are currently too many
	    #
	    # when counting the number of submitted jobs, include also the number of jobs ran by the same user in other projects
	    $nSubm = &nJobSubmitted( $par );
	    if( $nSubm >= $$par{"maxNumRunning"} ){ sleep $$par{"queueSubmitWaitSec"} }
        }while( $nSubm >= $$par{"maxNumRunning"} );

	# ------- submit new jobs to the cluster's queue ---------
        # if fewer networks are in the queue than the maximum allowed number, then fill up the number of submitted items by sending further ones to the cluster's queue
        if( $nSubm < $$par{"maxNumRunning"} ){

	    # list all networks that can be submitted to the queue now
	    my @newNwList = grep { # the status data structure of the current network (the network ID is in $_)
		                 my $status = $ {$$par{"nwId2status"}}{$_}; 
	                         # select this network if 
	                         # (1) it is not currently submitted to the queue for simulation
	                         # AND (2) its number of finished jobs is zero
	                         #     (2b) OR its number of finished jobs is smaller than its total number of jobs
	                         ! $$status{"isSubm"} && 
				 ( 0 == $$status{"nJobFin"} || $$status{"nJobFin"} < $$status{"nJobTotal"} )
			       }
                          # the list of all network IDs in the requested order
	                  @{$$par{nwIdList_ordered}};

            # how many new networks will be sent to the cluster's queue
	    my $nNew = $$par{"maxNumRunning"} - $nSubm;
	    #
	    # there is a maximum on the number of jobs that can be submitted in one batch
	    if( $nNew > $$par{maxJobNumSubmit} ){ $nNew = $$par{maxJobNumSubmit}; }
	    #
	    # select at most this number of networks from the list of those networks that are not finished and not running
	    # and submit the simulations of these networks to the cluster's queue
            if( scalar @newNwList > $nNew ){ @newNwList = @newNwList[0..($nNew-1)]; }
            #
            # write all data necessary for submitting these new jobs to the cluster's queue
	    my @newJobList;
	    for my $nwId (@newNwList){
		#
		# list the parameters for the current network
		&listParameters( $par, $nwId );
		#
		# IF this is going to be first simulation run for the current network (i.e., its directory does not yet exist), THEN make its directory and set its status
		my $dir = $$par{"absPath_head_rootDir"}."/todo/".$nwId; 
		&ifNetworkNotYetRun_thenMakeDir_setTotalJobNum_setLastStatusFileNameAndIndex_writeStatusFile( $par, $dir, $nwId );
		#
		# the ID of the current simulation run is 1 larger than the index of the last status file
		my $runId = 1 + $ { $ {$$par{"nwId2status"}}{$nwId} }{"indexOfLastStatusFile"};
		#
		# write parameter file for the executable program
		my $parFileName;
		&writeParameterFile_saveParFileName( $par, $dir, $nwId, $runId, \$parFileName );
		# 
		# set the status of the job: submitted to the cluster's queue
		my ($statusFileName_current,$statusFileName_next);
		&setStatusToSubm_saveStatusFileNames( $par, $dir, $nwId, $runId, \$statusFileName_current, \$statusFileName_next );
		#
		# save the full path name of the parameter file, the current status file and the new status file
		push @newJobList, {"parFileName" => $parFileName, "statusFileName_current" => $statusFileName_current, "statusFileName_next" => $statusFileName_next, "nwId" => $nwId, "runId" => $runId };
	    }

            # write the command file that will be used by the job manager on the node to run the executable
            &writePerlSgeCmdFile_submitToQueue( $par, \@newJobList );

            # wait for some time before sending the next set of networks to the queue
	    sleep $$par{"queueSubmitWaitSec"};
	}
    }
}

# ================ main ====================

# initialize
&init( \%PAR );

# read list of topologies for which the simulations should be run, read data as a mapping: network ID --> compact adjacency matrix 
&read_key2value_fromSelectedColumns( $PAR{"absPath_head_nwIdList"}, \%{$PAR{"nwId2adjM"}}, 1, 2 );

# read the list of running jobs from other directories in other projects
&read_itemList( $PAR{inFile_otherTodoDirs}, \@{$PAR{otherProjDirList}} );

# run simulation jobs
&runJobs( \%PAR );
