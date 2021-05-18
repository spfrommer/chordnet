function [R,HO,THOP] = ht_match(H,USERAWCOUNTS,W,IX,MAXTOFILTER,WARPMAX,WARPSTEP)
% [R,HO,THOP] = ht_match(H,USERAWCOUNTS,W,IX,MAXTOFILTER,WARPMAX,WARPSTEP)
%     Match a set of hashes H against the database.
%     H consists of <time> <hash> rows.
%     Rows of R are potential maxes, in format
%      songID  modalDTcount modalDT
%     i.e. there were <modalDTcount> occurrences of hashes 
%     that occurred in the query and reference with a difference of 
%     <modalDT> frames (of 23.22ms).  Positive <modalDT> means the
%     query matches after the start of the reference track.
%     HO returns the actual hashes that this implies for IX'th
%     return.   If IX is a vector, HO is a cell array for each element.
%     as rows of song_id time_in_match_vid hash timeskew_of_query
%     W is the width (in time frames) of the coarse quantization of the 
%     time differences.  Differences within this window count as
%     matches.
%     MAXTOFILTER is the maximum number of tracks to add from each
%     individual has count (needs to be large if many tracks have
%     the same hashes, and more work will be done by time filtering
%     (100))
%     WARPMAX (0) and WARPSTEP (0.001) will potentially do a linear
%     search of possible time warps when doing time filtering out
%     to +/- WARPMAX in steps of WARPSTEP (default gives no search).
% 2010-10-24 Dan Ellis dpwe@ee.columbia.edu

global HashTableLengths HT_params

if nargin < 2;  USERAWCOUNTS = 0; end
if nargin < 3;  W = 1;  end
if nargin < 4;  IX = [];  end
% Prune raw track returns based on unfiltered common hash counts
if nargin < 5; MAXTOFILTER = 100; end
if nargin < 6; WARPMAX = 0.0; end
if nargin < 7; WARPSTEP = 0.001; end

% (just used to inform match_query_hashes)
THOP = HT_params.hoptime;

%disp([num2str(size(H,1)),' hashes']);
if length(H) > 0
  Rt = ht_get_hits(H);
  nr = size(Rt,1);
else
  nr = 0;
end

if nr > 0

  % Find all the unique tracks referenced
  [utrks,xx] = unique(sort(Rt(:,1)),'first');
  utrkcounts = diff([xx',nr]);

%  disp([num2str(length(utrks)),' tracks matched']);
  
  [utcvv,utcxx] = sort(utrkcounts./HashTableLengths(utrks), 'descend');
  % Keep at most MAXTOFILTER per hit
  utcxx = utcxx(1:min(MAXTOFILTER, length(utcxx)));
  utrkcounts = utrkcounts(utcxx);
  utrks = utrks(utcxx);
  
  nutrks = length(utrks);
  R = zeros(nutrks,4);
  
  if USERAWCOUNTS
    for i = 1:nutrks
      tkR = Rt(Rt(:,1)==utrks(i),:);
      R(i,:) = [utrks(i), size(tkR,1), 0, size(tkR,1)];
    end
  
  else
    % apply a time filter
    nwarps = 1 + 2*round(WARPMAX/WARPSTEP);
    for i = 1:nutrks
      tkR = Rt(Rt(:,1)==utrks(i),:);
      warpedcounts = [];
      for ww = 1:nwarps
        warp = (ww-(nwarps+1)/2)*WARPSTEP;
        % Quantize times per window
        wdts = round((double(tkR(:,2))-warp*double(tkR(:,4)))/W);
        % Find the most popular time offset
        [dts,xx] = unique(sort(wdts),'first');
        dtcounts = 1+diff([xx',size(tkR,1)]);
        [vv,xx] = max(dtcounts);
        %    [vv,xx] = sort(dtcounts, 'descend');
        %R(i,:) = [utrks(i),vv(1),dts(xx(1)),size(tkR,1)];
        % Keep everything with time within one unit of mode
        warpedcounts(ww) = sum(abs(wdts-dts(xx(1)))<=1);
        warpeddts(ww) = dts(xx(1));
      end
      [maxcounts, maxcountsix] = max(warpedcounts);
      R(i,:) = [utrks(i),maxcounts,warpeddts(maxcountsix),size(tkR,1)];
    end
  end
  
  % Sort by descending match count
  % To get consistent results, first sort by track ID, so ties in
  % hit counts will then be ordered by track ID
  [vv,xx] = sort(R(:,1));
  R = R(xx,:);
  % Now the actual sort we want, by hit count
  [vv,xx] = sort(R(:,2),'descend');
  R = R(xx,:);

  % Extract the actual landmarks
  % maybe just those that match time?
  %H = Rt((Rt(:,1)==R(IX,1)) & (abs(Rt(:,2)-R(IX,3))<=1),:);
  % no, return them all
  if size(R,1) > 0
    for IXi = 1:length(IX)
      Hix = find(Rt(:,1)==R(IX(IXi),1));
      HO2 = Rt(Hix,2);
      % Restore the original times
%      for i = 1:length(Hix)
%        hqix = find(H(:,2)==Rt(Hix(i),3));
%        HO2(i) = HO2(i) + H(hqix(1),1);
%      end
      HO{IXi} = [Rt(Hix,:),HO2];
    end
  else
    for IXi = 1:length(IX)
      HO{IXi} = zeros(0,4);
    end
  end
  if length(IX) == 1
    % Don't return a 1-element cell array, return a simple matrix
    HO = HO{1};
  end
    
else
  R = zeros(0,4);
  HO = zeros(0,4);
end
