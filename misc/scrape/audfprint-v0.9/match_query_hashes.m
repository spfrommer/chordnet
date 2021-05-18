function [R,L,O,S] = match_query_hashes(H,MINCOUNT,MINPROP,MAXRET,USERAWCOUNTS,MAXTOFILTER,MATCHWIDTH,MATCHALIGN,WARPMAX,WARPSTEP,QUIET)
% [R,L,O,S] = match_query_hashes(H,MINCOUNT,MINPROP,MAXRET,USERAWCOUNTS,MAXTOFILTER,MATCHWIDTH,MATCHALIGN,WARPMAX,WARPSTEP,QUIET)
%     match a query starting just from the set of hashes in H.
%     Rows of R are potential maxes, in format
%      songID  modalDTcount modalDT totalCommonCount
%     i.e. there were <modalDTcount> occurrences of hashes 
%     that occurred in the query and reference with a difference of 
%     <modalDT> frames (of 23.2ms).  Positive <modalDT> means the
%     query matches after the start of the reference track.
%     L returns the actual landmarks that this implies for top return.
%     as rows of <time in match vid> f1 f2 dt <timeskew of query>
%     MINCOUNT is the smallest number of matching hashes to report (0) 
%     MINPROP prunes returns with fewer than this proportion of the
%     best hit (0.1)
%     MAXRET specifies the maximum number of tracks to return (100)
%     USERAWCOUNTS does not filter by duration, but just uses
%     shared hash counts
%     MAXTOFILTER limits the total number of tracks retained per
%     individual hash hit (100)
%     MATCHWIDTH is the number of time-difference quantization bins
%     by which hashes can differ while still being included in the
%     modal time-skew bin
%     MATCHALIGN is a flag to run alignment on the hashes, in which
%     case O returns an offset, and S a slope (else 0 and 1).
%     WARPMAX is an optional maximum warp factor for repeated,
%     warped searches
%     WARPSTEP is the increment for trying warps (0.001), so the
%     total number of searches done is ~ 1+ 2*WARPMAX/WARPSTEP.
% 2013-05-18 dpwe@ee.columbia.edu refactor of match_query for matchaddthresh

if nargin < 2;  MINCOUNT = 0;  end
if nargin < 3;  MINPROP = 0.1;  end
if nargin < 4;  MAXRET = 100;  end
if nargin < 5;  USERAWCOUNTS = 0;  end
if nargin < 6;  MAXTOFILTER = 100;  end
if nargin < 7;  MATCHWIDTH = 1; end
if nargin < 8;  MATCHALIGN = 0; end
if nargin < 9;  WARPMAX = 0; end
if nargin < 10; WARPSTEP = 0.001; end
if nargin < 11;  QUIET = 0;  end

% Which match to return info about
IX = 1;
%% possibly make coarser quantization of time for W > 1
%MATCHWIDTH = 1;

% ht_match gets all the hits and does the time filtering (most of
% the work)
[R,L,THOP] = ht_match(H,USERAWCOUNTS,MATCHWIDTH,IX,MAXTOFILTER,WARPMAX,WARPSTEP);

if MATCHALIGN
  if size(R,1) == 0
    disp('No matches - no align');
  else
    % Rebuild hash times from return
  %  Ho = sum(L(:,[1 2]),2) - 1;  % - 1 empirical to give best time alignments
  %  Ho = [Ho,L(:,3)];
    % Get all the original hashes for best-matching ID
    Ho = ht_retrieve(R(1,1));
    % calculate & display alignment
    [hh,O,S,hc] = alignhashes(Ho, H, THOP);
  end
else
  O = 0; S = 1;
end
  
nr = size(R,1);

if nr > 0

  % Return no more than 100 hits, and only down to 10% the #hits in
  % most popular
  if size(R,1) > MAXRET
    R = R(1:MAXRET,:);
  end
  maxhits = R(1,2);
  nuffhits = find(R(:,2)> max(MINCOUNT, R(:,2)>(MINPROP*maxhits)));
  R = R(nuffhits,:);

else
  R = zeros(0,4);
  if ~QUIET
    disp('*** NO HITS FOUND ***');
  end
end
