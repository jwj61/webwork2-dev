################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2003 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork-modperl/lib/WeBWorK/ContentGenerator/Instructor/PGProblemEditor.pm,v 1.47 2004/07/08 23:27:16 gage Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::ContentGenerator::Instructor::PGProblemEditor;
use base qw(WeBWorK::ContentGenerator::Instructor);


=head1 NAME

WeBWorK::ContentGenerator::Instructor::PGProblemEditor - Edit a pg file

=cut

use strict;
use warnings;
use CGI qw();
use WeBWorK::Utils qw(readFile surePathToFile);
use Apache::Constants qw(:common REDIRECT);
use HTML::Entities;
use WeBWorK::Utils::Tasks qw(fake_set fake_problem);

###########################################################
# This editor will edit problem files or set header files or files, such as course_info
# whose name is defined in the global.conf database
#
# Only files under the template directory ( or linked to this location) can be edited.
#
# The course information and problems are located in the course templates directory.
# Course information has the name  defined by courseFiles->{course_info}
# 
# Only files under the template directory ( or linked to this location) can be edited.
#
# editMode = temporaryFile    (view the temp file defined by course_info.txt.user_name.tmp
#                              instead of the file course_info.txt)
# The editFileSuffix is "user_name.tmp" by default.  It's definition should be moved to Instructor.pm #FIXME                              
###########################################################

#our $libraryName;
#our $rowheight;

sub pre_header_initialize {
	my ($self) = @_;
	my $r = $self->r;
	my $ce = $r->ce;
	my $urlpath = $r->urlpath;
	my $authz = $r->authz;
	my $user = $r->param('user');
	
	my $submit_button = $r->param('submit');  # obtain submit command from form
	my $file_type = $r->param("file_type") || '';

	# Check permissions
	return unless ($authz->hasPermissions($user, "access_instructor_tools"));
	return unless ($authz->hasPermissions($user, "modify_problem_sets"));

	# Save problem to permanent or temporary file, then redirect for viewing
	if (defined($submit_button) and 
	  ($submit_button eq 'Save' or $submit_button eq 'Refresh'
	  or ($submit_button eq 'Save as' and $file_type eq 'problem'))) {
		my $setName = $r->urlpath->arg("setID");
		my $problemNumber = $r->urlpath->arg("problemID");
		
		# write the necessary files
		# return file path for viewing problem in $self->{currentSourceFilePath}
		# obtain the appropriate seed
		$self->saveFileChanges($setName, $problemNumber);
		
		##### calculate redirect URL based on file type #####
		
		# get some information
		#my $hostname = $r->hostname();
		#my $port = $r->get_server_port();
		#my $uri = $r->uri;
		my $courseName  = $urlpath->arg("courseID");
		my $problemSeed = ($r->param('problemSeed')) ? $r->param('problemSeed') : '';
		my $displayMode = ($r->param('displayMode')) ? $r->param('displayMode') : '';
		
		my $viewURL = '';
		
		if($self->{file_type} eq 'problem') {
			if($submit_button eq 'Save as') { # redirect to myself
				my $sourceFile = $self->{problemPath};
				# strip off template directory prefix
				my $edit_level = $r->param("edit_level") || 0;
				$edit_level++;
				$sourceFile =~ s|^$ce->{courseDirs}->{templates}/||;
				my $problemPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::PGProblemEditor",
					courseID => $courseName, setID => 'Undefined_Set', problemID => $problemNumber);
				$viewURL = $self->systemLink($problemPage, params=>{sourceFilePath => $sourceFile, edit_level=>$edit_level});
			} else { # other problems redirect to Problem.pm
				my $problemPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Problem",
					courseID => $courseName, setID => $setName, problemID => $problemNumber);
				$self->{currentSourceFilePath} =~ s|^$ce->{courseDirs}->{templates}/||;
				$viewURL = $self->systemLink($problemPage,
					params => {
						displayMode     => $displayMode,
						problemSeed     => $problemSeed,
						editMode        => ($submit_button eq "Save" ? "savedFile" : "temporaryFile"),
						sourceFilePath  => $self->{currentSourceFilePath},
						success		=> $self->{sucess},
						failure		=> $self->{failure},
					}
				);
			} 
		}
		
		# set headers redirect to ProblemSet.pm
		$self->{file_type} eq 'set_header' and do {
			my $problemSetPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::ProblemSet",
				courseID => $courseName, setID => $setName);
			$viewURL = $self->systemLink($problemSetPage,
				params => {
					displayMode => $displayMode,
					problemSeed => $problemSeed,
					editMode => ($submit_button eq "Save" ? "savedFile" : "temporaryFile"),
				}
			);
		};
		
		# course info redirects to ProblemSets.pm
		$self->{file_type} eq 'course_info' and do {
			my $problemSetsPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::ProblemSets",
				courseID => $courseName);
			$viewURL = $self->systemLink($problemSetsPage,
				params => {
					editMode => ($submit_button eq "Save" ? "savedFile" : "temporaryFile"),
				}
			);
		};

		# don't redirect on bad save attempts
		# FIXME: even with an error we still open a new page because of the target specified in the form
		return if $self->{failure};
				
		if ($viewURL) {
			$self->reply_with_redirect($viewURL);
		} else {
			die "Invalid file_type ", $self->{file_type}, " specified by saveFileChanges";
		}
	}
}

sub initialize  {
	my ($self) = @_;
	my $r = $self->r;
	my $authz = $r->authz;
	my $user = $r->param('user');
	
	my $setName = $r->urlpath->arg("setID");
	my $problemNumber = $r->urlpath->arg("problemID");

	# Check permissions
	return unless ($authz->hasPermissions($user, "access_instructor_tools"));
	return unless ($authz->hasPermissions($user, "modify_problem_sets"));

	# if we got to initialize(), then saveFileChanges was not called in pre_header_initialize().
	# therefore we call it here unless there has been an error already:
	$self->saveFileChanges($setName, $problemNumber) unless $self->{failure};
	# this seems like a good place to deal with the add to set
	my $submit_button = $r->param('submit') || '';
	if($submit_button eq 'Add this problem to: ') {
		my $ce = $r->ce;
		my $sourcePath = $self->{problemPath};
		$sourcePath =~ s|^$ce->{courseDirs}->{templates}/||;
		$self->addProblemToSet(setName => $r->param('target_set'),
		                       sourceFile => $sourcePath);
		$self->addgoodmessage("Added $sourcePath to ". $r->param('target_set') );
	}
}

sub path {
	my ($self, $args) = @_;
	my $r = $self->r;
	my $urlpath = $r->urlpath;
	my $courseName  = $urlpath->arg("courseID");
	my $setName = $r->urlpath->arg("setID") || '';
	my $problemNumber = $r->urlpath->arg("problemID") || '';

	# we need to build a path to the problem being edited by hand, since it is not the same as the urlpath
	# For this page the bread crum path leads back to the problem being edited, not to the Instructor tool.
	my @path = ( 'WeBWork', $r->location,
	          "$courseName", $r->location."/$courseName",
	          "$setName",    $r->location."/$courseName/$setName",
	          "$problemNumber", $r->location."/$courseName/$setName/$problemNumber",
	          "Editor", ""
	);
# 	do {
# 		unshift @path, $urlpath->name, $r->location . $urlpath->path;
# 	} while ($urlpath = $urlpath->parent);
# 	
# 	$path[$#path] = ""; # we don't want the last path element to be a link
	
	#print "\n<!-- BEGIN " . __PACKAGE__ . "::path -->\n";
	print $self->pathMacro($args, @path);
	#print "<!-- END " . __PACKAGE__ . "::path -->\n";
	
	return "";
}
sub title {
	my $self = shift;
	my $r = $self->r;
	my $problemNumber = $r->urlpath->arg("problemID");
	my $file_type = $self->{'file_type'} || '';
	return "Set Header" if ($file_type eq 'set_header');
	return "Hardcopy Header" if ($file_type eq 'hardcopy_header');
	return "Course Information" if($file_type eq 'course_info');
	return 'Problem ' . $r->{urlpath}->name;
}

sub body {
	my ($self) = @_;
	my $r = $self->r;
	my $db = $r->db;
	my $ce = $r->ce;
	my $authz = $r->authz;
	my $user = $r->param('user');
	my $make_local_copy = $r->param('make_local_copy');

	# Check permissions
	return CGI::div({class=>"ResultsWithError"}, "You are not authorized to access the Instructor tools.")
		unless $authz->hasPermissions($r->param("user"), "access_instructor_tools");
	
	return CGI::div({class=>"ResultsWithError"}, "You are not authorized to modify problems.")
		unless $authz->hasPermissions($r->param("user"), "modify_student_data");

	
	# Gathering info
	my $editFilePath = $self->{problemPath}; # path to the permanent file to be edited
	my $inputFilePath = $self->{inputFilePath}; # path to the file currently being worked with (might be a .tmp file)
	
	my $header = CGI::i("Editing problem:  $inputFilePath");
	
	#########################################################################
	# Find the text for the problem, either in the tmp file, if it exists
	# or in the original file in the template directory
	#########################################################################
	
	my $problemContents = ${$self->{r_problemContents}};
	
	#########################################################################
	# Format the page
	#########################################################################
	
	# Define parameters for textarea
	# FIXME 
	# Should the seed be set from some particular user instance??
	my $rows = 20;
	my $columns = 80;
	my $mode_list = $ce->{pg}->{displayModes};
	my $displayMode = $self->{displayMode};
	my $problemSeed = $self->{problemSeed};	
	my $uri = $r->uri;
	my $edit_level = $r->param('edit_level') || 0;
	
	my $force_field = defined($r->param('sourceFilePath')) ?
		CGI::hidden(-name=>'sourceFilePath',
		            -default=>$r->param('sourceFilePath')) : '';

	my @allSetNames = sort $db->listGlobalSets;
	for (my $j=0; $j<scalar(@allSetNames); $j++) {
		$allSetNames[$j] =~ s|^set||;
		$allSetNames[$j] =~ s|\.def||;
	}
	# next, the content of our "add to stuff", which only appears if we are a problem
	my $add_to_stuff = '';
	if($self->{file_type} eq 'problem') {
		# second form which does not open a new window
		$add_to_stuff = CGI::start_form(-method=>"POST", -action=>"$uri").
		$self->hidden_authen_fields.
		$force_field.
		CGI::hidden(-name=>'file_type',-default=>$self->{file_type}).
		CGI::hidden(-name=>'problemSeed',-default=>$problemSeed).
		CGI::hidden(-name=>'displayMode',-default=>$displayMode).
		CGI::hidden(-name=>'problemContents',-default=>$problemContents).
		CGI::p(
			CGI::submit(-value=>'Add this problem to: ',-name=>'submit'),
			CGI::popup_menu(-name=>'target_set',-values=>\@allSetNames)
		).
		CGI::end_form();
	}

	my $target = "problem$edit_level";   
	return CGI::p($header),
		CGI::start_form({method=>"POST", name=>"editor", action=>"$uri", target=>$target, enctype=>"application/x-www-form-urlencoded"}),
		$self->hidden_authen_fields,
		$force_field,
		CGI::hidden(-name=>'file_type',-default=>$self->{file_type}),
		CGI::div(
			'Seed: ',
			CGI::textfield(-name=>'problemSeed',-value=>$problemSeed),
			'Mode: ',
			CGI::popup_menu(-name=>'displayMode', -values=>$mode_list, -default=>$displayMode),
			CGI::a({-href=>'http://webwork.math.rochester.edu/docs/docs/pglanguage/manpages/',-target=>"manpage_window"},
				'Manpages',
			)
		),
		CGI::p(
			CGI::textarea(
				-name => 'problemContents', -default => $problemContents,
				-rows => $rows, -columns => $columns, -override => 1,
			),
		),
		CGI::p(
			CGI::submit(-value=>'Refresh',-name=>'submit'),
			$make_local_copy ? CGI::submit(-value=>'Save',-name=>'submit', -disabled=>1) : CGI::submit(-value=>'Save',-name=>'submit'),
			CGI::submit(-value=>'Revert', -name=>'submit'),
			CGI::submit(-value=>'Save as',-name=>'submit'),
			CGI::textfield(-name=>'save_to_new_file', -size=>40, -value=>""),
		),
		CGI::end_form(),
	 	$add_to_stuff;
}

################################################################################
# Utilities
################################################################################

# saveFileChanges does most of the work. it is a separate method so that it can
# be called from either pre_header_initialize() or initilize(), depending on
# whether a redirect is needed or not.
# 
# it actually does a lot more than save changes to the file being edited, and
# sometimes less.

sub saveFileChanges {
	my ($self, $setName, $problemNumber) = @_;
	my $r = $self->r;
	my $ce = $r->ce;
	my $db = $r->db;
	my $urlpath = $r->urlpath;
	
	my $courseName = $urlpath->arg("courseID");
	my $user = $r->param('user');
	my $effectiveUserName = $r->param('effectiveUser');

	$setName = '' unless defined $setName;
	$problemNumber = '' unless defined $problemNumber;
	
	##### Determine path to the file to be edited. #####
	
	my $editFilePath = $ce->{courseDirs}->{templates};
	my $problem_record = undef;
	
	my $file_type = $r->param("file_type") || '';
	
	if ($file_type eq 'course_info') {
		# we are editing the course_info file
		$self->{file_type}       = 'course_info';
		
		# value of courseFiles::course_info is relative to templates directory
		$editFilePath           .= '/' . $ce->{courseFiles}->{course_info};
	} else {
		# we are editing a problem file or a set header file
		
		# FIXME  there is a discrepancy in the way that the problems are found.
		# FIXME  more error checking is needed in case the problem doesn't exist.
		# (i wonder what the above comments mean... -sam)
		
		if (defined $problemNumber) {
			if ($problemNumber == 0) {
				# we are editing a header file
				if ($file_type eq 'set_header' or $file_type eq 'hardcopy_header') {
					$self->{file_type} = $file_type 
				} else {
					$self->{file_type} = 'set_header';
				}
				
				# first try getting the merged set for the effective user
				my $set_record = $db->getMergedSet($effectiveUserName, $setName); # checked
				
				# if that doesn't work (the set is not yet assigned), get the global record
				$set_record = $db->getGlobalSet($setName); # checked
				
				# bail if no set is found
				die "Cannot find a set record for set $setName" unless defined($set_record);
				
				my $header_file = "";
				$header_file = $set_record->{$self->{file_type}};
				if ($header_file && $header_file ne "") {
					$editFilePath .= '/' . $header_file;
				} else {
					# if the set record doesn't specify the filename
					# then the set uses the deafult from snippets
					# so we'll load that file, but change where it will be saved
					# to and grey out the "Save" button
					if ($r->param('make_local_copy')) {
						$editFilePath = $ce->{webworkFiles}->{screenSnippets}->{setHeader} if $self->{file_type} eq 'set_header';
						$editFilePath = $ce->{webworkFiles}->{hardcopySnippets}->{setHeader} if $self->{file_type} eq 'hardcopy_header';
						$self->addbadmessage("$editFilePath is the default header file and cannot be edited directly.");
						$self->addbadmessage("Any changes you make will have to be saved as another file.");
					}
				}
					
				
			} else {
				# we are editing a "real" problem
				$self->{file_type} = 'problem';
				
				# first try getting the merged problem for the effective user
				$problem_record = $db->getMergedProblem($effectiveUserName, $setName, $problemNumber); # checked
				
				# if that doesn't work (the problem is not yet assigned), get the global record
				$problem_record = $db->getGlobalProblem($setName, $problemNumber) unless defined($problem_record); # checked
				

				if(not defined($problem_record)) {
				  my $forcedSourceFile = $r->param('sourceFilePath');
									# bail if no problem is found and we aren't faking it
					die "Cannot find a problem record for set $setName / problem $problemNumber" unless defined($forcedSourceFile);
				  $problem_record = fake_problem($db);
				  $problem_record->problem_id($problemNumber);
				  $problem_record->source_file($forcedSourceFile);
				}

				
				$editFilePath .= '/' . $problem_record->source_file;
			}
		}
	}
	
	# if a set record or problem record contains an empty blank for a header or problem source_file
	# we could find ourselves trying to edit /blah/templates/.toenail.tmp or something similar
	# which is almost undoubtedly NOT desirable

	if (-d $editFilePath) {
		$self->{failure} = "The file $editFilePath is a directory!";
		$self->addbadmessage("The file $editFilePath is a directory!");
	}

	
	my $editFileSuffix = $user.'.tmp';
	my $submit_button = $r->param('submit');
	
	##############################################################################
	# Determine the display mode
	# try to get problem seed from the input parameter, or from the problem record
	# This will be needed for viewing the problem via redirect.
	# They are also two of the parameters which can be set by the editor
	##############################################################################
	
	my $displayMode;
	if (defined $r->param('displayMode')) {
		$displayMode = $r->param('displayMode');
	} else {
		$displayMode = $ce->{pg}->{options}->{displayMode};
	}
	
	my $problemSeed;
	if (defined $r->param('problemSeed')) {
		$problemSeed = $r->param('problemSeed');	
	} elsif (defined($problem_record) and  $problem_record->can('problem_seed')) {
		$problemSeed = $problem_record->problem_seed;
	}
	
	# make absolutely sure that the problem seed is defined, if it hasn't been.
	$problemSeed = '123456' unless defined $problemSeed and $problemSeed =~/\S/;
	
	##############################################################################
	# read and update the targetFile and targetFile.tmp files in the directory
	# if a .tmp file already exists use that, unless the revert button has been pressed.
	# These .tmp files are
	# removed when the file is finally saved.
	##############################################################################
	
	my $problemContents = '';
	my $currentSourceFilePath = '';
	my $editErrors = '';	
	
	my $inputFilePath;
	if (-r "$editFilePath.$editFileSuffix") {
		$inputFilePath = "$editFilePath.$editFileSuffix";
	} else {
		$inputFilePath = $editFilePath;
	}
	
	$inputFilePath = $editFilePath  if defined($submit_button) and $submit_button eq 'Revert';
	
	##### handle button clicks #####
	
	if (not defined $submit_button or $submit_button eq 'Revert' ) {
		# this is a fresh editing job
		# copy the pg file to a new file with the same name with .tmp added
		# store this name in the $self->currentSourceFilePath for use in body 
		
		# try to read file
		if(-e $inputFilePath and not -d $inputFilePath) {
			eval { $problemContents = WeBWorK::Utils::readFile($inputFilePath) };
			$problemContents = $@ if $@;
		} else { # file not existing is not an error
			$problemContents = '';
		}
		
		$currentSourceFilePath = "$editFilePath.$editFileSuffix"; 
		$self->{currentSourceFilePath} = $currentSourceFilePath; 
		$self->{problemPath} = $editFilePath;
	} elsif ($submit_button	eq 'Refresh') {
		# grab the problemContents from the form in order to save it to the tmp file
		# store tmp file name in the $self->currentSourceFilePath for use in body 
		$problemContents = $r->param('problemContents');
		
		$currentSourceFilePath = "$editFilePath.$editFileSuffix";	
		$self->{currentSourceFilePath} = $currentSourceFilePath;
		$self->{problemPath} = $editFilePath;
	} elsif ($submit_button eq 'Save') {
		# grab the problemContents from the form in order to save it to the permanent file
		# later we will unlink (delete) the temporary file
	 	# store permanent file name in the $self->currentSourceFilePath for use in body 
		$problemContents = $r->param('problemContents');
		
		$currentSourceFilePath = "$editFilePath"; 		
		$self->{currentSourceFilePath} = $currentSourceFilePath;	
		$self->{problemPath} = $editFilePath;
	} elsif ($submit_button eq 'Save as') {
		# grab the problemContents from the form in order to save it to a new permanent file
		# later we will unlink (delete) the current temporary file
	 	# store new permanent file name in the $self->currentSourceFilePath for use in body 
		$problemContents = $r->param('problemContents');
		# Save the user in case they forgot to end the file with .pg
		if($self->{file_type} eq 'problem') {
			my $save_to_new_file = $r->param('save_to_new_file');
			$save_to_new_file =~ s/\.pg$//; # remove it if it is there
			$save_to_new_file .= '.pg'; # put it there
			$r->param('save_to_new_file', $save_to_new_file);
		}
		$currentSourceFilePath = $ce->{courseDirs}->{templates} . '/' . $r->param('save_to_new_file'); 		
		$self->{currentSourceFilePath} = $currentSourceFilePath;	
		$self->{problemPath} = $currentSourceFilePath;
	} elsif ($submit_button eq 'Add this problem to: ') {
		$problemContents = $r->param('problemContents');
		$currentSourceFilePath = "$editFilePath.$editFileSuffix";	
		$self->{currentSourceFilePath} = $currentSourceFilePath;	
		$self->{problemPath} = $editFilePath;
	} else {
		die "Unrecognized submit command: $submit_button";
	}
	
	# Handle the problem of line endings.  Make sure that all of the line endings.  Convert \r\n to \n
	$problemContents =~ s/\r\n/\n/g;
	$problemContents =~ s/\r/\n/g;
	
	# FIXME  convert all double returns to paragraphs for .txt files
	# instead of doing this here, it should be done n the PLACE WHERE THE FILE IS DISPLAYED!!!
	#if ($self->{file_type} eq 'course_info' ) {
	#	$problemContents =~ s/\n\n/\n<p>\n/g;
	#}
	

	##############################################################################
	# write changes to the approriate files
	# FIXME  make sure that the permissions are set correctly!!!
	# Make sure that the warning is being transmitted properly.
	##############################################################################

	# FIXME  set a local state rather continue to call on the submit button.
	if (defined $submit_button and $submit_button eq 'Save as' and $r->param('save_to_new_file') !~ /\w/) {
		# setting $self->{failure} stops any future redirects
		$self->{failure} = "Please specify a file to save to.";
		$self->addbadmessage(CGI::p("Please specify a file to save to."));
	} elsif (defined $submit_button and $submit_button eq 'Save as' and defined $currentSourceFilePath and -e $currentSourceFilePath) {
		# setting $self->{failure} stops any future redirects
		$self->{failure} = "File $currentSourceFilePath exists.  File not saved.";
		$self->addbadmessage(CGI::p("File $currentSourceFilePath exists.  File not saved."));
	} else {
		# make sure any missing directories are created
		$currentSourceFilePath = WeBWorK::Utils::surePathToFile($ce->{courseDirs}->{templates},$currentSourceFilePath);
		eval {
			local *OUTPUTFILE;
			open OUTPUTFILE, ">", $currentSourceFilePath
					or die "Failed to open $currentSourceFilePath";
			print OUTPUTFILE $problemContents;
			close OUTPUTFILE;
		};  # any errors are caught in the next block
	}

	###########################################################
	# Catch errors in saving files,  clean up temp files
	###########################################################

	my $openTempFileErrors = $@ if $@;

	if ($openTempFileErrors) {
	
		$currentSourceFilePath =~ m|^(/.*?/)[^/]+$|;
		my $currentDirectory = $1;
	
		my $errorMessage;
		# check why we failed to give better error messages
		if ( not -w $ce->{courseDirs}->{templates} ) {
			$errorMessage = "Write permissions have not been enabled in the templates directory.  No changes can be made.";
		} elsif ( not -w $currentDirectory ) {
			$errorMessage = "Write permissions have not been enabled in $currentDirectory.  Changes must be saved to a different directory for viewing.";
		} elsif ( -e $currentSourceFilePath and not -w $currentSourceFilePath ) {
			$errorMessage = "Write permissions have not been enabled for $currentSourceFilePath.  Changes must be saved to another file for viewing.";
		} else {
			$errorMessage = "Unable to write to $currentSourceFilePath: $openTempFileErrors";
		}

		$self->{failure} = $errorMessage;
		$self->addbadmessage(CGI::p($errorMessage));
		
	} else {
		$self->{success} = "Problem saved to: $currentSourceFilePath";
		# unlink the temporary file if there are no errors and the save button has been pushed
		unlink("$editFilePath.$editFileSuffix")
			if defined $submit_button and ($submit_button eq 'Save' or $submit_button eq 'Save as');
	}
		
	# return values for use in the body subroutine
	$self->{inputFilePath}            =   $inputFilePath;
	$self->{displayMode}              =   $displayMode;
	$self->{problemSeed}              =   $problemSeed;
	$self->{r_problemContents}        =   \$problemContents;
	$self->{editFileSuffix}           =   $editFileSuffix;
}

1;
