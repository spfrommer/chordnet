function [R,N,T,THOP,L,Lq] = match_query_byname(F,TSKIP,TDUR,DENS,OSAMP,MINCOUNT,MINPROP,MAXRET,USERAWCOUNTS,MAXTOFILTER,MATCHWIDTH,MATCHALIGN,ALIGNOUTDIR,DEFAULTOUTEXT,WARPMAX,WARPSTEP,THOPI,TARGETSR,QUIET)
% [R,N,T,THOP,L,Lq] = match_query_byname(F,TSKIP,TDUR,DENS,OSAMP,MINCOUNT,MINPROP,MAXRET,USERAWCOUNTS,MAXTOFILTER,MATCHWIDTH,MATCHALIGN,ALIGNOUTDIR,DEFAULTOUTEXT,THOPI,TARGETSR,QUIET)
%     Match landmarks from an audio query against the database.
%     Rows of R are potential maxes, in format
%      songID  modalDTcount modalDT totalCommonCount
%     i.e. there were <modalDTcount> occurrences of hashes 
%     that occurred in the query and reference with a difference of 
%     <modalDT> frames (of 23.2ms).  Positive <modalDT> means the
%     query matches after the start of the reference track.
%     N returns the number of landmarks for this query and T
%     returns its total duration.
%     P is the frame period of analysis in seconds.
%     L returns the actual landmarks that this implies for IX'th return.
%     as rows of <time in match vid> f1 f2 dt <timeskew of query>
%     Lq returns the landmarks for the query.
%     DENS and OSAMP are arguments to landmark calculation.
%     Return hits only if >= MINCOUNT common hashes are found (0).
%     USERAWCOUNTS prevents filtering to find time-consistent hits.
%     TSKIP > 0 drops that many seconds of sound from the start of
%     each file read, then TDUR truncates to at most that time.
%     MAXTOFILTER sets the number of tracks to retain per hash hit.
%     THOPI is the incoming value for THOP
%     TARGETSR is the sampling rate for landmark extraction (11025)
%     MATCHALIGN is a flag to actually calculate the best linear
%       skew/offset of the query to the reference, and 
%     ALIGNOUTDIR is a directory to write aligned versions to,
%     where DEFAULTOUTEXT is added to the output file name if none
%     is present in the hash table names record.
%     WARPMAX, WARPSTEP are passed to match_query_hashes.
% 2008-12-29 Dan Ellis dpwe@ee.columbia.edu

if nargin < 2;  TSKIP = 0; end
if nargin < 3;  TDUR = 0; end
if nargin < 4;  DENS = 20;  end
if nargin < 5;  OSAMP = 0;  end
if nargin < 6;  MINCOUNT = 0;  end
if nargin < 7;  MINPROP = 0.1;  end
if nargin < 8;  MAXRET = 100;  end
if nargin < 9;  USERAWCOUNTS = 0;  end
if nargin < 10; MAXTOFILTER = 100;  end
if nargin < 11; MATCHWIDTH = 1; end
if nargin < 12; MATCHALIGN = 0; end
if nargin < 13; ALIGNOUTDIR = 0; end
if nargin < 14; DEFAULTOUTEXT = '';  end
if nargin < 15; WARPMAX = 0; end
if nargin < 16; WARPSTEP = 0.001; end
if nargin < 17; THOPI = 0; end
if nargin < 18; TARGETSR = 11025; end
if nargin < 19; QUIET = 0;  end

targetsr = 11025;
forcemono = 1;
[D,SR] = audioread_custom(F,targetsr,forcemono,TSKIP,TDUR);
T = length(D)/SR;

if length(D) == 0
  R = zeros(0,4);
  N = 0;
  T = 0;
  P = 0;
  L = [];
  Lq = [];
  THOP = 0;
  return
end

if OSAMP == 0
  % special case - analyze each track four times & merge results
  % slow, but gives best results
  [Lq,THOP] = find_landmarks(D,SR, DENS, THOPI, OSAMP, TARGETSR);
  %Lq = fuzzify_landmarks(Lq);
  % Augment with landmarks calculated quarter-window advances too
  Lq = [Lq;find_landmarks(D(round(THOP/4*SR):end),SR, ...
                          DENS, THOP, OSAMP, TARGETSR)];
  Lq = [Lq;find_landmarks(D(round(THOP/2*SR):end),SR, ...
                          DENS, THOP, OSAMP, TARGETSR)];
  Lq = [Lq;find_landmarks(D(round(3*THOP/4*SR):end),SR, ...
                          DENS, THOP, OSAMP, TARGETSR)];
  % add in quarter-hop offsets too for even better recall
else
  [Lq,THOP] = find_landmarks(D,SR, DENS, THOPI, OSAMP, TARGETSR);
end

%Hq = landmark2hash(Lq);
Hq = unique(landmark2hash(Lq), 'rows');

N = length(Hq);

if ~QUIET
  %disp(['landmarks ',num2str(size(Lq,1)),' -> ', num2str(size(Hq,1)),' hashes']);
  disp([F,' (',sprintf('%.1f',length(D)/SR),' s)', ... 
        ' analyzed to ',num2str(size(Hq,1)),' hashes']);
end

% factor off to common back-end
[R,L,O,S] = match_query_hashes(Hq, MINCOUNT, MINPROP, MAXRET, ...
                               USERAWCOUNTS, MAXTOFILTER, ...
                               MATCHWIDTH, MATCHALIGN, ...
                               WARPMAX, WARPSTEP, ...
                               QUIET);

if length(ALIGNOUTDIR) > 0 && size(R,1) > 0
  % need to rewrite warped
  % default output type
  %if length(DEFAULTOUTEXT) == 0
    %DEFAULTOUTEXT = '.wav';
  %end
  DEFAULTOUTEXT = '.wav';
  songid = R(1,1);
  outfile = fullfile(ALIGNOUTDIR, ht_name(songid));
  [p,n,e] = myfileparts(outfile);
  %if length(e) == 0
    outfile = fullfile(p, [n,DEFAULTOUTEXT]);
  %end
  % figure max duration from landmarks
  [hashes, thop] = ht_retrieve(songid);
  maxdur = max(hashes(:,1)) * thop + 5.0;  % add 5 sec off the end
  rewrite_aligned_audio(F, outfile, O, S, maxdur);
  disp(['Warped query written to ', outfile]);
end
