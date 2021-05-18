function audfprint(varargin)
% audfprint(varargin)
% Utility to create audio fingerprint databases and match audio
% files to it.
%
% Usage;
%   audfprint [options]
%
%   See http://labrosa.ee.columbia.edu/projects/audfprint
%   for full documentation
%
% 2011-08-21 Dan Ellis dpwe@ee.columbia.edu
% $Header: $

VERSION = 0.9;
DATE = 20140304;

% Parse out the optional arguments
[DBASE, CLEARDBASE, ADD, ADDLIST, ADDDIR, ...
 ADDSKIP, ADDCHECKPOINT, MATCHONADDTHRESH, ...
 OUTDIR, REMOVE, REMOVELIST, ...
 MATCH, MATCHLIST, MATCHDIR, DENSITY, ...
 MATCHMAXRET, MATCHMINCOUNT, MATCHMINPROP, ...
 MAXTOFILTER, MATCHWIDTH, MATCHALIGN, ALIGNOUTDIR, ALIGNOUTEXT, ...
 WARPMAX, WARPSTEP, ...
 NHASHBITS, MAXNENTRIES, TIMESIZE, HOPTIME, TARGETSR, OVERSAMP, ...
 USERAWCOUNTS, ...
 SKIP, MAXDUR, ...
 LIST, ...
 JENKINS, ...
 QUIET, OUT, ...
 XTRA] = ...
    process_options(varargin, ...
                    '-dbase', '', ...
		    '-cleardbase', 0, ...
                    '-add', '', ...
                    '-addlist', '', ...
                    '-adddir', '', ...
                    '-addskip', 0, ...
                    '-addcheckpoint', 0, ...
                    '-matchonaddthresh', 0, ...
                    '-outdir', '', ...
                    '-remove', '', ...
                    '-removelist', '', ...
                    '-match', '', ...
                    '-matchlist', '', ...
                    '-matchdir', '', ...
                    '-density', 7, ...
                    '-matchmaxret', 5, ...
                    '-matchmincount', 0, ...
                    '-matchminprop', 0.1, ...
                    '-maxtofilter', 100, ...
                    '-matchwidth', 1, ...
                    '-matchalign', 0, ...
                    '-alignoutdir', '', ...
                    '-alignoutext', '.mp3', ...
                    '-warpmax', 0, ...
                    '-warpstep', 0.001, ...
                    '-nhashbits', 20, ...
                    '-maxnentries', 100, ...
                    '-timesize', 16384, ...
                    '-hoptime', 0.02322, ...
                    '-targetsr', 11025, ...
                    '-oversamp', 0, ...
                    '-userawcounts', 0, ...
                    '-skip', 0, ...
                    '-maxdur', 0, ...
                    '-list', '', ...
                    '-jenkins', 0, ...
                    '-quiet', 0, ...
                    '-out', '');

% To resume pre-v0.9 behavior:
%BACKWARDS_COMPATIBLE=1;
%if BACKWARDS_COMPATIBLE
%  HOPTIME = 0.032;
%end

% Start building lists of addfiles and matchfiles
ADDFILES = [];
if length(ADD)
  ADDFILES{1} = ADD;
end
MATCHFILES = [];
if length(MATCH)
  MATCHFILES{1} = MATCH;
end
REMOVEFILES = [];
if length(REMOVE)
  REMOVEFILES{1} = REMOVE;
end
if length(REMOVELIST) > 0
  REMOVEFILES = [REMOVEFILES, listfileread(REMOVELIST)];
end

HELP = 0;
if length(XTRA) > 0
  % if -add or -match are specified, add extra options to that
  if length(ADDFILES)
    ADDFILES = [ADDFILES, XTRA];
  elseif length(MATCHFILES)
    MATCHFILES = [MATCHFILES, XTRA];
  elseif length(REMOVEFILES)
    REMOVEFILES = [REMOVEFILES, XTRA];
  else
    % don't know what the extra options are
    HELP = length(strmatch('-help',XTRA,'exact')) > 0;
    if ~HELP
      disp(['Unrecognized options:',sprintf(' %s',XTRA{1:end})]);
      HELP = 1;
    end
  end
end

if length(DBASE) == 0
  disp('No dbase specified!');
  HELP = 1;
end

if HELP
  disp(['audfprint v',num2str(VERSION),' of ',num2str(DATE)]);
  disp('usage: audfprint ...');
  disp('   -dbase <file>     The reference database file');
  disp('   -cleardbase 0/1   Create a new database with options...');
  disp('     -nhashbits <num>  log_2 of hash table size (20)');
  disp('     -maxnentries <num> maximum number of entries per bin (100)');
  disp('     -timesize <num>   Maximum value of abs time index (16384)');
  disp('     -hoptime <time>   Hop between time windows (0.02322)');
  disp('     -targetsr <rate>  Resample to this SR (11025)');
  disp('     -jenkins 0/1      use jenkins hash on hashes (0)');
  disp('   -density <num>    Target hashes/sec (default: 7.0)');
  disp('   -add <file ...>   Sound file(s) to add to database');
  disp('   -addlist <file>   List of audio files to add to database');
  disp('   -adddir <dir>     Watch this directory and add any files');  
  disp('   -addskip <count>  Skip this many initial files in addlist');
  disp('   -addcheckpoint <count>  Save database every <count> tracks');
  disp('   -matchonaddthresh <thr>  Don''t add files if match >= thr (0)');
  disp('   -remove <name ...> Delete named track(s) from dbase');
  disp('   -removelist <file> Delete tracks named in file from dbase');
  disp('   -match <file ...> Audio file(s) to match');
  disp('   -matchlist <file> List of audio files to match against database');
  disp('   -matchdir  <dir>  Watch this directory and match any files');
  disp('   -matchmaxret <num> Max num matches to report for each query (5)');
  disp('   -matchmincount <num> Minimum count of common hashes to report (0)');
  disp('   -matchminprop <num>  Min proportion of max hash count to report (0.1)');
  disp('   -maxtofilter <num> Max tracks retained per hash hit (100)');
  disp('   -matchwidth <bins> Width of "modal time skew" search (1)');
  disp('   -matchalign 0/1   calculate time skew alignment for match (0)');
  disp('   -alignoutdir <dir> write aligned versions of queries here');
  disp('   -alignoutext <ext> default extension for aligned outputs (.mp3)');
  disp('   -warpmax <factor> repeat filtering with warp factors to this (0)'); 
  disp('   -warpstep <step   step size for repeating with warps (0.001)'); 
  disp('   -oversamp <num>   oversampling factor for queries (0..special)');
  disp('   -userawcounts 0/1 count hits without applying synchrony filter');
  disp('   -skip <time>      drop time from start of each sound');
  disp('   -maxdur <time>    truncate soundfiles at this duration (0=all)');
  disp('   -list <regexp>    list matching files in the database (. for all)');
  disp('   -quiet 0/1        suppress status messages');
  
  disp('   -out <file>       File to write matches out to (stdout)');
  disp('   -outdir <dir>     Write match reports to this directory');

  return
end

% logic
% alignoutdir needs matchalign
if length(ALIGNOUTDIR) > 0
  MATCHALIGN = 1;
end

% Set up database

% Maybe load the database?
if CLEARDBASE
  NHASHES = 2^NHASHBITS;
  ht_clear(NHASHES, MAXNENTRIES, TIMESIZE, HOPTIME, TARGETSR, ~JENKINS);
else

  [inver, HOPTIME, TARGETSR] = ht_load(DBASE, VERSION);
  % should set HashTable, HashTableNames, HashTableCounts, HT_params
  
end

% Are we adding?
if length(ADDLIST) > 0
  ADDFILES =  [ADDFILES, listfileread(ADDLIST)];
end

% Add any files in the add watch directory too
if length(ADDDIR) > 0
  BYDATE = 1;
  adddirfiles = myls(ADDDIR,BYDATE);
  ADDFILES = [ADDFILES, adddirfiles];
end

naddfiles = max(0,length(ADDFILES)-ADDSKIP);

%HOPTIME = 0;

if naddfiles > 0

  addblock = ADDCHECKPOINT;
  if addblock == 0; addblock = naddfiles; end
  for i = (ADDSKIP+1):addblock:naddfiles
    thesefiles = ADDFILES(i:min(i+addblock-1,naddfiles));
    [N,T,H,HOPTIME] = add_tracks_byname(thesefiles, ...
                                        SKIP, MAXDUR, DENSITY, ...
                                        MATCHONADDTHRESH, ...
                                        HOPTIME, TARGETSR, ...
                                        QUIET);
    ht_save(DBASE,HOPTIME,VERSION);
  end
end

if length(ADDDIR) > 0
  % if we're waiting to add, make it save the database on
  % termination
  onCleanup(@()ht_save(DBASE,HOPTIME,VERSION));
  % also, track how many we've added for intermediate checkpointing
  nnewadded = 0;
end

% Are we removing?
if length(REMOVEFILES) > 0
  nremoved = 0;
  for i = 1:length(REMOVEFILES)
    nremoved = nremoved + ht_remove(REMOVEFILES{i});
  end
%  if nremoved > 0
%    ht_save(DBASE,HOPTIME,VERSION);
%  end
  % Save now happens regardless at end of main
end

% Are we querying?
if length(MATCHLIST) > 0
  MATCHFILES = [MATCHFILES, listfileread(MATCHLIST)];
end
% Add any files in the match watch directory too
if length(MATCHDIR) > 0
  BYDATE = 1;
  matchdirfiles = myls(MATCHDIR,BYDATE);
  MATCHFILES = [MATCHFILES, matchdirfiles];
end

% where to write outputs?
STDOUT = 1; % stream ID for stdout
OF = STDOUT; 
if length(OUT) > 0
  if length(OUTDIR) > 0
    warn('Specifying -outdir overrides specifying -out');
  else
    if strcmp(OUT, '-') == 0
      OF = fopen(OUT, 'w');
    end
  end
end  

% collect results
%if length(MATCHFILES) > 0  
done = 0;
while ~done
  tstart = tic;
  TT = 0;
  NN = 0;
  nd = length(MATCHFILES);
  for i = 1:nd
    F = MATCHFILES{i};

    [R,N,T,HOPTIME] = match_query_byname(F, SKIP, MAXDUR, DENSITY, OVERSAMP, ...
                                         MATCHMINCOUNT, MATCHMINPROP, ...
                                         MATCHMAXRET, USERAWCOUNTS, ...
                                         MAXTOFILTER, MATCHWIDTH, ...
                                         MATCHALIGN, ...
                                         ALIGNOUTDIR, ALIGNOUTEXT, ...
                                         WARPMAX, WARPSTEP, ...
                                         HOPTIME, TARGETSR, QUIET);
    % write report to custom file, or to STDOUT
    if length(OUTDIR)
      [p,n] = fileparts(F);
      opfname = fullfile(OUTDIR, [n,'.txt']);
      OF = fopen(opfname, 'w');
      if OF == -1
        error(['Could not create output file ',opfname]);
      end
    end
    for j = 1:min(MATCHMAXRET, size(R,1))
      fprintf(OF,'%s %d %s %d %.3f\n', F, j, ht_name(R(j,1)), R(j,2), ...
              R(j,3)*HOPTIME);
    end
    if OF ~= STDOUT; fclose(OF); OF = STDOUT; end
    TT = TT+T;
    NN = NN+N;
  end
  clocktime = toc(tstart);
  if nd > 0 && ~QUIET
    disp(['matched ',num2str(nd),' tracks (',num2str(TT),' secs, ', ...
          num2str(NN),' hashes, ',num2str(NN/TT),' hashes/sec)', ...
          ' in ',sprintf('%.1f',clocktime),' sec', ...
          ' = ',sprintf('%.3f',clocktime/TT),' x RT']);
  end
  % Mark all matchfiles processed
  MATCHFILES = [];
  
  if length(ADDDIR) > 0 || length(MATCHDIR) > 0
    % we will never be done, just wait here until new files appear
    while length(MATCHFILES) == 0
      wait = 0; bydate = 1;
      % Maybe check for files to add (and add them)
      if length(ADDDIR) > 0
        [ADDFILES,adddirfiles] ...
            = check_for_new_files(ADDDIR, adddirfiles, wait, bydate);
        if length(ADDFILES)
          [N,T,H,HOPTIME] = add_tracks_byname(ADDFILES, 0, ...
                                              MAXDUR, DENSITY, ...
                                              MATCHONADDTHRESH, ...
                                              HOPTIME, QUIET);
          nnewadded = nnewadded + length(ADDFILES);
          if ADDCHECKPOINT > 0 && nnewadded > ADDCHECKPOINT
            % maybe save out the new database occasionally
            ht_save(DBASE,HOPTIME,VERSION);
            nnewadded = 0;
          end
        end
      end
      if length(MATCHDIR) > 0
        [MATCHFILES,matchdirfiles] ...
            = check_for_new_files(MATCHDIR, matchdirfiles, wait, bydate);
      end
    end
  else
    % no directories to watch
    done = 1;
  end
end

% If the database is still dirty, save it
ht_save(DBASE,HOPTIME,VERSION);

if length(LIST) > 0
  ht_list(OF, LIST);
end

if OF ~= STDOUT
  fclose(OF);
end

if ~QUIET; disp('done'); end


% usage:
% > % Create & populate database
% > audfprint -dbase tmpdb1 -cleardbase 1 -addlist matthews.txt
% > % Run queries (here, the same items used in building the database
% > audfprint -dbase tmpdb1 -matchlist matthews.txt

